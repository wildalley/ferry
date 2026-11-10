import 'dart:async';
import 'dart:io';

import 'package:ferry/platform/clash_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  late ServerSocket server;
  late ClashApiClient api;
  late http.Client transport;
  late Completer<void> disconnected;
  late List<Socket> sockets;
  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    transport = http.Client();
    api = ClashApiClient(
        port: server.port,
        secret: 'secret',
        client: transport,
        requestTimeout: const Duration(milliseconds: 200),
        maxResponseBytes: 64);
    disconnected = Completer<void>();
    sockets = [];
  });
  tearDown(() async {
    api.dispose();
    transport.close();
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close();
  });
  void serve(String? reply) {
    server.listen((socket) {
      sockets.add(socket);
      var replied = false;
      socket.listen(
          (_) {
            if (!replied) {
              replied = true;
              if (reply != null) socket.write(reply);
            }
          },
          onError: (Object _) {},
          onDone: () {
            if (!disconnected.isCompleted) disconnected.complete();
          });
    });
  }

  Future<void> closed() =>
      disconnected.future.timeout(const Duration(seconds: 2));

  test('header timeout aborts even an injected shared transport', () async {
    serve(null);
    expect(await api.version(), isNull);
    await closed();
  });
  test('body timeout cancels the response stream', () async {
    serve('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n1\r\nx\r\n');
    expect(await api.version(), isNull);
    await closed();
  });
  test('chunked body cannot exceed its byte budget', () async {
    serve(
        'HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n41\r\n${'x' * 65}\r\n');
    expect(await api.version(), isNull);
    await closed();
  });
  test('Content-Length is checked before waiting for a body', () async {
    serve('HTTP/1.1 200 OK\r\nContent-Length: 10000\r\n\r\n');
    expect(await api.version(), isNull);
    await closed();
  });
  test('failed PUT does not drain an endless error response', () async {
    serve('HTTP/1.1 403 Forbidden\r\nTransfer-Encoding: chunked\r\n\r\n');
    await expectLater(
        api.select('proxy', 'node'), throwsA(isA<ClashApiException>()));
    await closed();
  });
  test('dispose aborts a pending shared request before its timeout', () async {
    serve(null);
    final pending = api.version(timeout: const Duration(seconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    api.dispose();
    expect(await pending.timeout(const Duration(seconds: 2)), isNull);
    await closed();
  });
}
