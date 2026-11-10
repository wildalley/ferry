/// Shared brand artwork. Decorative images never participate in hit testing.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';


class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/branding/app-icon.png',
        width: size,
        height: size,
        excludeFromSemantics: true,
        filterQuality: FilterQuality.medium,
      );
}

/// The brand plate: violet, lit from the upper left. Fixed rather than read
/// from the theme so the mark in the app matches the launcher icon exactly.
const brandPlateLight = Color(0xFF8A66FF);
const brandPlateDark = Color(0xFF5A33E6);

/// Paints the mark — a paper plane over a wave — into a [size] square.
///
/// The one drawing every copy of the mark comes from: the rail's [BrandLogo]
/// and, through `test/render_icons_test.dart`, the launcher, tray and Windows
/// icons. A paper plane reads as "send" at any size and in any language,
/// which is what makes it recognisable as a connection tool; the wave under it
/// is the water it crosses.
///
/// [plate] fills a rounded tile ([round] for a disc) with [plateColors];
/// without it the background stays clear, for Android's adaptive foreground.
/// [waves] off drops the wave, for sizes where it would blur into the plane.
void paintBrandMark(
  Canvas canvas,
  double size, {
  bool plate = true,
  bool round = false,
  bool waves = true,
  List<Color> plateColors = const [brandPlateLight, brandPlateDark],
  Color ink = Colors.white,
}) {
  final rect = Offset.zero & Size(size, size);
  if (plate) {
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: plateColors,
      ).createShader(rect);
    if (round) {
      canvas.drawOval(rect, paint);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(size * .24)),
        paint,
      );
    }
  }

  // The plane, in a box over the upper two thirds; lifted when no wave sits
  // under it so it centres on its own.
  final box = Rect.fromLTWH(
    size * .19,
    size * (waves ? .17 : .24),
    size * .6,
    size * .44,
  );
  Offset at(double u, double v) =>
      Offset(box.left + box.width * u, box.top + box.height * v);
  final tip = at(1, 0);
  final wing = at(0, .44);
  final fold = at(.4, .6);
  final tail = at(.56, 1);
  // Upper facet solid, lower facet a shade back: the fold is what turns a
  // triangle into a folded plane.
  canvas.drawPath(
    Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(wing.dx, wing.dy)
      ..lineTo(fold.dx, fold.dy)
      ..close(),
    Paint()..color = ink,
  );
  canvas.drawPath(
    Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(fold.dx, fold.dy)
      ..lineTo(tail.dx, tail.dy)
      ..close(),
    Paint()..color = ink.withValues(alpha: .72),
  );

  if (!waves) return;
  final pen = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = math.max(1.2, size * .05)
    ..color = ink.withValues(alpha: .92);
  void wave(double y, double from, double to, double alpha) {
    final path = Path();
    const steps = 32;
    for (var i = 0; i <= steps; i++) {
      final x = from + (to - from) * i / steps;
      final dy = math.sin(i / steps * math.pi * 3) * size * .028;
      if (i == 0) {
        path.moveTo(x, y + dy);
      } else {
        path.lineTo(x, y + dy);
      }
    }
    canvas.drawPath(path, pen..color = ink.withValues(alpha: alpha));
  }

  wave(size * .76, size * .2, size * .8, .92);
}

/// The mark as a widget, for the rail and anywhere else the brand appears.
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: CustomPaint(
          size: Size.square(size),
          painter: _BrandLogoPainter(),
        ),
      );
}

class _BrandLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => paintBrandMark(canvas, size.width);

  @override
  bool shouldRepaint(covariant _BrandLogoPainter oldDelegate) => false;
}
