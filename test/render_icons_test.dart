/// Renders the launcher, app, tray and desktop icons from code into the
/// platform resource folders.
///
/// Not part of the default suite — it rewrites checked-in bitmaps. Run it after
/// changing the mark, then review the PNGs:
///
///   RENDER_ICONS=1 flutter test test/render_icons_test.dart
///
/// Every copy comes from [paintBrandMark], the same function the app's rail
/// draws with, so the launcher and the window can never disagree.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:singbox_client/ui/brand.dart';

final _run = Platform.environment['RENDER_ICONS'] == '1';

/// The disconnected tray icon: the same mark, greyed.
const _mutedPlate = [Color(0xFF8E8DA3), Color(0xFF5F5E70)];

Future<Uint8List> _png(int size, void Function(Canvas, double) draw) async {
  final recorder = ui.PictureRecorder();
  draw(Canvas(recorder), size.toDouble());
  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  return bytes!.buffer.asUint8List();
}

/// A Windows icon holding PNG-compressed entries, which Vista and later read.
Uint8List _ico(List<(int, Uint8List)> entries) {
  final header = BytesBuilder()
    ..add(_u16(0))
    ..add(_u16(1))
    ..add(_u16(entries.length));
  var offset = 6 + 16 * entries.length;
  final directory = BytesBuilder();
  for (final (size, png) in entries) {
    directory
      ..addByte(size >= 256 ? 0 : size)
      ..addByte(size >= 256 ? 0 : size)
      ..addByte(0)
      ..addByte(0)
      ..add(_u16(1))
      ..add(_u16(32))
      ..add(_u32(png.length))
      ..add(_u32(offset));
    offset += png.length;
  }
  return (BytesBuilder()
        ..add(header.toBytes())
        ..add(directory.toBytes())
        ..add([for (final (_, png) in entries) ...png]))
      .toBytes();
}

List<int> _u16(int v) => [v & 0xFF, (v >> 8) & 0xFF];
List<int> _u32(int v) =>
    [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

void main() {
  testWidgets('render icons', skip: !_run, (tester) async {
    await tester.runAsync(() async {
      Future<void> write(String file, Uint8List data) async {
        await File(file).parent.create(recursive: true);
        await File(file).writeAsBytes(data);
      }

      Future<Uint8List> tile(int size, {bool round = false}) =>
          _png(size, (c, s) => paintBrandMark(c, s, round: round));

      const res = 'android/app/src/main/res';
      // Adaptive foreground: the plane and wave alone, inset into the safe
      // circle by ic_launcher_foreground.xml; the violet comes from the
      // background drawable.
      await write(
        '$res/drawable-nodpi/ic_launcher_art.png',
        await _png(512, (c, s) {
          c.translate(s * .12, s * .12);
          paintBrandMark(c, s * .76, plate: false);
        }),
      );
      for (final (density, size) in [
        ('mdpi', 48),
        ('hdpi', 72),
        ('xhdpi', 96),
        ('xxhdpi', 144),
        ('xxxhdpi', 192),
      ]) {
        await write('$res/mipmap-$density/ic_launcher.png', await tile(size));
        await write(
          '$res/mipmap-$density/ic_launcher_round.png',
          await tile(size, round: true),
        );
      }
      await write('assets/branding/app-icon.png', await tile(256));
      // The hicolor sizes scripts/package.sh installs for the Linux desktop
      // entry. Outside assets/ so they do not ride along in every bundle.
      for (final size in [64, 128, 256, 512]) {
        await write('docs/design/icon/linux/$size.png', await tile(size));
      }
      // Tray: no wave — at 16–24px it would blur into the plane.
      await write(
        'assets/tray/tray_connected.png',
        await _png(64, (c, s) => paintBrandMark(c, s, waves: false)),
      );
      await write(
        'assets/tray/tray_disconnected.png',
        await _png(
          64,
          (c, s) =>
              paintBrandMark(c, s, waves: false, plateColors: _mutedPlate),
        ),
      );
      await write(
        'windows/runner/resources/app_icon.ico',
        _ico([
          for (final size in [16, 24, 32, 48, 64, 128, 256])
            (size, await tile(size)),
        ]),
      );
    });
  });
}
