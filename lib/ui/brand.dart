/// Shared brand artwork. Decorative images never participate in hit testing.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chart_painting.dart';
import 'theme.dart';

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

/// In light mode luminance becomes alpha, producing a violet engraving instead
/// of putting a black rectangle behind the controls. Both use the same asset.
///
/// The artwork is not only a bitmap anymore. The image supplies the fine fibre
/// detail, while [_SilkPainter] reshapes and highlights the main ribbons from
/// the live throughput samples, download and upload separately. A beat starts
/// for each non-zero reading, so a flowing tunnel keeps the silk alive without
/// a free-running ticker implying traffic when the tunnel is idle.
class SignalArtwork extends StatefulWidget {
  const SignalArtwork({
    super.key,
    this.opacity = 1,
    this.alignment = Alignment.centerRight,
    this.animate = false,
    this.downlink = const [],
    this.uplink = const [],
  });

  final double opacity;
  final Alignment alignment;
  final bool animate;
  final List<int> downlink;
  final List<int> uplink;

  @override
  State<SignalArtwork> createState() => _SignalArtworkState();
}

class _SignalArtworkState extends State<SignalArtwork>
    with SingleTickerProviderStateMixin {
  /// One beat per traffic reading, the same contract as the console backdrop.
  ///
  /// Readings land about once a second, so a beat a little shorter than that
  /// finishes and rests before the next one restarts it; the painter keeps
  /// every motion a whole number of cycles per beat so the restart is seamless.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );

  static const _fullScale = 8 * 1024 * 1024;

  /// The latest sample in one direction as a 0..1 level on a log scale, so a
  /// chat poll and a download are both visible without one pegging the other.
  static double _level(List<int> samples) {
    final rate = samples.isEmpty ? 0 : samples.last;
    if (rate <= 0) return 0;
    final value = math.log(1 + rate) / math.log(1 + _fullScale);
    return value.clamp(0.0, 1.0);
  }

  double get _down => _level(widget.downlink);
  double get _up => _level(widget.uplink);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant SignalArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  /// The reading the last beat was started for.
  ///
  /// A beat belongs to a new sample, not to a rebuild. The dashboard also
  /// rebuilds once a second for its uptime clock, and restarting on that would
  /// turn one beat per reading into continuous motion with nothing behind it.
  Object? _beatFor;

  static Object _reading(SignalArtwork w) => (
        w.downlink.length,
        w.downlink.isEmpty ? 0 : w.downlink.last,
        w.uplink.length,
        w.uplink.isEmpty ? 0 : w.uplink.last,
      );

  void _syncAnimation() {
    final canAnimate = widget.animate &&
        (_down > 0 || _up > 0) &&
        !MediaQuery.of(context).disableAnimations &&
        TickerMode.valuesOf(context).enabled;
    if (!canAnimate) {
      _controller.stop();
      _beatFor = null;
      return;
    }
    final reading = _reading(widget);
    if (reading == _beatFor) return;
    _beatFor = reading;
    if (!_controller.isAnimating) _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.palette;
    final base = Image.asset(
      'assets/branding/signal-flow.webp',
      fit: BoxFit.cover,
      alignment: widget.alignment,
      excludeFromSemantics: true,
      filterQuality: FilterQuality.medium,
    );
    Widget artwork = base;
    if (!dark) {
      artwork = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          0,
          0,
          0,
          0,
          86,
          0,
          0,
          0,
          0,
          58,
          0,
          0,
          0,
          0,
          184,
          .2126,
          .7152,
          .0722,
          0,
          0,
        ]),
        child: artwork,
      );
    }
    // The bitmap no longer drifts. A moving image under moving lines doubled
    // the motion on the card for no extra information, and it was the part
    // that kept the whole hero repainting; the ribbons alone carry the traffic.
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Opacity(
          opacity: widget.opacity * (dark ? 1 : .45),
          child: ClipRect(
            child: CustomPaint(
              foregroundPainter: _SilkPainter(
                downColor: palette.sky,
                upColor: palette.mint,
                dark: dark,
                phase: _controller,
                down: _down,
                up: _up,
              ),
              child: artwork,
            ),
          ),
        ),
      ),
    );
  }
}

/// The live ribbons over the artwork: two for download, two for upload.
///
/// Each pair answers to its own direction. A ribbon's sway, brightness and the
/// speed of the light running along it all come from that direction's latest
/// rate, so a download wakes the sky pair while the mint pair stays calm, and an
/// upload does the reverse. Download light runs along the fold, upload light
/// runs back against it. A direction carrying nothing draws as a faint still
/// line: the link is there, nothing is moving on it.
class _SilkPainter extends CustomPainter {
  _SilkPainter({
    required this.downColor,
    required this.upColor,
    required this.dark,
    required this.phase,
    required this.down,
    required this.up,
  }) : super(repaint: phase);

  final Color downColor;
  final Color upColor;
  final bool dark;
  final Animation<double> phase;

  /// 0..1 levels for each direction.
  final double down;
  final double up;

  static const _anchors = <Offset>[
    Offset(-.16, .80),
    Offset(.02, .81),
    Offset(.20, .72),
    Offset(.37, .52),
    Offset(.53, .35),
    Offset(.69, .31),
    Offset(.86, .18),
    Offset(1.12, .00),
  ];

  static const _ribbons = <_RibbonSpec>[
    _RibbonSpec(offset: -.046, amplitude: .030, width: 2.0, seed: .4),
    _RibbonSpec(offset: -.014, amplitude: .044, width: 3.2, seed: 1.9),
    _RibbonSpec(offset: .020, amplitude: .050, width: 3.0, seed: 3.4, up: true),
    _RibbonSpec(offset: .053, amplitude: .032, width: 1.8, seed: 5.3, up: true),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 80 || size.height < 80) return;

    for (final ribbon in _ribbons) {
      final level = ribbon.up ? up : down;
      final color = ribbon.up ? upColor : downColor;
      // Some sway even at a trickle, so "moving" and "idle" read apart.
      final activity = level <= 0 ? 0.0 : .25 + level * .75;
      final path = _pathFor(ribbon, size, activity);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = ribbon.width * 4.5
          ..color = color.withValues(alpha: (dark ? .07 : .05) * activity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = ribbon.width * (1 + level * .6)
          ..color = color.withValues(
            alpha: (dark ? .09 : .07) + activity * (dark ? .18 : .12),
          ),
      );
      if (level > 0 && ribbon.width >= 2.5) {
        _drawTravelingHighlight(canvas, path, ribbon, level);
      }
    }
  }

  /// Whole laps per beat: faster traffic, faster light.
  ///
  /// A whole number so the beat's end and the next beat's start coincide;
  /// a fractional lap would snap the highlight back each second.
  static int _laps(double level) => 1 + (level * 3).round();

  void _drawTravelingHighlight(
    Canvas canvas,
    Path path,
    _RibbonSpec ribbon,
    double level,
  ) {
    final metric = path.computeMetrics().firstOrNull;
    if (metric == null || metric.length <= 0) return;

    // A short feathered segment travels along the ribbon, split into pieces
    // so its tail fades and wrap-around never jumps from end to start.
    final travel =
        (phase.value * _laps(level) + ribbon.seed / (math.pi * 2)) % 1;
    final position = ribbon.up ? 1 - travel : travel;
    final length = metric.length * (.10 + level * .10);
    final center = position * metric.length;
    const pieces = 9;
    final pieceLength = length / pieces;
    for (var index = 0; index < pieces; index++) {
      final distance = center - length / 2 + (index + .5) * pieceLength;
      var start = distance % metric.length;
      if (start < 0) start += metric.length;
      final end = start + pieceLength;
      final alpha = math.sin((index + 1) / (pieces + 1) * math.pi);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = .9 + level * .9
        ..color = Colors.white.withValues(
          alpha: alpha * ((dark ? .18 : .12) + level * (dark ? .18 : .12)),
        );
      if (end <= metric.length) {
        canvas.drawPath(metric.extractPath(start, end), paint);
      } else {
        canvas.drawPath(metric.extractPath(start, metric.length), paint);
        canvas.drawPath(metric.extractPath(0, end - metric.length), paint);
      }
    }
  }

  Path _pathFor(_RibbonSpec ribbon, Size size, double activity) {
    // Whole turns per beat, for the same seam reason as [_laps]. Upload sways
    // the other way round so the two pairs never move in lock step.
    final radians = phase.value * math.pi * 2 * (ribbon.up ? -1 : 1);
    final points = <Offset>[];
    for (final anchor in _anchors) {
      final x = anchor.dx;
      final wave = math.sin(radians + x * 8.8 + ribbon.seed) *
          ribbon.amplitude *
          activity;
      final secondary = math.cos(radians * 2 + x * 14.0 + ribbon.seed * 1.9) *
          ribbon.amplitude *
          .38 *
          activity;
      final y = anchor.dy + ribbon.offset + wave + secondary;
      points.add(Offset(x * size.width, y * size.height));
    }
    return smoothThrough(
      points,
      minY: -size.height * .3,
      maxY: size.height * 1.3,
    );
  }

  @override
  bool shouldRepaint(covariant _SilkPainter oldDelegate) =>
      oldDelegate.downColor != downColor ||
      oldDelegate.upColor != upColor ||
      oldDelegate.dark != dark ||
      oldDelegate.down != down ||
      oldDelegate.up != up;
}

class _RibbonSpec {
  const _RibbonSpec({
    required this.offset,
    required this.amplitude,
    required this.width,
    required this.seed,
    this.up = false,
  });

  final double offset;
  final double amplitude;
  final double width;
  final double seed;

  /// Carries the upload rate rather than the download rate.
  final bool up;
}
