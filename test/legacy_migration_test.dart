/// The rename from SingBox Client to 渡 Ferry moved where desktop data lives;
/// the first launch after it has to bring an existing install along.
library;

import 'dart:io';

import 'package:ferry/platform/legacy_migration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('ferry-migration'));
  tearDown(() => root.deleteSync(recursive: true));

  File file(String path) => File('${root.path}/$path');

  Future<void> migrate() => migrateLegacyDesktopData(
        environment: {'XDG_DATA_HOME': root.path},
        windows: false,
      );

  test('preferences and rule-sets are copied to the new locations', () async {
    file('com.wildalley.singbox_client/shared_preferences.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('{"flutter.nodes.v1":"[]"}');
    file('singbox-client/rule-sets/geosite-cn.srs')
      ..createSync(recursive: true)
      ..writeAsStringSync('SRS');
    file('singbox-client/cache.db').writeAsStringSync('cache');
    file('singbox-client/config.json').writeAsStringSync('{}');

    await migrate();

    expect(
        file('com.wildalley.ferry/shared_preferences.json').readAsStringSync(),
        '{"flutter.nodes.v1":"[]"}');
    expect(file('ferry/rule-sets/geosite-cn.srs').readAsStringSync(), 'SRS');
    expect(file('ferry/cache.db').readAsStringSync(), 'cache');
    expect(file('ferry/config.json').existsSync(), isFalse,
        reason: 'the rendered config is regenerated, not carried');
    expect(
        file('com.wildalley.singbox_client/shared_preferences.json')
            .existsSync(),
        isTrue,
        reason: 'copied, not moved: a rollback still finds its data');
  });

  test('what the new version already has is never overwritten', () async {
    file('com.wildalley.singbox_client/shared_preferences.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('old');
    file('com.wildalley.ferry/shared_preferences.json')
      ..createSync(recursive: true)
      ..writeAsStringSync('new');

    await migrate();

    expect(
        file('com.wildalley.ferry/shared_preferences.json').readAsStringSync(),
        'new');
  });

  test('a fresh machine with nothing to migrate is left alone', () async {
    await migrate();

    expect(root.listSync(), isEmpty);
  });
}
