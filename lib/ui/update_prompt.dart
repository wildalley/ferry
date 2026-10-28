/// The optional-update prompt: a dismissible card on the dashboard, and the
/// shared way to open a release page.
///
/// Never modal and never repeated for a release the user closed — the app
/// keeps working on the version it is, and updating is their call.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../platform/open_url.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens [url] in the browser, or copies it when there is nothing to open it
/// with — a desktop without a handler should still get the user there.
Future<void> openReleasePage(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final copied = L10n.of(context).noticeLinkCopied;
  if (await openExternalUrl(url)) return;
  await Clipboard.setData(ClipboardData(text: url));
  messenger?.showSnackBar(SnackBar(content: Text(copied)));
}

class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final release = state.availableUpdate;
    if (release == null || !state.showUpdatePrompt) {
      return const SizedBox.shrink();
    }
    final l10n = L10n.of(context);
    final palette = context.palette;

    return Padding(
      padding: const EdgeInsets.only(bottom: Gap.md),
      child: Panel(
        accent: palette.violetSoft,
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(Icons.system_update_alt_rounded,
                size: 22, color: palette.violetSoft),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.updateBannerTitle(release.tag),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.updateBannerBody,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: state.dismissUpdate,
              style: TextButton.styleFrom(foregroundColor: palette.muted),
              child: Text(l10n.actionLater),
            ),
            FilledButton(
              onPressed: () => openReleasePage(context, release.url),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text(l10n.actionView),
            ),
          ],
        ),
      ),
    );
  }
}
