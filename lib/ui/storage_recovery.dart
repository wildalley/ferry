import 'dart:io';

import 'package:flutter/material.dart';

import '../data/secret_store.dart';
import '../data/storage.dart';
import '../l10n/app_localizations.dart';
import 'theme.dart';

/// Startup cannot proceed with an empty vault when the real one is locked.
/// Keep the original data and let the user unlock the OS keyring and retry.
class StorageRecovery extends StatefulWidget {
  const StorageRecovery({super.key, required this.onReady, this.detail});

  final ValueChanged<Storage> onReady;

  /// Why the vault could not be opened, shown so the failure can be reported.
  final String? detail;

  @override
  State<StorageRecovery> createState() => _StorageRecoveryState();
}

class _StorageRecoveryState extends State<StorageRecovery> {
  var _busy = false;
  late String? _detail = widget.detail;

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      final storage = await Storage.open();
      if (mounted) widget.onReady(storage);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _detail = error is SecureStorageUnavailable
              ? error.detail
              : error.runtimeType.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: buildAppTheme(Brightness.light),
        darkTheme: buildAppTheme(Brightness.dark),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(builder: (context) {
          final l10n = L10n.of(context);
          return Scaffold(
            body: SafeArea(
                child: Center(
                    child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_outline, size: 40),
                  const SizedBox(height: 24),
                  Semantics(
                      liveRegion: true,
                      child: Text(l10n.storageUnavailable,
                          style: Theme.of(context).textTheme.titleLarge)),
                  const SizedBox(height: 16),
                  Text(l10n.storageRecoveryBody),
                  if (_detail != null) ...[
                    const SizedBox(height: 16),
                    SelectableText(_detail!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                      onPressed: _busy ? null : _retry,
                      child: Text(
                          _busy ? l10n.storageOpening : l10n.storageRetry)),
                  TextButton(
                      onPressed: () => exit(0), child: Text(l10n.storageExit)),
                ]),
              ),
            ))),
          );
        }),
      );
}
