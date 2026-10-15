/// Root application widget and presentation lifecycle.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'models/app_settings.dart';
import 'state/app_state.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

export 'ui/app_shell.dart';

/// Hosts the Material/localization layer above the navigation shell.
class SingBoxApp extends StatefulWidget {
  const SingBoxApp({super.key, required this.state});

  final AppState state;

  @override
  State<SingBoxApp> createState() => _SingBoxAppState();
}

class _SingBoxAppState extends State<SingBoxApp> with WidgetsBindingObserver {
  var _lifecycleVisible = true;

  /// Presentation changes only; traffic and logs do not rebuild MaterialApp.
  late final _presentation =
      ValueNotifier<({AppThemeMode theme, AppLanguage language, bool visible})>(
          _read());

  ({AppThemeMode theme, AppLanguage language, bool visible}) _read() => (
        theme: widget.state.settings.themeMode,
        language: widget.state.settings.language,
        visible: widget.state.isWindowVisible && _lifecycleVisible,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_onStateChanged);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _lifecycleVisible = false;
    } else if (state == AppLifecycleState.resumed) {
      _lifecycleVisible = true;
    }
    _onStateChanged();
    // Android's VPN is a foreground service whose lifetime is intentionally
    // independent from the Flutter engine. Desktop has no such owner, so a
    // real engine detach still uses the awaited shutdown path.
    if (state == AppLifecycleState.detached && !Platform.isAndroid) {
      unawaited(_stopForLifecycle());
    }
  }

  Future<void> _stopForLifecycle() async {
    try {
      await widget.state.shutdown();
    } on Object {
      // Already shut down, most likely because the quit path got here first.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(_onStateChanged);
    _presentation.dispose();
    super.dispose();
  }

  void _onStateChanged() => _presentation.value = _read();

  static final _light = buildAppTheme(Brightness.light);
  static final _dark = buildAppTheme(Brightness.dark);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<
        ({AppThemeMode theme, AppLanguage language, bool visible})>(
      valueListenable: _presentation,
      builder: (context, settings, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          onGenerateTitle: (context) => L10n.of(context).appTitle,
          theme: _light,
          darkTheme: _dark,
          themeMode: switch (settings.theme) {
            AppThemeMode.system => ThemeMode.system,
            AppThemeMode.light => ThemeMode.light,
            AppThemeMode.dark => ThemeMode.dark,
          },
          localizationsDelegates: const [
            L10n.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: L10n.supportedLocales,
          locale: settings.language.code == null
              ? null
              : Locale(settings.language.code!),
          // Retain navigation and scroll state, but stop native painting and
          // animation allocations while the tunnel runs in the background.
          builder: (context, child) => TickerMode(
            enabled: settings.visible,
            child: Offstage(offstage: !settings.visible, child: child),
          ),
          home: AppShell(state: widget.state),
        );
      },
    );
  }
}
