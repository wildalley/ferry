/// What each notification from AppState is about, so the dashboard can skip
/// the per-second traffic samples and log bursts it does not draw from.
library;

import 'package:ferry/models/proxy_state.dart';
import 'package:ferry/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'widget_test.dart' show buildState, node;

void main() {
  test('traffic, logs and everything else are told apart', () async {
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);
    final kinds = <StateChange>[];
    var trafficTicks = 0;
    harness.state.addListener(() => kinds.add(harness.state.lastChange));
    harness.state.trafficChanges.addListener(() => trafficTicks++);
    // Startup work (the core version, the rule-set record) notifies too.
    await Future<void>.delayed(const Duration(milliseconds: 5));
    kinds.clear();

    harness.controller.emitTraffic(const ProxyTraffic(downlink: 1024));
    await Future<void>.delayed(Duration.zero);
    expect(kinds, [StateChange.traffic]);
    expect(trafficTicks, 1);

    harness.controller.emitLog('router: started');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(kinds.last, StateChange.logs);

    await harness.state.setNodeSort(harness.state.nodeSort);
    harness.controller.emit(const ProxyState(stage: ProxyStage.connected));
    await Future<void>.delayed(Duration.zero);
    expect(kinds.last, StateChange.general);
    expect(trafficTicks, 1, reason: 'only traffic samples tick trafficChanges');
    expect(harness.state.lastChange, StateChange.general,
        reason: 'outside a callback it reads general');
  });
}
