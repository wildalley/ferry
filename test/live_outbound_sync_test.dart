/// What the live engine knows, versus what the app renders.
///
/// An outbound tag is derived from the node's *display name* — see
/// [ConfigBuilder.outboundTag] — and panels routinely re-issue the same endpoint
/// under a new name. Every connect also triggers an automatic subscription
/// refresh, so this is the ordinary path, not a corner: refresh renames the
/// nodes, the running engine keeps the tags it started with, and the app then
/// asks the selector for a member that config never contained. The switch fails,
/// which reads as a node tap doing nothing at all.
///
/// Asserted against what the controller was actually handed, never against a
/// "should have reloaded" flag: a reload restarts sing-box and drops every open
/// connection, so the point is that it happens when the tags really drifted and
/// not otherwise.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ferry/data/config_builder.dart';
import 'package:ferry/data/importer.dart';
import 'package:ferry/data/storage.dart';
import 'package:ferry/models/node.dart';
import 'package:ferry/models/subscription.dart';
import 'package:ferry/state/app_state.dart';

import 'widget_test.dart' show FakeProxyController;

/// A node belonging to subscription [_remote.id].
ProxyNode _node(String id, String name) => ProxyNode(
      id: id,
      name: name,
      protocol: NodeProtocol.trojan,
      server: '$id.example.com',
      serverPort: 443,
      subscriptionId: _remote.id,
      raw: const {'password': 'secret'},
    );

const _remote = Subscription(
  id: 's1',
  name: 'Panel',
  kind: SubscriptionKind.remote,
  url: 'https://panel.example.com/sub',
);

/// Hands back a fixed node list, standing in for the panel.
class _FakeImporter extends Importer {
  _FakeImporter(this.nodes);

  final List<ProxyNode> nodes;

  @override
  Future<({Subscription subscription, List<ProxyNode> nodes})> refresh(
    Subscription subscription, {
    bool viaLocalProxy = false,
    int? localProxyPort,
  }) async =>
      (
        subscription: subscription.copyWith(
          nodeCount: nodes.length,
          updatedAt: DateTime(2026, 8, 30),
          clearFailure: true,
        ),
        nodes: nodes,
      );
}

Future<({AppState state, FakeProxyController controller})> _connected(
  Importer importer,
  List<ProxyNode> initial,
) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  await storage.writeSubscriptions([_remote]);
  await storage.writeNodes(initial);
  final controller = FakeProxyController();
  final state = AppState(
    storage: storage,
    controller: controller,
    importer: importer,
  );
  addTearDown(state.dispose);
  await state.connect();
  expect(state.isConnected, isTrue, reason: 'the tests below need a tunnel');
  return (state: state, controller: controller);
}

/// The tags a rendered config actually offers the selector.
Set<String> _tagsIn(String configJson) => {
      for (final line in configJson.split('\n'))
        if (RegExp(r'"tag":\s*"([^"]+)"').firstMatch(line)
            case final match?)
          match.group(1)!,
    };

void main() {
  test('a rename mid-session reloads, so the selected tag exists', () async {
    // Same endpoint id, new display name — which is a different outbound tag.
    final harness = await _connected(
      _FakeImporter([_node('a', 'Tokyo 09')]),
      [_node('a', 'Tokyo')],
    );
    final state = harness.state;
    final controller = harness.controller;
    final before = ConfigBuilder.outboundTag(_node('a', 'Tokyo'));
    expect(_tagsIn(controller.startedConfigs.single), contains(before));

    await state.refreshSubscription(_remote.id);
    final after = ConfigBuilder.outboundTag(state.nodes.single);
    expect(after, isNot(before), reason: 'the rename must move the tag');

    await state.selectNode(state.nodes.single);

    // The switch names a member the engine was actually given, which is the
    // whole point: before the fix this tag reached a config that never had it.
    expect(controller.selectedOutbounds.last, after);
    expect(controller.reloadedConfigs, hasLength(1));
    expect(_tagsIn(controller.reloadedConfigs.single), contains(after));
    expect(state.selectedNodeId, 'a', reason: 'the selection must commit');
  });

  test('a refresh that changes no tag leaves the tunnel alone', () async {
    // The guard against the lazy fix: reloading on every refresh would drop
    // every open connection each time a panel answered with the same nodes.
    final harness = await _connected(
      _FakeImporter([_node('a', 'Tokyo')]),
      [_node('a', 'Tokyo')],
    );
    final state = harness.state;

    await state.refreshSubscription(_remote.id);
    await state.selectNode(state.nodes.single);

    expect(harness.controller.reloadedConfigs, isEmpty);
    expect(
      harness.controller.selectedOutbounds.last,
      ConfigBuilder.outboundTag(state.nodes.single),
    );
  });

  test('a node the engine never had is reloaded in before selection', () async {
    // The other half of the drift: a refresh that *adds* an endpoint. Selecting
    // it cannot work until the engine has been given a config containing it.
    final harness = await _connected(
      _FakeImporter([_node('a', 'Tokyo'), _node('c', 'Seoul')]),
      [_node('a', 'Tokyo')],
    );
    final state = harness.state;

    await state.refreshSubscription(_remote.id);
    final fresh = state.nodes.firstWhere((node) => node.id == 'c');
    await state.selectNode(fresh);

    expect(harness.controller.reloadedConfigs, hasLength(1));
    expect(
      _tagsIn(harness.controller.reloadedConfigs.single),
      contains(ConfigBuilder.outboundTag(fresh)),
    );
    expect(state.selectedNodeId, 'c');
  });

  test('auto stays selectable after a refresh renames everything', () async {
    // `auto` is a fixed tag, so the selector call itself was never the problem —
    // but the urltest group behind it lists the *members*, and those moved.
    final harness = await _connected(
      _FakeImporter([_node('a', 'Tokyo 09')]),
      [_node('a', 'Tokyo')],
    );
    final state = harness.state;

    await state.refreshSubscription(_remote.id);
    await state.selectAuto();

    expect(state.isAutoSelected, isTrue);
    expect(harness.controller.selectedOutbounds.last, ConfigTags.auto);
    final members = _tagsIn(harness.controller.reloadedConfigs.single);
    expect(members, contains(ConfigBuilder.outboundTag(state.nodes.single)));
  });

  test('a reload failure leaves the previous selection in place', () async {
    // A refusal must not commit a choice the engine did not take, and must not
    // report success. The old node stays selected, on screen and on disk.
    final harness = await _connected(
      _FakeImporter([_node('a', 'Tokyo 09'), _node('c', 'Seoul')]),
      [_node('a', 'Tokyo')],
    );
    final state = harness.state;
    await state.refreshSubscription(_remote.id);
    state.takeNotice();
    harness.controller.reloadFails = true;

    final fresh = state.nodes.firstWhere((node) => node.id == 'c');
    await state.selectNode(fresh);

    expect(state.selectedNodeId, isNot('c'));
    expect(harness.controller.selectedOutbounds, isEmpty,
        reason: 'a member the engine lacks must never be selected');
    expect(state.takeNotice()?.kind, NoticeKind.reloadFailed);
  });
}
