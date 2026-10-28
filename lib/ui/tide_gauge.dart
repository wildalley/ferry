/// The dashboard's signature: a tide gauge whose water level is the tunnel's
/// throughput.
///
/// A basin with a log scale down its left edge and water inside it. The level
/// sits where the current rate falls on that scale, so a page load is a swell
/// and a download is high water; the surface rolls while bytes are moving. With
/// the tunnel down the basin holds only a dashed low-water line.
///
/// Motion follows the backdrop's rule: one beat per traffic reading, never a
/// free-running loop. A tunnel carrying nothing holds still, and a
/// frame-settling wait in a test can always finish.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// The rate at the top of the scale: a round 16 MB/s.
const _fullScale = 16 * 1024 * 1024;

/// The rate at the floor: 1 KB/s. Anything slower is a trickle — keepalives,
/// a chat app polling — and reads as low water.
const _floor = 1024;

/// Where [rate] sits on the gauge, 0 at the floor and 1 at the top.
///
/// Logarithmic between [_floor] and [_fullScale], because throughput spans
/// orders of magnitude: on a linear scale everything short of a saturated link
/// would lie flat on the floor. Starting the log at 1 KB/s rather than at zero
/// spreads the scale evenly — 64 KB/s near the middle, 1 MB/s at about two
/// thirds — instead of crowding every useful rate into the top fifth.
double tideLevel(int rate) {
  if (rate <= _floor) return 0;
  return (math.log(rate / _floor) / math.log(_fullScale / _floor))
      .clamp(0.0, 1.0);
}

class TideGauge extends StatefulWidget {
  const TideGauge({
    super.key,
    required this.live,
    this.reading,
    this.downlink = const [],
    this.uplink = const [],
    this.label,
    this.height = 120,
  });

  /// Whether the tunnel is up. Down, the basin shows low water only.
  final bool live;

  /// The latest traffic reading, compared by identity: a new object is a new
  /// reading and starts a beat. Without it a parent that rebuilds for other
  /// reasons — the dashboard's once-a-second uptime tick — would restart the
  /// beat forever on a steady sample, and nothing would ever settle.
  final Object? reading;

  /// Recent throughput in bytes per second, oldest first.
  final List<int> downlink;
  final List<int> uplink;

  /// Written in the basin's top-left corner: the level as a rate.
  final String? label;

  final double height;

  @override
  State<TideGauge> createState() => _TideGaugeState();
}

class _TideGaugeState extends State<TideGauge>
    with SingleTickerProviderStateMixin {
  /// One beat per reading; readings arrive about once a second, so the beats
  /// run together into a rolling surface while traffic flows.
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );

  int get _rate =>
      (widget.downlink.isEmpty ? 0 : widget.downlink.last) +
      (widget.uplink.isEmpty ? 0 : widget.uplink.last);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant TideGauge oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(fresh: !identical(oldWidget.reading, widget.reading));
  }

  void _sync({bool fresh = true}) {
    final canAnimate = widget.live &&
        _rate > 0 &&
        !MediaQuery.of(context).disableAnimations &&
        TickerMode.valuesOf(context).enabled;
    if (!canAnimate) {
      _beat.stop();
      return;
    }
    if (fresh && !_beat.isAnimating) _beat.forward(from: 0);
  }

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final target = widget.live ? math.max(.06, tideLevel(_rate)) : 0.0;

    return Semantics(
      label: widget.label,
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: RepaintBoundary(
          child: TweenAnimationBuilder<double>(
            // The level eases between readings rather than stepping, so a
            // burst reads as the water rising.
            tween: Tween(end: target),
            duration: motionOf(context, Motion.slow),
            curve: Motion.curve,
            builder: (context, level, child) => CustomPaint(
              painter: _TidePainter(
                level: level,
                live: widget.live,
                phase: _beat,
                water: palette.water,
                line: widget.live ? palette.violetSoft : palette.faint,
                basin: Color.alphaBlend(
                  palette.bg.withValues(alpha: dark ? .55 : .5),
                  palette.surface,
                ),
                grid: palette.border,
                scale: palette.faint,
                dark: dark,
              ),
              child: child,
            ),
            child: widget.label == null
                ? null
                : Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        _TidePainter.gutter + 10,
                        8,
                        10,
                        0,
                      ),
                      child: ExcludeSemantics(
                        child: Text(
                          widget.label!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: monoStyle(
                            size: 10.5,
                            weight: FontWeight.w500,
                            color: widget.live
                                ? palette.violetSoft
                                : palette.faint,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _TidePainter extends CustomPainter {
  _TidePainter({
    required this.level,
    required this.live,
    required this.phase,
    required this.water,
    required this.line,
    required this.basin,
    required this.grid,
    required this.scale,
    required this.dark,
  }) : super(repaint: phase);

  /// 0..1 up the basin.
  final double level;
  final bool live;
  final Animation<double> phase;
  final List<Color> water;
  final Color line;
  final Color basin;
  final Color grid;
  final Color scale;
  final bool dark;

  /// Width of the scale column left of the basin.
  static const gutter = 30.0;

  /// Scale marks, as rates.
  static const _marks = <(int, String)>[
    (16 * 1024 * 1024, '16M'),
    (1024 * 1024, '1M'),
    (64 * 1024, '64K'),
    (_floor, '1K'),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(gutter, 0, size.width, size.height);
    final r = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    canvas.drawRRect(r, Paint()..color = basin);

    // Floor and ceiling inset: the floor keeps the line inside the rounded
    // corners, and the ceiling leaves a band for the level label so high
    // water never runs under the text.
    const top = 26.0;
    final floor = size.height - 6;
    double yFor(double l) => floor - (floor - top) * l;

    // Scale: dashed rules across the basin and their rates in the gutter.
    final dash = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final (rate, text) in _marks) {
      final y = yFor(tideLevel(rate));
      if (rate > _floor) {
        for (var x = rect.left + 6; x < rect.right - 6; x += 7) {
          canvas.drawLine(Offset(x, y), Offset(x + 3, y), dash);
        }
      }
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: AppFonts.mono,
            fontSize: 9,
            color: scale,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          gutter - 5 - painter.width,
          (y - painter.height / 2).clamp(0.0, size.height - painter.height),
        ),
      );
    }

    canvas.save();
    canvas.clipRRect(r);
    if (!live) {
      // Low water: a still, dashed line near the floor.
      final y = yFor(.08);
      final low = Paint()
        ..color = line.withValues(alpha: .8)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      for (var x = rect.left + 8; x < rect.right - 8; x += 9) {
        canvas.drawLine(Offset(x, y), Offset(x + 4, y), low);
      }
      canvas.restore();
      return;
    }

    final surface = yFor(level);
    // Higher water rolls harder.
    final amplitude = 2.5 + 3.5 * level;
    const wavelength = 72.0;
    final shift = phase.value * wavelength;

    Path wave(double y, double amp, double offset) {
      final path = Path()..moveTo(rect.left, size.height);
      for (var x = rect.left; x <= rect.right; x += 3) {
        final t = (x + offset) / wavelength * 2 * math.pi;
        path.lineTo(x, y + math.sin(t) * amp);
      }
      return path
        ..lineTo(rect.right, size.height)
        ..close();
    }

    // Back swell: lighter, out of phase, a few pixels higher.
    canvas.drawPath(
      wave(surface - 4, amplitude * .8, -shift * .6 + wavelength / 3),
      Paint()..color = water.first.withValues(alpha: dark ? .10 : .12),
    );
    // Front water, deepening toward the floor.
    final front = wave(surface, amplitude, shift);
    canvas.drawPath(
      front,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            water.first.withValues(alpha: dark ? .22 : .20),
            water.last.withValues(alpha: dark ? .30 : .26),
          ],
        ).createShader(Rect.fromLTRB(0, surface, size.width, size.height)),
    );
    // The waterline itself.
    final crest = Path();
    for (var x = rect.left; x <= rect.right; x += 3) {
      final t = (x + shift) / wavelength * 2 * math.pi;
      final y = surface + math.sin(t) * amplitude;
      if (x == rect.left) {
        crest.moveTo(x, y);
      } else {
        crest.lineTo(x, y);
      }
    }
    if (dark) {
      canvas.drawPath(
        crest,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..color = line.withValues(alpha: .18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
    canvas.drawPath(
      crest,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round
        ..color = line,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TidePainter old) =>
      old.level != level ||
      old.live != live ||
      old.line != line ||
      old.basin != basin ||
      old.grid != grid ||
      old.scale != scale ||
      old.dark != dark ||
      old.water.first != water.first ||
      old.water.last != water.last;
}

/// A short solid bar in the brand foreground: a section's tick, the chosen
/// row's edge.
class AccentBar extends StatelessWidget {
  const AccentBar({super.key, this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.palette.violetSoft,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
