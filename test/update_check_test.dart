/// The optional update check: what counts as newer, when it asks, and what it
/// says.
///
/// It is advisory by design — nothing here downloads or installs — so the
/// behaviour to pin is restraint: automatic checks stay silent and run at most
/// daily, a closed prompt stays closed for that release, and only a check the
/// user asked for reports back.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ferry/data/storage.dart';
import 'package:ferry/data/update_checker.dart';
import 'package:ferry/state/app_state.dart';
import 'package:ferry/version.dart';

import 'widget_test.dart' show FakeProxyController, fakePortAllocator;

class FakeChecker extends UpdateChecker {
  FakeChecker({this.release, this.fails = false});

  AppRelease? release;
  bool fails;
  var calls = 0;

  @override
  Future<AppRelease> latest({
    bool viaLocalProxy = false,
    int? localProxyPort,
  }) async {
    calls++;
    if (fails || release == null) throw const SocketException('offline');
    return release!;
  }
}

AppRelease release(String tag) => AppRelease(
      tag: tag,
      version: parseAppVersion(tag)!,
      url: 'https://github.com/wildalley/ferry/releases/tag/$tag',
    );

Future<({AppState state, Storage storage})> harness(FakeChecker checker,
    {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final storage = await Storage.open();
  return (
    state: AppState(
      storage: storage,
      controller: FakeProxyController(),
      portAllocator: fakePortAllocator,
      updateChecker: checker,
    ),
    storage: storage,
  );
}

void main() {
  group('versions', () {
    test('tags and build suffixes parse to three numbers', () {
      expect(parseAppVersion('v0.3.1'), [0, 3, 1]);
      expect(parseAppVersion('0.2.0+17'), [0, 2, 0]);
      expect(parseAppVersion('1.4'), [1, 4, 0]);
      expect(parseAppVersion('nightly'), isNull);
    });

    test('newer compares field by field, not as text', () {
      expect(isNewerVersion([0, 10, 0], [0, 9, 9]), isTrue);
      expect(isNewerVersion([0, 2, 0], [0, 2, 0]), isFalse);
      expect(isNewerVersion([0, 1, 9], [0, 2, 0]), isFalse);
      expect(isNewerVersion([1, 0, 0], [0, 99, 99]), isTrue);
    });

    test('the version the UI shows is the one pubspec ships', () {
      // They drifted once: the release bumped pubspec to 0.2.0 and left the
      // UI on 0.1.5, which would have offered every user the release they
      // were already running.
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final line = RegExp(r'^version:\s*(\S+)', multiLine: true)
          .firstMatch(pubspec)!
          .group(1)!;
      expect(parseAppVersion(line), parseAppVersion(appVersion));
    });
  });

  group('release parsing', () {
    test('reads the tag, the page and the first lines of the notes', () {
      final parsed = UpdateChecker.parseRelease('''
{"tag_name": "v0.3.0",
 "html_url": "https://github.com/wildalley/ferry/releases/tag/v0.3.0",
 "body": "Policy groups\\nNew theme"}''');

      expect(parsed.tag, 'v0.3.0');
      expect(parsed.version, [0, 3, 0]);
      expect(parsed.url, startsWith('https://github.com/'));
      expect(parsed.notes, 'Policy groups\nNew theme');
    });

    test('a body without a version or an https page is refused', () {
      expect(
        () => UpdateChecker.parseRelease('{"tag_name": "latest"}'),
        throwsFormatException,
      );
      expect(
        () => UpdateChecker.parseRelease(
            '{"tag_name": "v9.0.0", "html_url": "javascript:alert(1)"}'),
        throwsFormatException,
      );
    });
  });

  group('state', () {
    test('a newer release is offered, and closing it is remembered', () async {
      final checker = FakeChecker(release: release('v99.0.0'));
      final h = await harness(checker);
      addTearDown(h.state.dispose);

      await h.state.checkForUpdate();
      expect(h.state.availableUpdate?.tag, 'v99.0.0');
      expect(h.state.showUpdatePrompt, isTrue);
      expect(h.state.takeNotice(), isNull,
          reason: 'an automatic check does not interrupt');

      await h.state.dismissUpdate();
      expect(h.state.showUpdatePrompt, isFalse);
      expect(h.storage.readDismissedUpdate(), 'v99.0.0');
      expect(h.state.availableUpdate, isNotNull,
          reason: 'settings still shows it after the prompt is closed');
    });

    test('a release newer than the closed one is offered again', () async {
      final checker = FakeChecker(release: release('v99.1.0'));
      final h =
          await harness(checker, prefs: {'update_dismissed.v1': 'v99.0.0'});
      addTearDown(h.state.dispose);

      await h.state.checkForUpdate();

      expect(h.state.showUpdatePrompt, isTrue);
    });

    test('the running version, or an older one, is not offered', () async {
      final checker = FakeChecker(release: release('v$appVersion'));
      final h = await harness(checker);
      addTearDown(h.state.dispose);

      await h.state.checkForUpdate();

      expect(h.state.availableUpdate, isNull);
      expect(h.state.showUpdatePrompt, isFalse);
    });

    test('automatic checks run at most once a day', () async {
      final checker = FakeChecker(release: release('v99.0.0'));
      final h = await harness(checker, prefs: {
        'update_checked_at.v1': DateTime.now()
            .subtract(const Duration(hours: 3))
            .millisecondsSinceEpoch,
      });
      addTearDown(h.state.dispose);

      await h.state.checkForUpdate();
      expect(checker.calls, 0);

      await h.state.checkForUpdate(manual: true);
      expect(checker.calls, 1, reason: 'asking by hand always asks');
    });

    test('a manual check says what it found', () async {
      final checker = FakeChecker(release: release('v$appVersion'));
      final h = await harness(checker);
      addTearDown(h.state.dispose);

      await h.state.checkForUpdate(manual: true);
      expect(h.state.takeNotice()?.kind, NoticeKind.upToDate);

      checker.release = release('v99.0.0');
      await h.state.checkForUpdate(manual: true);
      final notice = h.state.takeNotice();
      expect(notice?.kind, NoticeKind.updateAvailable);
      expect(notice?.detail, 'v99.0.0');
    });

    test('a failed check is silent unless it was asked for', () async {
      final checker = FakeChecker(fails: true);
      final h = await harness(checker);
      addTearDown(h.state.dispose);

      await h.state.checkForUpdate();
      expect(h.state.takeNotice(), isNull);
      expect(h.storage.readUpdateCheckedAt(), isNull,
          reason: 'a failure does not count as the daily check');

      await h.state.checkForUpdate(manual: true);
      final notice = h.state.takeNotice();
      expect(notice?.kind, NoticeKind.updateCheckFailed);
      expect(notice?.isError, isTrue);
    });
  });
}
