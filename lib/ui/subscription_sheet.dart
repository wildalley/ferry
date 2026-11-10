/// Editor for one subscription: its name, and for a remote one the URL and the
/// User-Agent it is fetched with.
///
/// The sheet itself does not touch state, as with the rule sheet; [editSubscription]
/// applies the result, so the settings row and the nodes header share one path.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/importer.dart';
import '../l10n/app_localizations.dart';
import '../models/subscription.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

typedef SubscriptionEdit = ({String name, String? url, String? userAgent});

/// Agents panels commonly switch on. Product names, so left untranslated.
const subscriptionUserAgentPresets = [
  'sing-box',
  'clash.meta',
  'mihomo',
  'clash-verge',
  'v2rayN',
];

/// Edits [subscription], returning the edit or null when cancelled.
Future<SubscriptionEdit?> showSubscriptionSheet(
  BuildContext context, {
  required Subscription subscription,
}) {
  return showModalBottomSheet<SubscriptionEdit>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _SubscriptionSheet(subscription: subscription),
  );
}

/// Opens the sheet for [subscription] and applies what comes back.
Future<void> editSubscription(
  BuildContext context,
  AppState state,
  Subscription subscription,
) async {
  final edit = await showSubscriptionSheet(context, subscription: subscription);
  if (edit == null) return;
  await state.updateSubscription(
    subscription.id,
    name: edit.name,
    url: edit.url,
    userAgent: edit.userAgent,
  );
}

class _SubscriptionSheet extends StatefulWidget {
  const _SubscriptionSheet({required this.subscription});

  final Subscription subscription;

  @override
  State<_SubscriptionSheet> createState() => _SubscriptionSheetState();
}

class _SubscriptionSheetState extends State<_SubscriptionSheet> {
  late final _name = TextEditingController(text: widget.subscription.name);
  late final _url = TextEditingController(text: widget.subscription.url);
  late final _userAgent =
      TextEditingController(text: widget.subscription.userAgent);

  /// Only shown after the first edit, as in the rule sheet.
  var _showProblem = false;

  bool get _isRemote => widget.subscription.isRemote;

  @override
  void initState() {
    super.initState();
    for (final controller in [_name, _url, _userAgent]) {
      controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _userAgent.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() => _showProblem = true);

  bool get _nameValid => _name.text.trim().isNotEmpty;

  /// The same test the importer applies, so a URL accepted here fetches.
  bool get _urlValid {
    if (!_isRemote) return true;
    final uri = Uri.tryParse(_url.text.trim());
    return uri != null &&
        (uri.isScheme('http') || uri.isScheme('https')) &&
        uri.host.isNotEmpty;
  }

  bool get _valid => _nameValid && _urlValid;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final insets = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: insets),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Gap.xl, Gap.md, Gap.xl, Gap.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: Gap.lg),
                decoration: BoxDecoration(
                  color: palette.borderStrong,
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
              ),
            ),
            Text(
              l10n.subscriptionEditTitle,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: Gap.xl),
            SectionLabel(l10n.subscriptionName),
            TextField(
              controller: _name,
              decoration: InputDecoration(
                errorText: _showProblem && !_nameValid
                    ? l10n.subscriptionNameRequired
                    : null,
              ),
            ),
            if (_isRemote) ...[
              const SizedBox(height: Gap.lg),
              SectionLabel(l10n.subscriptionUrl),
              TextField(
                controller: _url,
                minLines: 1,
                maxLines: 3,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.url,
                inputFormatters: [
                  FilteringTextInputFormatter.deny(RegExp(r'\s')),
                ],
                style: monoStyle(size: 12, color: palette.text),
                decoration: InputDecoration(
                  hintText: 'https://example.com/sub',
                  helperText: _url.text.trim().startsWith('http://')
                      ? l10n.plainHttpWarning
                      : null,
                  helperMaxLines: 5,
                  errorText: _showProblem && !_urlValid
                      ? l10n.subscriptionUrlInvalid
                      : null,
                ),
              ),
              const SizedBox(height: Gap.lg),
              SectionLabel(l10n.subscriptionUserAgent),
              TextField(
                controller: _userAgent,
                autocorrect: false,
                enableSuggestions: false,
                style: monoStyle(size: 12, color: palette.text),
                decoration: InputDecoration(
                  // Empty means the default, so the default is the hint.
                  hintText: Importer.defaultUserAgent,
                  helperText: l10n.subscriptionUserAgentHelp,
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  for (final preset in subscriptionUserAgentPresets)
                    ChoiceChip(
                      label: Text(preset),
                      selected: _userAgent.text.trim() == preset,
                      showCheckmark: false,
                      onSelected: (_) => _userAgent.text = preset,
                    ),
                ],
              ),
            ],
            const SizedBox(height: Gap.xxl),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.actionCancel),
                  ),
                ),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: FilledButton(
                    onPressed: _valid ? _save : null,
                    child: Text(l10n.actionSave),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    if (!_valid) {
      setState(() => _showProblem = true);
      return;
    }
    Navigator.of(context).pop<SubscriptionEdit>((
      name: _name.text.trim(),
      url: _isRemote ? _url.text.trim() : null,
      userAgent: _isRemote ? _userAgent.text.trim() : null,
    ));
  }
}
