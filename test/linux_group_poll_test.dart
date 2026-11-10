import 'dart:async';
import 'dart:io';

import 'package:ferry/data/config_builder.dart';
import 'package:ferry/models/app_settings.dart';
import 'package:ferry/models/proxy_state.dart';
import 'package:ferry/platform/app_paths.dart';
import 'package:ferry/platform/clash_api.dart';
import 'package:ferry/platform/linux_proxy_controller.dart';
import 'package:ferry/platform/linux_system_proxy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _SlowClient extends ClashApiClient {
  _SlowClient() : super(port: 1, secret: 'test');
  final pending = <Completer<ProxyGroup?>>[];
  @override
  Future<String?> version({Duration? timeout}) async => '1.13.19';
  @override
  Future<ProxyGroup?> group(String tag) {
    final result = Completer<ProxyGroup?>();
    pending.add(result);
    return result.future;
  }

  @override
  Stream<ProxyTraffic> traffic({bool Function()? includeConnectionDetails}) =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('slow group polling is single flight and a new session is independent',
      () async {
    final dir = await Directory.systemTemp.createTemp('ferry-poll-');
    final executable = File('${dir.path}/sing-box');
    await executable.writeAsString(
        '#!/bin/sh\nif [ "\$1" = version ]; then echo "sing-box version 1.13.19"; exit 0; fi\nexec sleep 60\n');
    await Process.run('/usr/bin/chmod', ['700', executable.path]);
    const channel = MethodChannel(appControlChannel);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => dir.path);
    final clients = <_SlowClient>[];
    final runtime = LinuxProxyController(
      binaryOverride: executable.path,
      groupPollInterval: const Duration(milliseconds: 10),
      systemProxy: LinuxSystemProxy(
          stateDirectory: dir.path, backend: SystemProxyBackend.unsupported),
      clientFactory: ({required port, required secret}) {
        final client = _SlowClient();
        clients.add(client);
        return client;
      },
    );
    addTearDown(() async {
      await runtime.shutdown();
      for (final client in clients) {
        for (final request in client.pending) {
          if (!request.isCompleted) request.complete(null);
        }
      }
      messenger.setMockMethodCallHandler(channel, null);
      await dir.delete(recursive: true);
    });
    final config = ConfigBuilder.encode(ConfigBuilder.build(
      nodes: const [],
      selectedNodeId: null,
      settings: const AppSettings(),
      clashSecret: 'test',
      android: false,
      tunOnly: false,
    ));
    await runtime.start(config);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(clients.first.pending.length, 1);
    await runtime.stop();
    expect(await File('${dir.path}/config.json').exists(), isFalse);
    await runtime.start(config);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(clients.length, 2);
    expect(clients.last.pending.length, 1);
    clients.first.pending.single.complete(null);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(clients.last.pending.length, 1,
        reason: 'old completion must not clear the new session guard');
    clients.last.pending.single.complete(null);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(clients.last.pending.length, 2);
  }, skip: !Platform.isLinux);
}
