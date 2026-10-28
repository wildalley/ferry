part of 'home_page.dart';

/// One line reporting the address the outside world sees.
///
/// The reading every other figure on this screen cannot give. Bytes moving and a
/// node selected look the same whether the traffic leaves through the node or
/// straight out of the user's own line, so this is the only thing on the
/// dashboard that actually answers "is it working". Hence the prominence of a
/// row of its own rather than a line in a settings list.
class _ExitAddressRow extends StatelessWidget {
  const _ExitAddressRow({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final address = state.exitAddress;
    final checking = state.isCheckingExitAddress;
    final connected = state.isConnected;

    // Four states, and they have to stay distinguishable: a dash means nothing
    // was asked, "checking" means in flight, an address is the answer, and
    // "unknown" means it was asked and nothing came back — which is worth
    // telling apart from the dash, because it can mean a tunnel that carries
    // nothing.
    final (String text, Color colour) =
        switch ((connected, checking, address)) {
      (_, true, _) => (l10n.settingsChecking, palette.faint),
      (_, _, final found?) => (found.ip, palette.text),
      (false, _, _) => (l10n.latencyUnknown, palette.faint),
      _ => (l10n.homeExitUnknown, palette.amber),
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.xs, Gap.sm),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(Icons.travel_explore_outlined, size: 15, color: palette.faint),
          const SizedBox(width: Gap.sm),
          Text(
            l10n.homeExitIp.toUpperCase(),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(letterSpacing: 1.1),
          ),
          const Spacer(),
          // The address is data, so it is monospaced like every other reading
          // here; it also stops the row twitching as digits change on a refresh.
          Flexible(
            child: AnimatedDefaultTextStyle(
              duration: motionOf(context, Motion.normal),
              curve: Motion.curve,
              style: DefaultTextStyle.of(context)
                  .style
                  .merge(monoStyle(color: colour, weight: FontWeight.w600)),
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          if (address?.countryCode case final code?) ...[
            const SizedBox(width: Gap.sm),
            // The country is the part a user actually reads: it says whether the
            // exit is where they picked, which a bare address does not.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: tintFill(palette.mint),
                borderRadius: BorderRadius.circular(AppRadius.xs),
                border: Border.all(color: palette.mint.withValues(alpha: .22)),
              ),
              child: Text(
                code,
                style: monoStyle(
                  size: 10,
                  color: palette.mint,
                  weight: FontWeight.w700,
                ),
              ),
            ),
          ],
          IconButton(
            // Left enabled while disconnected on purpose: that is how a user
            // checks what their own address is, and the request only goes out
            // when they ask for it.
            onPressed: checking ? null : state.refreshExitAddress,
            tooltip: l10n.actionRefresh,
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            color: palette.faint,
            icon: checking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }
}
