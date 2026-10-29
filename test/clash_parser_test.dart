/// Clash / mihomo YAML subscriptions: what each proxy type becomes, and that
/// the result goes through the same import, id and render paths as a share
/// link.
library;

import 'package:ferry/data/clash_parser.dart';
import 'package:ferry/data/config_builder.dart';
import 'package:ferry/data/importer.dart';
import 'package:ferry/data/share_link_parser.dart';
import 'package:ferry/models/app_settings.dart';
import 'package:ferry/models/node.dart';
import 'package:ferry/platform/config_facts.dart';
import 'package:flutter_test/flutter_test.dart';

const _config = '''
mixed-port: 7890
allow-lan: false
mode: rule
proxies:
  - name: "🇯🇵 东京 01"
    type: vless
    server: tokyo.example.net
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: www.microsoft.com
    client-fingerprint: chrome
    reality-opts:
      public-key: tVDDq0yh2mOtCZT6C1HMDiHPCGL7jr1fqLuy3TkoqVo
      short-id: abcd
  - {name: "SG ss", type: ss, server: sg.example.net, port: 8388, cipher: aes-128-gcm, password: "pw", udp-over-tcp: true}
  - name: HK vmess ws
    type: vmess
    server: hk.example.net
    port: 443
    uuid: 66666666-7777-8888-9999-000000000000
    alterId: 0
    cipher: auto
    tls: true
    servername: hk.example.net
    network: ws
    ws-opts:
      path: /ray
      headers:
        Host: cdn.example.net
  - name: US trojan grpc
    type: trojan
    server: us.example.net
    port: 443
    password: trojanpw
    sni: us.example.net
    skip-cert-verify: true
    network: grpc
    grpc-opts:
      grpc-service-name: tun
  - name: JP hy2
    type: hysteria2
    server: hy.example.net
    port: 8443
    password: hypw
    up: "50 Mbps"
    down: 200
    obfs: salamander
    obfs-password: obfspw
    sni: hy.example.net
  - name: TW tuic
    type: tuic
    server: tuic.example.net
    port: 443
    uuid: aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee
    password: bbbb
    congestion-controller: bbr
    udp-relay-mode: native
    alpn: [h3]
  - name: unsupported
    type: wireguard
    server: wg.example.net
    port: 51820
  - name: ss with shadow-tls
    type: ss
    server: stls.example.net
    port: 443
    cipher: aes-128-gcm
    password: pw
    plugin: shadow-tls
proxy-groups:
  - name: Proxy
    type: select
    proxies: ["🇯🇵 东京 01"]
rules:
  - MATCH,Proxy
''';

ProxyNode _named(List<ProxyNode> nodes, String name) =>
    nodes.firstWhere((n) => n.name == name);

void main() {
  test('detects a Clash config by its proxies key', () {
    expect(ClashParser.looksLikeClash(_config), isTrue);
    expect(ClashParser.looksLikeClash('vless://x@y:1#z'), isFalse);
    expect(ClashParser.looksLikeClash('{"outbounds": []}'), isFalse);
  });

  test('each supported type becomes its sing-box outbound', () {
    final parsed = ClashParser.parse(_config, subscriptionId: 'sub');
    expect(parsed.nodes, hasLength(6));
    expect(parsed.skipped, 2, reason: 'wireguard, and ss over shadow-tls');

    final vless = _named(parsed.nodes, '🇯🇵 东京 01');
    expect(vless.protocol, NodeProtocol.vless);
    expect(vless.subscriptionId, 'sub');
    expect(vless.raw['flow'], 'xtls-rprx-vision');
    final tls = vless.raw['tls'] as Map;
    expect(tls['server_name'], 'www.microsoft.com');
    expect(tls['utls'], {'enabled': true, 'fingerprint': 'chrome'});
    expect(tls['reality'],
        {'enabled': true, 'public_key': 'tVDDq0yh2mOtCZT6C1HMDiHPCGL7jr1fqLuy3TkoqVo', 'short_id': 'abcd'});

    final ss = _named(parsed.nodes, 'SG ss');
    expect(ss.raw, {'method': 'aes-128-gcm', 'password': 'pw', 'udp_over_tcp': true});

    final vmess = _named(parsed.nodes, 'HK vmess ws');
    expect(vmess.raw['transport'], {
      'type': 'ws',
      'path': '/ray',
      'headers': {'Host': 'cdn.example.net'},
    });

    final trojan = _named(parsed.nodes, 'US trojan grpc');
    expect((trojan.raw['tls'] as Map)['insecure'], isTrue);
    expect(trojan.raw['transport'], {'type': 'grpc', 'service_name': 'tun'});

    final hy2 = _named(parsed.nodes, 'JP hy2');
    expect(hy2.raw['up_mbps'], 50);
    expect(hy2.raw['down_mbps'], 200);
    expect(hy2.raw['obfs'], {'type': 'salamander', 'password': 'obfspw'});

    final tuic = _named(parsed.nodes, 'TW tuic');
    expect(tuic.raw['congestion_control'], 'bbr');
    expect((tuic.raw['tls'] as Map)['alpn'], ['h3']);
  });

  test('a node keeps the id it has as a share link', () {
    // The same endpoint offered in both formats is one node, so its latency
    // and favourite survive switching a subscription between them.
    final fromClash = _named(ClashParser.parse(_config).nodes, '🇯🇵 东京 01');
    final fromLink = ShareLinkParser.parse(
      'vless://11111111-2222-3333-4444-555555555555@tokyo.example.net:443'
      '?security=reality&pbk=tVDDq0yh2mOtCZT6C1HMDiHPCGL7jr1fqLuy3TkoqVo&sid=abcd&fp=chrome#renamed',
    );
    expect(fromClash.id, fromLink.id);
  });

  test('an unknown fingerprint is dropped, as for share links', () {
    final parsed = ClashParser.parse('''
proxies:
  - {name: a, type: trojan, server: a.example.net, port: 443, password: p, client-fingerprint: unsafe}
''');
    expect((parsed.nodes.single.raw['tls'] as Map).containsKey('utls'), isFalse);
  });

  test('pasted YAML imports through the importer', () async {
    final result = await Importer().importText(_config);
    expect(result.nodes, hasLength(6));
    expect(result.skipped, 2);
  });

  test('a config without proxies is a bad source', () {
    expect(
      () => Importer().importClashConfig('proxies: []\n'),
      throwsA(isA<ImportException>()),
    );
    expect(
      () => Importer().importClashConfig('proxies: [\n'),
      throwsA(isA<ImportException>()),
    );
  });

  test('the imported nodes render into a config that validates', () {
    final nodes = ClashParser.parse(_config).nodes;
    final config = ConfigBuilder.build(
      nodes: nodes,
      selectedNodeId: nodes.first.id,
      settings: const AppSettings(),
      clashSecret: 'secret',
    );
    ConfigFacts.fromMap(config);
    final tags = [
      for (final o in (config['outbounds'] as List).cast<Map>()) o['tag'],
    ];
    for (final node in nodes) {
      expect(tags, contains(ConfigBuilder.outboundTag(node)));
    }
  });
}
