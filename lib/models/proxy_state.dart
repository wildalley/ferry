/// Runtime state reported by the platform proxy controller.
library;

enum ProxyStage {
  disconnected,
  requestingPermission,
  starting,
  connected,
  stopping,
  error;

  bool get isBusy =>
      this == ProxyStage.starting ||
      this == ProxyStage.stopping ||
      this == ProxyStage.requestingPermission;

  bool get isActive =>
      this == ProxyStage.connected || this == ProxyStage.starting;
}

/// What traffic the current runtime is actually positioned to cover.
///
/// A connected core is not by itself proof that the host's traffic is using
/// it. Desktop system-proxy backends can be missing or reject a write while
/// the local mixed inbound and the sing-box process remain healthy, so the UI
/// keeps this fact separate from [ProxyStage.connected].
enum ProxyCoverage {
  /// A TUN adapter is carrying host traffic.
  tun,

  /// The desktop's system proxy points at the local mixed inbound.
  systemProxy,

  /// The core is alive, but the requested desktop proxy could not be applied.
  systemProxyUnavailable,

  /// Only the local mixed inbound is available; no host-wide takeover exists.
  localProxy,
}

/// A start failure the app detected itself, rather than engine output.
///
/// Most of what [ProxyState.message] carries is the engine's own words: not
/// translatable, and shown verbatim because rephrasing an engine error loses the
/// part that identifies it. These are different. They are conditions the app
/// worked out around the engine — no binary, too old a binary, a tun the kernel
/// would not give us, an elevation the user dismissed — and each has a specific
/// fix worth spelling out in the user's language.
///
/// So they travel as a marker in the same `message` field instead of an English
/// sentence built in the runtime layer, and the notice layer turns them into
/// words. No new field on [ProxyState], and nothing changes for the platform
/// that only ever reports engine text.
enum EngineProblem {
  /// No `sing-box` binary anywhere the runtime looks.
  missing,

  /// Found, but older than the schema the rendered config uses.
  tooOld,

  /// A tun start failed for want of `CAP_NET_ADMIN` (Linux) or of the
  /// administrator rights a Wintun adapter needs (Windows).
  ///
  /// [detailOf] carries the binary to grant the capability to on Linux, and
  /// nothing on Windows, where the fix is the UAC prompt rather than a path.
  unprivileged,

  /// The elevation handoff itself broke: UAC was accepted, or could not even be
  /// asked, but no elevated instance took over. Distinct from [unprivileged],
  /// where the user simply said no and re-connecting is the whole fix.
  elevationFailed,

  /// The rendered config was rejected before anything started listening.
  ///
  /// [detailOf] carries the engine's exit code, never its output: a malformed
  /// custom node puts credentials into that diagnostic.
  configRejected,

  /// The core started but never answered on its control API.
  apiTimeout,

  /// The host's proxy settings could not be taken over, so a connected engine
  /// would carry no traffic. See [ProxyCoverage.systemProxyUnavailable] for the
  /// same condition when the tunnel did come up.
  systemProxyUnavailable;

  static const _prefix = 'engine-problem:';

  /// Encodes this problem as a [ProxyState.message], optionally carrying one
  /// piece of detail — the version found, the path to fix.
  String encode([String? detail]) => detail == null || detail.isEmpty
      ? '$_prefix$name'
      : '$_prefix$name $detail';

  /// The problem [message] encodes, or null when it is plain engine output.
  static EngineProblem? of(String? message) {
    if (message == null || !message.startsWith(_prefix)) return null;
    final name = message.substring(_prefix.length).split(' ').first;
    for (final problem in values) {
      if (problem.name == name) return problem;
    }
    return null;
  }

  /// The detail [message] carried, or null. Everything after the first space,
  /// so a path containing one survives.
  static String? detailOf(String? message) {
    if (of(message) == null) return null;
    final space = message!.indexOf(' ');
    return space < 0 ? null : message.substring(space + 1);
  }
}

class ProxyState {
  const ProxyState({
    this.stage = ProxyStage.disconnected,
    this.message,
    this.since,
    this.sessionId,
    this.coverage,
  });

  final ProxyStage stage;

  /// Error detail when [stage] is [ProxyStage.error]; already redacted.
  final String? message;

  /// When the current connection was established.
  final DateTime? since;

  /// Monotonically increasing runtime generation, when the platform can provide
  /// one. A delayed event from an older process/session can then be ignored by
  /// the state owner instead of changing the UI after a newer operation won.
  final int? sessionId;

  /// The traffic coverage achieved by a connected runtime, when known.
  final ProxyCoverage? coverage;

  bool get isConnected => stage == ProxyStage.connected;

  static const disconnected = ProxyState();
}

/// Where the engine sent one connection.
enum ConnectionRoute { proxy, direct, reject }

/// One open connection as the Clash API lists it.
///
/// Only what the dashboard draws is kept. The API also carries source ports,
/// DNS mode and the full rule payload; holding those for every connection every
/// second would be memory spent on nothing shown.
class ProxyConnection {
  const ProxyConnection({
    required this.id,
    required this.host,
    required this.network,
    required this.route,
    required this.outbound,
    required this.rule,
    this.process,
    this.upload = 0,
    this.download = 0,
    this.start,
  });

  final String id;

  /// Hostname when the engine sniffed or was given one, else `ip:port`.
  final String host;

  /// `tcp` or `udp`.
  final String network;
  final ConnectionRoute route;

  /// The outbound the connection actually left through: a node's tag,
  /// `direct`, or the reject action.
  final String outbound;

  /// The matching rule as the engine names it, `final` for the fallthrough.
  final String rule;

  /// Executable name of the local process, when the engine resolved it.
  final String? process;
  final int upload;
  final int download;
  final DateTime? start;

  int get bytes => upload + download;

  /// Parses one entry of `/connections`. Null when it is not shaped like one.
  static ProxyConnection? fromClash(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final meta = raw['metadata'] is Map ? raw['metadata'] as Map : const {};
    String text(Object? v) => v is String ? v : '';

    final host = text(meta['host']);
    final ip = text(meta['destinationIP']);
    final port = text(meta['destinationPort']);
    final chains = raw['chains'] is List ? raw['chains'] as List : const [];
    // Clash lists the chain innermost-first: the first entry is where the
    // bytes physically left, which is the one worth showing.
    final outbound = chains.isEmpty ? '' : chains.first.toString();
    final rule = text(raw['rule']);

    final ConnectionRoute route;
    if (rule.contains('reject') || outbound == 'block') {
      route = ConnectionRoute.reject;
    } else if (outbound == 'direct') {
      route = ConnectionRoute.direct;
    } else {
      route = ConnectionRoute.proxy;
    }

    final path = text(meta['processPath']);
    return ProxyConnection(
      id: id,
      host: host.isNotEmpty
          ? host
          : (ip.isEmpty ? '?' : (port.isEmpty ? ip : '$ip:$port')),
      network: text(meta['network']),
      route: route,
      outbound: outbound,
      rule: rule,
      process: path.isEmpty ? null : path.split('/').last.split('\\').last,
      upload: _int(raw['upload']),
      download: _int(raw['download']),
      start: DateTime.tryParse(text(raw['start'])),
    );
  }
}

/// Traffic counters. Rates are per-second deltas reported by sing-box.
class ProxyTraffic {
  const ProxyTraffic({
    this.uplink = 0,
    this.downlink = 0,
    this.uplinkTotal = 0,
    this.downlinkTotal = 0,
    this.connectionsIn = 0,
    this.connectionsOut = 0,
    this.memory = 0,
    this.connectionList = const [],
  });

  final int uplink;
  final int downlink;
  final int uplinkTotal;
  final int downlinkTotal;
  final int connectionsIn;
  final int connectionsOut;
  final int memory;

  /// The open connections themselves, where the runtime lists them.
  ///
  /// Filled on the desktop, where the Clash API reports each one. libbox only
  /// gives counts, so Android leaves this empty and the dashboard hides the
  /// list rather than showing an empty table that reads as "no traffic".
  final List<ProxyConnection> connectionList;

  /// Open connections, as the one figure the UI shows.
  ///
  /// The two runtimes fill different slots. libbox reports both directions
  /// separately, while the Clash API has only an undirected list and puts its
  /// length in [connectionsIn], leaving [connectionsOut] at zero — so reading
  /// either field directly is zero on one platform or the other. Whichever
  /// carries the reading is the reading.
  ///
  /// The larger of the two rather than their sum: on libbox an inbound
  /// connection dials a matching outbound, so adding them reports roughly twice
  /// the connections there while still being correct on the desktop. Taking the
  /// maximum is right whether one slot is filled or both.
  int get connections =>
      connectionsIn > connectionsOut ? connectionsIn : connectionsOut;

  static const zero = ProxyTraffic();

  static ProxyTraffic fromMap(Map<Object?, Object?> map) => ProxyTraffic(
        uplink: _int(map['uplink']),
        downlink: _int(map['downlink']),
        uplinkTotal: _int(map['uplinkTotal']),
        downlinkTotal: _int(map['downlinkTotal']),
        connectionsIn: _int(map['connectionsIn']),
        connectionsOut: _int(map['connectionsOut']),
        memory: _int(map['memory']),
      );
}

/// Channel values arrive as `int` on one platform and `num` on another.
int _int(Object? value) => switch (value) {
      int v => v,
      num v => v.toInt(),
      _ => 0,
    };

/// One outbound group as the engine reports it, with its members' URL-test
/// delays.
///
/// These are the only latencies measured *through* the tunnel: the engine dials
/// the test URL over each member, so the number covers the proxy end to end
/// rather than a TCP handshake to its server address.
class ProxyGroup {
  const ProxyGroup({
    required this.tag,
    required this.selected,
    required this.delays,
  });

  final String tag;

  /// Member the group currently sends through.
  final String selected;

  /// Member tag to last URL-test delay in milliseconds.
  ///
  /// `0` is libbox's "no result" — never tested, or the last test failed — and
  /// is passed through as-is so callers can tell it apart from a real figure.
  final Map<String, int> delays;

  static ProxyGroup fromMap(Map<Object?, Object?> map) {
    final delays = <String, int>{};
    final items = map['items'];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final tag = item['tag']?.toString();
        if (tag == null || tag.isEmpty) continue;
        delays[tag] = _int(item['delay']);
      }
    }
    return ProxyGroup(
      tag: (map['tag'] ?? '').toString(),
      selected: (map['selected'] ?? '').toString(),
      delays: delays,
    );
  }
}

class ProxyLogEntry {
  /// [message] is stored with its terminal colouring removed.
  ///
  /// libbox writes log lines for a terminal, so they arrive wrapped in ANSI
  /// escapes: `\x1B[37mDEBUG\x1B[0m[0000] [\x1B[38;5;83m1604613780\x1B[0m …`.
  /// Nothing in Flutter interprets those — the log page renders each `\x1B` as
  /// a tofu box, and they end up in anything the user copies out of it. Every
  /// entry is built through this constructor, so stripping here covers the
  /// engine channel and the fakes alike.
  ProxyLogEntry({required String message, required this.at})
      : message = message.replaceAll(_ansi, '');

  final String message;
  final DateTime at;

  /// CSI sequences (colour, cursor), OSC strings, and the two-character forms.
  static final _ansi = RegExp(
    r'\x1B\[[0-9;:?]*[ -/]*[@-~]'
    r'|\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)'
    r'|\x1B[@-Z\\-_]',
  );
}

/// Formats a byte count for display: `1.2 MB`.
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Formats a per-second rate for display: `1.2 MB/s`.
String formatRate(int bytesPerSecond) =>
    bytesPerSecond <= 0 ? '—' : '${formatBytes(bytesPerSecond)}/s';

/// Formats an elapsed duration as `1h 04m` / `04:12`.
String formatUptime(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  if (hours > 0) {
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${seconds.toString().padLeft(2, '0')}';
}
