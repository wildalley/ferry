/// Reads a QR code out of an image file's bytes.
///
/// Pure Dart (the `image` decoder and a zxing port), so it works the same on
/// every platform — including the desktops, which have no camera scanner and
/// where a screenshot of a subscription's QR code is the usual source.
library;

import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// The longest edge decoding works at. A phone screenshot is ~3000px tall and
/// a QR code in it is still hundreds of pixels across at this size, while the
/// decode gets an order of magnitude cheaper.
const _maxEdge = 1600;

/// The text in the first QR code found in [bytes], or null when there is none
/// or the bytes are not an image. Runs off the UI isolate.
Future<String?> decodeQrImage(Uint8List bytes) =>
    Isolate.run(() => decodeQrImageSync(bytes));

/// [decodeQrImage] on the calling isolate, for tests.
String? decodeQrImageSync(Uint8List bytes) {
  var image = img.decodeImage(bytes);
  if (image == null) return null;
  final longest = math.max(image.width, image.height);
  if (longest > _maxEdge) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? _maxEdge : null,
      height: image.height > image.width ? _maxEdge : null,
    );
  }
  final pixels = Int32List(image.width * image.height);
  var i = 0;
  for (final p in image) {
    pixels[i++] = 0xFF000000 |
        (p.r.toInt() << 16) |
        (p.g.toInt() << 8) |
        p.b.toInt();
  }
  final source = RGBLuminanceSource(image.width, image.height, pixels);
  // The hybrid binarizer handles screenshots and photos alike; a photo of a
  // screen under uneven light is where the simpler global one gives up.
  final bitmap = BinaryBitmap(HybridBinarizer(source));
  try {
    final result = QRCodeReader()
        .decode(bitmap, hints: DecodeHints()..put(DecodeHintType.tryHarder));
    final text = _utf8Repaired(result) ?? result.text;
    return text.trim().isEmpty ? null : text.trim();
  } on ReaderException {
    return null;
  }
}

/// The code's byte segments read as UTF-8, when that is what they are.
///
/// zxing2 hands its byte segments to the text decoder as signed bytes, so any
/// byte over 0x7F — every byte of a Han character in UTF-8 — comes out as a
/// replacement character, with or without an ECI saying UTF-8. Share links
/// carry node names, and plenty of generators write them raw rather than
/// percent-encoded, so the raw segments are decoded again here. The repair is
/// taken only when it agrees with the original on every ASCII character, so a
/// code that mixes byte mode with other modes cannot be stitched wrong.
String? _utf8Repaired(Result result) {
  final text = result.text;
  if (!text.runes.any((r) => r > 0x7F)) return null;
  final segments =
      result.resultMetadata[ResultMetadataType.byteSegments] as List?;
  if (segments == null || segments.isEmpty) return null;
  final bytes = <int>[
    for (final segment in segments)
      for (final b in segment as List<int>) b & 0xFF,
  ];
  final String repaired;
  try {
    repaired = utf8.decode(bytes);
  } on FormatException {
    return null;
  }
  String ascii(String s) => String.fromCharCodes(s.runes.where((r) => r < 0x80));
  return ascii(repaired) == ascii(text) ? repaired : null;
}
