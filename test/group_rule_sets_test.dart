/// A policy group's rule-sets: whole lists of sites that go through it.
///
/// What matters: the forms a user can type, that only downloaded lists reach
/// the config (a missing file must never stop the engine), where their rules
/// sit, and the state flow — download on add, reload while connected, report
/// a failure, clean up a list no group uses any more.
library;

import 'dart:io';

import 'package:ferry/data/config_builder.dart';
import 'package:ferry/main.dart';
import 'package:ferry/data/rule_set_updater.dart';
import 'package:ferry/data/storage.dart';
import 'package:ferry/models/app_settings.dart';
import 'package:ferry/models/custom_rule.dart';
import 'package:ferry/models/policy_group.dart';
import 'package:ferry/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show FakeProxyController, fakePortAllocator, node;

/// Writes a minimal compiled-looking file instead of downloading, or fails.
class _FakeUpdater extends RuleSetUpdater {
  final fetched = <String>[];
  final failing = <String>{};

  @override
  Future<void> fetchSource(
    Directory dir,
    RuleSetSource source, {
    bool viaLocalProxy = false,
    int? localProxyPort,
  }) async {
    fetched.add(source.entry);
    if (failing.contains(source.entry)) {
      throw RuleSetUpdateException('${source.label}: HTTP 404');
    }
    await File('${dir.path}/${source.tag}.srs').writeAsString('SRS-fake');
  }
}

List<Map<String, dynamic>> _rules(Map<String, dynamic> config) =>
    ((config['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

void main() {
  group('sources', () {
    test('a bare name is a geosite category', () {
      final source = RuleSetSource.parse(' OpenAI ')!;
      expect(source.entry, 'geosite:openai');
      expect(source.label, 'openai');
      expect(source.tag, 'ext-geosite-openai');
      expect(source.url(base: 'https://h').toString(),
          'https://h/sing-geosite/rule-set/geosite-openai.srs');
    });

    test('geoip and links have their own forms', () {
      final geoip = RuleSetSource.parse('geoip:JP')!;
      expect(geoip.entry, 'geoip:jp');
      expect(geoip.url(base: 'https://h').toString(),
          'https://h/sing-geoip/rule-set/geoip-jp.srs');

      const link = 'https://example.net/lists/ai.srs';
      final url = RuleSetSource.parse(link)!;
      expect(url.entry, link);
      expect(url.label, 'ai.srs');
      expect(url.tag, startsWith('ext-url-'));
      expect(url.url(base: 'https://h').toString(), link);
    });

    test('anything else is refused', () {
      for (final bad in [
        '',
        'open ai',
        'http://x/a.srs',
        'geoip:',
        'ftp://x'
      ]) {
        expect(RuleSetSource.parse(bad), isNull, reason: bad);
      }
    });

    test('a group with rule-sets round-trips', () {
      const group = PolicyGroup(
        id: 'g',
        name: 'AI',
        ruleSets: ['geosite:openai', 'geoip:jp'],
      );
      expect(PolicyGroup.fromJson(group.toJson()), group);
    });
  });

  group('rendering', () {
    Map<String, dynamic> build({
      Map<String, List<String>> groupRuleSets = const {},
      String? ruleSetDir = '/rs',
    }) =>
        ConfigBuilder.build(
          nodes: [node('a', 'Tokyo')],
          selectedNodeId: 'a',
          settings: const AppSettings(blockAds: true),
          clashSecret: 's',
          ruleSetDir: ruleSetDir,
          customRules: const [
            CustomRule(
              id: 'r',
              matcher: RuleMatcher.domainSuffix,
              value: 'work.example.cn',
              target: RuleTarget.direct,
            ),
          ],
          policyGroups: const [
            PolicyGroup(id: 'g1', name: 'AI'),
            PolicyGroup(id: 'g2', name: 'Video'),
          ],
          groupRuleSets: groupRuleSets,
        );

    test('a downloaded list routes to its group, after the own rules', () {
      final config = build(groupRuleSets: {
        'g1': ['ext-geosite-openai'],
      });
      final rules = _rules(config);
      final group =
          rules.indexWhere((r) => r['outbound'] == ConfigTags.group('g1'));
      final own = rules.indexWhere((r) =>
          (r['domain_suffix'] as List?)?.contains('work.example.cn') ?? false);
      final ads = rules.indexWhere(
          (r) => (r['rule_set'] as List?)?.contains('geosite-ads') ?? false);
      final cn = rules.indexWhere(
          (r) => (r['rule_set'] as List?)?.contains('geosite-cn') ?? false);

      expect(rules[group]['rule_set'], ['ext-geosite-openai']);
      expect(own, lessThan(group), reason: 'a typed rule is more specific');
      expect(group, lessThan(ads));
      expect(group, lessThan(cn));
      final sets = ((config['route'] as Map)['rule_set'] as List).cast<Map>();
      expect(
        sets.firstWhere((s) => s['tag'] == 'ext-geosite-openai'),
        {
          'type': 'local',
          'tag': 'ext-geosite-openai',
          'format': 'binary',
          'path': '/rs/ext-geosite-openai.srs',
        },
      );
    });

    test('a list shared by two groups is declared once', () {
      final config = build(groupRuleSets: {
        'g1': ['ext-geosite-google'],
        'g2': ['ext-geosite-google', 'ext-geosite-youtube'],
      });
      final tags = [
        for (final s
            in ((config['route'] as Map)['rule_set'] as List).cast<Map>())
          s['tag'],
      ];
      expect(tags.where((t) => t == 'ext-geosite-google'), hasLength(1));
      expect(tags, contains('ext-geosite-youtube'));
    });

    test('nothing renders for a deleted group, or without a rule-set dir', () {
      for (final config in [
        build(groupRuleSets: {
          'gone': ['ext-geosite-openai']
        }),
        build(groupRuleSets: {
          'g1': ['ext-geosite-openai']
        }, ruleSetDir: null),
      ]) {
        expect(
          _rules(config).where((r) =>
              (r['rule_set'] as List?)?.contains('ext-geosite-openai') ??
              false),
          isEmpty,
        );
      }
    });
  });

  group('state', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ferry-rs'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<
        ({
          AppState state,
          FakeProxyController controller,
          _FakeUpdater updater
        })> harness() async {
      SharedPreferences.setMockInitialValues({});
      final storage = await Storage.open();
      await storage.writeNodes([node('a', 'Tokyo')]);
      await storage
          .writePolicyGroups(const [PolicyGroup(id: 'g1', name: 'AI')]);
      final controller = FakeProxyController();
      final updater = _FakeUpdater();
      return (
        state: AppState(
          storage: storage,
          controller: controller,
          portAllocator: fakePortAllocator,
          ruleSetUpdater: updater,
          ruleSetDir: dir.path,
        ),
        controller: controller,
        updater: updater,
      );
    }

    test('adding downloads the list and puts it in the running config',
        () async {
      final h = await harness();
      addTearDown(h.state.dispose);
      await h.state.connect();
      final reloads = h.controller.reloadedConfigs.length;

      expect(await h.state.addGroupRuleSet('g1', 'openai'), isTrue);

      expect(h.updater.fetched, ['geosite:openai']);
      expect(h.state.isRuleSetDownloaded('geosite:openai'), isTrue);
      expect(h.state.policyGroup('g1')!.ruleSets, ['geosite:openai']);
      expect(h.controller.reloadedConfigs.length, greaterThan(reloads));
      expect(h.controller.reloadedConfigs.last, contains('ext-geosite-openai'));
    });

    test('a bad or repeated entry is refused without a download', () async {
      final h = await harness();
      addTearDown(h.state.dispose);

      expect(await h.state.addGroupRuleSet('g1', 'open ai'), isFalse);
      await h.state.addGroupRuleSet('g1', 'openai');
      expect(await h.state.addGroupRuleSet('g1', 'geosite:openai'), isFalse);
      expect(h.updater.fetched, ['geosite:openai']);
    });

    test('a failed download is reported and kept out of the config', () async {
      final h = await harness();
      addTearDown(h.state.dispose);
      h.updater.failing.add('geosite:nosuch');

      await h.state.addGroupRuleSet('g1', 'nosuch');

      expect(h.state.isRuleSetDownloaded('geosite:nosuch'), isFalse);
      final notice = h.state.takeNotice();
      expect(notice?.kind, NoticeKind.ruleSetDownloadFailed);
      expect(notice?.detail, 'nosuch');
      expect(h.state.previewConfig(), isNot(contains('ext-geosite-nosuch')));
      expect(h.state.policyGroup('g1')!.ruleSets, ['geosite:nosuch'],
          reason: 'kept, so it can be retried');
    });

    test('removing the last reference deletes the file', () async {
      final h = await harness();
      addTearDown(h.state.dispose);
      await h.state.addGroupRuleSet('g1', 'openai');
      final file = File('${dir.path}/ext-geosite-openai.srs');
      expect(file.existsSync(), isTrue);

      await h.state.removeGroupRuleSet('g1', 'geosite:openai');

      expect(h.state.policyGroup('g1')!.ruleSets, isEmpty);
      expect(file.existsSync(), isFalse);
    });

    testWidgets('the sheet lists a group\'s sets and adds a common one',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final h = await tester.runAsync(harness);
      addTearDown(h!.state.dispose);
      await tester.runAsync(() => h.state.addGroupRuleSet('g1', 'openai'));

      await tester.pumpWidget(SingBoxApp(state: h.state));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.alt_route_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rule sets'));
      await tester.pumpAndSettle();

      expect(find.text('openai'), findsOneWidget);
      expect(find.text('Downloaded'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.widgetWithText(ActionChip, 'netflix'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(h.state.policyGroup('g1')!.ruleSets,
          ['geosite:openai', 'geosite:netflix']);
      expect(tester.takeException(), isNull);
    });
  });
}
