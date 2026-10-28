import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ferry/main.dart';
import 'package:ferry/models/proxy_state.dart';
import 'package:ferry/platform/desktop_shell.dart';
import 'package:ferry/ui/home_page.dart';
import 'package:ferry/ui/logs_page.dart';

import 'widget_test.dart' show buildState, node;

class _CountingBinding extends AutomatedTestWidgetsFlutterBinding {
  var postFrameCallbacks = 0;

  @override
  void addPostFrameCallback(FrameCallback callback,
      {String debugLabel = 'callback'}) {
    postFrameCallbacks++;
    super.addPostFrameCallback(callback, debugLabel: debugLabel);
  }
}

void main() {
  final binding = _CountingBinding();

  testWidgets(
      'closing to the tray parks presentation and activation restores it',
      (tester) async {
    const trayChannel = MethodChannel('tray_manager');
    const windowChannel = MethodChannel('window_manager');
    final windowCalls = <String>[];
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(trayChannel, (_) async => null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(windowChannel,
        (call) async {
      windowCalls.add(call.method);
      if (call.method == 'isMinimized') return false;
      return null;
    });
    addTearDown(() {
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(trayChannel, null);
      binding.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, null);
    });
    final harness = await buildState();
    addTearDown(harness.state.dispose);
    final shell = DesktopShell(harness.state);
    await shell.start();
    addTearDown(shell.dispose);
    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();

    shell.onWindowClose();
    await tester.pumpAndSettle();
    expect(windowCalls, contains('hide'));
    expect(find.byType(HomePage), findsNothing);
    expect(harness.controller.didShutdown, isFalse);

    shell.activate();
    await tester.pumpAndSettle();
    expect(windowCalls, containsAllInOrder(['hide', 'show', 'focus']));
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('minimized dashboard stops ticking while counters keep updating',
      (tester) async {
    final harness = await buildState(nodes: [node('a', 'Tokyo')]);
    addTearDown(harness.state.dispose);
    final shell = DesktopShell(harness.state);
    harness.controller.emit(const ProxyState(stage: ProxyStage.connected));
    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();
    final home = tester.element(find.byType(HomePage));

    harness.controller.emitTraffic(const ProxyTraffic(downlink: 4096));
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);

    shell.onWindowMinimize();
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsNothing);
    expect(tester.hasRunningAnimations, isFalse);

    for (var i = 0; i < 1000; i++) {
      harness.controller.emitTraffic(ProxyTraffic(downlink: i));
      harness.controller.emitLog('background $i');
    }
    await tester.pump(Duration.zero);
    await tester.pumpAndSettle();
    expect(harness.state.traffic.downlink, 999);
    expect(harness.state.downlinkHistory, hasLength(60));
    expect(harness.state.logs, hasLength(500));
    expect(harness.controller.stopCount, 0);
    expect(tester.hasRunningAnimations, isFalse);

    // With no incoming data, even the uptime timer should stop requesting frames.
    await tester.pump(const Duration(seconds: 2));
    await tester.idle();
    expect(binding.hasScheduledFrame, isFalse);

    shell.onWindowRestore();
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(HomePage)), same(home));
    expect(harness.state.isConnected, isTrue);
  });

  testWidgets('lifecycle hiding also parks and restores presentation',
      (tester) async {
    final harness = await buildState();
    addTearDown(harness.state.dispose);
    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();

    binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    // The real scheduler stops frames on hidden; force one to inspect the
    // pending presentation update without resuming the lifecycle first.
    binding.scheduleForcedFrame();
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsNothing);
    expect(harness.controller.didShutdown, isFalse);

    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('logs queue only one follow callback while frames are suspended',
      (tester) async {
    final harness = await buildState();
    addTearDown(harness.state.dispose);
    await tester.pumpWidget(SingBoxApp(state: harness.state));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    final logsPage = tester.element(find.byType(LogsPage));

    harness.state.setWindowVisible(false);
    await tester.pumpAndSettle();
    final before = binding.postFrameCallbacks;

    // Deliver separate event-loop batches without drawing a frame, like a
    // window left in the tray. A ring buffer alone does not bound this queue.
    for (var i = 0; i < 2000; i++) {
      harness.controller.emitLog('line $i');
      harness.controller.emitTraffic(ProxyTraffic(downlink: i));
      await tester.idle();
    }
    expect(binding.postFrameCallbacks - before, 1);
    expect(harness.state.logs, hasLength(500));

    harness.state.setWindowVisible(true);
    await tester.pumpAndSettle();
    expect(tester.element(find.byType(LogsPage)), same(logsPage));
    final position =
        tester.state<ScrollableState>(find.byType(Scrollable).last).position;
    expect(position.pixels, closeTo(position.maxScrollExtent, 1));

    // A queued callback must also be harmless if its page is disposed first.
    harness.controller.emitLog('last');
    await tester.idle();
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
