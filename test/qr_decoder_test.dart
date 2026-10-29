/// QR codes read out of image files: the desktop's way to add a subscription
/// it can only see on screen, and the phone's way to use a saved one.
library;

import 'dart:typed_data';

import 'package:ferry/data/qr_decoder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

/// [text] as a QR code drawn [scale] pixels per module on a white page of
/// [width]×[height], encoded as PNG — a stand-in for a screenshot.
Uint8List qrPng(
  String text, {
  int scale = 6,
  int width = 600,
  int height = 900,
}) {
  // UTF-8 rather than the encoder's Latin-1 default: share links carry node
  // names, and some generators put them in raw rather than percent-encoded.
  final matrix = Encoder.encode(
    text,
    ErrorCorrectionLevel.m,
    hints: EncodeHints()..put(EncodeHintType.characterSet, CharacterSetECI.UTF8),
  ).matrix!;
  final page = img.Image(width: width, height: height);
  img.fill(page, color: img.ColorRgb8(255, 255, 255));
  final left = (width - matrix.width * scale) ~/ 2;
  final top = (height - matrix.height * scale) ~/ 2;
  for (var y = 0; y < matrix.height; y++) {
    for (var x = 0; x < matrix.width; x++) {
      if (matrix.get(x, y) != 1) continue;
      img.fillRect(
        page,
        x1: left + x * scale,
        y1: top + y * scale,
        x2: left + (x + 1) * scale - 1,
        y2: top + (y + 1) * scale - 1,
        color: img.ColorRgb8(0, 0, 0),
      );
    }
  }
  return img.encodePng(page);
}

void main() {
  test('a subscription link round-trips through a screenshot', () {
    const link = 'https://sub.example.net/api/v1/client/subscribe?token=abc123';
    expect(decodeQrImageSync(qrPng(link)), link);
  });

  test('a share link with non-ASCII in its name survives', () {
    const link = 'vless://id@tokyo.example.net:443?security=reality#东京 01';
    expect(decodeQrImageSync(qrPng(link)), link);
  });

  test('a large screenshot is scaled down and still read', () {
    const link = 'trojan://pass@la.example.net:443#LA';
    expect(
      decodeQrImageSync(qrPng(link, scale: 14, width: 1440, height: 3168)),
      link,
    );
  });

  test('an image without a code, or not an image, gives null', () {
    final blank = img.Image(width: 200, height: 200);
    img.fill(blank, color: img.ColorRgb8(255, 255, 255));
    expect(decodeQrImageSync(img.encodePng(blank)), isNull);
    expect(decodeQrImageSync(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
