/// Policy groups: a named exit with its own node, and rules that send to it.
///
/// Three things are worth pinning. The rendered config has to give each group
/// a selector with a valid default and route a group rule to it. A deleted group
/// must not leave a rule naming a missing outbound — sing-box refuses to start
/// on that. And switching a group's node while connected has to move only that
/// group's selector, live, without touching the main one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ferry/data/config_builder.dart';
import 'package:ferry/data/storage.dart';
import 'package:ferry/models/app_settings.dart';
import 'package:ferry/models/custom_rule.dart';
import 'package:ferry/models/node.dart';
import 'package:ferry/models/policy_group.dart';
import 'package:ferry/state/app_state.dart';

import 'widget_test.dart' show FakeProxyController, fakePortAllocator, node;

CustomRule groupRule(String groupId, {String id = 'r1'}) => CustomRule(
      id: id,
      matcher: RuleMatcher.domainSuffix,
      value: 'openai.com',
      target: RuleTarget.group,
      groupId: groupId,
    );

Map<String, dynamic> build({
  List<ProxyNode>? nodes,
  List<PolicyGroup> groups = const [],
  List<CustomRule> rules = const [],
}) =>
    ConfigBuilder.build(
      nodes: nodes ?? [node('a', 'Tokyo'), node('b', 'Los Angeles')],
      selectedNodeId: 'a',
      settings: const AppSettings(),
      clashSecret: 'secret',
      customRules: rules,
      policyGroups: groups,
      ruleSetDir: '/tmp/rule-sets',
    );

Map<String, dynamic>? outbound(Map<String, dynamic> config, String tag) {
  for (final item in (config['outbounds'] as List).cast<Map>()) {
    if (item['tag'] == tag) return item.cast<String, dynamic>();
  }
  return null;
}

Map<String, dynamic> ruleFor(Map<String, dynamic> config, String domain) =>
    ((config['route'] as Map)['rules'] as List)
        .cast<Map>()
        .firstWhere((rule) =>
            (rule['domain_suffix'] as List?)?.contains(domain) ?? false)
        .cast<String, dynamic>();

Future<({AppState state, FakeProxyController controller, Storage storage})>
    harness({
  List<PolicyGroup> groups = const [],
  List<CustomRule> rules = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final storage = await Storage.open();
  await storage.writeNodes([node('a', 'Tokyo'), node('b', 'Los Angeles')]);
  if (groups.isNotEmpty) await storage.writePolicyGroups(groups);
  if (rules.isNotEmpty) await storage.writeCustomRules(rules);
  final controller = FakeProxyController();
  return (
    state: AppState(
      storage: storage,
      controller: controller,
      portAllocator: fakePortAllocator,
    ),
    controller: controller,
    storage: storage,
  );
}

void main() {
  group('rendering', () {
    test('a group is a selector over the same exits, on its own node', () {
      final b = node('b', 'Los Angeles');
      final config = build(
        groups: [const PolicyGroup(id: 'g1', name: 'AI', nodeId: 'b')],
      );
      final selector = outbound(config, ConfigTags.group('g1'))!;

      expect(selector['type'], 'selector');
      expect(selector['default'], ConfigBuilder.outboundTag(b));
      expect(selector['outbounds'], [
        ConfigTags.auto,
        ConfigBuilder.outboundTag(node('a', 'Tokyo')),
        ConfigBuilder.outboundTag(b),
      ]);
      // The main selector is untouched by the group's choice.
      expect(outbound(config, ConfigTags.proxy)!['default'],
          ConfigBuilder.outboundTag(node('a', 'Tokyo')));
    });

    test('no node, or a node that is gone, defaults to the urltest group', () {
      final config = build(groups: [
        const PolicyGroup(id: 'g1', name: 'Auto'),
        const PolicyGroup(id: 'g2', name: 'Stale', nodeId: 'deleted'),
      ]);

      expect(outbound(config, ConfigTags.group('g1'))!['default'],
          ConfigTags.auto);
      expect(
          outbound(config, ConfigTags.group('g2'))!['default'], ConfigTags.auto,
          reason: 'a default that is not a member fails at startup');
    });

    test('with no nodes a group falls back to direct, like the main one', () {
      final config = build(
        nodes: const [],
        groups: [const PolicyGroup(id: 'g1', name: 'AI')],
      );
      final selector = outbound(config, ConfigTags.group('g1'))!;

      expect(selector['outbounds'], [ConfigTags.direct]);
      expect(selector['default'], ConfigTags.direct);
    });

    test('a group rule routes to the group', () {
      final config = build(
        groups: [const PolicyGroup(id: 'g1', name: 'AI')],
        rules: [groupRule('g1')],
      );

      expect(ruleFor(config, 'openai.com')['outbound'], ConfigTags.group('g1'));
    });

    test('a rule whose group is gone routes to the main selector', () {
      final config = build(rules: [groupRule('deleted')]);

      expect(ruleFor(config, 'openai.com')['outbound'], ConfigTags.proxy);
    });
  });

  group('persistence', () {
    test('a group round-trips', () {
      for (final group in const [
        PolicyGroup(id: 'g1', name: 'AI'),
        PolicyGroup(id: 'g2', name: '流媒体', nodeId: 'b'),
      ]) {
        expect(PolicyGroup.fromJson(group.toJson()), group);
      }
    });

    test('a group rule keeps its group', () {
      final rule = groupRule('g1');
      expect(CustomRule.fromJson(rule.toJson()), rule);
    });
  });

  group('state', () {
    test('a new group is saved, and a blank name is refused', () async {
      final h = await harness();
      addTearDown(h.state.dispose);

      final group = await h.state.addPolicyGroup('  AI  ');
      expect(await h.state.addPolicyGroup('   '), isNull);

      expect(group?.name, 'AI');
      expect(h.storage.readPolicyGroups().map((g) => g.name), ['AI']);
    });

    test('choosing a node while disconnected just saves it', () async {
      final h = await harness(
        groups: [const PolicyGroup(id: 'g1', name: 'AI')],
      );
      addTearDown(h.state.dispose);

      await h.state.selectGroupNode('g1', 'b');

      expect(h.state.policyGroup('g1')?.nodeId, 'b');
      expect(h.storage.readPolicyGroups().single.nodeId, 'b');
      expect(h.controller.groupSelections, isEmpty);
    });

    test('choosing a node while connected moves only that group, live',
        () async {
      final h = await harness(
        groups: [const PolicyGroup(id: 'g1', name: 'AI')],
      );
      addTearDown(h.state.dispose);
      await h.state.connect();
      final reloads = h.controller.reloadedConfigs.length;

      await h.state.selectGroupNode('g1', 'b');

      expect(h.controller.groupSelections, [
        (
          ConfigTags.group('g1'),
          ConfigBuilder.outboundTag(node('b', 'Los Angeles'))
        ),
      ]);
      expect(h.controller.selectedOutbounds, isEmpty,
          reason: 'the main selector is not the one that moved');
      expect(h.controller.reloadedConfigs, hasLength(reloads),
          reason: 'a live switch keeps the connections');
      expect(h.state.policyGroup('g1')?.nodeId, 'b');
    });

    test('a rejected live switch keeps the old choice', () async {
      final h = await harness(
        groups: [const PolicyGroup(id: 'g1', name: 'AI', nodeId: 'a')],
      );
      addTearDown(h.state.dispose);
      await h.state.connect();
      h.controller.selectOutboundError = 'rejected';

      await h.state.selectGroupNode('g1', 'b');

      expect(h.state.policyGroup('g1')?.nodeId, 'a');
      expect(h.storage.readPolicyGroups().single.nodeId, 'a');
    });

    test('a group made while connected is put into the running config',
        () async {
      final h = await harness();
      addTearDown(h.state.dispose);
      await h.state.connect();
      final reloads = h.controller.reloadedConfigs.length;

      final group = await h.state.addPolicyGroup('AI');

      expect(h.controller.reloadedConfigs, hasLength(reloads + 1));
      expect(h.controller.reloadedConfigs.last,
          contains(ConfigTags.group(group!.id)));
    });

    test('deleting a group moves its rules to the main exit', () async {
      final h = await harness(
        groups: [const PolicyGroup(id: 'g1', name: 'AI')],
        rules: [groupRule('g1')],
      );
      addTearDown(h.state.dispose);

      await h.state.removePolicyGroup('g1');

      expect(h.state.policyGroups, isEmpty);
      expect(h.state.customRules.single.target, RuleTarget.proxy);
      expect(h.storage.readCustomRules().single.target, RuleTarget.proxy);
    });

    test('a rename changes the name and nothing in the config', () async {
      final h = await harness(
        groups: [const PolicyGroup(id: 'g1', name: 'AI')],
      );
      addTearDown(h.state.dispose);
      await h.state.connect();
      final reloads = h.controller.reloadedConfigs.length;

      await h.state.renamePolicyGroup('g1', 'Assistants');

      expect(h.state.policyGroup('g1')?.name, 'Assistants');
      expect(h.controller.reloadedConfigs, hasLength(reloads),
          reason: 'the tag comes from the id, so the engine needs nothing');
    });
  });
}
