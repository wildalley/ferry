import 'dart:convert';
import 'dart:io';

import 'package:ferry/data/config_builder.dart';
import 'package:ferry/data/local_proxy.dart';
import 'package:ferry/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> build(
          {required bool android,
          bool desktopAuth = false,
          String? secret = 'random-secret'}) =>
      ConfigBuilder.build(
          nodes: const [],
          selectedNodeId: null,
          settings: AppSettings(localProxyAuth: desktopAuth),
          clashSecret: 'independent-api-secret',
          localProxySecret: secret,
          android: android,
          tunOnly: android);

  test('Android requires credentials; desktop defaults to compatibility mode',
      () {
    Map mixed(Map<String, dynamic> config) => (config['inbounds'] as List)
        .cast<Map>()
        .firstWhere((i) => i['type'] == 'mixed');
    expect(mixed(build(android: true))['users'], [
      {'username': 'ferry', 'password': 'random-secret'}
    ]);
    expect(mixed(build(android: false)).containsKey('users'), isFalse);
    expect(
        mixed(build(android: false, desktopAuth: true))['users'], isNotEmpty);
    expect(() => build(android: true, secret: null), throwsFormatException);
  });

  test('internal HTTP responds to a loopback proxy challenge with credentials',
      () async {
    final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await proxy.close(force: true);
    });
    final expected =
        'Basic ${base64.encode(utf8.encode('ferry:random-secret'))}';
    proxy.listen((request) async {
      if (request.uri.path == '/direct') {
        expect(request.headers.value(HttpHeaders.proxyAuthorizationHeader),
            isNull);
        request.response.write('direct');
        await request.response.close();
        return;
      }
      if (request.headers.value(HttpHeaders.proxyAuthorizationHeader) !=
          expected) {
        request.response.statusCode = HttpStatus.proxyAuthenticationRequired;
        request.response.headers
            .set(HttpHeaders.proxyAuthenticateHeader, 'Basic realm="sing-box"');
      } else {
        request.response.write('authenticated');
      }
      await request.response.close();
    });
    routeHttp(client,
        viaLocalProxy: true,
        localProxyPort: proxy.port,
        localProxySecret: 'random-secret');
    final request =
        await client.getUrl(Uri.parse('http://destination.invalid/resource'));
    final response = await request.close();
    expect(response.statusCode, 200);
    expect(await utf8.decoder.bind(response).join(), 'authenticated');
    client.findProxy = (_) => 'PROXY localhost:${proxy.port}';
    final untrusted =
        await (await client.getUrl(Uri.parse('http://destination.invalid/')))
            .close();
    expect(untrusted.statusCode, HttpStatus.proxyAuthenticationRequired);
    await untrusted.drain<void>();
    routeHttp(client, viaLocalProxy: false, localProxySecret: 'random-secret');
    final direct = await (await client
            .getUrl(Uri.parse('http://127.0.0.1:${proxy.port}/direct')))
        .close();
    expect(await utf8.decoder.bind(direct).join(), 'direct');
  });
}
