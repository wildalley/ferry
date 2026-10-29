part of 'widgets.dart';

/// Rounded card with a subtle border and no heavy shadow.
///
/// Tappable panels share one hover, press, and selected treatment. That keeps
/// the controls in nodes, subscriptions, and other dashboard surfaces feeling
/// related while avoiding any layout-changing hover effects.
class Panel extends StatefulWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Gap.lg),
    this.accent,
    this.onTap,
    this.glowing = false,
    this.selected = false,
  });

  final Widget child;
  final EdgeInsets padding;

  /// When set, tints the border to signal state (mint connected, amber warning).
  final Color? accent;
  final VoidCallback? onTap;

  /// Strengthens the [accent] edge. Only for the one panel on a screen that
  /// carries live state — more than one and it stops meaning anything.
  final bool glowing;

  /// Applies a tinted fill and a stronger edge to a selected, tappable item.
  final bool selected;

  @override
  State<Panel> createState() => _PanelState();
}

class _PanelState extends State<Panel> {
  var _hovered = false;
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final interactive = widget.onTap != null;
    final accent = widget.accent ?? palette.violet;
    final lit = widget.glowing && widget.accent != null;
    final elevated = interactive && (_hovered || _pressed);

    final baseSurface = palette.surface;
    var fill = widget.selected
        ? Color.alphaBlend(accent.withValues(alpha: .10), baseSurface)
        : baseSurface;
    if (elevated) {
      fill = Color.alphaBlend(
        accent.withValues(alpha: _pressed ? .095 : .045),
        fill,
      );
    }

    // [glowing] is an edge now rather than a halo: still the one panel that
    // carries live state, said with a firmer border instead of light.
    final borderColor = widget.selected
        ? accent.withValues(alpha: .65)
        : elevated
            ? accent.withValues(alpha: .38)
            : widget.accent?.withValues(alpha: lit ? .50 : .28) ??
                palette.border;
    final light = Theme.of(context).brightness == Brightness.light;
    // Flat: one fill, one hairline. The diagonal wash and the halo made every
    // card a light source, and on a dense dashboard that is a dozen of them
    // competing; the data inside is what should carry the contrast.
    final decoration = BoxDecoration(
      color: fill,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: borderColor),
      boxShadow: [
        if (elevated)
          BoxShadow(
            color: Colors.black.withValues(
              alpha: light ? (_pressed ? .06 : .03) : (_pressed ? .14 : .09),
            ),
            blurRadius: _pressed ? 6 : 10,
            offset: Offset(0, _pressed ? 1 : 3),
          ),
        if (!elevated && light)
          BoxShadow(
            color: palette.text.withValues(alpha: .03),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
      ],
    );

    if (!interactive) {
      return Container(
        width: double.infinity,
        padding: widget.padding,
        decoration: decoration,
        // Clipped to the rounded edge: rows inside (settings, a source's
        // nodes) paint rectangular press ripples, which otherwise poke out
        // past the corners on the first and last row.
        clipBehavior: Clip.antiAlias,
        child: widget.child,
      );
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHover: (value) {
          if (_hovered != value && mounted) setState(() => _hovered = value);
        },
        onHighlightChanged: (value) {
          if (_pressed != value && mounted) setState(() => _pressed = value);
        },
        mouseCursor: SystemMouseCursors.click,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: AnimatedScale(
          scale: _pressed ? .992 : 1,
          duration: motionOf(context, Motion.fast),
          curve: Motion.curve,
          child: AnimatedContainer(
            duration: motionOf(context, Motion.fast),
            curve: Motion.curve,
            width: double.infinity,
            padding: widget.padding,
            decoration: decoration,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Splits [width] into columns by [flex], each landing on a whole device pixel.
///
/// [Expanded] divides space exactly, so four cards across 1032px come out at
/// 247.5px each and every other card's 1px border straddles two device pixels:
/// drawn at half strength across both, which reads as a soft, unfocused edge
/// next to its sharp neighbour. Flooring each column and handing the leftover
/// to the last keeps every edge on the pixel grid.
List<double> pixelColumns(
  double width,
  List<int> flex, {
  required double gap,
  required double devicePixelRatio,
}) {
  final total = flex.fold(0, (sum, f) => sum + f);
  final usable = width - gap * (flex.length - 1);
  double snap(double v) =>
      (v * devicePixelRatio).floorToDouble() / devicePixelRatio;
  final widths = [for (final f in flex) snap(usable * f / total)];
  widths[widths.length - 1] =
      usable - widths.take(widths.length - 1).fold(0.0, (a, b) => a + b);
  return widths;
}

/// A row of equal-height columns at whole-pixel widths — see [pixelColumns].
///
/// Measures from outside its [IntrinsicHeight] rather than inside: a
/// [LayoutBuilder] cannot answer intrinsic-size queries, so it has to be the
/// one asking.
class PixelRow extends StatelessWidget {
  const PixelRow({
    super.key,
    required this.children,
    this.flex,
    this.gap = Gap.lg,
    this.stretch = true,
  });

  final List<Widget> children;

  /// Relative widths; equal columns when null.
  final List<int>? flex;
  final double gap;

  /// Match the tallest child's height, as `IntrinsicHeight` + stretch would.
  final bool stretch;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final widths = pixelColumns(
          constraints.maxWidth,
          flex ?? List.filled(children.length, 1),
          gap: gap,
          devicePixelRatio: dpr,
        );
        final row = Row(
          crossAxisAlignment:
              stretch ? CrossAxisAlignment.stretch : CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              SizedBox(width: widths[i], child: children[i]),
            ],
          ],
        );
        return stretch ? IntrinsicHeight(child: row) : row;
      },
    );
  }
}

/// Section label above a group of panels.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Row(
        children: [
          // A short tick in the river's colour instead of the old `//` sigil.
          const Padding(
            padding: EdgeInsets.only(right: Gap.sm),
            child: AccentBar(width: 10, height: 2),
          ),
          Expanded(
            child: Text(
              text.toUpperCase(),
              // Wide tracking is what makes an all-caps label read as a label
              // rather than as shouting; uppercase alone looks cramped.
              style: labelStyle?.copyWith(letterSpacing: 1.2),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Panel header with a leading icon.
class PanelTitle extends StatelessWidget {
  const PanelTitle({
    super.key,
    required this.title,
    required this.icon,
    this.trailing,
  });

  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: context.palette.faint),
        const SizedBox(width: Gap.sm),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: .1,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Scrollable page scaffold with a display-font title.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
    this.onRefresh,
    this.fill = false,
    this.slivers = const [],
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  /// Stretches the last child to whatever height the header leaves, instead of
  /// letting it choose its own.
  ///
  /// For a body that is already a scroller — the log pane — where the
  /// alternative is guessing a pixel height that is too short on a desktop
  /// window and leaves dead space under the panel on a phone. Only pass this
  /// when the last child actually wants the room: stretching a short card (an
  /// empty state) to full height looks like a bug, not a layout.
  final bool fill;

  /// Slivers after [children], inside the same padding and scroll. For a body
  /// long enough that it should be built lazily — the node list — rather than
  /// all at once as [children] are.
  final List<Widget> slivers;

  /// Wide enough for the dashboard's connection table to keep its columns on
  /// a 1440px display, narrow enough that a line of text stays readable.
  static const _maxWidth = 1240.0;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context).width;
    final wide = screen >= 1100;
    // A phone gets 16px gutters: 24 on each side of a 360px screen spends an
    // eighth of the width on margin and clips every row's name before it has to.
    final phone = screen < 600;
    final padding = phone
        ? const EdgeInsets.fromLTRB(16, 10, 16, 24)
        : const EdgeInsets.fromLTRB(Gap.xl, 22, Gap.xl, 28);

    // A toolbar-height header rather than a hero: on a dashboard the title
    // only says where you are, and the 36px display line it used to be pushed
    // the first row of figures below the fold on a 720px-tall window.
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontSize: wide ? 26 : (phone ? 21 : 23),
                        ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        // Air instead of a rule: the panels below carry their own edges, and
        // a full-width line over them read as a second header bar.
        SizedBox(height: phone ? Gap.lg : Gap.xl),
      ],
    );

    // Two shapes, because the scroll ownership differs.
    //
    // Normally the page owns the scroll and the children stack up as tall as
    // they like, header included.
    //
    // Filling is the other way round: the last child is already a scroller, so
    // it takes the room the header leaves and the page itself does not scroll at
    // all. The header sits *outside* any viewport there — it is chrome, and a
    // title that scrolls away from the pane it labels is a title in the wrong
    // place.
    //
    // This used to be a CustomScrollView with a SliverFillRemaining in both
    // cases, which put the header inside the scrollable even when filling. The
    // sliver was sized to the viewport while SliverPadding added 50px on top of
    // it, so the outer view had exactly that much scroll — just enough to drag
    // the title out of sight above a log pane that was doing its own scrolling
    // underneath. Two nested scrollables, and the wrong one moved.
    final Widget content;
    if (fill && children.isNotEmpty) {
      content = Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            ...children.take(children.length - 1),
            Expanded(child: children.last),
          ],
        ),
      );
    } else {
      content = CustomScrollView(
        slivers: [
          SliverPadding(
            padding: padding,
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverList.list(children: [header, ...children]),
                ...slivers,
              ],
            ),
          ),
        ],
      );
    }

    // Centred by a floored inset rather than [Center]: an odd leftover width
    // puts Center's child on a half pixel, and every border and chart rule
    // inside it then blurs across two device pixels.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final centered = LayoutBuilder(
      builder: (context, constraints) {
        final spare = constraints.maxWidth - _maxWidth;
        final inset =
            spare <= 0 ? 0.0 : (spare / 2 * dpr).floorToDouble() / dpr;
        // Anchored top-left so a centring parent (the tab switcher's Stack)
        // cannot centre this again and undo the floor above.
        return Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(left: inset),
            child: SizedBox(
              width: spare <= 0 ? constraints.maxWidth : _maxWidth,
              child: content,
            ),
          ),
        );
      },
    );

    // A RefreshIndicator needs a scrollable of its own to drive it, and in the
    // filling shape the page has none — the scroller belongs to the last child.
    // No caller combines the two today; the assert says so rather than leaving a
    // pull-to-refresh that silently never fires.
    assert(slivers.isEmpty || !fill,
        'PageFrame cannot fill and take slivers: filling has no scroll of its own');
    assert(
      onRefresh == null || !fill,
      'PageFrame cannot combine onRefresh with fill: the filling shape has no '
      'scrollable of its own for the indicator to follow',
    );
    if (onRefresh == null) return centered;
    return RefreshIndicator(
      onRefresh: onRefresh!,
      color: context.palette.violetSoft,
      backgroundColor: context.palette.surface,
      child: centered,
    );
  }
}

/// Small pill showing a status word with a coloured dot.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.compact = false,
    this.bare = false,
  });

  final String label;
  final Color color;
  final bool compact;

  /// Dot and label only, for a pill that already sits inside a tinted card;
  /// a second box inside the first reads as nesting rather than status.
  final bool bare;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: Motion.fast,
      curve: Motion.curve,
      padding: bare
          ? EdgeInsets.zero
          : EdgeInsets.symmetric(
              horizontal: compact ? Gap.sm : 10,
              vertical: compact ? 5 : 8,
            ),
      decoration: bare
          ? const BoxDecoration()
          : BoxDecoration(
              color: tintFill(color),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: color.withValues(alpha: .22)),
            ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              // A 7px dot is too small for the full two-layer glow; one tight
              // ring is enough to make it read as lit rather than printed.
              boxShadow: [
                BoxShadow(
                  color: color.withValues(
                    alpha: .55 * glowIntensity(Theme.of(context).brightness),
                  ),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Segmented control used for routing mode and similar small choices.
///
/// One indicator slides between the segments rather than each segment fading its
/// own fill in and out. Two fills cross-fading reads as two things blinking; one
/// moving reads as the selection travelling, which is what happened.
class SegmentedChoice<T> extends StatelessWidget {
  const SegmentedChoice({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  /// Edge on the indicator, and the inset it costs the labels.
  ///
  /// The labels carry it too. The indicator is a layer of its own now, so it no
  /// longer contributes its edge to the track's height the way a border on each
  /// segment did — without this the control loses those two pixels and every
  /// row below it on the page moves up.
  static const _edge = 1.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(Gap.xs),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Stack(
        children: [
          // Positioned, so it does not size the stack — the row below does, and
          // painting first puts the indicator behind the labels.
          Positioned.fill(
            child: AnimatedOpacity(
              // A selection that is none of these values — a rule sent to a
              // policy group, say — shows no segment as chosen.
              opacity: values.contains(selected) ? 1 : 0,
              duration: motionOf(context, Motion.fast),
              child: AnimatedAlign(
                alignment: _indicatorAlignment,
                duration: motionOf(context, Motion.normal),
                curve: Motion.curve,
                child: FractionallySizedBox(
                  widthFactor: 1 / values.length,
                  child: Container(
                    decoration: BoxDecoration(
                      color: palette.surface3,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: palette.borderStrong,
                        width: _edge,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (final value in values)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(value),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedDefaultTextStyle(
                      duration: motionOf(context, Motion.normal),
                      curve: Motion.curve,
                      // Merged onto the ambient style rather than given whole.
                      // AnimatedDefaultTextStyle *replaces* the default for its
                      // subtree, where a style handed to a Text merges into it —
                      // so stating only the differences here is what keeps the
                      // body family, the CJK fallback, and the 1.4 line height
                      // that sets this control's height.
                      style: DefaultTextStyle.of(context).style.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: value == selected
                                ? palette.text
                                : palette.muted,
                          ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 10 + _edge,
                        ),
                        child: Center(child: Text(labelOf(value))),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Centre of the selected segment, in the [-1, 1] the alignment uses.
  ///
  /// A segment's centre sits half a segment in from its edge, so the usable
  /// travel is the track minus one segment — mapping the index across that is
  /// what keeps the indicator concentric with its label at both ends.
  Alignment get _indicatorAlignment {
    if (values.length < 2) return Alignment.center;
    final index = values.indexOf(selected);
    if (index < 0) return Alignment.center;
    return Alignment(-1 + 2 * index / (values.length - 1), 0);
  }
}

/// Settings row: icon, title, subtitle, and either a switch or a chevron.
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onChanged,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// When non-null, the row renders a switch.
  final bool? value;
  final ValueChanged<bool>? onChanged;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final Widget? tail = switch ((value, trailing)) {
      (final bool current, _) => Switch(
          value: current,
          onChanged: onChanged,
        ),
      (null, final Widget widget) => widget,
      _ => onTap == null
          ? null
          : Icon(Icons.chevron_right, color: palette.faint, size: 19),
    };

    // Panel paints its own background, so the tile needs a Material of its own
    // for taps to show ink instead of being hidden behind that decoration.
    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap ??
            (value != null && onChanged != null
                ? () => onChanged!(!value!)
                : null),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        minLeadingWidth: 24,
        horizontalTitleGap: 14,
        // A plain glyph. A tinted tile behind every row's icon made a settings
        // page into a column of violet squares that all said the same thing.
        leading: Icon(icon, color: palette.muted, size: 20),
        title: Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle!,
                style: TextStyle(color: palette.muted, fontSize: 11),
              ),
        trailing: tail,
      ),
    );
  }
}

/// Panel wrapping a list of [SettingRow]s with dividers between them.
class SettingGroup extends StatelessWidget {
  const SettingGroup({super.key, required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(title),
        Panel(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                rows[i],
                if (i < rows.length - 1)
                  Divider(
                    indent: 54,
                    endIndent: 0,
                    height: 1,
                    color: palette.border.withValues(alpha: dark ? .5 : .8),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: Gap.xl),
      ],
    );
  }
}

/// Centred empty state with an optional call to action.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Panel(
      padding:
          const EdgeInsets.symmetric(horizontal: Gap.xl, vertical: Gap.xxl),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: palette.surface2,
              shape: BoxShape.circle,
              border: Border.all(color: palette.border),
            ),
            child: Icon(icon, color: palette.violetSoft, size: 24),
          ),
          const SizedBox(height: Gap.lg),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (action != null) ...[
            const SizedBox(height: Gap.xl),
            action!,
          ],
        ],
      ),
    );
  }
}
