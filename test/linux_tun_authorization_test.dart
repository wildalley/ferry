import 'dart:async';
import 'dart:io';

import 'package:ferry/data/config_builder.dart';
import 'package:ferry/l10n/app_localizations_en.dart';
import 'package:ferry/l10n/app_localizations_zh.dart';
import 'package:ferry/models/app_settings.dart';
import 'package:ferry/models/proxy_state.dart';
import 'package:ferry/platform/app_paths.dart';
import 'package:ferry/platform/clash_api.dart';
import 'package:ferry/platform/linux_privileges.dart';
import 'package:ferry/platform/linux_proxy_controller.dart';
import 'package:ferry/platform/linux_system_proxy.dart';
import 'package:ferry/state/app_state.dart';
import 'package:ferry/ui/notice_text.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Privileges extends LinuxPrivileges {
  TunAuthorization inspection = TunAuthorization.required;
  TunAuthorization grant = TunAuthorization.granted;
  Completer<TunAuthorization>? pending;
  int checks = 0;
  int prompts = 0;

  @override
  Future<TunAuthorization> inspectTunCapabilities(String binary) async {
    checks++;
    return inspection;
  }

  @override
  Future<TunAuthorization> grantTunCapabilities(String binary) async {
    prompts++;
    return pending == null ? grant : await pending!.future;
  }
}

class _Client extends ClashApiClient {
  _Client() : super(port: 1, secret: 'test');
  @override
  Future<String?> version({Duration? timeout}) async => '1.14.4';
  @override
  Future<ProxyGroup?> group(String tag) async => null;
  @override
  Stream<ProxyTraffic> traffic({bool Function()? includeConnectionDetails}) =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const failures = {
    TunAuthorization.declined: EngineProblem.tunCancelled,
    TunAuthorization.missingTools: EngineProblem.tunToolsMissing,
    TunAuthorization.authenticationFailed:
        EngineProblem.tunAuthenticationFailed,
    TunAuthorization.unsafePath: EngineProblem.tunUnsafePath,
    TunAuthorization.nixosSetupRequired: EngineProblem.tunNixosSetup,
    TunAuthorization.checkFailed: EngineProblem.tunCapabilityCheckFailed,
    TunAuthorization.failed: EngineProblem.tunGrantFailed,
  };

  test('authorization recovery text is distinct in both languages', () {
    for (final l10n in [L10nEn(), L10nZh()]) {
      final messages = failures.values
          .map(
            (problem) => noticeText(l10n, AppState.noticeFor(problem.encode())),
          )
          .toSet();
      expect(messages.length, failures.length);
      expect(messages.every((message) => message.isNotEmpty), isTrue);
      expect(
        messages.any((message) => message.contains('sudo setcap')),
        isFalse,
      );
    }
  });

  group('TUN preflight', () {
    late Directory dir;
    late _Privileges privileges;
    late LinuxProxyController runtime;
    const channel = MethodChannel(appControlChannel);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('ferry-tun-test-');
      final executable = File('${dir.path}/sing-box');
      await executable.writeAsString(
        '#!/bin/sh\n'
        'if [ "\$1" = version ]; then echo "sing-box version 1.14.4"; exit 0; fi\n'
        'exec sleep 60\n',
      );
      await Process.run('/usr/bin/chmod', ['700', executable.path]);
      messenger.setMockMethodCallHandler(channel, (_) async => dir.path);
      privileges = _Privileges();
      runtime = LinuxProxyController(
        binaryOverride: executable.path,
        privileges: privileges,
        systemProxy: LinuxSystemProxy(
          stateDirectory: dir.path,
          backend: SystemProxyBackend.unsupported,
        ),
        clientFactory: ({required port, required secret}) => _Client(),
      );
    });
    tearDown(() async {
      await runtime.shutdown();
      messenger.setMockMethodCallHandler(channel, null);
      await dir.delete(recursive: true);
    });

    String config({bool tun = true}) => ConfigBuilder.encode(
      ConfigBuilder.build(
        nodes: const [],
        selectedNodeId: null,
        settings: AppSettings(
          proxyMode: tun ? ProxyMode.tun : ProxyMode.systemProxy,
        ),
        clashSecret: 'test',
        android: false,
        tunOnly: false,
      ),
    );

    for (final entry in failures.entries) {
      test(
        '${entry.key.name} prevents core startup and has a specific notice',
        () async {
          privileges.grant = entry.key;
          await runtime.start(config());
          expect(EngineProblem.of(runtime.currentState.message!), entry.value);
          expect(runtime.currentState.stage, ProxyStage.error);
          expect(privileges.prompts, 1);
          expect(File('${dir.path}/config.json').existsSync(), isFalse);
        },
      );
    }

    test('a failed preflight does not ask for authorization', () async {
      privileges.inspection = TunAuthorization.missingTools;
      await runtime.start(config());
      expect(privileges.prompts, 0);
      expect(
        EngineProblem.of(runtime.currentState.message!),
        EngineProblem.tunToolsMissing,
      );
    });

    test('existing capabilities skip the prompt', () async {
      privileges.inspection = TunAuthorization.granted;
      await runtime.start(config());
      expect(privileges.prompts, 0);
      expect(runtime.currentState.stage, ProxyStage.connected);
    });

    test('an accepted authorization proceeds to core startup', () async {
      await runtime.start(config());
      expect(privileges.prompts, 1);
      expect(runtime.currentState.stage, ProxyStage.connected);
    });

    test('system proxy mode never checks or requests capabilities', () async {
      privileges.inspection = TunAuthorization.missingTools;
      await runtime.start(config(tun: false));
      expect(privileges.checks, 0);
      expect(privileges.prompts, 0);
      expect(runtime.currentState.stage, ProxyStage.connected);
    });

    test('disposing during authorization ignores its late result', () async {
      privileges.pending = Completer<TunAuthorization>();
      final waiting = runtime.states.firstWhere(
        (s) => s.stage == ProxyStage.requestingPermission,
      );
      final start = runtime.start(config());
      await waiting.timeout(const Duration(seconds: 5));
      runtime.dispose();
      privileges.pending!.complete(TunAuthorization.granted);
      await start;
      expect(File('${dir.path}/config.json').existsSync(), isFalse);
    });
  }, skip: !Platform.isLinux);
}
