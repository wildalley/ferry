/// Parsing the Clash API's per-connection list into what the dashboard shows.
///
/// Shapes are taken from a running sing-box 1.14 `/connections` reply, with
/// addresses and names replaced.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ferry/models/proxy_state.dart';
import 'package:ferry/platform/clash_api.dart';

Map<String, Object?> _conn({
  String id = 'c1',
  String host = 'example.com',
  String ip = '203.0.113.7',
  String port = '443',
  String network = 'tcp',
  List<String> chains = const ['node-a'],
  String rule = 'final',
  String process = '/usr/lib/firefox/firefox',
  int upload = 10,
  int download = 90,
}) =>
    {
      'id': id,
      'metadata': {
        'network': network,
        'type': 'tun/tun-in',
        'sourceIP': '172.19.0.1',
        'destinationIP': ip,
        'sourcePort': '51000',
        'destinationPort': port,
        'host': host,
        'dnsMode': 'normal',
        'processPath': process,
      },
      'upload': upload,
      'download': download,
      'start': '2026-10-27T14:30:00.000+08:00',
      'chains': chains,
      'rule': rule,
      'rulePayload': '',
    };

void main() {
  test('reads host, route, outbound and bytes', () {
    final c = ProxyConnection.fromClash(_conn())!;
    expect(c.host, 'example.com');
    expect(c.network, 'tcp');
    expect(c.route, ConnectionRoute.proxy);
    expect(c.outbound, 'node-a');
    expect(c.rule, 'final');
    expect(c.process, 'firefox');
    expect(c.bytes, 100);
    expect(c.start, isNotNull);
  });

  test('a direct rule is reported as direct', () {
    final c = ProxyConnection.fromClash(_conn(
      chains: const ['direct'],
      rule: 'rule_set=[geosite-cn geoip-cn] => route(direct)',
    ))!;
    expect(c.route, ConnectionRoute.direct);
  });

  test('a reject action is reported as rejected', () {
    final c = ProxyConnection.fromClash(_conn(
      chains: const [],
      rule: 'rule_set=[geosite-ads] => reject',
    ))!;
    expect(c.route, ConnectionRoute.reject);
  });

  test('falls back to ip:port when nothing named the host', () {
    final c = ProxyConnection.fromClash(_conn(host: ''))!;
    expect(c.host, '203.0.113.7:443');
  });

  test('a Windows process path is shortened to its executable', () {
    final c = ProxyConnection.fromClash(
      _conn(process: r'C:\Program Files\App\app.exe'),
    )!;
    expect(c.process, 'app.exe');
  });

  test('skips entries that are not connections', () {
    final list = ClashApiClient.parseConnections([
      _conn(id: 'a'),
      'garbage',
      {'id': ''},
      _conn(id: 'b'),
    ]);
    expect(list.map((c) => c.id), ['a', 'b']);
    expect(ClashApiClient.parseConnections(null), isEmpty);
  });
}
