import 'package:ferry/data/secret_store.dart';
import 'package:ferry/data/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Vault implements SecretStore {
  final values = <String, String>{};
  String? failKey;
  bool discardWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (key == failKey) throw StateError('locked');
    if (!discardWrites) values[key] = value;
  }
}

void main() {
  const legacy = {
    'nodes.v1': '[]',
    'subscriptions.v1': '[]',
    'clash_secret.v1': 'legacy-token',
  };
  setUp(() => SharedPreferences.setMockInitialValues(legacy));

  test('moves all secrets, verifies them, then removes legacy plaintext',
      () async {
    final vault = _Vault();
    final storage = await Storage.open(secrets: vault);
    expect(storage.readClashSecret(), 'legacy-token');
    expect(storage.readProxySecret(), isNot('legacy-token'));
    final prefs = await SharedPreferences.getInstance();
    for (final key in legacy.keys) {
      expect(prefs.containsKey(key), isFalse);
      expect(vault.values[key], legacy[key]);
    }
    final reopened = await Storage.open(secrets: vault);
    expect(reopened.readProxySecret(), storage.readProxySecret());
  });

  test('interrupted migration keeps every legacy key and resumes', () async {
    final vault = _Vault()..failKey = 'subscriptions.v1';
    await expectLater(
        Storage.open(secrets: vault), throwsA(isA<SecureStorageUnavailable>()));
    final prefs = await SharedPreferences.getInstance();
    for (final key in legacy.keys) {
      expect(prefs.getString(key), legacy[key]);
    }
    vault.failKey = null;
    expect(
        (await Storage.open(secrets: vault)).readClashSecret(), 'legacy-token');
  });

  test('a write that does not survive readback cannot delete plaintext',
      () async {
    final vault = _Vault()..discardWrites = true;
    await expectLater(
        Storage.open(secrets: vault), throwsA(isA<SecureStorageUnavailable>()));
    expect((await SharedPreferences.getInstance()).getString('clash_secret.v1'),
        'legacy-token');
  });

  test('a missing migrated vault does not silently reset the installation',
      () async {
    await Storage.open(secrets: _Vault());
    await expectLater(Storage.open(secrets: _Vault()),
        throwsA(isA<SecureStorageUnavailable>()));
  });

  test('corrupt legacy payload is retained for recovery', () async {
    SharedPreferences.setMockInitialValues({...legacy, 'nodes.v1': '{broken'});
    await expectLater(Storage.open(secrets: _Vault()),
        throwsA(isA<SecureStorageUnavailable>()));
    expect((await SharedPreferences.getInstance()).getString('nodes.v1'), '{broken');
  });

  test('a failed write keeps cached data and does not poison later writes',
      () async {
    final vault = _Vault();
    final storage = await Storage.open(secrets: vault);
    vault.failKey = 'clash_secret.v1';
    await expectLater(storage.writeClashSecret('new-token'),
        throwsA(isA<SecureStorageUnavailable>()));
    expect(storage.readClashSecret(), 'legacy-token');
    vault.failKey = null;
    await storage.writeClashSecret('new-token');
    expect(storage.readClashSecret(), 'new-token');
    expect(
        (await SharedPreferences.getInstance()).containsKey('clash_secret.v1'),
        isFalse);
  });
}
