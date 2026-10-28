part of 'app_state.dart';

// See AppStateConnection for why ChangeNotifier lint is intentionally scoped.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension _AppStateUpdate on AppState {
  /// How long an automatic check is good for.
  static const _checkInterval = Duration(hours: 24);

  Future<void> _checkForUpdate({required bool manual}) async {
    if (_checkingUpdate || !_acceptingWork) return;
    if (!manual) {
      final last = _storage.readUpdateCheckedAt();
      if (last != null && DateTime.now().difference(last) < _checkInterval) {
        return;
      }
    }

    _checkingUpdate = true;
    notifyListeners();
    try {
      final release = await _updateChecker.latest(
        viaLocalProxy: isConnected,
        localProxyPort: _localProxyPort,
      );
      await _storage.writeUpdateCheckedAt(DateTime.now());
      final current = parseAppVersion(appVersion) ?? const [0, 0, 0];
      final newer = isNewerVersion(release.version, current);
      _availableUpdate = newer ? release : null;
      if (manual) {
        _notice = newer
            ? AppNotice(NoticeKind.updateAvailable, detail: release.tag)
            : const AppNotice(NoticeKind.upToDate);
      }
    } on Object {
      // An automatic check failing is not news: offline, rate-limited and
      // blocked all read the same, and the next launch tries again.
      if (manual) _notice = const AppNotice.error(NoticeKind.updateCheckFailed);
    } finally {
      _checkingUpdate = false;
      _notifyUnlessDisposed();
    }
  }

  Future<void> _dismissUpdate() async {
    final tag = _availableUpdate?.tag;
    if (tag == null) return;
    _dismissedUpdate = tag;
    await _storage.writeDismissedUpdate(tag);
    notifyListeners();
  }
}
