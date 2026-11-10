import 'dart:async';
import 'dart:io';

import 'package:ferry/data/bounded_http.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ServerSocket server;
  late HttpClient client;
  late Uri uri;
  late Completer<void> disconnected;
  late List<Socket> sockets;
  late List<Timer> timers;

  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    uri = Uri.parse('http://127.0.0.1:${server.port}/download');
    disconnected = Completer<void>();
    sockets = [];
    timers = [];
  });

  tearDown(() async {
    client.close(force: true);
    for (final timer in timers) {
      timer.cancel();
    }
    for (final socket in sockets) {
      socket.destroy();
    }
    await server.close();
  });

  void serve(void Function(Socket) reply) {
    server.listen((socket) {
      sockets.add(socket);
      var replied = false;
      socket.listen(
          (_) {
            if (!replied) {
              replied = true;
              reply(socket);
            }
          },
          onError: (Object _) {},
          onDone: () {
            if (!disconnected.isCompleted) disconnected.complete();
          });
    });
  }

  Future<List<int>> download({int maxBytes = 64, int timeoutMs = 200}) =>
      getBoundedBytes(client, uri,
          timeout: Duration(milliseconds: timeoutMs), maxBytes: maxBytes);

  Future<void> expectDisconnected() =>
      disconnected.future.timeout(const Duration(seconds: 2));

  test('reads a successful bounded response', () async {
    serve((socket) =>
        socket.write('HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\nSRS'));
    expect(await download(), 'SRS'.codeUnits);
    await expectDisconnected();
  });

  test('rejects HTTP errors without waiting for their endless body', () async {
    serve((socket) => socket.write(
        'HTTP/1.1 503 Unavailable\r\nTransfer-Encoding: chunked\r\n\r\n'));
    await expectLater(download(), throwsA(isA<HttpException>()));
    await expectDisconnected();
  });

  test('rejects oversized Content-Length without waiting for a body', () async {
    serve((socket) =>
        socket.write('HTTP/1.1 200 OK\r\nContent-Length: 9999999\r\n\r\n'));
    await expectLater(download(), throwsFormatException);
    await expectDisconnected();
  });

  test('bounds chunked bodies even without Content-Length', () async {
    serve((socket) => socket.write('HTTP/1.1 200 OK\r\n'
        'Transfer-Encoding: chunked\r\n\r\n5\r\n12345\r\n'));
    await expectLater(download(maxBytes: 4), throwsFormatException);
    await expectDisconnected();
  });

  test('bounds the decompressed body, not just the compressed size', () async {
    final compressed = gzip.encode(List.filled(4096, 65));
    expect(compressed.length, lessThan(128));
    serve((socket) {
      socket.write('HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\n'
          'Content-Length: ${compressed.length}\r\n\r\n');
      socket.add(compressed);
    });
    await expectLater(download(maxBytes: 128), throwsFormatException);
    await expectDisconnected();
  });

  test('a body timeout closes the transport, not just the returned future',
      () async {
    serve((socket) => socket.write('HTTP/1.1 200 OK\r\n'
        'Transfer-Encoding: chunked\r\n\r\n1\r\nx\r\n'));
    await expectLater(download(), throwsA(isA<TimeoutException>()));
    await expectDisconnected();
  });

  test('an endless trickle cannot reset the overall deadline', () async {
    serve((socket) {
      socket.write('HTTP/1.1 200 OK\r\n'
          'Transfer-Encoding: chunked\r\n\r\n');
      timers.add(Timer.periodic(const Duration(milliseconds: 10), (_) {
        if (!disconnected.isCompleted) socket.write('1\r\nx\r\n');
      }));
    });
    await expectLater(
        download(maxBytes: 1024).timeout(const Duration(seconds: 2)),
        throwsA(isA<TimeoutException>()));
    await expectDisconnected();
  });

  test('a header timeout also aborts the transport', () async {
    serve((_) {});
    await expectLater(download(), throwsA(isA<TimeoutException>()));
    await expectDisconnected();
  });
}
