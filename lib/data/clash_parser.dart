/// Reads the `proxies:` list out of a Clash / mihomo YAML config.
///
/// Many providers in China serve only this format. Each proxy is translated to
/// the sing-box outbound fields the rest of the app already understands, so a
/// node imported from YAML renders, tests and switches exactly like one from a
/// share link. Node ids are derived the same way as the share-link parser's —
/// protocol, server, port, secret — so the same endpoint keeps its latency and
/// favourite whichever format it arrived in.
///
/// Proxy groups and rules are ignored: they are the provider's routing, and
/// this app has its own.
library;

import 'package:yaml/yaml.dart';

import '../models/node.dart';
import 'share_link_parser.dart';

class ClashParser {
  const ClashParser._();

  /// True when [text] has a top-level `proxies:` key — the one part of a Clash
  /// config this reads. A cheap test, done before committing to a YAML parse.
  static bool looksLikeClash(String text) =>
      RegExp(r'^proxies\s*:', multiLine: true).hasMatch(text);

  /// The nodes in [text]'s `proxies:` list. Entries of an unsupported type, or
  /// missing a server, port or secret, are counted in `skipped` rather than
  /// failing the whole import.
  ///
  /// Throws [FormatException] when [text] is not YAML or has no proxy list.
  static ({List<ProxyNode> nodes, int skipped}) parse(
    String text, {
    String? subscriptionId,
  }) {
    final Object? doc;
    try {
      doc = loadYaml(text);
    } on YamlException catch (error) {
      throw FormatException('invalid YAML: ${error.message}');
    }
    final proxies = doc is YamlMap ? doc['proxies'] : null;
    if (proxies is! YamlList) {
      throw const FormatException('no proxies list');
    }

    final nodes = <ProxyNode>[];
    var skipped = 0;
    for (final entry in proxies) {
      final node = entry is YamlMap
          ? _node(_plain(entry) as Map<String, dynamic>, subscriptionId)
          : null;
      if (node == null) {
        skipped++;
      } else {
        nodes.add(node);
      }
    }
    return (nodes: nodes, skipped: skipped);
  }

  /// YAML nodes as ordinary Dart maps and lists, so the outbound maps built
  /// from them serialise to JSON without carrying YAML types along.
  static Object? _plain(Object? value) => switch (value) {
        YamlMap map => <String, dynamic>{
            for (final entry in map.entries)
              entry.key.toString(): _plain(entry.value),
          },
        YamlList list => [for (final item in list) _plain(item)],
        _ => value,
      };

  static ProxyNode? _node(Map<String, dynamic> p, String? subscriptionId) {
    final type = _str(p['type']).toLowerCase();
    final name = _str(p['name']);
    final server = _str(p['server']);
    final port = _int(p['port']);
    if (server.isEmpty || port <= 0) return null;

    final built = switch (type) {
      'ss' => _shadowsocks(p),
      'vmess' => _vmess(p),
      'vless' => _vless(p),
      'trojan' => _trojan(p),
      'hysteria2' || 'hy2' => _hysteria2(p),
      'tuic' => _tuic(p),
      'anytls' => _anytls(p),
      'socks5' => _socks(p),
      'http' => _http(p),
      _ => null,
    };
    if (built == null) return null;
    final (protocol, scheme, secret, raw) = built;
    return ProxyNode(
      id: ShareLinkParser.makeId(scheme, server, port, secret),
      name: name.isEmpty ? '$server:$port' : name,
      protocol: protocol,
      server: server,
      serverPort: port,
      raw: raw,
      subscriptionId: subscriptionId,
    );
  }

  // ------------------------------------------------------------- protocols

  /// Each returns the protocol, the share-link scheme its id is made under,
  /// the secret in that id, and the outbound fields; or null when the entry
  /// cannot be used.
  static (NodeProtocol, String, String, Map<String, dynamic>)? _shadowsocks(
    Map<String, dynamic> p,
  ) {
    final method = _str(p['cipher']);
    final password = _str(p['password']);
    if (method.isEmpty || password.isEmpty) return null;
    final raw = <String, dynamic>{'method': method, 'password': password};
    if (p['udp-over-tcp'] == true) raw['udp_over_tcp'] = true;

    final plugin = _str(p['plugin']);
    if (plugin.isNotEmpty) {
      final opts = _map(p['plugin-opts']);
      switch (plugin) {
        case 'obfs':
          raw['plugin'] = 'obfs-local';
          raw['plugin_opts'] = [
            'obfs=${_str(opts['mode'], 'http')}',
            if (_str(opts['host']).isNotEmpty)
              'obfs-host=${_str(opts['host'])}',
          ].join(';');
        case 'v2ray-plugin':
          raw['plugin'] = 'v2ray-plugin';
          raw['plugin_opts'] = [
            'mode=${_str(opts['mode'], 'websocket')}',
            if (opts['tls'] == true) 'tls',
            if (_str(opts['host']).isNotEmpty) 'host=${_str(opts['host'])}',
            if (_str(opts['path']).isNotEmpty) 'path=${_str(opts['path'])}',
          ].join(';');
        default:
          // shadow-tls, restls and the like have no sing-box plugin
          // equivalent; importing the node without it would not connect.
          return null;
      }
    }
    return (NodeProtocol.shadowsocks, 'ss', password, raw);
  }

  static (NodeProtocol, String, String, Map<String, dynamic>)? _vmess(
    Map<String, dynamic> p,
  ) {
    final uuid = _str(p['uuid']);
    if (uuid.isEmpty) return null;
    final raw = <String, dynamic>{
      'uuid': uuid,
      'security': _str(p['cipher'], 'auto'),
      'alter_id': _int(p['alterId']),
    };
    if (p['tls'] == true) raw['tls'] = _tls(p, serverName: p['servername']);
    _addTransport(raw, p);
    return (NodeProtocol.vmess, 'vmess', uuid, raw);
  }

  static (NodeProtocol, String, String, Map<String, dynamic>)? _vless(
    Map<String, dynamic> p,
  ) {
    final uuid = _str(p['uuid']);
    if (uuid.isEmpty) return null;
    final raw = <String, dynamic>{'uuid': uuid};
    final flow = _str(p['flow']);
    if (flow.isNotEmpty) raw['flow'] = flow;
    final encoding = _str(p['packet-encoding']);
    if (encoding.isNotEmpty) raw['packet_encoding'] = encoding;
    if (p['tls'] == true || p['reality-opts'] != null) {
      raw['tls'] = _tls(p, serverName: p['servername']);
    }
    _addTransport(raw, p);
    return (NodeProtocol.vless, 'vless', uuid, raw);
  }

  static (NodeProtocol, String, String, Map<String, dynamic>)? _trojan(
    Map<String, dynamic> p,
  ) {
    final password = _str(p['password']);
    if (password.isEmpty) return null;
    final raw = <String, dynamic>{
      'password': password,
      // Trojan is TLS by definition; Clash only spells out the extras.
      'tls': _tls(p, serverName: p['sni']),
    };
    _addTransport(raw, p);
    return (NodeProtocol.trojan, 'trojan', password, raw);
  }

  static (NodeProtocol, String, String, Map<String, dynamic>)? _hysteria2(
    Map<String, dynamic> p,
  ) {
    final password = _str(p['password'], _str(p['auth']));
    if (password.isEmpty) return null;
    final raw = <String, dynamic>{
      'password': password,
      'tls': _tls(p, serverName: p['sni']),
    };
    final up = _mbps(p['up']);
    final down = _mbps(p['down']);
    if (up > 0) raw['up_mbps'] = up;
    if (down > 0) raw['down_mbps'] = down;
    final obfs = _str(p['obfs']);
    if (obfs.isNotEmpty) {
      raw['obfs'] = {
        'type': obfs,
        if (_str(p['obfs-password']).isNotEmpty)
          'password': _str(p['obfs-password']),
      };
    }
    return (NodeProtocol.hysteria2, 'hysteria2', password, raw);
  }

  static (NodeProtocol, String, String, Map<String, dynamic>)? _tuic(
    Map<String, dynamic> p,
  ) {
    final uuid = _str(p['uuid']);
    final password = _str(p['password']);
    // TUIC v4 authenticates with a token instead; sing-box speaks only v5.
    if (uuid.isEmpty || password.isEmpty) return null;
    final raw = <String, dynamic>{
      'uuid': uuid,
      'password': password,
      'tls': _tls(p, serverName: p['sni']),
    };
    final congestion = _str(p['congestion-controller']);
    if (congestion.isNotEmpty) raw['congestion_control'] = congestion;
    final relay = _str(p['udp-relay-mode']);
    if (relay.isNotEmpty) raw['udp_relay_mode'] = relay;
    if (p['reduce-rtt'] == true) raw['zero_rtt_handshake'] = true;
    return (NodeProtocol.tuic, 'tuic', '$uuid:$password', raw);
  }

  static (NodeProtocol, String, String, Map<String, dynamic>)? _anytls(
    Map<String, dynamic> p,
  ) {
    final password = _str(p['password']);
    if (password.isEmpty) return null;
    return (
      NodeProtocol.anytls,
      'anytls',
      password,
      {'password': password, 'tls': _tls(p, serverName: p['sni'])},
    );
  }

  static (NodeProtocol, String, String, Map<String, dynamic>)? _socks(
    Map<String, dynamic> p,
  ) {
    final user = _str(p['username']);
    final pass = _str(p['password']);
    final raw = <String, dynamic>{
      'version': '5',
      if (user.isNotEmpty) 'username': user,
      if (pass.isNotEmpty) 'password': pass,
    };
    return (
      NodeProtocol.socks,
      'socks',
      user.isEmpty ? '' : '$user:$pass',
      raw
    );
  }

  static (NodeProtocol, String, String, Map<String, dynamic>)? _http(
    Map<String, dynamic> p,
  ) {
    final user = _str(p['username']);
    final pass = _str(p['password']);
    final raw = <String, dynamic>{
      if (user.isNotEmpty) 'username': user,
      if (pass.isNotEmpty) 'password': pass,
    };
    if (p['tls'] == true) raw['tls'] = _tls(p, serverName: p['sni']);
    return (NodeProtocol.http, 'http', user.isEmpty ? '' : '$user:$pass', raw);
  }

  // ---------------------------------------------------------- shared parts

  /// The sing-box `tls` member from Clash's scattered TLS keys.
  static Map<String, dynamic> _tls(
    Map<String, dynamic> p, {
    Object? serverName,
  }) {
    final tls = <String, dynamic>{'enabled': true};
    final sni = _str(serverName);
    tls['server_name'] = sni.isNotEmpty ? sni : _str(p['server']);
    if (p['skip-cert-verify'] == true) tls['insecure'] = true;
    final alpn = p['alpn'];
    if (alpn is List && alpn.isNotEmpty) {
      tls['alpn'] = [for (final a in alpn) a.toString()];
    }
    // Same whitelist as share links: an unknown fingerprint makes sing-box
    // refuse the whole config, so it is dropped rather than passed on.
    final utls = ShareLinkParser.utls(p['client-fingerprint']);
    if (utls != null) tls['utls'] = utls;
    final reality = _map(p['reality-opts']);
    if (reality.isNotEmpty) {
      tls['reality'] = {
        'enabled': true,
        if (_str(reality['public-key']).isNotEmpty)
          'public_key': _str(reality['public-key']),
        if (_str(reality['short-id']).isNotEmpty)
          'short_id': _str(reality['short-id']),
      };
    }
    return tls;
  }

  /// The sing-box `transport` member for Clash's `network` and its options.
  static void _addTransport(Map<String, dynamic> raw, Map<String, dynamic> p) {
    final transport = switch (_str(p['network'])) {
      'ws' => _ws(_map(p['ws-opts'])),
      'grpc' => {
          'type': 'grpc',
          'service_name': _str(_map(p['grpc-opts'])['grpc-service-name']),
        },
      'h2' => () {
          final opts = _map(p['h2-opts']);
          final hosts = opts['host'];
          return {
            'type': 'http',
            if (hosts is List && hosts.isNotEmpty)
              'host': [for (final h in hosts) h.toString()],
            if (_str(opts['path']).isNotEmpty) 'path': _str(opts['path']),
          };
        }(),
      'http' => () {
          final opts = _map(p['http-opts']);
          final paths = opts['path'];
          final hosts = _map(opts['headers'])['Host'];
          return {
            'type': 'http',
            if (paths is List && paths.isNotEmpty)
              'path': paths.first.toString(),
            if (hosts is List && hosts.isNotEmpty)
              'host': [for (final h in hosts) h.toString()],
            if (_str(opts['method']).isNotEmpty) 'method': _str(opts['method']),
          };
        }(),
      _ => null,
    };
    if (transport != null) raw['transport'] = transport;
  }

  /// WebSocket, or HTTPUpgrade when mihomo's `v2ray-http-upgrade` says so.
  static Map<String, dynamic> _ws(Map<String, dynamic> opts) {
    final headers = _map(opts['headers']);
    final host = _str(headers['Host'], _str(headers['host']));
    final path = _str(opts['path'], '/');
    if (opts['v2ray-http-upgrade'] == true) {
      return {
        'type': 'httpupgrade',
        'path': path,
        if (host.isNotEmpty) 'host': host,
      };
    }
    return {
      'type': 'ws',
      'path': path,
      if (host.isNotEmpty) 'headers': {'Host': host},
      if (_int(opts['max-early-data']) > 0)
        'max_early_data': _int(opts['max-early-data']),
      if (_str(opts['early-data-header-name']).isNotEmpty)
        'early_data_header_name': _str(opts['early-data-header-name']),
    };
  }

  static String _str(Object? value, [String fallback = '']) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static int _int(Object? value) => switch (value) {
        int v => v,
        num v => v.toInt(),
        String v => int.tryParse(v.trim()) ?? 0,
        _ => 0,
      };

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  /// `100`, `"100 Mbps"` or `"100Mbps"` as a whole number of Mbps.
  static int _mbps(Object? value) {
    if (value is num) return value.toInt();
    final match = RegExp(r'\d+').firstMatch('${value ?? ''}');
    return match == null ? 0 : int.parse(match.group(0)!);
  }
}
