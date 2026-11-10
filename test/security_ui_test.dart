import 'package:ferry/data/storage.dart';
import 'package:ferry/l10n/app_localizations.dart';
import 'package:ferry/models/app_settings.dart';
import 'package:ferry/state/app_state.dart';
import 'package:ferry/ui/settings_page.dart';
import 'package:ferry/ui/storage_recovery.dart';
import 'package:ferry/ui/theme.dart';
import 'package:ferry/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeProxyController, fakePortAllocator;

void main() {
  for (final size in [const Size(375, 812), const Size(812, 375)]) {
    testWidgets('vault recovery fits $size with large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(StorageRecovery(onReady: (_) {}));
      await tester.pumpAndSettle();
      expect(find.text('Secure storage is unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  for (final brightness in Brightness.values) {
    testWidgets('proxy credentials require an explicit reveal in $brightness',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final state = AppState(
          storage: await Storage.open(),
          controller: FakeProxyController(),
          portAllocator: fakePortAllocator);
      addTearDown(state.dispose);
      await state.applySettings(const AppSettings(localProxyAuth: true));
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(brightness),
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: SettingsPage(state: state, onOpenLogs: () {})),
      ));
      await tester.pumpAndSettle();
      expect(find.text(state.localProxyPassword), findsNothing);
      expect(state.previewConfig(), isNot(contains(state.localProxyPassword)));
      await tester.ensureVisible(find.text('Show proxy credentials'));
      await tester.tap(find.text('Show proxy credentials'));
      await tester.pumpAndSettle();
      expect(find.text(state.localProxyPassword), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('system proxy compatibility warning follows the auth switch',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final state = AppState(
        storage: await Storage.open(),
        controller: FakeProxyController(),
        portAllocator: fakePortAllocator);
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Brightness.light),
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(body: SettingsPage(state: state, onOpenLogs: () {})),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ProxyCompatibilityNotice), findsNothing);
    final auth = find.ancestor(
        of: find.text('Local proxy authentication'),
        matching: find.byType(SettingRow));
    await tester.ensureVisible(auth);
    await tester.tap(find.descendant(of: auth, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(find.byType(ProxyCompatibilityNotice), findsOneWidget);
    expect(find.textContaining('may lose internet access'), findsOneWidget);
    expect(find.text(state.localProxyPassword), findsNothing);
    await tester.tap(find.descendant(of: auth, matching: find.byType(Switch)));
    await tester.pumpAndSettle();
    expect(find.byType(ProxyCompatibilityNotice), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final android in [true, false]) {
    for (final size in [const Size(375, 812), const Size(812, 375)]) {
      for (final brightness in Brightness.values) {
        testWidgets('proxy warning fits $android $size $brightness',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 2;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(MaterialApp(
            theme: buildAppTheme(brightness),
            locale: Locale(android ? 'zh' : 'en'),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: ProxyCompatibilityNotice(android: android),
              ),
            ),
          ));
          await tester.pumpAndSettle();
          expect(find.textContaining(android ? '可能无法联网' : 'may lose internet access'),
              findsOneWidget);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
