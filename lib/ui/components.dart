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
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A dot in the series colour, not a tinted icon tile: the colour is
          // what ties the card to its line on the chart below, and the tile
          // was a second, louder way of saying the label.
          Semantics(
            label: label,
            child: Row(
              children: [
                ExcludeSemantics(
                  child: Icon(icon, size: 13, color: accent),
                ),
                const SizedBox(width: 6),
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
              ],
            ),
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
          line: palette.text.withValues(alpha: dark ? .035 : .05),
          glowColour: accent.withValues(alpha: dark ? .045 : .025),
          signalColour: accent,
          dark: dark,
          phase: widget.showSignals ? _signalController : null,
          showSignals: widget.showSignals,
          intensity: _intensity,
          levels: _levels,
          downIntensity: _downIntensity,
          upIntensity: _upIntensity,
          downColor: palette.violet,
          upColor: palette.sky,
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

  static const _cell = 40.0;

  @override
  void paint(Canvas canvas, Size size) {
    // A faint grid, then light: a wash from the top, and on a live dashboard a
    // soft bloom that brightens with the tunnel's throughput and drifts while
    // bytes are moving. The grid is drawn at the floor of what renders — it
    // is texture behind the panels, and the panels are solid, so it only ever
    // shows in the gutters between them.
    final bounds = Rect.fromLTWH(0, 0, size.width, size.height);
    final pen = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += _cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), pen);
    }
    for (var y = 0.0; y <= size.height; y += _cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), pen);
    }
    final top = Offset(size.width * .35, 0);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          colors: [glowColour, glowColour.withValues(alpha: 0)],
        ).createShader(
          Rect.fromCircle(center: top, radius: size.height * .9),
        ),
    );

    if (!showSignals) return;
    final drift = math.sin((phase?.value ?? 0) * math.pi) * .02;
    final lift = (dark ? .05 : .035) + intensity * (dark ? .07 : .04);
    void bloom(Offset centre, double radius, Color colour, double alpha) {
      canvas.drawRect(
        bounds,
        Paint()
          ..shader = RadialGradient(
            colors: [
              colour.withValues(alpha: alpha),
              colour.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: centre, radius: radius)),
      );
    }

    final extent = math.max(size.width, size.height);
    bloom(
      Offset(size.width * (.86 + drift), size.height * .08),
      extent * (.38 + .1 * downIntensity),
      downColor,
      lift,
    );
    bloom(
      Offset(size.width * (.62 - drift), size.height * .02),
      extent * (.30 + .1 * upIntensity),
      upColor,
      lift * .9,
    );
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
