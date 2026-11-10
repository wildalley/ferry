/// Platform-protected credentials. Errors deliberately contain no key or value.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class PlatformSecretStore implements SecretStore {
  const PlatformSecretStore();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'ferry_credentials',
      resetOnError: false,
      migrateWithBackup: true,
    ),
  );

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

/// Android fallback for devices whose Keystore cannot be used at all.
///
/// Some OEM Keystore implementations fail every operation, which left the app
/// stuck on the recovery screen straight after installation. The values live
/// in the app's private preferences instead: readable only by this app's uid,
/// and excluded from cloud backup and device transfer by the manifest rules —
/// how credentials were kept before the vault existed. [Storage.open] selects
/// it only when the Keystore never held Ferry's data, so nothing is orphaned.
class DeviceSecretStore implements SecretStore {
  DeviceSecretStore(this._prefs);

  final SharedPreferences _prefs;
  static const _prefix = 'device_secret.';

  @override
  Future<String?> read(String key) async => _prefs.getString('$_prefix$key');

  @override
  Future<void> write(String key, String value) async {
    if (!await _prefs.setString('$_prefix$key', value)) {
      throw const SecureStorageUnavailable('device-write-failed');
    }
  }
}

class SecureStorageUnavailable implements Exception {
  const SecureStorageUnavailable([this.detail]);

  /// What failed, for the recovery screen and bug reports. Only error codes
  /// and platform messages — never a stored value.
  final String? detail;

  @override
  String toString() => 'Secure storage is unavailable; saved data was retained.'
      '${detail == null ? '' : ' ($detail)'}';
}
