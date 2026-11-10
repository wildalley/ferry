/// Import pipelines: subscription URL, share links, sing-box JSON, and Clash /
/// mihomo YAML.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/node.dart';
import '../models/subscription.dart';
import '../version.dart';
import 'bounded_http.dart';
import 'clash_parser.dart';
import 'local_proxy.dart';
import 'share_link_parser.dart';

class ImportException implements Exception {
  ImportException(
    this.message, {
    this.failure = SubscriptionFailure.unusableContent,
    this.statusCode,
  });

  /// English, for the log and for `toString()`. Never shown to the user: the UI
  /// renders [failure] instead.
  final String message;

  /// What the UI reports, localized.
  final SubscriptionFailure failure;

  /// Set with [SubscriptionFailure.httpStatus].
  final int? statusCode;

  @override
  String toString() => message;
}

/// Outcome of any import: the nodes found plus how many entries were skipped.
class ImportResult {
  const ImportResult({
    required this.nodes,
    this.skipped = 0,
    this.subscriptionName,
    this.expiresAt,
    this.usedBytes,
    this.totalBytes,
  });

  final List<ProxyNode> nodes;
  final int skipped;

  /// Name advertised by the panel (`profile-title` header), if any.
  final String? subscriptionName;
  final DateTime? expiresAt;
  final int? usedBytes;
  final int? totalBytes;
}

class Importer {
  Importer({HttpClient? httpClient}) : _sharedClient = httpClient;

  /// A supplied client is retained for callers that need to inject a transport
  /// in tests. The normal path creates one client per fetch, because
  /// [HttpClient.findProxy] is mutable and tunnel/direct fallback must not race
  /// when two sources are refreshed at once.
  final HttpClient? _sharedClient;
  final _activeClients = <HttpClient>{};
  final _fetchWaiters = Queue<Completer<void>>();
  Future<void> _sharedClientTail = Future<void>.value();
  var _disposed = false;
  var _activeFetches = 0;

  static const _timeout = Duration(seconds: 20);
  static const _maxResponseBytes = 4 * 1024 * 1024;
  static const _maxConcurrentFetches = 3;

  /// Sent when a subscription has no User-Agent of its own.
  static const defaultUserAgent = 'sing-box; SingBoxClient/$appVersion';

  /// Detects the format of pasted [text] and imports it.
  ///
  /// Handles a subscription URL, one or more share links, a sing-box JSON
  /// config, and base64-wrapped link lists. [viaLocalProxy] applies only to the
  /// URL case; see [fetchSubscription].
  Future<ImportResult> importText(
    String text, {
    String? subscriptionId,
    bool viaLocalProxy = false,
    int? localProxyPort,
    String? localProxySecret,
  }) async {
    _checkInputSize(text);
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ImportException(
        'Nothing to import',
        failure: SubscriptionFailure.badSource,
      );
    }

    // A bare http(s) URL is a subscription, not an http:// proxy share link:
    // share links carry credentials or a fragment, subscriptions do not.
    if (_looksLikeSubscriptionUrl(trimmed)) {
      return fetchSubscription(
        trimmed,
        subscriptionId: subscriptionId,
        viaLocalProxy: viaLocalProxy,
        localProxyPort: localProxyPort,
        localProxySecret: localProxySecret,
      );
    }

    return _parsePayload(trimmed, subscriptionId);
  }

  /// Parses one or many share links, transparently unwrapping a base64 blob.
  ImportResult importShareLinks(String text, {String? subscriptionId}) {
    final payload = _maybeDecodeBase64List(text.trim());
    final parsed =
        ShareLinkParser.parseMany(payload, subscriptionId: subscriptionId);
    if (parsed.nodes.isEmpty) {
      throw ImportException(
        parsed.skipped > 0
            ? 'No supported links found (${parsed.skipped} unrecognised)'
            : 'No supported links found',
      );
    }
    return ImportResult(nodes: parsed.nodes, skipped: parsed.skipped);
  }

  /// Extracts usable outbounds from a full or partial sing-box config.
  ///
  /// Accepts a whole config object, a bare `outbounds` array, or a single
  /// outbound object.
  ImportResult importSingBoxConfig(String text, {String? subscriptionId}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on Object {
      throw ImportException(
        'Invalid JSON',
        failure: SubscriptionFailure.badSource,
      );
    }

    final List<dynamic> outbounds;
    switch (decoded) {
      case Map map when map['outbounds'] is List:
        outbounds = map['outbounds'] as List;
      case Map map when map['type'] != null:
        outbounds = [map];
      case List list:
        outbounds = list;
      default:
        throw ImportException('No outbounds found in config');
    }

    final nodes = <ProxyNode>[];
    var skipped = 0;
    for (final entry in outbounds) {
      if (entry is! Map) {
        skipped++;
        continue;
      }
      final node = _nodeFromOutbound(
        Map<String, dynamic>.from(entry),
        subscriptionId: subscriptionId,
      );
      if (node == null) {
        skipped++;
      } else {
        nodes.add(node);
      }
    }

    if (nodes.isEmpty) {
      throw ImportException('No usable proxy outbounds in config');
    }
    return ImportResult(nodes: nodes, skipped: skipped);
  }

  /// Reads the `proxies:` list of a Clash / mihomo YAML config.
  ImportResult importClashConfig(String text, {String? subscriptionId}) {
    final ({List<ProxyNode> nodes, int skipped}) parsed;
    try {
      parsed = ClashParser.parse(text, subscriptionId: subscriptionId);
    } on FormatException catch (error) {
      throw ImportException(
        'Invalid Clash config: ${error.message}',
        failure: SubscriptionFailure.badSource,
      );
    }
    if (parsed.nodes.isEmpty) {
      throw ImportException(
        parsed.skipped > 0
            ? 'No supported proxies in Clash config (${parsed.skipped} unsupported)'
            : 'No proxies in Clash config',
      );
    }
    return ImportResult(nodes: parsed.nodes, skipped: parsed.skipped);
  }

  /// Reads a config or link-list file from disk.
  Future<ImportResult> importFile(String path, {String? subscriptionId}) async {
    final file = File(path);
    if (!await file.exists()) {
      throw ImportException(
        'File not found: $path',
        failure: SubscriptionFailure.badSource,
      );
    }
    if (await file.length() > _maxResponseBytes) _tooLarge();
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.openRead()) {
      if (chunk.length > _maxResponseBytes - bytes.length) _tooLarge();
      bytes.add(chunk);
    }
    final content = utf8.decode(bytes.takeBytes());
    return importText(content, subscriptionId: subscriptionId);
  }

  /// Fetches a subscription URL and parses its body.
  ///
  /// Panels return a base64 link list, a sing-box JSON config or a Clash YAML
  /// config, and
  /// advertise quota/expiry through `subscription-userinfo`.
  ///
  /// With [viaLocalProxy] the tunnel is tried first and the direct path second.
  /// Both attempts are needed: the app is excluded from the VPN (see
  /// `local_proxy.dart`), so a blocked panel is unreachable while connected
  /// unless the request goes through the loopback inbound — while a panel that
  /// refuses proxied clients only answers on the direct path, which is the one
  /// every refresh used before this. Falling back does re-expose the URL to the
  /// local network, which is why the tunnel goes first.
  Future<ImportResult> fetchSubscription(
    String url, {
    String? subscriptionId,
    bool viaLocalProxy = false,
    int? localProxyPort,
    String? localProxySecret,
    String? userAgent,
  }) async {
    final Uri uri;
    try {
      uri = Uri.parse(url);
    } on Object {
      throw ImportException(
        'Invalid subscription URL',
        failure: SubscriptionFailure.badSource,
      );
    }
    if (!uri.isScheme('http') && !uri.isScheme('https')) {
      throw ImportException(
        'Subscription URL must be http or https',
        failure: SubscriptionFailure.badSource,
      );
    }

    // The tunnel first, the direct path second.
    final paths = viaLocalProxy ? const [true, false] : const [false];
    ImportException? unreachable;
    for (final throughTunnel in paths) {
      try {
        return await _fetchOnce(
          uri,
          subscriptionId: subscriptionId,
          viaLocalProxy: throughTunnel,
          localProxyPort: localProxyPort,
          localProxySecret: localProxySecret,
          userAgent: userAgent,
        );
      } on ImportException catch (error) {
        // Only a transport failure is worth the other path. A status code or an
        // unusable body is the panel's own answer, and it would say the same
        // thing again.
        if (error.failure != SubscriptionFailure.unreachable &&
            error.failure != SubscriptionFailure.timeout) {
          rethrow;
        }
        unreachable = error;
      }
    }
    throw unreachable!;
  }

  Future<ImportResult> _fetchOnce(
    Uri uri, {
    String? subscriptionId,
    required bool viaLocalProxy,
    int? localProxyPort,
    String? localProxySecret,
    String? userAgent,
  }) async {
    if (_disposed) {
      throw StateError('Importer is disposed');
    }
    await _acquireFetchSlot();
    try {
      if (_disposed) throw StateError('Importer is disposed');
      final shared = _sharedClient;
      if (shared != null) {
        return await _serializeSharedFetch(
          () => _fetchOnceWithClient(
            shared,
            uri,
            subscriptionId: subscriptionId,
            viaLocalProxy: viaLocalProxy,
            localProxyPort: localProxyPort,
            localProxySecret: localProxySecret,
            userAgent: userAgent,
          ),
        );
      }
      return await _fetchOnceWithClient(
        HttpClient()
          ..connectionTimeout = _timeout
          ..idleTimeout = _timeout,
        uri,
        subscriptionId: subscriptionId,
        viaLocalProxy: viaLocalProxy,
        localProxyPort: localProxyPort,
        localProxySecret: localProxySecret,
        userAgent: userAgent,
        closeClient: true,
      );
    } finally {
      _releaseFetchSlot();
    }
  }

  Future<void> _acquireFetchSlot() {
    if (_disposed) return Future.error(StateError('Importer is disposed'));
    if (_activeFetches < _maxConcurrentFetches) {
      _activeFetches++;
      return Future<void>.value();
    }
    final waiter = Completer<void>();
    _fetchWaiters.add(waiter);
    return waiter.future;
  }

  void _releaseFetchSlot() {
    while (_fetchWaiters.isNotEmpty) {
      final waiter = _fetchWaiters.removeFirst();
      if (waiter.isCompleted) continue;
      // Transfer the slot directly. The active count remains unchanged until
      // that waiter finishes, so a burst cannot exceed the configured bound.
      waiter.complete();
      return;
    }
    _activeFetches--;
  }

  Future<ImportResult> _serializeSharedFetch(
    Future<ImportResult> Function() operation,
  ) {
    final previous = _sharedClientTail;
    final result = previous.then((_) => operation());
    _sharedClientTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  Future<ImportResult> _fetchOnceWithClient(
    HttpClient client,
    Uri uri, {
    String? subscriptionId,
    required bool viaLocalProxy,
    int? localProxyPort,
    String? localProxySecret,
    String? userAgent,
    bool closeClient = false,
  }) async {
    if (closeClient) _activeClients.add(client);
    try {
      routeHttp(
        client,
        viaLocalProxy: viaLocalProxy,
        localProxyPort: localProxyPort,
        localProxySecret: localProxySecret,
      );

      late HttpClientResponse response;
      String body;
      try {
        body = utf8.decode(await getBoundedBytes(
          client,
          uri,
          timeout: _timeout,
          maxBytes: _maxResponseBytes,
          headers: {
            HttpHeaders.userAgentHeader: switch (userAgent?.trim()) {
              final String value when value.isNotEmpty => value,
              _ => defaultUserAgent,
            }
          },
          onResponse: (value) => response = value,
        ));
      } on HttpBodyTooLarge {
        _tooLarge();
      } on HttpStatusException catch (error) {
        throw ImportException('Subscription returned HTTP ${error.statusCode}',
            failure: SubscriptionFailure.httpStatus,
            statusCode: error.statusCode);
      } on TimeoutException catch (error) {
        throw ImportException(
          'Subscription fetch timed out: ${_redact(error)}',
          failure: SubscriptionFailure.timeout,
        );
      } on FormatException {
        throw ImportException(
          'Subscription response is not valid UTF-8',
          failure: SubscriptionFailure.unusableContent,
        );
      } on Object catch (error) {
        // Never surface the URL itself: it usually carries the token.
        throw ImportException(
          'Subscription fetch failed: ${_redact(error)}',
          failure: SubscriptionFailure.unreachable,
        );
      }

      final base = await _parsePayload(body, subscriptionId);

      final info =
          _parseUserInfo(response.headers.value('subscription-userinfo'));
      final title = _decodeHeaderTitle(response.headers.value('profile-title'));
      return ImportResult(
        nodes: base.nodes,
        skipped: base.skipped,
        subscriptionName: title,
        expiresAt: info.expiresAt,
        usedBytes: info.usedBytes,
        totalBytes: info.totalBytes,
      );
    } finally {
      if (closeClient) {
        _activeClients.remove(client);
        client.close(force: true);
      }
    }
  }

  static Never _tooLarge() => throw ImportException('Import exceeds 4 MiB',
      failure: SubscriptionFailure.responseTooLarge);

  static void _checkInputSize(String text) {
    if (text.length > _maxResponseBytes ||
        utf8.encode(text).length > _maxResponseBytes) {
      _tooLarge();
    }
  }

  static Future<ImportResult> _parsePayload(String text, String? id) {
    // A static closure captures only the payload, never HttpClient or the UI.
    if (text.length >= 64 * 1024) {
      return Isolate.run(() => _parsePayloadSync(text, id));
    }
    return Future.value(_parsePayloadSync(text, id));
  }

  static ImportResult _parsePayloadSync(String text, String? id) {
    final parser = Importer();
    final trimmed = text.trim();
    if (_looksLikeJson(trimmed)) {
      return parser.importSingBoxConfig(trimmed, subscriptionId: id);
    }
    if (ClashParser.looksLikeClash(trimmed)) {
      return parser.importClashConfig(trimmed, subscriptionId: id);
    }
    return parser.importShareLinks(trimmed, subscriptionId: id);
  }

  /// Re-fetches [subscription] and returns the refreshed nodes and metadata.
  Future<({Subscription subscription, List<ProxyNode> nodes})> refresh(
    Subscription subscription, {
    bool viaLocalProxy = false,
    int? localProxyPort,
    String? localProxySecret,
  }) async {
    final url = subscription.url;
    if (url == null || url.isEmpty) {
      throw ImportException(
        'This subscription has no URL to refresh',
        failure: SubscriptionFailure.badSource,
      );
    }
    final result = await fetchSubscription(
      url,
      subscriptionId: subscription.id,
      viaLocalProxy: viaLocalProxy,
      localProxyPort: localProxyPort,
      localProxySecret: localProxySecret,
      userAgent: subscription.userAgent,
    );
    return (
      subscription: subscription.copyWith(
        // A name the user typed outranks the panel's `profile-title`.
        name: !subscription.nameLocked &&
                result.subscriptionName?.isNotEmpty == true
            ? result.subscriptionName
            : null,
        updatedAt: DateTime.now(),
        nodeCount: result.nodes.length,
        expiresAt: result.expiresAt,
        usedBytes: result.usedBytes,
        totalBytes: result.totalBytes,
        clearFailure: true,
      ),
      nodes: result.nodes,
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    while (_fetchWaiters.isNotEmpty) {
      final waiter = _fetchWaiters.removeFirst();
      if (!waiter.isCompleted) {
        waiter.completeError(StateError('Importer is disposed'));
      }
    }
    _sharedClient?.close(force: true);
    for (final client in _activeClients) {
      client.close(force: true);
    }
    _activeClients.clear();
  }

  // -------------------------------------------------------------- helpers

  /// Converts a sing-box outbound object into a node, or null when the entry
  /// is a selector/urltest/direct/block pseudo-outbound rather than a server.
  static ProxyNode? _nodeFromOutbound(
    Map<String, dynamic> outbound, {
    String? subscriptionId,
  }) {
    final type = (outbound['type'] ?? '').toString().toLowerCase();
    const skipTypes = {
      'selector',
      'urltest',
      'direct',
      'block',
      'dns',
      '', // untyped
    };
    if (skipTypes.contains(type)) return null;

    final protocol = NodeProtocol.fromTag(type);
    if (protocol == NodeProtocol.unknown) return null;

    final server = (outbound['server'] ?? '').toString();
    final port = switch (outbound['server_port']) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value) ?? 0,
      _ => 0,
    };
    if (server.isEmpty || port == 0) return null;

    final tag = (outbound['tag'] ?? '').toString();
    final raw = Map<String, dynamic>.from(outbound)
      ..remove('type')
      ..remove('tag')
      ..remove('server')
      ..remove('server_port');

    return ProxyNode(
      id: _outboundId(type, server, port, tag),
      name: tag.isNotEmpty ? tag : '$server:$port',
      protocol: protocol,
      server: server,
      serverPort: port,
      raw: raw,
      subscriptionId: subscriptionId,
    );
  }

  static String _outboundId(String type, String server, int port, String tag) {
    var hash = 0x811c9dc5;
    for (final unit in '$type|$server|$port|$tag'.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static bool _looksLikeJson(String text) =>
      text.startsWith('{') || text.startsWith('[');

  /// True for a plain http(s) URL with no credentials and no fragment, which
  /// distinguishes a subscription from an `http://user:pass@host` share link.
  static bool _looksLikeSubscriptionUrl(String text) {
    if (text.contains('\n')) return false;
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      return false;
    }
    final uri = Uri.tryParse(text);
    if (uri == null) return false;
    return uri.userInfo.isEmpty && uri.fragment.isEmpty;
  }

  /// Subscription bodies are usually base64 of a newline-separated link list.
  static String _maybeDecodeBase64List(String text) {
    if (text.contains('://')) return text;
    final compact = text.replaceAll(RegExp(r'\s'), '');
    if (compact.isEmpty) return text;
    if (!RegExp(r'^[A-Za-z0-9+/\-_=]+$').hasMatch(compact)) return text;
    try {
      var value = compact.replaceAll('-', '+').replaceAll('_', '/');
      final remainder = value.length % 4;
      if (remainder > 0) {
        value = value.padRight(value.length + 4 - remainder, '=');
      }
      final decoded = utf8.decode(base64.decode(value));
      return decoded.contains('://') ? decoded : text;
    } on Object {
      return text;
    }
  }

  /// Parses `upload=1; download=2; total=3; expire=1700000000`.
  static ({DateTime? expiresAt, int? usedBytes, int? totalBytes})
      _parseUserInfo(String? header) {
    if (header == null || header.isEmpty) {
      return (expiresAt: null, usedBytes: null, totalBytes: null);
    }
    int? upload;
    int? download;
    int? total;
    DateTime? expire;
    for (final part in header.split(';')) {
      final pair = part.split('=');
      if (pair.length != 2) continue;
      final key = pair[0].trim().toLowerCase();
      final value = int.tryParse(pair[1].trim());
      if (value == null) continue;
      switch (key) {
        case 'upload':
          upload = value;
        case 'download':
          download = value;
        case 'total':
          total = value;
        case 'expire':
          if (value > 0) {
            expire = DateTime.fromMillisecondsSinceEpoch(value * 1000);
          }
      }
    }
    final used = (upload ?? 0) + (download ?? 0);
    return (
      expiresAt: expire,
      usedBytes: used > 0 ? used : null,
      totalBytes: total,
    );
  }

  /// `profile-title` may be `base64:<payload>` for non-ASCII names.
  static String? _decodeHeaderTitle(String? header) {
    if (header == null || header.isEmpty) return null;
    if (!header.startsWith('base64:')) return header;
    try {
      var value = header.substring('base64:'.length);
      final remainder = value.length % 4;
      if (remainder > 0) {
        value = value.padRight(value.length + 4 - remainder, '=');
      }
      return utf8.decode(base64.decode(value));
    } on Object {
      return null;
    }
  }

  /// Strips anything URL-shaped from an error before it reaches the UI.
  static String _redact(Object error) {
    final message = error.toString();
    return message.replaceAll(RegExp(r'https?://\S+'), '<url>');
  }
}
