/// Responsive navigation shell shared by desktop and mobile layouts.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/proxy_state.dart' show formatRate;
import '../state/app_state.dart';
import '../version.dart';
import 'brand.dart';
import 'components.dart';
import 'home_page.dart';
import 'logs_page.dart';
import 'nodes_page.dart';
import 'notice_text.dart';
import 'rules_page.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// Navigation destinations, shared by both layouts.
enum AppTab {
  home(Icons.home_outlined, Icons.home_rounded),
  nodes(Icons.hub_outlined, Icons.hub_rounded),
  rules(Icons.alt_route_outlined, Icons.alt_route_rounded),
  logs(Icons.receipt_long_outlined, Icons.receipt_long_rounded),
  settings(Icons.settings_outlined, Icons.settings_rounded);

  const AppTab(this.icon, this.selectedIcon);

  final IconData icon;
  final IconData selectedIcon;

  String label(L10n l10n) => switch (this) {
        AppTab.home => l10n.navHome,
        AppTab.nodes => l10n.navNodes,
        AppTab.rules => l10n.navRules,
        AppTab.logs => l10n.navLogs,
        AppTab.settings => l10n.navSettings,
      };

  String railLabel(L10n l10n) =>
      this == AppTab.home ? l10n.railOverview : label(l10n);
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.state});

  final AppState state;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  var _tab = AppTab.home;

  late final _connected = ValueNotifier<bool>(widget.state.isConnected);

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_onStateChanged);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onStateChanged);
    _connected.dispose();
    super.dispose();
  }

  /// Surfaces one-shot notices from [AppState] as localized snackbars.
  void _onStateChanged() {
    _connected.value = widget.state.isConnected;
    final notice = widget.state.takeNotice();
    if (notice == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final palette = context.palette;
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            noticeText(L10n.of(context), notice),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          backgroundColor: notice.isError
              ? Color.alphaBlend(
                  palette.danger.withValues(alpha: .18),
                  palette.surface3,
                )
              : null,
        ),
      );
  }

  void _goToTab(AppTab tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final page = switch (_tab) {
      AppTab.home => HomePage(
          state: widget.state,
          onOpenNodes: () => _goToTab(AppTab.nodes),
        ),
      AppTab.nodes => NodesPage(state: widget.state),
      AppTab.rules => RulesPage(state: widget.state),
      AppTab.logs => LogsPage(state: widget.state),
      AppTab.settings => SettingsPage(
          state: widget.state,
          onOpenLogs: () => _goToTab(AppTab.logs),
        ),
    };

    return ValueListenableBuilder<bool>(
      valueListenable: _connected,
      builder: (context, connected, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final accent =
                connected ? context.palette.mint : context.palette.violet;
            final transitioningPage = _TabTransition(
              tab: _tab,
              child: page,
            );
            // Only the dashboard gets the signal field, and only while the
            // tunnel is up: it reports throughput, so it has nothing to say on
            // the settings or rules screens and would just be noise under text.
            final signals = connected && _tab == AppTab.home;
            if (constraints.maxWidth >= 840) {
              return Scaffold(
                body: _Backdrop(
                  state: widget.state,
                  accent: accent,
                  signals: signals,
                  child: Row(
                    children: [
                      _DesktopRail(
                        state: widget.state,
                        selected: _tab,
                        onSelected: _goToTab,
                      ),
                      Expanded(child: transitioningPage),
                    ],
                  ),
                ),
              );
            }

            return Scaffold(
              body: _Backdrop(
                state: widget.state,
                accent: accent,
                signals: signals,
                child: SafeArea(bottom: false, child: transitioningPage),
              ),
              bottomNavigationBar: NavigationBar(
                selectedIndex: _tab.index,
                onDestinationSelected: (index) =>
                    _goToTab(AppTab.values[index]),
                destinations: [
                  for (final tab in AppTab.values)
                    NavigationDestination(
                      icon: Icon(tab.icon),
                      selectedIcon: Icon(tab.selectedIcon),
                      label: tab.label(l10n),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// The console backdrop, fed the tunnel's throughput.
///
/// A separate widget so the traffic samples do not rebuild the page in front of
/// them. [AppState] notifies on every reading — about once a second while
/// connected — and the shell's own build produces the whole page subtree, so
/// listening up there would rebuild five screens' worth of widgets a second to
/// move some dots. The page arrives here as an already-built [child] that
/// [ListenableBuilder] passes through untouched.
class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.state,
    required this.accent,
    required this.signals,
    required this.child,
  });

  final AppState state;
  final Color accent;

  /// Whether this surface should carry the signal field at all.
  final bool signals;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!signals) {
      // Nothing to listen for: the grid and vignette do not depend on traffic,
      // so an idle or non-dashboard surface should not subscribe at all.
      return ConsoleBackground(accent: accent, child: child);
    }
    return ListenableBuilder(
      listenable: state,
      builder: (context, child) => ConsoleBackground(
        accent: accent,
        animate: true,
        showSignals: true,
        downlink: state.downlinkHistory,
        uplink: state.uplinkHistory,
        child: child,
      ),
      child: child,
    );
  }
}

/// Fade-through between tabs: the old page is gone before the new one appears.
///
/// It used to cross-fade the two while sliding them 1.2% sideways. Both pages
/// were on screen at once for most of the 300ms, a few pixels apart, so every
/// heading and label briefly drew twice — which reads as a rendering fault, not
/// as motion. Splitting the timeline means at most one page has meaningful
/// opacity at any instant, and nothing moves, so text never smears. Reduced
/// motion gets an immediate replacement.
class _TabTransition extends StatelessWidget {
  const _TabTransition({required this.tab, required this.child});

  final AppTab tab;
  final Widget child;

  /// The outgoing page fades over the first part; the incoming over the rest.
  static const _outEnd = .4;

  @override
  Widget build(BuildContext context) {
    final duration = motionOf(context, Motion.fast * 1.4);
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: duration,
      // The incoming child runs 0→1 and the outgoing 1→0 on the same clock, so
      // one interval per direction gives them disjoint windows.
      switchInCurve: const Interval(_outEnd, 1, curve: Curves.easeOut),
      switchOutCurve: const Interval(1 - _outEnd, 1, curve: Curves.easeIn),
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: KeyedSubtree(key: ValueKey(tab), child: child),
    );
  }
}

class _DesktopRail extends StatelessWidget {
  const _DesktopRail({
    required this.state,
    required this.selected,
    required this.onSelected,
  });

  final AppState state;
  final AppTab selected;
  final ValueChanged<AppTab> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Container(
      width: 240,
      padding: const EdgeInsets.fromLTRB(Gap.lg, 26, Gap.lg, Gap.lg),
      decoration: BoxDecoration(
        color: Color.lerp(palette.bg, palette.surface, .35),
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: Gap.xs, bottom: 28),
            child: const _Wordmark(),
          ),
          for (final tab in AppTab.values)
            _RailItem(
              tab: tab,
              active: tab == selected,
              onTap: () => onSelected(tab),
            ),
          const Spacer(),
          // Status lives at the foot of the rail, next to the control that
          // changes it. A pill at the top said "connected" and nothing else;
          // this says through what, how fast, and offers the way out.
          ListenableBuilder(
            listenable: state,
            builder: (context, _) => _RailStatus(state: state),
          ),
          const SizedBox(height: Gap.md),
          Padding(
            padding: const EdgeInsets.only(left: Gap.xs),
            child: Text(
              'v$appVersion',
              style: monoStyle(color: palette.faint, size: 10),
            ),
          ),
        ],
      ),
    );
  }
}

/// The rail's connection card: stage, exit, live rates and a toggle.
class _RailStatus extends StatelessWidget {
  const _RailStatus({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final connected = state.isConnected;
    final accent = connected ? palette.mint : palette.muted;
    final traffic = state.traffic;
    final exit = state.isAutoSelected
        ? l10n.nodesAuto
        : state.selectedNode?.name ?? l10n.homeNoNodeSelected;

    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.xs, Gap.md),
      decoration: BoxDecoration(
        color: connected
            ? Color.alphaBlend(
                palette.mint.withValues(alpha: .05), palette.surface)
            : palette.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color:
              connected ? palette.mint.withValues(alpha: .24) : palette.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: StatusPill(
                  label:
                      connected ? l10n.stageConnected : l10n.stageDisconnected,
                  color: accent,
                  compact: true,
                  bare: true,
                ),
              ),
              IconButton(
                onPressed: state.nodes.isEmpty || state.isBusy
                    ? null
                    : state.toggleConnection,
                tooltip: connected ? l10n.actionDisconnect : l10n.actionConnect,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                color: connected ? palette.mint : palette.violetSoft,
                icon: state.isBusy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.power_settings_new_rounded),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(right: Gap.sm),
            child: Text(
              exit,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: Gap.sm),
          Row(
            children: [
              Icon(Icons.arrow_downward_rounded,
                  size: 12, color: connected ? palette.sky : palette.faint),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  connected ? formatRate(traffic.downlink) : '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(size: 11, color: palette.muted),
                ),
              ),
              Icon(Icons.arrow_upward_rounded,
                  size: 12, color: connected ? palette.mint : palette.faint),
              const SizedBox(width: 3),
              Expanded(
                child: Text(
                  connected ? formatRate(traffic.uplink) : '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: monoStyle(size: 11, color: palette.muted),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The launcher and sidebar share one recognisable mark.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;

    return Row(
      children: [
        const BrandMark(size: 44),
        const SizedBox(width: Gap.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.appShortName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.display,
                  fontFamilyFallback: AppFonts.cjkFallback,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                l10n.appTagline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.faint,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.tab,
    required this.active,
    required this.onTap,
  });

  final AppTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            curve: Motion.curve,
            padding:
                const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 11),
            decoration: BoxDecoration(
              gradient: active
                  ? LinearGradient(
                      colors: [
                        palette.violet.withValues(alpha: .22),
                        palette.violet.withValues(alpha: .06),
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: active
                    ? palette.violet.withValues(alpha: .40)
                    : Colors.transparent,
              ),
              boxShadow: active
                  ? [
                      BoxShadow(
                        color: palette.violet.withValues(alpha: .20),
                        blurRadius: 8,
                      )
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  active ? tab.selectedIcon : tab.icon,
                  size: 19,
                  color: active ? palette.violetSoft : palette.muted,
                ),
                const SizedBox(width: Gap.md),
                Text(
                  tab.railLabel(L10n.of(context)),
                  style: TextStyle(
                    color: active ? palette.text : palette.muted,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
