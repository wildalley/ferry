part of 'home_page.dart';

// ============================================================================
// Desktop View: High-productivity Command Center
// ============================================================================

class _DesktopHomeDashboard extends StatelessWidget {
  const _DesktopHomeDashboard({
    required this.state,
    required this.onOpenNodes,
    required this.wide,
  });

  final AppState state;
  final VoidCallback onOpenNodes;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final connected = state.isConnected;
    final traffic = state.traffic;
    final showConnections = connected &&
        (traffic.connectionList.isNotEmpty || traffic.connections == 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DesktopCommandHorizon(
          state: state,
          onOpenNodes: onOpenNodes,
        ),
        const SizedBox(height: Gap.lg),
        _StatTiles(state: state, columns: wide ? 4 : 2),
        const SizedBox(height: Gap.lg),
        _TrafficPanel(state: state, height: wide ? 168 : 120),
        if (showConnections) ...[
          const SizedBox(height: Gap.lg),
          _ConnectionsPanel(state: state, compact: !wide),
        ],
      ],
    );
  }
}

/// Unified, futuristic widescreen Command Horizon for desktop screens.
class _DesktopCommandHorizon extends StatelessWidget {
  const _DesktopCommandHorizon({
    required this.state,
    required this.onOpenNodes,
  });

  final AppState state;
  final VoidCallback onOpenNodes;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final proxy = state.proxyState;
    final connected = proxy.isConnected;
    final failed = proxy.stage == ProxyStage.error;
    final accent = _stageAccent(palette, proxy.stage);
    final node = state.selectedNode;
    final list = state.traffic.connectionList;
    final listed = list.isNotEmpty || state.traffic.connections == 0;

    (int, int) tally(ConnectionRoute route) {
      var count = 0, bytes = 0;
      for (final c in list) {
        if (c.route != route) continue;
        count++;
        bytes += c.bytes;
      }
      return (count, bytes);
    }

    final nodeFacts = node == null || state.isAutoSelected
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: palette.surface3,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(color: palette.border),
                ),
                child: Text(
                  node.protocol.label,
                  style: monoStyle(size: 11, color: palette.faint),
                ),
              ),
              const SizedBox(width: Gap.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: latencyColor(palette, node.latencyMs)
                      .withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  border: Border.all(
                    color: latencyColor(palette, node.latencyMs)
                        .withValues(alpha: .35),
                  ),
                ),
                child: Text(
                  _latencyText(l10n, node.latencyMs),
                  style: monoStyle(
                    size: 11,
                    weight: FontWeight.w600,
                    color: latencyColor(palette, node.latencyMs),
                  ),
                ),
              ),
            ],
          );

    return Panel(
      padding: EdgeInsets.zero,
      accent: connected || failed ? accent : null,
      glowing: connected || failed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Stack(
          children: [
            // Background flowing artwork
            Positioned.fill(
              child: SignalArtwork(
                opacity: .85,
                animate: connected,
                downlink: state.downlinkHistory,
                uplink: state.uplinkHistory,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      palette.surface.withValues(alpha: .85),
                      palette.surface.withValues(alpha: .60),
                      palette.surface.withValues(alpha: .15),
                    ],
                    stops: const [0, .5, 1],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top Bar: Stage Pill, Title, Node badges, Uptime capsule
                  Row(
                    children: [
                      StatusPill(
                        label: _stageLabel(l10n, proxy.stage),
                        color: accent,
                        compact: true,
                      ),
                      const SizedBox(width: Gap.md),
                      Expanded(
                        child: Text(
                          _exitName(l10n, state),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    letterSpacing: -0.2,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ),
                      if (nodeFacts != null) ...[
                        nodeFacts,
                        const SizedBox(width: Gap.md),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: palette.surface2,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: palette.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer_outlined,
                                size: 13, color: palette.faint),
                            const SizedBox(width: Gap.xs),
                            Text(
                              connected && proxy.since != null
                                  ? formatUptime(
                                      clockNow().difference(proxy.since!))
                                  : '—',
                              style: monoStyle(
                                size: 11,
                                weight: FontWeight.w600,
                                color: palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (state.nodes.isNotEmpty) ...[
                        const SizedBox(width: Gap.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: palette.surface2,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: palette.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.dns_rounded,
                                  size: 13, color: palette.faint),
                              const SizedBox(width: Gap.xs),
                              Text(
                                l10n.homeAvailableOf(
                                  _availableNodes(state.nodes),
                                  state.nodes.length,
                                ),
                                style: monoStyle(
                                  size: 11,
                                  weight: FontWeight.w600,
                                  color: palette.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _stageDetail(l10n, state),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: Gap.xl),

                  // Middle Horizon: Twin Speed Cockpits + Split Allocation + Primary Action
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Download Speed Pod
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                            minWidth: 100, maxWidth: 155),
                        child: _RateReadout(
                          key: const Key('home-download-rate'),
                          label: l10n.homeDownload,
                          icon: Icons.arrow_downward_rounded,
                          color: palette.sky,
                          rate: state.traffic.downlink,
                          connected: connected,
                          size: 32,
                        ),
                      ),
                      const SizedBox(width: Gap.md),
                      // Upload Speed Pod
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                            minWidth: 100, maxWidth: 155),
                        child: _RateReadout(
                          label: l10n.homeUpload,
                          icon: Icons.arrow_upward_rounded,
                          color: palette.mint,
                          rate: state.traffic.uplink,
                          connected: connected,
                          size: 32,
                        ),
                      ),
                      const Spacer(),
                      // Exit IP & Route Split Bar
                      SizedBox(
                        width: 200,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ExitAddressRow(state: state),
                            const SizedBox(height: Gap.sm),
                            _TrafficSplitBar(
                              proxy:
                                  listed ? tally(ConnectionRoute.proxy).$1 : 0,
                              direct:
                                  listed ? tally(ConnectionRoute.direct).$1 : 0,
                              reject:
                                  listed ? tally(ConnectionRoute.reject).$1 : 0,
                              total: list.length,
                              proxyColor: palette.violetSoft,
                              directColor: palette.mint,
                              rejectColor: palette.danger,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: Gap.md),
                      // Action triggers
                      SizedBox(
                        width: 130,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _ConnectButton(
                                state: state, onOpenNodes: onOpenNodes),
                            const SizedBox(height: Gap.xs),
                            OutlinedButton(
                              onPressed: onOpenNodes,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 36),
                                padding: EdgeInsets.zero,
                              ),
                              child: Text(
                                state.nodes.isEmpty
                                    ? l10n.homeAddNodes
                                    : l10n.homeChangeNode,
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Mobile View: Dedicated Thumb-Friendly Ergonomic Experience
// ============================================================================

class _MobileHomeDashboard extends StatelessWidget {
  const _MobileHomeDashboard({
    required this.state,
    required this.onOpenNodes,
  });

  final AppState state;
  final VoidCallback onOpenNodes;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final connected = state.isConnected;
    final list = state.traffic.connectionList;
    final showConnections = connected &&
        (list.isNotEmpty || state.traffic.connections == 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Central Holographic Connection Dial
        _MobileConnectionDial(state: state, onOpenNodes: onOpenNodes),
        const SizedBox(height: Gap.lg),

        // 2. Twin Speed Readouts (Download & Upload with bandwidth meters)
        Row(
          children: [
            Expanded(
              child: _RateReadout(
                key: const Key('home-download-rate'),
                label: l10n.homeDownload,
                icon: Icons.arrow_downward_rounded,
                color: palette.sky,
                rate: state.traffic.downlink,
                connected: connected,
                size: 26,
              ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: _RateReadout(
                label: l10n.homeUpload,
                icon: Icons.arrow_upward_rounded,
                color: palette.mint,
                rate: state.traffic.uplink,
                connected: connected,
                size: 26,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gap.md),

        // 3. Quick Node & Exit IP Card
        _MobileExitCard(state: state, onOpenNodes: onOpenNodes),
        const SizedBox(height: Gap.md),

        // 4. Primary Connection Action Button
        _ConnectButton(state: state, onOpenNodes: onOpenNodes),
        const SizedBox(height: Gap.xl),

        // 5. System Health & Performance (2x2 Grid)
        _StatTiles(state: state, columns: 2),
        const SizedBox(height: Gap.lg),

        // 6. Live Traffic Flow Horizon
        _TrafficPanel(state: state, height: 110),
        const SizedBox(height: Gap.lg),

        // 7. Routing Split & Rules Matrix
        _RoutingPanel(state: state, onOpenNodes: onOpenNodes, stretch: false),

        // 8. Active Connections (when connected)
        if (showConnections) ...[
          const SizedBox(height: Gap.lg),
          _ConnectionsPanel(state: state, compact: true),
        ],
      ],
    );
  }
}

/// Dedicated Mobile Connection Dial: Cyber ring that accelerates with throughput.
class _MobileConnectionDial extends StatefulWidget {
  const _MobileConnectionDial({
    required this.state,
    required this.onOpenNodes,
  });

  final AppState state;
  final VoidCallback onOpenNodes;

  @override
  State<_MobileConnectionDial> createState() => _MobileConnectionDialState();
}

class _MobileConnectionDialState extends State<_MobileConnectionDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dialController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _MobileConnectionDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final canAnimate = widget.state.isConnected &&
        (widget.state.traffic.downlink > 0 || widget.state.traffic.uplink > 0) &&
        !MediaQuery.of(context).disableAnimations &&
        TickerMode.valuesOf(context).enabled;
    if (!canAnimate) {
      _dialController.stop();
      return;
    }
    if (!_dialController.isAnimating) _dialController.forward(from: 0);
  }

  @override
  void dispose() {
    _dialController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final proxy = widget.state.proxyState;
    final connected = proxy.isConnected;
    final accent = _stageAccent(palette, proxy.stage);
    final empty = widget.state.nodes.isEmpty;
    final rate = widget.state.traffic.downlink + widget.state.traffic.uplink;
    final speedFactor = (rate <= 0
            ? 0.0
            : math.log(1 + rate) / math.log(1 + 32 * 1024 * 1024))
        .clamp(0.0, 1.0);

    return Center(
      child: GestureDetector(
        onTap: widget.state.isBusy
            ? null
            : (empty ? widget.onOpenNodes : widget.state.toggleConnection),
        child: SizedBox(
          width: 210,
          height: 210,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer dynamic rotating aura ring
              AnimatedBuilder(
                animation: _dialController,
                builder: (context, _) => CustomPaint(
                  size: const Size(210, 210),
                  painter: _DialRingPainter(
                    accent: accent,
                    connected: connected,
                    speedFactor: speedFactor,
                    progress: _dialController.value,
                    dark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
              ),
              // Inner frosted dial container
              Container(
                width: 168,
                height: 168,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: palette.surface,
                  border: Border.all(
                    color: connected
                        ? accent.withValues(alpha: .38)
                        : palette.border,
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: connected
                          ? accent.withValues(alpha: .20)
                          : Colors.black.withValues(alpha: .06),
                      blurRadius: 20,
                      spreadRadius: connected ? 2 : 0,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (widget.state.isBusy)
                        SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: accent,
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accent.withValues(alpha: .12),
                          ),
                          child: Icon(
                            switch (true) {
                              _ when empty => Icons.add_rounded,
                              _ when connected =>
                                Icons.power_settings_new_rounded,
                              _ => Icons.power_settings_new_rounded,
                            },
                            size: 26,
                            color: accent,
                          ),
                        ),
                      const SizedBox(height: Gap.xs),
                      StatusPill(
                        label: _stageLabel(l10n, proxy.stage),
                        color: accent,
                        compact: true,
                        bare: true,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _exitName(l10n, widget.state),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DialRingPainter extends CustomPainter {
  _DialRingPainter({
    required this.accent,
    required this.connected,
    required this.speedFactor,
    required this.progress,
    required this.dark,
  });

  final Color accent;
  final bool connected;
  final double speedFactor;
  final double progress;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;

    // Track
    final trackPaint = Paint()
      ..color = connected
          ? accent.withValues(alpha: dark ? .18 : .12)
          : (dark ? Colors.white10 : Colors.black12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(center, radius, trackPaint);

    if (!connected) return;

    // Energy arcs rotating with progress and speed
    final turns = 1 + (speedFactor * 3).round();
    final angle = (progress * turns) * math.pi * 2;
    final arcPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 3.5;

    // Main rotating arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      angle,
      math.pi * (0.35 + speedFactor * 0.45),
      false,
      arcPaint,
    );
    // Counter-arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      angle + math.pi,
      math.pi * 0.25,
      false,
      Paint()
        ..color = accent.withValues(alpha: .45)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.0,
    );
  }

  @override
  bool shouldRepaint(covariant _DialRingPainter oldDelegate) =>
      oldDelegate.accent != accent ||
      oldDelegate.connected != connected ||
      oldDelegate.speedFactor != speedFactor ||
      oldDelegate.progress != progress ||
      oldDelegate.dark != dark;
}

/// Compact mobile card showing node details and exit country.
class _MobileExitCard extends StatelessWidget {
  const _MobileExitCard({
    required this.state,
    required this.onOpenNodes,
  });

  final AppState state;
  final VoidCallback onOpenNodes;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final node = state.selectedNode;
    final address = state.exitAddress;

    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      onTap: onOpenNodes,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: palette.violet.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.hub_rounded, size: 16, color: palette.violetSoft),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _exitName(l10n, state),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (address?.countryCode case final code?) ...[
                      const SizedBox(width: Gap.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: tintFill(palette.mint),
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Text(
                          code,
                          style: monoStyle(
                            size: 9,
                            color: palette.mint,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  node == null || state.isAutoSelected
                      ? l10n.homeChangeNode
                      : '${node.protocol.label} · ${_latencyText(l10n, node.latencyMs)}',
                  style: monoStyle(size: 11, color: palette.faint),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, size: 18, color: palette.faint),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ status

/// One direction's live rate: a keyed label over a large mono figure, with
/// the unit trailing on the baseline and a dynamic bandwidth activity bar.
class _RateReadout extends StatelessWidget {
  const _RateReadout({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.rate,
    required this.connected,
    required this.size,
  });

  final String label;
  final IconData icon;
  final Color color;

  /// Bytes per second.
  final int rate;
  final bool connected;

  /// Figure size; the unit scales from it.
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final unit = connected ? formatRate(rate).split(' ').last : '';
    final progress = !connected || rate <= 0
        ? 0.0
        : (math.log(1 + rate) / math.log(1 + 32 * 1024 * 1024)).clamp(0.04, 1.0);

    return Container(
      constraints: BoxConstraints(minWidth: size > 30 ? 105 : 0),
      padding: EdgeInsets.symmetric(
        horizontal: size > 30 ? 12 : 10,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: palette.surface2.withValues(alpha: .50),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: connected
              ? color.withValues(alpha: .22)
              : palette.border.withValues(alpha: .6),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: (connected ? color : palette.faint).withValues(alpha: .14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 12, color: connected ? color : palette.faint),
              ),
              const SizedBox(width: Gap.xs),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: Gap.xs),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AnimatedCount(
                  // A unit change starts a fresh count. Tweening a KB value
                  // beside the new MB label would overstate the rate during the
                  // transition.
                  key: ValueKey(connected ? unit : 'unavailable'),
                  value: rate,
                  format: (value) =>
                      connected ? formatRate(value).split(' ').first : '—',
                  style: monoStyle(
                    size: size,
                    weight: FontWeight.w600,
                    color: palette.text,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  unit,
                  style: monoStyle(
                    size: math.max(11, size * .32),
                    color: palette.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // Speed activity indicator bar
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Container(
              height: 3,
              color: palette.border.withValues(alpha: .4),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final barWidth = constraints.hasBoundedWidth
                      ? constraints.maxWidth
                      : (size > 30 ? 130.0 : 90.0);
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      width: (barWidth * progress).clamp(0.0, barWidth),
                      height: 3,
                      decoration: BoxDecoration(
                        color: connected ? color : Colors.transparent,
                        boxShadow: connected && progress > 0.05
                            ? [
                                BoxShadow(
                                  color: color.withValues(alpha: .6),
                                  blurRadius: 4,
                                )
                              ]
                            : null,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- routing

/// How the open connections split across proxy, direct and block, plus the
/// exit address and the way into the node list.
class _RoutingPanel extends StatelessWidget {
  const _RoutingPanel({
    required this.state,
    required this.onOpenNodes,
    required this.stretch,
  });

  final AppState state;
  final VoidCallback onOpenNodes;

  /// Sitting in an equal-height row, so the footer can be pushed to the
  /// bottom. A Spacer in an unbounded column would throw.
  final bool stretch;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final list = state.traffic.connectionList;
    // The runtime reported a count but no list (libbox): the split is
    // unknown, which is not the same as zero.
    final listed = list.isNotEmpty || state.traffic.connections == 0;

    (int, int) tally(ConnectionRoute route) {
      var count = 0, bytes = 0;
      for (final c in list) {
        if (c.route != route) continue;
        count++;
        bytes += c.bytes;
      }
      return (count, bytes);
    }

    final rows = [
      for (final (route, label, color) in [
        (ConnectionRoute.proxy, l10n.rulesTargetProxy, palette.violetSoft),
        (ConnectionRoute.direct, l10n.rulesTargetDirect, palette.mint),
        (ConnectionRoute.reject, l10n.rulesTargetBlock, palette.danger),
      ])
        _RouteRow(
          label: label,
          color: color,
          tally: listed ? tally(route) : null,
          total: list.length,
        ),
    ];

    return Panel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelTitle(title: l10n.homeRouting, icon: Icons.alt_route_rounded),
          const SizedBox(height: Gap.md),
          _TrafficSplitBar(
            proxy: listed ? tally(ConnectionRoute.proxy).$1 : 0,
            direct: listed ? tally(ConnectionRoute.direct).$1 : 0,
            reject: listed ? tally(ConnectionRoute.reject).$1 : 0,
            total: list.length,
            proxyColor: palette.violetSoft,
            directColor: palette.mint,
            rejectColor: palette.danger,
          ),
          const SizedBox(height: Gap.sm),
          ...rows,
          if (stretch) const Spacer() else const SizedBox(height: Gap.md),
          const SizedBox(height: Gap.sm),
          _ExitAddressRow(state: state),
          const SizedBox(height: Gap.sm),
          OutlinedButton(
            onPressed: onOpenNodes,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 40),
            ),
            // On the node list rather than on the selection: under Auto there
            // is no node to name, and offering to add one would be wrong with
            // a subscription already imported.
            child: Text(
              state.nodes.isEmpty ? l10n.homeAddNodes : l10n.homeChangeNode,
            ),
          ),
        ],
      ),
    );
  }
}

/// Visual distribution bar indicating the share of traffic across routes.
class _TrafficSplitBar extends StatelessWidget {
  const _TrafficSplitBar({
    required this.proxy,
    required this.direct,
    required this.reject,
    required this.total,
    required this.proxyColor,
    required this.directColor,
    required this.rejectColor,
  });

  final int proxy;
  final int direct;
  final int reject;
  final int total;
  final Color proxyColor;
  final Color directColor;
  final Color rejectColor;

  @override
  Widget build(BuildContext context) {
    if (total == 0) {
      return Container(
        height: 4,
        decoration: BoxDecoration(
          color: context.palette.border,
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 5,
        child: Row(
          children: [
            if (proxy > 0)
              Expanded(
                flex: proxy,
                child: Container(color: proxyColor),
              ),
            if (direct > 0)
              Expanded(
                flex: direct,
                child: Container(color: directColor),
              ),
            if (reject > 0)
              Expanded(
                flex: reject,
                child: Container(color: rejectColor),
              ),
          ],
        ),
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.label,
    required this.color,
    required this.tally,
    required this.total,
  });

  final String label;
  final Color color;

  /// Connections and their bytes, or null when the runtime does not say.
  final (int, int)? tally;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final (count, bytes) = tally ?? (0, 0);
    final share = tally == null || total == 0 ? null : count * 100 ~/ total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: Gap.sm),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: palette.muted),
            ),
          ),
          Text(
            tally == null ? '—' : '$count',
            style: monoStyle(
              size: 13,
              weight: FontWeight.w600,
              color: palette.text,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              share == null ? '' : '$share%',
              textAlign: TextAlign.right,
              style: monoStyle(size: 11, color: palette.faint),
            ),
          ),
          SizedBox(
            width: 68,
            child: Text(
              tally == null ? '' : formatBytes(bytes),
              textAlign: TextAlign.right,
              style: monoStyle(size: 11, color: palette.faint),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- tiles

/// Totals and levels, four across on a desktop and two by two on a phone.
class _StatTiles extends StatelessWidget {
  const _StatTiles({required this.state, required this.columns});

  final AppState state;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final traffic = state.traffic;
    final connected = state.isConnected;

    final tiles = [
      MetricCard(
        label: l10n.homeDownload,
        value: traffic.downlinkTotal,
        format: formatBytes,
        caption: connected ? formatRate(traffic.downlink) : '—',
        icon: Icons.arrow_downward_rounded,
        accent: palette.sky,
        chart: Sparkline(
          values: state.downlinkHistory,
          color: connected ? palette.sky : palette.faint,
          height: 28,
        ),
      ),
      MetricCard(
        label: l10n.homeUpload,
        value: traffic.uplinkTotal,
        format: formatBytes,
        caption: connected ? formatRate(traffic.uplink) : '—',
        icon: Icons.arrow_upward_rounded,
        accent: palette.mint,
        chart: Sparkline(
          values: state.uplinkHistory,
          color: connected ? palette.mint : palette.faint,
          height: 28,
        ),
      ),
      MetricCard(
        label: l10n.homeConnections,
        value: traffic.connections,
        format: (value) => '$value',
        // Not hub_outlined: that is the Nodes tab, and one glyph naming two
        // different things sends a reader to the wrong page.
        icon: Icons.lan_outlined,
        accent: palette.violetSoft,
        // A level: the open-connection count rarely visits zero, so it is
        // drawn as variation around its own range rather than from zero.
        chart: Sparkline(
          values: state.connectionHistory,
          color: connected ? palette.violetSoft : palette.faint,
          height: 28,
          level: true,
        ),
      ),
      MetricCard(
        label: l10n.homeMemory,
        // The runtime only reports memory while it is running; zero would
        // read as a measurement, so idle shows a dash.
        value: traffic.memory,
        format: (value) => connected ? formatBytes(value) : '—',
        icon: Icons.memory_outlined,
        accent: palette.amber,
        chart: Sparkline(
          values: state.memoryHistory,
          color: connected ? palette.amber : palette.faint,
          height: 28,
          level: true,
        ),
      ),
    ];

    if (columns >= 4) return PixelRow(children: tiles);
    return Column(
      children: [
        PixelRow(children: tiles.sublist(0, 2)),
        const SizedBox(height: Gap.lg),
        PixelRow(children: tiles.sublist(2)),
      ],
    );
  }
}

// ----------------------------------------------------------------- traffic

/// Both rates over the last minute on one shared scale, with that scale's top
/// written on the chart so the curve's height means a number.
class _TrafficPanel extends StatelessWidget {
  const _TrafficPanel({required this.state, required this.height});

  final AppState state;
  final double height;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final connected = state.isConnected;
    final down = state.downlinkHistory;
    final up = state.uplinkHistory;
    final peak = [...down, ...up].fold(0, math.max);

    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: PanelTitle(
                  title: l10n.homeLiveTraffic,
                  icon: Icons.show_chart_rounded,
                ),
              ),
              _FlowLegend(
                label: l10n.homeDownload,
                color: connected ? palette.sky : palette.faint,
              ),
              const SizedBox(width: Gap.md),
              _FlowLegend(
                label: l10n.homeUpload,
                color: connected ? palette.mint : palette.faint,
              ),
            ],
          ),
          const SizedBox(height: Gap.md),
          Stack(
            children: [
              TrafficFlowChart(
                downlink: down,
                uplink: up,
                downColor: connected ? palette.sky : palette.faint,
                upColor: connected ? palette.mint : palette.faint,
                height: height,
              ),
              // The top rule's value. Samples carry no timestamps, so the
              // x-axis is stated below rather than ticked.
              if (peak > 0)
                Positioned(
                  right: 0,
                  top: 2,
                  child: Text(
                    formatRate(peak),
                    style: monoStyle(size: 10, color: palette.faint),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Gap.sm),
          Text(
            l10n.homeLastMinute,
            style: monoStyle(color: palette.faint, size: 11),
          ),
        ],
      ),
    );
  }
}

/// Dot-and-label key for one series on the traffic chart.
class _FlowLegend extends StatelessWidget {
  const _FlowLegend({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

// ------------------------------------------------------------- connections

/// The busiest open connections: where each is going, how it was routed,
/// which exit it took and how much it has moved.
class _ConnectionsPanel extends StatelessWidget {
  const _ConnectionsPanel({required this.state, required this.compact});

  final AppState state;

  /// Phone width: two stacked lines per row instead of five columns.
  final bool compact;

  /// Enough to see what is busy without the table becoming the page.
  static const _desktopRows = 12;
  static const _phoneRows = 6;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final list = [...state.traffic.connectionList]
      ..sort((a, b) => b.bytes.compareTo(a.bytes));
    final shown = list.take(compact ? _phoneRows : _desktopRows).toList();
    // Outbound tags carry a hash suffix the user never typed; show the name
    // they know the node by.
    final names = {
      for (final node in state.nodes)
        ConfigBuilder.outboundTag(node): node.name,
    };

    return Panel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PanelTitle(
            title: l10n.homeActiveConnections,
            icon: Icons.lan_outlined,
            trailing: Text(
              '${list.length}',
              style: monoStyle(size: 12, color: palette.faint),
            ),
          ),
          const SizedBox(height: Gap.md),
          if (!compact && shown.isNotEmpty) ...[
            _ConnectionRow.header(l10n),
            const Divider(),
          ],
          if (shown.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Gap.lg),
              child: Text(
                l10n.homeNoConnections,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) Divider(color: palette.border.withValues(alpha: .6)),
            _ConnectionRow(
              connection: shown[i],
              outbound: names[shown[i].outbound] ?? shown[i].outbound,
              compact: compact,
            ),
          ],
          if (list.length > shown.length)
            Padding(
              padding: const EdgeInsets.only(top: Gap.sm, bottom: Gap.xs),
              child: Text(
                l10n.homeConnectionsMore(list.length - shown.length),
                style: monoStyle(size: 11, color: palette.faint),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    required ProxyConnection this.connection,
    required this.outbound,
    required this.compact,
  }) : _header = null;

  const _ConnectionRow.header(L10n l10n)
      : connection = null,
        outbound = '',
        compact = false,
        _header = l10n;

  final ProxyConnection? connection;
  final String outbound;
  final bool compact;
  final L10n? _header;

  static const _trafficWidth = 76.0;

  /// `rule_set=[geosite-cn geoip-cn] => route(direct)` → `geosite-cn geoip-cn`.
  /// The action half repeats the route column.
  static String _shortRule(String rule) {
    final cut = rule.indexOf(' => ');
    final head = cut < 0 ? rule : rule.substring(0, cut);
    return head
        .replaceAll('rule_set=', '')
        .replaceAll('[', '')
        .replaceAll(']', '');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    if (_header case final l10n?) {
      final style = Theme.of(context).textTheme.labelSmall;
      Widget cell(String text, int flex) => Expanded(
            flex: flex,
            child: Text(text.toUpperCase(), style: style),
          );
      return Padding(
        padding: const EdgeInsets.only(bottom: Gap.sm),
        child: Row(
          children: [
            cell(l10n.homeColHost, 5),
            cell(l10n.homeRouting, 2),
            cell(l10n.homeColRoute, 3),
            cell(l10n.homeColRule, 3),
            SizedBox(
              width: _trafficWidth,
              child: Text(
                l10n.homeColTraffic.toUpperCase(),
                textAlign: TextAlign.right,
                style: style,
              ),
            ),
          ],
        ),
      );
    }

    final c = connection!;
    final host = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: c.host),
          if (c.process case final process?)
            TextSpan(
              text: '  $process',
              style: TextStyle(color: palette.faint, fontSize: 10),
            ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: monoStyle(size: 12, color: palette.text),
    );
    final bytes = Text(
      formatBytes(c.bytes),
      textAlign: TextAlign.right,
      style: monoStyle(size: 12, color: palette.muted),
    );
    final exit = Text(
      c.route == ConnectionRoute.proxy ? outbound : '—',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: monoStyle(size: 11, color: palette.muted),
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: Gap.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  host,
                  const SizedBox(height: Gap.xs),
                  Row(
                    children: [
                      _RouteBadge(route: c.route),
                      const SizedBox(width: Gap.sm),
                      Expanded(child: exit),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.md),
            bytes,
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(flex: 5, child: host),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _RouteBadge(route: c.route),
            ),
          ),
          Expanded(flex: 3, child: exit),
          Expanded(
            flex: 3,
            child: Text(
              _shortRule(c.rule),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(size: 11, color: palette.faint),
            ),
          ),
          SizedBox(width: _trafficWidth, child: bytes),
        ],
      ),
    );
  }
}

/// The same PROXY / DIRECT / BLOCK badges the rules page uses, so one word
/// means one thing across the app.
class _RouteBadge extends StatelessWidget {
  const _RouteBadge({required this.route});

  final ConnectionRoute route;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final (label, color) = switch (route) {
      ConnectionRoute.proxy => (l10n.rulesBadgeProxy, palette.violetSoft),
      ConnectionRoute.direct => (l10n.rulesBadgeDirect, palette.mint),
      ConnectionRoute.reject => (l10n.rulesBadgeBlock, palette.danger),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: tintFill(color),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: color.withValues(alpha: .25)),
      ),
      child: Text(
        label,
        style: monoStyle(size: 9, weight: FontWeight.w500, color: color),
      ),
    );
  }
}
