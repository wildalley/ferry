/// Client for the Clash-compatible API sing-box exposes.
///
/// This is the desktop counterpart to libbox's `CommandClient`. On Android the
/// engine runs in-process and reports over a JNI command socket; a supervised
/// `sing-box` binary offers no such thing, but the config already asks it for
/// `experimental.clash_api`, so the same three jobs — read the groups, switch
/// the selector, URL-test the members — go over HTTP on loopback instead.
///
/// What the two do not share is push. libbox streams group updates; the Clash
/// API answers requests and streams only counters, so the caller polls
/// [group]. Traffic is the mirror image: three separate sockets, no single
/// snapshot, which is why [traffic] merges them here rather than leaving the
/// controller to hold three sets of partial numbers.
///
/// Every request carries the config's `secret`. It is not decoration: the
/// controller can switch outbounds and read the node list, so an unauthenticated
/// listener on 127.0.0.1 would hand that to anything else on the machine.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/proxy_state.dart';

/// A live JSON feed and the way to shut it down.
typedef ClashSocket = ({
  Stream<Object?> frames,
  Future<void> Function() close,
});

/// Opens one of the API's WebSocket endpoints. Injectable for tests.
typedef ClashSocketConnector = Future<ClashSocket> Function(
  Uri uri,
  Map<String, String> headers,
);

class ClashApiClient {
  ClashApiClient({
    required this.port,
    required this.secret,
    this.host = '127.0.0.1',
    this.requestTimeout = const Duration(seconds: 8),
    this.webSocketTimeout = const Duration(seconds: 8),
    this.maxResponseBytes = 8 * 1024 * 1024,
    http.Client? client,
    ClashSocketConnector? connector,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _connect = connector ?? _openWebSocket;

  final int port;
  final String secret;
  final String host;

  /// Bounds the complete HTTP request, including its response body.
  final Duration requestTimeout;

  /// Bounds WebSocket connection and close operations during engine churn.
  final Duration webSocketTimeout;
  final int maxResponseBytes;
  final _pendingRequests = <Completer<void>>{};
  bool _disposed = false;

  final http.Client _client;
  final bool _ownsClient;
  final ClashSocketConnector _connect;

  /// The same target the `urltest` outbound uses, so a manual test and the
  /// engine's own periodic one measure the same thing.
  static const testUrl = 'https://www.gstatic.com/generate_204';

  Map<String, String> get _headers => {
        if (secret.isNotEmpty) 'Authorization': 'Bearer $secret',
      };

  Uri _uri(String path, [Map<String, String>? query]) => Uri(
        scheme: 'http',
        host: host,
        port: port,
        path: path,
        queryParameters: query,
      );

  /// The engine's version string, or null when nothing answers.
  ///
  /// Doubles as the readiness probe: the API starts listening as part of
  /// `sing-box run` coming up, so the first successful call is the earliest
  /// moment the engine is actually able to carry traffic.
  Future<String?> version({Duration? timeout}) async {
    final body = await _get('/version', timeout: timeout);
    if (body == null) return null;
    final value = body['version'];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// Every proxy the engine knows, keyed by name.
  Future<Map<String, Map<String, Object?>>> proxies() async {
    final body = await _get('/proxies');
    final proxies = body?['proxies'];
    if (proxies is! Map) return const {};
    return {
      for (final entry in proxies.entries)
        if (entry.value is Map)
          entry.key.toString(): Map<String, Object?>.from(
            entry.value as Map,
          ),
    };
  }

  /// One group as a [ProxyGroup], or null when [tag] is not a group.
  ///
  /// Member delays come from each proxy's own `history`, which is where the
  /// engine records both its periodic `urltest` results and anything [delay]
  /// measured. A member with no history reports 0 — libbox's "no result" — so
  /// the UI cannot mistake an untested node for an instant one.
  Future<ProxyGroup?> group(String tag) async {
    final all = await proxies();
    return groupFrom(all, tag);
  }

  /// Folds an already-fetched [proxies] map into a group. Separate so a caller
  /// reading several groups pays for one request.
  static ProxyGroup? groupFrom(
    Map<String, Map<String, Object?>> proxies,
    String tag,
  ) {
    final self = proxies[tag];
    if (self == null) return null;
    final members = self['all'];
    if (members is! List) return null;
    final delays = <String, int>{};
    for (final member in members) {
      final name = member?.toString();
      if (name == null || name.isEmpty) continue;
      delays[name] = _lastDelay(proxies[name]);
    }
    return ProxyGroup(
      tag: tag,
      selected: (self['now'] ?? '').toString(),
      delays: delays,
    );
  }

  /// Points [group] at [member]. Throws on refusal, so the caller can report a
  /// failed switch instead of showing one that did not happen.
  Future<void> select(String group, String member) async {
    final response = await _request(
      'PUT',
      _uri('/proxies/${Uri.encodeComponent(group)}'),
      body: jsonEncode({'name': member}),
    );
    if (response.statusCode ~/ 100 != 2) {
      throw ClashApiException(
        'select $member: HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  /// URL-tests one proxy, in milliseconds. 0 means it did not answer — a
  /// timeout, a refused connection, or a non-2xx from the test URL — matching
  /// [ProxyGroup.delays]'s "no result" so both paths read the same.
  Future<int> delay(
    String name, {
    Duration timeout = const Duration(seconds: 5),
    String url = testUrl,
  }) async {
    final body = await _get(
      '/proxies/${Uri.encodeComponent(name)}/delay',
      query: {'url': url, 'timeout': '${timeout.inMilliseconds}'},
    );
    final value = body?['delay'];
    return value is num ? value.toInt() : 0;
  }

  /// URL-tests every member of [group] in one request, in milliseconds.
  ///
  /// `/group/{name}/delay` is a Clash.Meta endpoint, and sing-box does serve it
  /// — verified against a running 1.14.0, and present in
  /// `experimental/clashapi/api_meta_group.go` since 1.12, which is this app's
  /// minimum. A comment here used to claim the opposite and the Linux runtime
  /// tested members one at a time because of it; Windows called this endpoint all
  /// along. One of the two had to be wrong, and it was the comment.
  ///
  /// The engine omits members it could not reach rather than reporting them as 0,
  /// so a missing key means "no result" — the same thing [delay] returns 0 for.
  /// Callers merging this into a [ProxyGroup] should keep their previous reading
  /// for an absent member instead of overwriting it with a zero.
  ///
  /// Returns null when the request itself did not succeed: [group] is not a group
  /// (404), the engine could not finish inside [timeout] (504), or nothing
  /// answered. That is distinct from an empty map, which means the test ran and
  /// no member came back.
  ///
  /// Two engine-side quirks worth knowing. A `urltest` group ignores [url] and
  /// uses the one from its own config, since the group performs its own test. And
  /// an `http://` [url] is discarded by the engine — it only probes HTTPS — so
  /// the default is left as [testUrl].
  Future<Map<String, int>?> groupDelay(
    String group, {
    Duration timeout = const Duration(seconds: 10),
    String url = testUrl,
  }) async {
    final body = await _get(
      '/group/${Uri.encodeComponent(group)}/delay',
      // Not optional: the engine parses this parameter and answers 400 when it
      // is missing or unparseable.
      query: {'url': url, 'timeout': '${timeout.inMilliseconds}'},
      // The whole group is tested behind this one request, so the HTTP call has
      // to outlive the test the engine is running. The default request timeout is
      // shorter than the test it would be waiting on.
      timeout: timeout + const Duration(seconds: 5),
    );
    if (body == null) return null;
    // A 504 carries `{"message": ...}` rather than delays; treating that as an
    // empty result would report every member unreachable.
    if (body['message'] != null) return null;
    return {
      for (final entry in body.entries)
        if (entry.value case final num delay when delay > 0)
          entry.key: delay.toInt(),
    };
  }

  /// Merged counters, as one [ProxyTraffic] per update.
  ///
  /// The API splits what the UI shows across three endpoints: `/traffic` has
  /// the per-second rates and no totals, `/connections` the totals and the open
  /// connection count, `/memory` the resident figure. Each socket pushes about
  /// once a second on its own schedule, so the last value from each is held and
  /// a full snapshot goes out whenever any of them moves.
  ///
  /// Cancelling the subscription closes all three sockets.
  Stream<ProxyTraffic> traffic({bool Function()? includeConnectionDetails}) {
    var up = 0, down = 0, upTotal = 0, downTotal = 0, count = 0, memory = 0;
    var list = const <ProxyConnection>[];
    late StreamController<ProxyTraffic> controller;
    final sockets = <ClashSocket>[];
    final subscriptions = <StreamSubscription<Object?>>[];
    var cancelled = false;

    void push() {
      if (cancelled) return;
      controller.add(ProxyTraffic(
        uplink: up,
        downlink: down,
        uplinkTotal: upTotal,
        downlinkTotal: downTotal,
        // The Clash API counts connections without a direction; the UI's two
        // slots come from libbox. Reporting the same number in both would
        // read as twice the connections, so only inbound is filled.
        connectionsIn: count,
        memory: memory,
        connectionList: list,
      ));
    }

    Future<void> closeSocket(ClashSocket socket) async {
      try {
        await socket.close().timeout(webSocketTimeout);
      } on Object {
        // The engine may already be gone or refuse the close handshake.
      }
    }

    Future<ClashSocket> connect(String path) {
      var abandoned = false;
      // Future.timeout does not cancel the handshake. Reclaim a socket that
      // arrives after its caller has timed out, including after cancellation.
      return _connect(_uri(path), _headers).then((socket) {
        if (abandoned) unawaited(closeSocket(socket));
        return socket;
      }).timeout(webSocketTimeout, onTimeout: () {
        abandoned = true;
        throw TimeoutException('control WebSocket timed out');
      });
    }

    Future<void> open() async {
      for (final (path, handler)
          in <(String, void Function(Map<String, Object?>))>[
        (
          '/traffic',
          (frame) {
            up = _int(frame['up']);
            down = _int(frame['down']);
          }
        ),
        (
          '/connections',
          (frame) {
            upTotal = _int(frame['uploadTotal']);
            downTotal = _int(frame['downloadTotal']);
            final connections = frame['connections'];
            count = connections is List ? connections.length : 0;
            list = (includeConnectionDetails?.call() ?? true)
                ? parseConnections(connections)
                : const [];
            // Present on sing-box, absent on some Clash implementations; the
            // /memory socket below is the primary source either way.
            final inline = _int(frame['memory']);
            if (inline > 0) memory = inline;
          }
        ),
        ('/memory', (frame) => memory = _int(frame['inuse'])),
      ]) {
        if (cancelled) break;
        final socket = await connect(path);
        if (cancelled) {
          await closeSocket(socket);
          break;
        }
        sockets.add(socket);
        subscriptions.add(socket.frames.listen(
          (frame) {
            if (cancelled ||
                (frame is String && frame.length > maxResponseBytes)) {
              return;
            }
            final decoded = _decode(frame);
            if (decoded == null) return;
            handler(decoded);
            push();
          },
          // One endpoint going away should not take the other two with it:
          // the engine closing /memory still leaves rates worth showing.
          onError: (Object _) {},
          cancelOnError: false,
        ));
      }
    }

    Future<void> shut() async {
      cancelled = true;
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      subscriptions.clear();
      for (final socket in sockets) {
        await closeSocket(socket);
      }
      sockets.clear();
    }

    controller = StreamController<ProxyTraffic>(
      onListen: () => open().onError((error, _) {
        if (!cancelled && !controller.isClosed) {
          controller.addError(error ?? 'socket failed');
        }
      }),
      onCancel: shut,
    );
    return controller.stream;
  }

  Future<Map<String, Object?>?> _get(
    String path, {
    Map<String, String>? query,
    Duration? timeout,
  }) async {
    try {
      final response =
          await _request('GET', _uri(path, query), timeout: timeout);
      if (response.statusCode ~/ 100 != 2) return null;
      final decoded = jsonDecode(response.body);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on Object {
      // Not listening yet, gone, or answering with something that is not JSON.
      // Every caller has a meaningful answer for "no data", so none of them
      // benefits from an exception here.
      return null;
    }
  }

  Future<http.Response> _request(
    String method,
    Uri uri, {
    String? body,
    Duration? timeout,
  }) async {
    if (_disposed) throw StateError('Clash client is disposed');
    final abort = Completer<void>();
    _pendingRequests.add(abort);
    final watch = Stopwatch()..start();
    final budget = timeout ?? requestTimeout;
    Duration remaining() {
      final duration = budget - watch.elapsed;
      if (duration <= Duration.zero) {
        throw TimeoutException('Control HTTP timed out');
      }
      return duration;
    }

    final request =
        http.AbortableRequest(method, uri, abortTrigger: abort.future)
          ..headers.addAll(_headers);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = body;
    }
    StreamIterator<List<int>>? stream;
    var finished = false;
    try {
      final response = await _client.send(request).then((response) {
        if (finished) response.stream.listen(null).cancel().ignore();
        return response;
      }).timeout(remaining());
      if (response.statusCode ~/ 100 != 2 ||
          (response.contentLength ?? 0) > maxResponseBytes) {
        response.stream.listen(null).cancel().ignore();
        if (response.statusCode ~/ 100 != 2) {
          return http.Response('', response.statusCode);
        }
        throw const FormatException('Control response too large');
      }
      final bytes = BytesBuilder(copy: false);
      stream = StreamIterator(response.stream);
      while (await stream.moveNext().timeout(remaining())) {
        if (stream.current.length > maxResponseBytes - bytes.length) {
          throw const FormatException('Control response too large');
        }
        bytes.add(stream.current);
      }
      return http.Response.bytes(bytes.takeBytes(), response.statusCode,
          headers: response.headers);
    } finally {
      finished = true;
      if (!abort.isCompleted) abort.complete();
      _pendingRequests.remove(abort);
      await stream?.cancel();
    }
  }

  /// Releases the HTTP client, when this object made it.
  void dispose() {
    _disposed = true;
    for (final abort in _pendingRequests) {
      if (!abort.isCompleted) abort.complete();
    }
    if (_ownsClient) _client.close();
  }

  static int _lastDelay(Map<String, Object?>? proxy) {
    final history = proxy?['history'];
    if (history is! List || history.isEmpty) return 0;
    final last = history.last;
    return last is Map ? _int(last['delay']) : 0;
  }

  static Map<String, Object?>? _decode(Object? frame) {
    if (frame is! String) return null;
    try {
      final decoded = jsonDecode(frame);
      return decoded is Map ? Map<String, Object?>.from(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  static int _int(Object? value) => value is num ? value.toInt() : 0;

  /// The `connections` array of a `/connections` frame, minus anything that is
  /// not shaped like a connection.
  static List<ProxyConnection> parseConnections(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        ?ProxyConnection.fromClash(item),
    ];
  }

  static Future<ClashSocket> _openWebSocket(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final socket = await WebSocket.connect(
      uri.replace(scheme: 'ws').toString(),
      headers: headers,
    );
    return (frames: socket, close: socket.close);
  }
}

class ClashApiException implements Exception {
  const ClashApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'ClashApiException: $message';
}
