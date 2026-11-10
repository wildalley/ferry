import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class HttpStatusException extends HttpException {
  HttpStatusException(this.statusCode) : super('HTTP $statusCode');
  final int statusCode;
}

class HttpBodyTooLarge extends FormatException {
  const HttpBodyTooLarge() : super('HTTP response too large');
}

/// A small download with one deadline for connecting, headers and body.
///
/// Future.timeout alone leaves the underlying response subscription alive.
/// Explicit cancellation releases the socket and buffered bytes on every exit,
/// including HTTP errors whose bodies never finish. The cap also applies to
/// chunked and automatically decompressed responses.
Future<Uint8List> getBoundedBytes(
  HttpClient client,
  Uri uri, {
  required Duration timeout,
  required int maxBytes,
  Map<String, String> headers = const {},
  void Function(HttpClientResponse)? onResponse,
  String method = 'GET',
  String? requestBody,
  bool acceptAny2xx = false,
}) async {
  final watch = Stopwatch()..start();
  HttpClientRequest? request;
  StreamIterator<List<int>>? body;
  var finished = false;

  Duration remaining() {
    final duration = timeout - watch.elapsed;
    if (duration <= Duration.zero) {
      throw TimeoutException('HTTP download timed out');
    }
    return duration;
  }

  try {
    final opening =
        method == 'GET' ? client.getUrl(uri) : client.openUrl(method, uri);
    request = await opening.then((value) {
      // A connection may complete after Future.timeout has already returned.
      if (finished) {
        value.done.ignore();
        value.abort();
      }
      return value;
    }).timeout(remaining());
    // A tunnel/selector change must not reuse the previous proxy connection.
    request.persistentConnection = false;
    headers.forEach((name, value) => request!.headers.set(name, value));
    if (requestBody != null) request.write(requestBody);
    final response = await request.close().timeout(remaining());
    if (acceptAny2xx
        ? response.statusCode ~/ 100 != 2
        : response.statusCode != HttpStatus.ok) {
      response.listen(null).cancel().ignore();
      throw HttpStatusException(response.statusCode);
    }
    if (response.contentLength > maxBytes) {
      response.listen(null).cancel().ignore();
      throw const HttpBodyTooLarge();
    }
    onResponse?.call(response);
    body = StreamIterator(response);
    final bytes = BytesBuilder(copy: false);
    while (await body.moveNext().timeout(remaining())) {
      final chunk = body.current;
      if (chunk.length > maxBytes - bytes.length) {
        throw const HttpBodyTooLarge();
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  } finally {
    finished = true;
    // abort handles a request still waiting for headers; cancelling the body
    // handles a response that already arrived (abort alone cannot close it).
    request?.done.ignore();
    request?.abort();
    await body?.cancel();
  }
}
