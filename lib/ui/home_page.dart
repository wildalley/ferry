/// Home dashboard: status, routing split, totals, live traffic and the open
/// connections.
///
/// One set of panels at every width, rearranged rather than redesigned: four
/// tiles across and the status beside the routing panel on a desktop, stacked
/// with two-by-two tiles on a phone.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/config_builder.dart';
import '../l10n/app_localizations.dart';
import '../models/proxy_state.dart';
import '../state/app_state.dart';
import 'clock.dart';
import 'components.dart';
import 'notice_text.dart';
import 'tide_gauge.dart';
import 'update_prompt.dart';
import 'theme.dart';
import 'widgets.dart';

part 'home_dashboard.dart';
part 'home_readouts.dart';

/// Above this the status and routing panels sit side by side and the tiles go
/// four across.
const _wideWidth = 900.0;

/// Below this the page switches to the dedicated mobile layout.
const _phoneWidth = 600.0;

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state, required this.onOpenNodes});

  final AppState state;
  final VoidCallback onOpenNodes;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Ticks once a second while connected, for the uptime line alone. It used
  /// to setState the whole page every second.
  Timer? _ticker;
  final _clock = _Ticker();

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ticker?.cancel();
    _ticker = null;
    if (TickerMode.valuesOf(context).enabled) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && widget.state.isConnected) _clock.notify();
      });
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _ticker?.cancel();
    _clock.dispose();
    super.dispose();
  }

  /// Rebuilds the page for anything but a traffic sample or a log burst. The
  /// widgets that show traffic listen to [AppState.trafficChanges] themselves,
  /// and nothing here shows the log.
  void _onStateChanged() {
    if (!mounted || widget.state.lastChange != StateChange.general) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final state = widget.state;

    return PageFrame(
      title: _greeting(l10n),
      subtitle: l10n.homeSubtitle,
      trailing: IconButton(
        onPressed: state.nodes.isEmpty ? null : state.testLatency,
        tooltip: l10n.actionTestLatency,
        icon: state.isTestingLatency
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(Icons.speed_outlined, color: palette.muted),
      ),
      children: [
        UpdateBanner(state: state),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final isMobile = width < _phoneWidth;
            if (isMobile) {
              return _MobileHomeDashboard(
                state: state,
                onOpenNodes: widget.onOpenNodes,
                clock: _clock,
              );
            }
            return _DesktopHomeDashboard(
              state: state,
              onOpenNodes: widget.onOpenNodes,
              clock: _clock,
              wide: width > _wideWidth,
            );
          },
        ),
      ],
    );
  }

  static String _greeting(L10n l10n) {
    final hour = clockNow().hour;
    if (hour < 5) return l10n.greetingNight;
    if (hour < 12) return l10n.greetingMorning;
    if (hour < 18) return l10n.greetingAfternoon;
    return l10n.greetingEvening;
  }
}

// --------------------------------------------------------------- shared bits

/// A [ChangeNotifier] whose only job is to say "now".
class _Ticker extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Rebuilds [builder] on each traffic sample, without the page around it.
class _OnTraffic extends StatelessWidget {
  const _OnTraffic({required this.state, required this.builder});

  final AppState state;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: state.trafficChanges,
        builder: (context, _) => builder(context),
      );
}

/// Accent for the current stage: mint healthy, danger failed, muted otherwise.
///
/// Every caller draws this as a foreground — the [StatusPill] dot and text, the
/// hero's edge — so it has to be a text colour. Idle is muted rather than the
/// brand colour: the river's colour means "up", and a disconnected tunnel
/// printed in it read as connected at a glance.
Color _stageAccent(AppPalette palette, ProxyStage stage) => switch (stage) {
      ProxyStage.connected => palette.mint,
      ProxyStage.error => palette.danger,
      _ => palette.muted,
    };

String _stageLabel(L10n l10n, ProxyStage stage) => switch (stage) {
      ProxyStage.connected => l10n.stageConnected,
      ProxyStage.starting => l10n.stageConnecting,
      ProxyStage.stopping => l10n.stageDisconnecting,
      ProxyStage.requestingPermission => l10n.stageAwaitingPermission,
      ProxyStage.error => l10n.stageFailed,
      ProxyStage.disconnected => l10n.stageDisconnected,
    };

String? _coverageLabel(L10n l10n, ProxyCoverage? coverage) =>
    switch (coverage) {
      null => null,
      ProxyCoverage.tun => l10n.homeCoverageTun,
      ProxyCoverage.systemProxy => l10n.homeCoverageSystemProxy,
      ProxyCoverage.systemProxyUnavailable =>
        l10n.homeCoverageSystemProxyUnavailable,
      ProxyCoverage.localProxy => l10n.homeCoverageLocalProxy,
    };

String _stageDetail(L10n l10n, AppState state) {
  final proxy = state.proxyState;
  return switch (proxy.stage) {
    ProxyStage.connected => _connectedDetail(l10n, proxy),
    // Engine messages are not translatable and arrive already redacted, but the
    // failures the app detected itself travel as a marker — so both go through
    // the notice mapping rather than being printed raw.
    ProxyStage.error => proxy.message == null
        ? l10n.homeCheckTheLogs
        : noticeText(l10n, AppState.noticeFor(proxy.message!)),
    _ => state.nodes.isEmpty ? l10n.homeNoNodesYet : l10n.homeReadyToConnect,
  };
}

String _connectedDetail(L10n l10n, ProxyState proxy) {
  final coverage = _coverageLabel(l10n, proxy.coverage);
  if (coverage == null) {
    return proxy.since == null
        ? l10n.homeProtected
        : l10n.homeProtectedFor(
            formatUptime(clockNow().difference(proxy.since!)));
  }
  final uptime = proxy.since == null
      ? null
      : formatUptime(clockNow().difference(proxy.since!));
  return [coverage, if (uptime != null) uptime].join(' · ');
}

String _latencyText(L10n l10n, int? latency) => switch (latency) {
      null => l10n.nodesUntested,
      < 0 => l10n.nodesUnreachable,
      final value => '$value ms',
    };

/// What the active exit is called.
///
/// Auto names no node, so [AppState.selectedNode] is null under it — but it is a
/// selection the user made, and reading it as "no node selected" would say the
/// opposite. Every card that names the exit goes through here.
String _exitName(L10n l10n, AppState state) => state.isAutoSelected
    ? l10n.nodesAuto
    : state.selectedNode?.name ?? l10n.homeNoNodeSelected;

/// The primary action, shared by both layouts so the label and disabled rules
/// can only be defined once.
class _ConnectButton extends StatelessWidget {
  const _ConnectButton({required this.state, required this.onOpenNodes});

  final AppState state;
  final VoidCallback onOpenNodes;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final connected = state.isConnected;
    final empty = state.nodes.isEmpty;
    final busy = state.isBusy;

    // A switch, not a button: the paper plane sits on the left, on a violet
    // knob, while the tunnel is down, and rides to the right once it is up —
    // where the whole track turns violet and the knob goes white.
    final trackOn = palette.violet;
    const onText = Colors.white;

    final knob = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: connected ? onText : palette.violet,
        boxShadow: [
          BoxShadow(
            color: (connected ? Colors.black : palette.violet)
                .withValues(alpha: connected ? .12 : .28),
            blurRadius: connected ? 6 : 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: busy
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: connected ? trackOn : Colors.white,
              ),
            )
          : empty
              ? const Icon(Icons.add_rounded, size: 22, color: Colors.white)
              : Transform.rotate(
                  angle: -math.pi / 7,
                  child: Icon(
                    Icons.send_rounded,
                    size: 20,
                    color: connected ? trackOn : Colors.white,
                  ),
                ),
    );

    final label = Text(
      switch (true) {
        _ when empty => l10n.homeAddNodes,
        _ when connected => l10n.actionDisconnect,
        _ => l10n.actionConnect,
      },
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
    // Nothing under the label when there is nothing to connect to: the hero
    // above already says the list is empty.
    final hint = empty
        ? null
        : Text(
            connected
                ? l10n.homeSwitchOnHint
                : l10n.homeSwitchOffHint(_exitName(l10n, state)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w400,
              color: connected ? onText.withValues(alpha: .86) : palette.muted,
            ),
          );
    final texts = Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          label,
          if (hint != null) ...[const SizedBox(height: 1), hint],
        ],
      ),
    );

    return Semantics(
      toggled: connected,
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed:
              busy ? null : (empty ? onOpenNodes : state.toggleConnection),
          style: FilledButton.styleFrom(
            backgroundColor: connected ? trackOn : palette.surface3,
            disabledBackgroundColor: connected ? trackOn : palette.surface3,
            foregroundColor: connected ? onText : palette.text,
            disabledForegroundColor: connected ? onText : palette.text,
            // Flat in both states. A raised shadow shows through a tinted face
            // on Linux and turns the light-theme hover grey; the ink overlay
            // still gives hover and focus feedback.
            elevation: 0,
            shadowColor: Colors.transparent,
            side: connected ? null : BorderSide(color: palette.border),
            minimumSize: const Size(0, 60),
            // Desktop's adaptive density is compact, which takes 8px off the
            // height but not the sides — the knob then sat 2px from the top
            // and 6px from the left, reading as off-centre. Standard density
            // keeps the 6px ring even on every platform.
            visualDensity: VisualDensity.standard,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: connected
                ? const EdgeInsets.fromLTRB(22, 6, 6, 6)
                : const EdgeInsets.fromLTRB(6, 6, 18, 6),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(
              fontFamily: AppFonts.body,
              fontFamilyFallback: AppFonts.cjkFallback,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Row(
            children: connected
                ? [texts, const SizedBox(width: Gap.md), knob]
                : [
                    knob,
                    const SizedBox(width: Gap.md),
                    texts,
                    Icon(Icons.arrow_forward_rounded,
                        size: 18, color: palette.faint),
                  ],
          ),
        ),
      ),
    );
  }
}
