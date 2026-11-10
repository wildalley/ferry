/// Platform-protected credentials. Errors deliberately contain no key or value.
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

class SecureStorageUnavailable implements Exception {
  const SecureStorageUnavailable();

  @override
  String toString() =>
      'Secure storage is unavailable; saved data was retained.';
}
