part of 'home_page.dart';

// ------------------------------------------------------------------ layouts

/// Tablet and desktop: the hero across the top, totals in a row, then traffic
/// beside the routing split.
///
/// Everything that reads traffic is wrapped in [_OnTraffic], so a sample
/// redraws those panels and not the page.
class _DesktopHomeDashboard extends StatelessWidget {
  const _DesktopHomeDashboard({
    required this.state,
    required this.onOpenNodes,
    required this.clock,
    required this.wide,
  });

  final AppState state;
  final VoidCallback onOpenNodes;
  final Listenable clock;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroPanel(
          state: state,
          onOpenNodes: onOpenNodes,
          clock: clock,
          wide: true,
        ),
        const SizedBox(height: Gap.lg),
        _OnTraffic(
          state: state,
          builder: (_) => _StatTiles(state: state, columns: wide ? 4 : 2),
        ),
        const SizedBox(height: Gap.lg),
        _OnTraffic(
          state: state,
          builder: (_) => wide
              ? PixelRow(
                  flex: const [5, 3],
                  children: [
                    _TrafficPanel(state: state, height: 168),
                    _RoutingPanel(state: state, stretch: true),
                  ],
                )
              : Column(
                  children: [
                    _TrafficPanel(state: state, height: 120),
                    const SizedBox(height: Gap.lg),
                    _RoutingPanel(state: state, stretch: false),
                  ],
                ),
        ),
        _OnTraffic(
          state: state,
          builder: (_) => _showConnections(state)
              ? Padding(
                  padding: const EdgeInsets.only(top: Gap.lg),
                  child: _ConnectionsPanel(state: state, compact: !wide),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Whether the connections panel has something to say: connected, and either a
/// list to show or an honest zero. The runtime can report a count without a
/// list (libbox), and an empty panel there would read as "no connections".
bool _showConnections(AppState state) {
  final traffic = state.traffic;
  return state.isConnected &&
      (traffic.connectionList.isNotEmpty || traffic.connections == 0);
}

/// Phone: everything the tunnel needs in the hero, within a thumb's reach of
/// the connect button, and the readings below it in one compact grid.
///
/// Each fact appears once. The old phone page named the exit twice and printed
/// both rates twice — in a dial, a pair of readouts and again in the tiles —
/// which pushed the totals and the chart below the fold for no new information.
class _MobileHomeDashboard extends StatelessWidget {
  const _MobileHomeDashboard({
    required this.state,
    required this.onOpenNodes,
    required this.clock,
  });

  final AppState state;
  final VoidCallback onOpenNodes;
  final Listenable clock;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeroPanel(
          state: state,
          onOpenNodes: onOpenNodes,
          clock: clock,
          wide: false,
        ),
        const SizedBox(height: Gap.md),
        _OnTraffic(state: state, builder: (_) => _StatGrid(state: state)),
        const SizedBox(height: Gap.md),
        _OnTraffic(
          state: state,
          builder: (_) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TrafficPanel(state: state, height: 104),
              const SizedBox(height: Gap.md),
              _RoutingPanel(state: state, stretch: false),
              if (_showConnections(state)) ...[
                const SizedBox(height: Gap.md),
                _ConnectionsPanel(state: state, compact: true),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------- hero

/// The tunnel: its stage, the exit it goes through, the prism beam, both live
/// rates, the address the world sees, and the way to turn it on or off.
class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.state,
    required this.onOpenNodes,
    required this.clock,
    required this.wide,
  });

  final AppState state;
  final VoidCallback onOpenNodes;

  /// Ticks the uptime in the status line, and nothing else.
  final Listenable clock;

  /// Beam beside the text instead of under it.
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final proxy = state.proxyState;
    final connected = proxy.isConnected;
    final failed = proxy.stage == ProxyStage.error;
    final accent = _stageAccent(palette, proxy.stage);

    final status = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusPill(
          label: _stageLabel(l10n, proxy.stage),
          color: accent,
          compact: true,
          bare: true,
        ),
        const SizedBox(height: 4),
        ListenableBuilder(
          listenable: clock,
          builder: (context, _) => Text(
            _stageDetail(l10n, state),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );

    final exit = _ExitName(state: state, onTap: onOpenNodes, large: wide);

    final beam = _OnTraffic(
      state: state,
      builder: (_) {
        final down = state.downlinkHistory;
        final up = state.uplinkHistory;
        return TideGauge(
          live: connected,
          reading: state.traffic,
          downlink: down,
          uplink: up,
          height: wide ? 170 : 124,
          label: l10n.homeTideLevel(
            connected
                ? formatRate(
                    (down.isEmpty ? 0 : down.last) + (up.isEmpty ? 0 : up.last))
                : '—',
          ),
        );
      },
    );

    final rates = _OnTraffic(
      state: state,
      builder: (_) => Row(
        children: [
          Expanded(
            child: _RateReadout(
              key: const Key('home-download-rate'),
              label: l10n.homeDownload,
              icon: Icons.south_rounded,
              color: palette.sky,
              rate: state.traffic.downlink,
              connected: connected,
              size: wide ? 34 : 26,
            ),
          ),
          const SizedBox(width: Gap.lg),
          Expanded(
            child: _RateReadout(
              label: l10n.homeUpload,
              icon: Icons.north_rounded,
              color: palette.mint,
              rate: state.traffic.uplink,
              connected: connected,
              size: wide ? 34 : 26,
            ),
          ),
        ],
      ),
    );

    final actions = Row(
      children: [
        Expanded(
          child: _ConnectButton(state: state, onOpenNodes: onOpenNodes),
        ),
        if (state.nodes.isNotEmpty) ...[
          const SizedBox(width: Gap.sm + 2),
          SizedBox(
            width: 60,
            height: 60,
            child: Tooltip(
              message: l10n.homeChangeNode,
              child: FilledButton(
                onPressed: onOpenNodes,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: const CircleBorder(),
                  backgroundColor: palette.surface3,
                  foregroundColor: palette.text,
                  elevation: 0,
                  shadowColor: Colors.transparent,
                ),
                child: const Icon(Icons.swap_horiz_rounded, size: 20),
              ),
            ),
          ),
        ],
      ],
    );

    final Widget body;
    if (wide) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(26, 24, 26, 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  status,
                  const SizedBox(height: Gap.lg),
                  exit,
                  const SizedBox(height: Gap.xl),
                  rates,
                  const SizedBox(height: Gap.xl),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: actions,
                  ),
                ],
              ),
            ),
            const SizedBox(width: Gap.xl),
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  const SizedBox(height: Gap.xl),
                  beam,
                  const SizedBox(height: Gap.lg),
                  _ExitAddressRow(state: state),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            status,
            const SizedBox(height: Gap.md),
            exit,
            const SizedBox(height: Gap.sm),
            beam,
            const SizedBox(height: Gap.sm),
            rates,
            const SizedBox(height: Gap.md),
            _ExitAddressRow(state: state),
            const SizedBox(height: Gap.md),
            actions,
          ],
        ),
      );
    }

    return Panel(
      padding: EdgeInsets.zero,
      accent: connected || failed ? accent : null,
      glowing: connected || failed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Stack(
          children: [
            body,
          ],
        ),
      ),
    );
  }
}

/// The exit's name set large, with its protocol and latency under it. The
/// whole block opens the node list.
class _ExitName extends StatelessWidget {
  const _ExitName({
    required this.state,
    required this.onTap,
    required this.large,
  });

  final AppState state;
  final VoidCallback onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final node = state.selectedNode;
    final auto = state.isAutoSelected;

    final facts = <Widget>[
      if (auto)
        _Fact(text: 'URL-TEST', color: palette.violetSoft)
      else if (node != null) ...[
        _Fact(text: node.protocol.label, color: palette.muted),
        _Fact(
          text: _latencyText(l10n, node.latencyMs),
          color: latencyColor(palette, node.latencyMs),
        ),
      ],
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    _exitName(l10n, state),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontSize: large ? 30 : 23,
                          height: 1.12,
                        ),
                  ),
                ),
                const SizedBox(width: Gap.xs),
                Icon(Icons.chevron_right_rounded,
                    size: large ? 26 : 22, color: palette.faint),
              ],
            ),
            if (facts.isNotEmpty) ...[
              const SizedBox(height: Gap.sm),
              Wrap(spacing: Gap.sm, runSpacing: Gap.xs, children: facts),
            ],
          ],
        ),
      ),
    );
  }
}

/// A small mono fact beside the exit name: protocol, latency.
class _Fact extends StatelessWidget {
  const _Fact({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: tintFill(color),
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: Border.all(color: color.withValues(alpha: .22)),
      ),
      child: Text(
        text,
        style: monoStyle(size: 11, weight: FontWeight.w500, color: color),
      ),
    );
  }
}

// ------------------------------------------------------------------ status

/// One direction's live rate: a small keyed label over a large display-face
/// figure, the unit trailing on the baseline.
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

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: connected ? color : palette.faint),
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
        const SizedBox(height: 2),
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
                style: TextStyle(
                  fontFamily: AppFonts.display,
                  fontFamilyFallback: AppFonts.cjkFallback,
                  fontSize: size,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -size * .03,
                  height: 1.1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: connected ? palette.text : palette.faint,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                unit,
                style: monoStyle(
                  size: math.max(11, size * .36),
                  color: palette.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- routing

/// How the open connections split across proxy, direct and block.
class _RoutingPanel extends StatelessWidget {
  const _RoutingPanel({required this.state, required this.stretch});

  final AppState state;

  /// Sitting in an equal-height row, so the rows can be pushed to the top
  /// and the bar to the foot. A Spacer in an unbounded column would throw.
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
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
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
          if (stretch) const Spacer(),
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
    // Segments with a hairline of air between them, so a thin share still
    // reads as its own part rather than as the edge of its neighbour.
    final segments = [
      if (proxy > 0) (proxy, proxyColor),
      if (direct > 0) (direct, directColor),
      if (reject > 0) (reject, rejectColor),
    ];
    return SizedBox(
      height: 6,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < segments.length; i++) ...[
            if (i > 0) const SizedBox(width: 2),
            Expanded(
              flex: segments[i].$1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: segments[i].$2,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
            ),
          ],
        ],
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

/// The phone's totals: the same four readings as [_StatTiles], in one panel
/// split by hairlines rather than four cards with a sparkline each — the live
/// chart sits right below, so the sparklines only repeated it at a size too
/// small to read.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final traffic = state.traffic;
    final connected = state.isConnected;

    final cells = [
      _StatCell(
        label: l10n.homeDownload,
        color: palette.sky,
        value: traffic.downlinkTotal,
        format: formatBytes,
        caption: connected ? formatRate(traffic.downlink) : '—',
      ),
      _StatCell(
        label: l10n.homeUpload,
        color: palette.mint,
        value: traffic.uplinkTotal,
        format: formatBytes,
        caption: connected ? formatRate(traffic.uplink) : '—',
      ),
      _StatCell(
        label: l10n.homeConnections,
        color: palette.violetSoft,
        value: traffic.connections,
        format: (value) => '$value',
      ),
      _StatCell(
        label: l10n.homeMemory,
        color: palette.amber,
        // Only reported while running; zero would read as a measurement.
        value: traffic.memory,
        format: (value) => connected ? formatBytes(value) : '—',
      ),
    ];

    Widget pair(Widget a, Widget b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: a),
              VerticalDivider(width: 1, color: palette.border),
              Expanded(child: b),
            ],
          ),
        );

    return Panel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          pair(cells[0], cells[1]),
          Divider(height: 1, color: palette.border),
          pair(cells[2], cells[3]),
        ],
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.label,
    required this.color,
    required this.value,
    required this.format,
    this.caption,
  });

  final String label;
  final Color color;
  final int value;
  final String Function(int value) format;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          AnimatedCount(
            value: value,
            format: format,
            style: monoStyle(
              size: 18,
              weight: FontWeight.w500,
              color: palette.text,
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 2),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: monoStyle(size: 11, color: palette.faint),
            ),
          ],
        ],
      ),
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
