/// Dashboard components: metric cards, the traffic flow chart, and the
/// console background.
///
/// These are the pieces the wide-screen dashboard is built from. They are kept
/// out of `widgets.dart` because that file holds the primitives every page
/// uses, while these only appear on the dashboard.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'chart_painting.dart';
import 'theme.dart';
import 'widgets.dart' show AnimatedCount;

/// One dashboard figure: label, value, and an optional trailing chart.
///
/// The value is monospaced so a column of these keeps its digits aligned while
/// numbers tick over.
class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.format,
    required this.icon,
    required this.accent,
    this.caption,
    this.chart,
  });

  final String label;

  /// The reading itself, as a number so it can be tweened. [format] turns it
  /// into the text that is drawn.
  final int value;

  /// Renders [value]. Cards with nothing to report yet — a rate while
  /// disconnected — return a placeholder from here and ignore the argument.
  final String Function(int value) format;

  /// Secondary line under the value: a rate, a unit, a share.
  final String? caption;
  final IconData icon;
  final Color accent;

  /// Optional visual, a sparkline, pinned under the value.
  final Widget? chart;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.lg, Gap.lg, Gap.md),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: Color.alphaBlend(accent.withValues(alpha: .15), palette.border),
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: .025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label first, glyph trailing: the label is what a reader scans the
          // row for, and a tinted tile in front of it competed with the value.
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Icon(icon, size: 14, color: accent),
              ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          AnimatedCount(
            value: value,
            format: format,
            style: monoStyle(
                size: 24, weight: FontWeight.w600, color: palette.text),
          ),
          // Always one line high, so an equal-height row of cards keeps its
          // values and charts on shared baselines whether or not a card has a
          // second figure.
          const SizedBox(height: Gap.xs),
          Text(
            caption ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: monoStyle(size: 11, color: palette.muted),
          ),
          if (chart != null) ...[
            // Minimum gap first, then the spacer: these cards sit in an
            // equal-height row, and a card stretched by a taller neighbour would
            // otherwise float its chart mid-card. On the tallest card the
            // spacer collapses to zero and the gap holds.
            const SizedBox(height: Gap.md),
            const Spacer(),
            chart!,
          ],
        ],
      ),
    );
  }
}

bool _sameValues(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Programmatic console backdrop: a faint grid under a radial vignette.
///
/// Drawn rather than shipped as a bitmap — see the design note in
/// `docs/design/synapse-v4.md` §3. Alphas are deliberately near the floor of
/// what renders: this should register as texture, not as a visible grid. The
/// optional signal field belongs only on a live connection surface, keeping the
/// rest of the app calm while still giving the dashboard the presence of the
/// reference console.
///
/// The signal field reads the tunnel's own throughput. It used to be a fixed
/// diagram on a twelve-second loop, which meant it kept flowing at a steady rate
/// through an idle tunnel and looked identical during a download — a decoration
/// that implied activity it knew nothing about. Given [downlink] and [uplink] it
/// instead brightens, quickens and stills with the traffic actually moving.
class ConsoleBackground extends StatefulWidget {
  const ConsoleBackground({
    super.key,
    this.child,
    this.accent,
    this.animate = false,
    this.showSignals = false,
    this.downlink = const [],
    this.uplink = const [],
  });

  final Widget? child;

  /// Tint for the vignette and the optional signal field. Defaults to violet.
  final Color? accent;

  /// Whether the signal field should move. It automatically pauses for reduced
  /// motion, while this subtree is not ticker-enabled, and while the samples
  /// below are all zero — an idle tunnel holds still rather than burning a
  /// ticker on motion nobody asked for.
  final bool animate;

  /// Draws the low-contrast node-and-packet field behind a live surface.
  final bool showSignals;

  /// Recent throughput in bytes per second, oldest first.
  ///
  /// The same series [TrafficFlowChart] draws, and normalised the same way, so
  /// the backdrop and the chart in front of it cannot disagree about what a
  /// burst looked like. Empty leaves the field at rest.
  final List<int> downlink;
  final List<int> uplink;

  @override
  State<ConsoleBackground> createState() => _ConsoleBackgroundState();
}

class _ConsoleBackgroundState extends State<ConsoleBackground>
    with SingleTickerProviderStateMixin {
  /// One beat of motion, run once per traffic reading.
  ///
  /// Deliberately not a `repeat()`. A free-running loop would keep the field
  /// moving at a constant rate regardless of the tunnel, which is the dishonesty
  /// this replaces — and it would also never let a frame-settling wait finish, so
  /// every test that renders a connected app would hang instead of failing.
  /// Readings arrive about once a second while connected, so one beat per reading
  /// is continuous motion while traffic flows and stillness the moment it stops.
  ///
  /// A little shorter than the reading interval, so a beat lands and rests rather
  /// than being cut off mid-flight by the next one.
  late final AnimationController _signalController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// How many nodes the field draws, and so how many samples it reads.
  static const _nodeCount = 12;

  /// The rate that lights the field fully, in bytes per second.
  ///
  /// A round 8 MB/s: fast enough that an ordinary download does not peg the
  /// field, slow enough that one is clearly busier than a chat app polling.
  static const _fullScale = 8 * 1024 * 1024;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant ConsoleBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  /// Starts a beat if the tunnel is carrying something, and stops otherwise.
  ///
  /// Called on every rebuild, which while connected means once per traffic
  /// reading: each one sets off a beat, and the beats run together into motion
  /// for as long as the readings keep coming. When they stop — or carry nothing —
  /// the last beat finishes and the field comes to rest by itself.
  void _syncAnimation() {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final canAnimate = widget.animate &&
        widget.showSignals &&
        // Nothing is moving through the tunnel, so nothing moves here either.
        // The graph stays drawn — it is the tunnel's shape, not its activity.
        _rate(widget) > 0 &&
        !reduceMotion &&
        TickerMode.valuesOf(context).enabled;
    if (!canAnimate) {
      _signalController.stop();
      return;
    }
    // From zero rather than resumed: a beat is one pass of the packets along
    // their links, and restarting it is what makes a new reading visible.
    if (!_signalController.isAnimating) _signalController.forward(from: 0);
  }

  /// The most recent combined throughput sample, in bytes per second.
  static int _rate(ConsoleBackground widget) =>
      (widget.downlink.isEmpty ? 0 : widget.downlink.last) +
      (widget.uplink.isEmpty ? 0 : widget.uplink.last);

  static double _logIntensity(int rate) {
    if (rate <= 0) return 0;
    final value = math.log(1 + rate) / math.log(1 + _fullScale);
    return value.clamp(0.0, 1.0);
  }

  /// Current throughput as a 0..1 brightness, on a log scale.
  ///
  /// Log rather than linear because throughput spans orders of magnitude: on a
  /// linear scale against any ceiling worth having, everything short of a
  /// saturated link would sit indistinguishably at the dim end.
  double get _intensity => _logIntensity(_rate(widget));

  double get _downIntensity =>
      _logIntensity(widget.downlink.isEmpty ? 0 : widget.downlink.last);

  double get _upIntensity =>
      _logIntensity(widget.uplink.isEmpty ? 0 : widget.uplink.last);

  /// The recent history as one 0..1 level per node, oldest first.
  ///
  /// Normalised to the peak across both directions, which is exactly how
  /// [TrafficFlowChart] scales the same samples — so the backdrop and the chart
  /// drawn in front of it cannot disagree about how big a burst was.
  List<double> get _levels {
    final down = widget.downlink;
    final up = widget.uplink;
    final length = math.max(down.length, up.length);
    if (length == 0) return List.filled(_nodeCount, 0);

    final combined = <int>[
      for (var i = 0; i < length; i++)
        (i < down.length ? down[i] : 0) + (i < up.length ? up[i] : 0),
    ];
    final peak = combined.fold(0, math.max);
    if (peak <= 0) return List.filled(_nodeCount, 0);

    // Nearest sample rather than an average: a burst is usually one tall
    // sample, and averaging it with its quiet neighbours is how it disappears.
    return [
      for (var i = 0; i < _nodeCount; i++)
        combined[(i * length / _nodeCount).floor()] / peak,
    ];
  }

  @override
  void dispose() {
    _signalController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accent ?? palette.violet;
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ConsolePainter(
          line: palette.text.withValues(alpha: dark ? .014 : .018),
          glowColour: accent.withValues(alpha: dark ? .045 : .025),
          signalColour: accent,
          dark: dark,
          phase: widget.showSignals ? _signalController : null,
          showSignals: widget.showSignals,
          intensity: _intensity,
          levels: _levels,
          downIntensity: _downIntensity,
          upIntensity: _upIntensity,
          downColor: palette.sky,
          upColor: palette.mint,
        ),
        child: widget.child,
      ),
    );
  }
}

class _ConsolePainter extends CustomPainter {
  _ConsolePainter({
    required this.line,
    required this.glowColour,
    required this.signalColour,
    required this.dark,
    required this.phase,
    required this.showSignals,
    required this.intensity,
    required this.levels,
    this.downIntensity = 0.0,
    this.upIntensity = 0.0,
    this.downColor = const Color(0xFF7FD2FF),
    this.upColor = const Color(0xFF22E1A6),
  }) : super(repaint: phase);

  final Color line;
  final Color glowColour;
  final Color signalColour;
  final bool dark;
  final Animation<double>? phase;
  final bool showSignals;

  /// Current throughput, 0..1 on a log scale. Drives brightness and speed.
  final double intensity;

  /// One 0..1 level per node, oldest first — the recent history of the same
  /// samples the traffic chart draws.
  final List<double> levels;

  final double downIntensity;
  final double upIntensity;
  final Color downColor;
  final Color upColor;

  static const _cell = 48.0;

  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = line
      ..strokeWidth = 1;

    for (var x = 0.0; x <= size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), pen);
    }
    for (var y = 0.0; y <= size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), pen);
    }

    // Grid intersection highlights when traffic is moving
    if (showSignals && intensity > 0 && size.width > 200) {
      final crossPaint = Paint()
        ..color = signalColour.withValues(
          alpha: (dark ? 0.08 : 0.04) * intensity,
        )
        ..strokeWidth = 1;
      const step = _cell * 2;
      for (var x = _cell; x < size.width; x += step) {
        for (var y = _cell; y < size.height; y += step) {
          canvas.drawLine(Offset(x - 2, y), Offset(x + 2, y), crossPaint);
          canvas.drawLine(Offset(x, y - 2), Offset(x, y + 2), crossPaint);
        }
      }
    }

    // Vignette from the top: pulls attention to the header and fades the grid
    // out before it reaches the content below.
    final centre = Offset(size.width / 2, 0);
    final radius = size.height * 0.95;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = RadialGradient(
          colors: [glowColour, glowColour.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: centre, radius: radius)),
    );

    // Speed-driven auroral glows (Download cyan, Upload mint)
    if (showSignals && (downIntensity > 0 || upIntensity > 0)) {
      if (downIntensity > 0) {
        final downCenter = Offset(size.width * 0.78, size.height * 0.26);
        final downRadius = size.height * (0.35 + downIntensity * 0.45);
        final downAlpha =
            (dark ? 0.22 : 0.14) + downIntensity * (dark ? 0.40 : 0.24);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()
            ..shader = RadialGradient(
              colors: [
                downColor.withValues(alpha: downAlpha),
                downColor.withValues(alpha: downAlpha * 0.4),
                downColor.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(
                Rect.fromCircle(center: downCenter, radius: downRadius)),
        );
      }
      if (upIntensity > 0) {
        final upCenter = Offset(size.width * 0.65, size.height * 0.74);
        final upRadius = size.height * (0.30 + upIntensity * 0.40);
        final upAlpha =
            (dark ? 0.18 : 0.12) + upIntensity * (dark ? 0.35 : 0.20);
        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()
            ..shader = RadialGradient(
              colors: [
                upColor.withValues(alpha: upAlpha),
                upColor.withValues(alpha: upAlpha * 0.4),
                upColor.withValues(alpha: 0),
              ],
              stops: const [0.0, 0.5, 1.0],
            ).createShader(Rect.fromCircle(center: upCenter, radius: upRadius)),
        );
      }
    }

    if (showSignals && size.width >= 180 && size.height >= 120) {
      final progress = phase?.value ?? 0;
      _drawSpeedWaves(canvas, size, progress);
      _drawSignalField(canvas, size, progress);
    }
  }

  /// Dynamic fluid speed waves across the background that undulate in real time
  /// according to download and upload speeds.
  void _drawSpeedWaves(Canvas canvas, Size size, double progress) {
    // Download wave (cascades across upper-mid canvas)
    if (downIntensity > 0) {
      final laps = 1 + (downIntensity * 3).round();
      final phaseVal = (progress * laps) * math.pi * 2;
      final waveAmp = 10.0 + downIntensity * 28.0;
      final baseY = size.height * 0.34;
      final points = <Offset>[];
      const count = 7;
      final startX = size.width * 0.30;
      final spanX = size.width * 0.74;
      for (var i = 0; i <= count; i++) {
        final t = i / count;
        final x = startX + t * spanX;
        final sinVal = math.sin(phaseVal + t * math.pi * 2.8);
        final cosVal = math.cos(phaseVal * 1.4 + t * math.pi * 1.6) * 0.35;
        final y = baseY + (sinVal + cosVal) * waveAmp;
        points.add(Offset(x, y));
      }
      final wavePath = smoothThrough(points, minY: 0, maxY: size.height);
      final alpha =
          (dark ? 0.18 : 0.12) + downIntensity * (dark ? 0.38 : 0.22);

      canvas.drawPath(
        wavePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 6.0 + downIntensity * 8.0
          ..color = downColor.withValues(alpha: alpha * 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawPath(
        wavePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 2.0 + downIntensity * 1.5
          ..color = downColor.withValues(alpha: alpha),
      );
    }

    // Upload wave (ripples across lower-mid canvas)
    if (upIntensity > 0) {
      final laps = 1 + (upIntensity * 3).round();
      final phaseVal = -(progress * laps) * math.pi * 2;
      final waveAmp = 8.0 + upIntensity * 24.0;
      final baseY = size.height * 0.68;
      final points = <Offset>[];
      const count = 7;
      final startX = size.width * 0.36;
      final spanX = size.width * 0.68;
      for (var i = 0; i <= count; i++) {
        final t = i / count;
        final x = startX + t * spanX;
        final sinVal = math.sin(phaseVal + t * math.pi * 2.5);
        final cosVal = math.cos(phaseVal * 1.3 + t * math.pi * 1.7) * 0.3;
        final y = baseY + (sinVal + cosVal) * waveAmp;
        points.add(Offset(x, y));
      }
      final wavePath = smoothThrough(points, minY: 0, maxY: size.height);
      final alpha =
          (dark ? 0.16 : 0.10) + upIntensity * (dark ? 0.32 : 0.18);

      canvas.drawPath(
        wavePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 5.0 + upIntensity * 7.0
          ..color = upColor.withValues(alpha: alpha * 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawPath(
        wavePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.8 + upIntensity * 1.2
          ..color = upColor.withValues(alpha: alpha),
      );
    }
  }

  /// A small network diagram, biased to the right side of the card so headings
  /// and controls retain a quiet reading surface.
  ///
  /// The layout is fixed — it stands for the tunnel, which does not change shape
  /// while it is up — but everything drawn over it comes from [levels] and
  /// [intensity]. Each node carries one recent throughput sample: a busy moment
  /// is a bright wide node, a quiet one nearly disappears, and the row of them
  /// left to right is the same history the traffic chart plots. The packets move
  /// at a rate the tunnel is actually sustaining, and an idle tunnel holds
  /// perfectly still.
  void _drawSignalField(Canvas canvas, Size size, double progress) {
    const points = <Offset>[
      Offset(.52, .16),
      Offset(.70, .10),
      Offset(.87, .18),
      Offset(.62, .32),
      Offset(.80, .36),
      Offset(.95, .43),
      Offset(.49, .52),
      Offset(.69, .57),
      Offset(.88, .64),
      Offset(.61, .75),
      Offset(.79, .82),
      Offset(.97, .78),
    ];
    const links = <(int, int)>[
      (0, 1),
      (0, 3),
      (1, 2),
      (1, 4),
      (2, 4),
      (2, 5),
      (3, 4),
      (3, 6),
      (4, 5),
      (4, 7),
      (5, 8),
      (6, 7),
      (6, 9),
      (7, 8),
      (7, 9),
      (7, 10),
      (8, 10),
      (8, 11),
      (9, 10),
      (10, 11),
    ];

    /// The sample at [index], or 0 where there is no history for it yet.
    double level(int index) {
      if (index < 0 || index >= levels.length) return 0;
      final value = levels[index];
      return value < 0 ? 0 : (value > 1 ? 1 : value);
    }

    Offset pointAt(int index) {
      final source = points[index];
      final angle = progress * math.pi * 2 + index * 1.73;
      // Sub-pixel drift is enough to keep the field alive. Larger motion makes
      // a dense dashboard feel unstable, especially beside changing figures.
      // Busy nodes drift furthest, so the eye finds the active part of the
      // history without the whole field becoming restless.
      final reach = 1.1 + level(index) * 2.2;
      return Offset(
        source.dx * size.width + math.sin(angle) * reach,
        source.dy * size.height + math.cos(angle * 1.17) * reach * .88,
      );
    }

    final resolved = <Offset>[
      for (var i = 0; i < points.length; i++) pointAt(i)
    ];

    // The graph is always drawn: it stands for the tunnel, which is up whether
    // or not bytes are moving right now. Its links only brighten with the two
    // samples they join, so an idle tunnel is a faint outline rather than a
    // missing one.
    final baseLink = dark ? .055 : .032;
    final litLink = dark ? .105 : .065;
    for (final (from, to) in links) {
      final share = (level(from) + level(to)) / 2;
      canvas.drawLine(
        resolved[from],
        resolved[to],
        Paint()
          ..color = signalColour.withValues(
            alpha: baseLink + (litLink - baseLink) * share,
          )
          ..strokeWidth = 1,
      );
    }

    for (var i = 0; i < resolved.length; i++) {
      final share = level(i);
      final haloAlpha = (dark ? .07 : .04) + (dark ? .16 : .09) * share;
      final nodeAlpha = (dark ? .26 : .18) + (dark ? .40 : .28) * share;
      canvas.drawCircle(
        resolved[i],
        2.6 + share * 2.4,
        Paint()
          ..color = signalColour.withValues(alpha: haloAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      canvas.drawCircle(
        resolved[i],
        1.1 + share * .9,
        Paint()..color = signalColour.withValues(alpha: nodeAlpha),
      );
    }

    // Active hub sonar radar pulse during traffic bursts
    if (intensity > 0.05 && resolved.length > 4) {
      final center = resolved[4]; // Central junction node
      final pulseRadius = 5.0 + progress * (24.0 + intensity * 32.0);
      final pulseAlpha = (1.0 - progress) * (dark ? 0.32 : 0.18) * intensity;
      canvas.drawCircle(
        center,
        pulseRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = (downIntensity >= upIntensity ? downColor : upColor)
              .withValues(alpha: pulseAlpha),
      );
    }

    // Packets are the part that has to be honest: a moving dot reads as traffic,
    // so their number and speed come from the throughput rather than from a
    // fixed loop. Nothing moving means none drawn — the caller has stopped the
    // ticker by then, so this is what an idle tunnel actually looks like.
    if (intensity <= 0) return;

    const packetLinks = <(int, int)>[
      (0, 4),
      (3, 7),
      (6, 10),
      (4, 8),
      (1, 4),
      (4, 5),
      (7, 9),
      (8, 11),
    ];
    final count = 1 + (intensity * (packetLinks.length - 1)).round();
    // Traversals per beat, so throughput sets the speed: a busy tunnel sends a
    // packet along its link six times where an idle-but-open one sends it once.
    final turns = 1 + (intensity * 5).round();

    for (var i = 0; i < count; i++) {
      final (from, to) = packetLinks[i];
      final isUp = i.isOdd;
      final pktColor = isUp ? upColor : downColor;
      final travel = (progress * turns + i * .27) % 1;
      final eased = Curves.easeInOut.transform(travel);
      final head = Offset.lerp(resolved[from], resolved[to], eased)!;

      // Laser streak speed tail
      final tailTravel = (travel - (0.04 + intensity * 0.12)).clamp(0.0, 1.0);
      final tailEased = Curves.easeInOut.transform(tailTravel);
      final tail = Offset.lerp(resolved[from], resolved[to], tailEased)!;

      if ((head - tail).distance > 1.2) {
        canvas.drawLine(
          tail,
          head,
          Paint()
            ..color = pktColor.withValues(
              alpha: (dark ? 0.40 : 0.24) * intensity,
            )
            ..strokeWidth = 2.4 + intensity * 1.6
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
        );
        canvas.drawLine(
          tail,
          head,
          Paint()
            ..color = pktColor.withValues(alpha: dark ? 0.85 : 0.65)
            ..strokeWidth = 1.2
            ..strokeCap = StrokeCap.round,
        );
      }

      // Packet head
      canvas.drawCircle(
        head,
        4.6 + intensity * 2.0,
        Paint()
          ..color = pktColor.withValues(alpha: dark ? .42 : .24)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawCircle(
        head,
        1.8 + intensity * 0.8,
        Paint()..color = Colors.white.withValues(alpha: dark ? .95 : .85),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ConsolePainter oldDelegate) =>
      oldDelegate.line != line ||
      oldDelegate.glowColour != glowColour ||
      oldDelegate.signalColour != signalColour ||
      oldDelegate.dark != dark ||
      oldDelegate.showSignals != showSignals ||
      // A new traffic sample has to reach the canvas even while the ticker is
      // stopped: an idle field that just took one reading is not repainted by
      // `repaint: phase` alone, and would keep showing the old history.
      oldDelegate.intensity != intensity ||
      oldDelegate.downIntensity != downIntensity ||
      oldDelegate.upIntensity != upIntensity ||
      oldDelegate.downColor != downColor ||
      oldDelegate.upColor != upColor ||
      !_sameLevels(oldDelegate.levels, levels);

  static bool _sameLevels(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// The wide dashboard's centrepiece: down and up rates on one shared scale.
///
/// Both series share a peak so the two curves stay comparable — scaling each to
/// its own maximum would make a trickle of upload look like a flood. Sized for
/// the full panel width rather than the sparkline's inline strip.
class TrafficFlowChart extends StatelessWidget {
  const TrafficFlowChart({
    super.key,
    required this.downlink,
    required this.uplink,
    required this.downColor,
    required this.upColor,
    this.height = 168,
  });

  final List<int> downlink;
  final List<int> uplink;
  final Color downColor;
  final Color upColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _FlowPainter(
          downlink: downlink,
          uplink: uplink,
          downColor: downColor,
          upColor: upColor,
          gridColor: palette.border,
          dpr: MediaQuery.of(context).devicePixelRatio,
        ),
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.downlink,
    required this.uplink,
    required this.downColor,
    required this.upColor,
    required this.gridColor,
    required this.dpr,
  });

  final List<int> downlink;
  final List<int> uplink;
  final Color downColor;
  final Color upColor;
  final Color gridColor;

  /// Device pixel ratio, so the rules land on whole pixels. A painter cannot
  /// read it itself.
  final double dpr;

  /// Horizontal rules, including the baseline. Four is enough to read height off
  /// without turning the panel into graph paper.
  static const _gridLines = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i < _gridLines; i++) {
      final span = size.height - 1;
      final y = crispLine(span - span * i / (_gridLines - 1), dpr);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // One shared peak across both series, so the curves stay comparable.
    final peak = [...downlink, ...uplink].fold(0, math.max);
    if (peak <= 0) return;

    // Upload drawn first: it is usually the smaller series, so leaving it on top
    // would let its fill wash over the download curve.
    _series(canvas, size, uplink, peak, upColor);
    _series(canvas, size, downlink, peak, downColor);
  }

  void _series(
    Canvas canvas,
    Size size,
    List<int> values,
    int peak,
    Color color,
  ) {
    if (values.length < 2) return;

    final step = size.width / (values.length - 1);
    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(i * step, size.height - (values[i] / peak) * (size.height - 6)),
    ];

    // Through every sample — see [smoothThrough]. The old midpoint smoothing
    // drew a burst at about half its height, on the one chart whose job is to
    // show bursts.
    final line = smoothThrough(points, minY: 1, maxY: size.height - 1);

    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawPath(
      Path.from(line)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: .22),
            color.withValues(alpha: 0),
          ],
        ).createShader(bounds),
    );

    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _FlowPainter oldDelegate) =>
      oldDelegate.downColor != downColor ||
      oldDelegate.upColor != upColor ||
      oldDelegate.gridColor != gridColor ||
      oldDelegate.dpr != dpr ||
      !_sameValues(oldDelegate.downlink, downlink) ||
      !_sameValues(oldDelegate.uplink, uplink);
}
