/// Asks GitHub whether a newer release of the app exists.
///
/// Advisory only: the app never downloads or installs anything. It finds the
/// latest published release, compares its tag with [appVersion], and hands
/// back the release page for the user to open if they want it. The core is not
/// updated separately — it ships inside each release, matched to the config the
/// same release renders.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'bounded_http.dart';
import 'local_proxy.dart';

/// A published release, as much of it as the prompt needs.
class AppRelease {
  const AppRelease({
    required this.tag,
    required this.version,
    required this.url,
    this.notes,
  });

  /// As tagged, e.g. `v0.3.0`.
  final String tag;

  /// `[major, minor, patch]`.
  final List<int> version;

  /// The release page, which lists the downloads for every platform.
  final String url;

  /// The first lines of the release body, or null when it has none.
  final String? notes;
}

/// `0.2.0`, `v0.2.0` or `0.2.0+17` → `[0, 2, 0]`; null when no version is in it.
List<int>? parseAppVersion(String text) {
  final match = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(text);
  if (match == null) return null;
  return [
    for (var group = 1; group <= 3; group++)
      int.tryParse(match.group(group) ?? '0') ?? 0,
  ];
}

/// Whether [candidate] is a later version than [current].
bool isNewerVersion(List<int> candidate, List<int> current) {
  for (var i = 0; i < 3; i++) {
    final a = i < candidate.length ? candidate[i] : 0;
    final b = i < current.length ? current[i] : 0;
    if (a != b) return a > b;
  }
  return false;
}

class UpdateChecker {
  UpdateChecker({
    this.repository = 'wildalley/ferry',
    HttpClient? httpClient,
  }) : _httpClient = httpClient ?? (HttpClient()..connectionTimeout = _timeout);

  /// `owner/name` on GitHub.
  final String repository;
  final HttpClient _httpClient;

  static const _timeout = Duration(seconds: 12);

  /// A release JSON is a few KB; anything far past that is not one.
  static const _maxBytes = 512 * 1024;

  /// The latest published release, skipping drafts and pre-releases — which
  /// is what GitHub's `releases/latest` already means.
  ///
  /// [viaLocalProxy] sends the request through the running tunnel: the GitHub
  /// API is unreachable on many of the links this app exists for.
  Future<AppRelease> latest({
    bool viaLocalProxy = false,
    int? localProxyPort,
    String? localProxySecret,
  }) async {
    routeHttp(
      _httpClient,
      viaLocalProxy: viaLocalProxy,
      localProxyPort: localProxyPort,
      localProxySecret: localProxySecret,
    );
    final uri =
        Uri.parse('https://api.github.com/repos/$repository/releases/latest');
    final bytes = await getBoundedBytes(
      _httpClient,
      uri,
      timeout: _timeout,
      maxBytes: _maxBytes,
      headers: {
        HttpHeaders.acceptHeader: 'application/vnd.github+json',
        HttpHeaders.userAgentHeader: 'ferry-update-check',
      },
    );
    return parseRelease(utf8.decode(bytes), repository: repository);
  }

  /// Reads the fields the prompt needs out of a `releases/latest` body.
  static AppRelease parseRelease(
    String body, {
    String repository = 'wildalley/ferry',
  }) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('not a release');
    final tag = decoded['tag_name']?.toString() ?? '';
    final version = parseAppVersion(tag);
    final url = decoded['html_url']?.toString() ?? '';
    final uri = Uri.tryParse(url);
    final expectedPath = '/$repository/releases/tag/$tag';
    if (version == null ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'github.com' ||
        uri.userInfo.isNotEmpty ||
        uri.port != 443 ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.path != expectedPath ||
        tag.contains('/') ||
        !RegExp(r'^v?\d+\.\d+\.\d+(?:\+\d+)?$').hasMatch(tag)) {
      throw const FormatException('release without a version or page');
    }
    final notes = decoded['body']?.toString().trim();
    return AppRelease(
      tag: tag,
      version: version,
      url: url,
      notes: notes == null || notes.isEmpty
          ? null
          : notes.split('\n').take(6).join('\n'),
    );
  }

  void dispose() => _httpClient.close(force: true);
}
