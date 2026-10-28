/// Editor for one custom routing rule.
///
/// A sheet rather than a page: a rule is three fields, and the list it came from
/// is the context for what you are typing.
///
/// The save button stays disabled until the rule is valid. That is the point of
/// [CustomRule.problem] being checked here — sing-box refuses to start on a
/// malformed route rule, so a rule that cannot be rendered must not be able to
/// reach the config in the first place.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/custom_rule.dart';
import '../models/policy_group.dart';
import 'notice_text.dart';
import 'theme.dart';
import 'widgets.dart';

/// Edits [rule], returning the edited copy or null when cancelled.
///
/// The caller decides whether the result is an add or an update — this sheet does
/// not touch state, so the same code path serves both.
Future<CustomRule?> showRuleSheet(
  BuildContext context, {
  required CustomRule rule,
  required bool isNew,
  List<PolicyGroup> groups = const [],
}) {
  return showModalBottomSheet<CustomRule>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _RuleSheet(rule: rule, isNew: isNew, groups: groups),
  );
}

class _RuleSheet extends StatefulWidget {
  const _RuleSheet({
    required this.rule,
    required this.isNew,
    required this.groups,
  });

  final CustomRule rule;
  final bool isNew;

  /// Policy groups the rule can be sent to, beside the three plain targets.
  final List<PolicyGroup> groups;

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  late final TextEditingController _value =
      TextEditingController(text: widget.rule.value);
  late RuleMatcher _matcher = widget.rule.matcher;
  // A rule whose group was deleted comes in pointing at nothing; it opens as
  // proxy, which is where the config has been sending it.
  late RuleTarget _target = widget.rule.target == RuleTarget.group &&
          !widget.groups.any((group) => group.id == widget.rule.groupId)
      ? RuleTarget.proxy
      : widget.rule.target;
  late String? _groupId = widget.rule.groupId;

  /// Only shown after the first edit or a failed save. Flagging "enter a value"
  /// on a field the user has not reached yet reads as an error they caused.
  var _showProblem = false;

  @override
  void initState() {
    super.initState();
    _value.addListener(_onValueChanged);
  }

  @override
  void dispose() {
    _value.removeListener(_onValueChanged);
    _value.dispose();
    super.dispose();
  }

  void _onValueChanged() => setState(() => _showProblem = true);

  /// The rule as currently edited, whether or not it is valid.
  CustomRule get _draft => widget.rule.copyWith(
        matcher: _matcher,
        value: _value.text.trim(),
        target: _target,
        groupId: _groupId,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    final draft = _draft;
    final problem = draft.problem;

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
              widget.isNew ? l10n.rulesCustomAdd : l10n.rulesCustomEdit,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: Gap.xl),
            SectionLabel(l10n.rulesMatchOn),
            const SizedBox(height: Gap.sm),
            _MatcherPicker(
              selected: _matcher,
              // Changing the matcher changes what the value means, so the
              // problem is re-evaluated against the new one immediately — a port
              // that was valid is not a valid CIDR.
              onChanged: (value) => setState(() => _matcher = value),
            ),
            const SizedBox(height: Gap.lg),
            TextField(
              controller: _value,
              autofocus: widget.isNew,
              keyboardType: _matcher == RuleMatcher.port
                  ? TextInputType.number
                  : TextInputType.text,
              inputFormatters: [
                // A hostname or address never contains whitespace, and a pasted
                // value that ends in a stray space is invisible in the field and
                // fatal to the match.
                FilteringTextInputFormatter.deny(RegExp(r'\s')),
              ],
              decoration: InputDecoration(
                hintText: ruleValueHint(l10n, _matcher),
                errorText: _showProblem && problem != null
                    ? ruleProblemText(l10n, problem)
                    : null,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: Gap.lg),
            SectionLabel(l10n.rulesSendTo),
            const SizedBox(height: Gap.sm),
            SegmentedChoice<RuleTarget>(
              values: const [
                RuleTarget.proxy,
                RuleTarget.direct,
                RuleTarget.block,
              ],
              selected: _target,
              labelOf: (value) => ruleTargetText(l10n, value),
              onChanged: (value) => setState(() => _target = value),
            ),
            if (widget.groups.isNotEmpty) ...[
              const SizedBox(height: Gap.lg),
              Text(
                l10n.rulesSendToGroup,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: Gap.sm),
              Wrap(
                spacing: Gap.sm,
                runSpacing: Gap.sm,
                children: [
                  for (final group in widget.groups)
                    ChoiceChip(
                      label: Text(group.name),
                      avatar: Icon(
                        Icons.call_split_rounded,
                        size: 16,
                        color: _isGroup(group)
                            ? palette.violetSoft
                            : palette.muted,
                      ),
                      selected: _isGroup(group),
                      showCheckmark: false,
                      backgroundColor: palette.surface,
                      selectedColor: palette.violetSoft.withValues(alpha: .14),
                      side: BorderSide(
                        color: _isGroup(group)
                            ? palette.violetSoft
                            : palette.border,
                      ),
                      shape: const StadiumBorder(),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color:
                            _isGroup(group) ? palette.violetSoft : palette.text,
                      ),
                      onSelected: (_) => setState(() {
                        _target = RuleTarget.group;
                        _groupId = group.id;
                      }),
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
                    // Disabled rather than accepting and failing later: an
                    // invalid rule reaching the config means the tunnel refuses
                    // to start, with nothing naming the rule that did it.
                    onPressed: draft.isValid ? _save : null,
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

  bool _isGroup(PolicyGroup group) =>
      _target == RuleTarget.group && _groupId == group.id;

  void _save() {
    final draft = _draft;
    if (!draft.isValid) {
      setState(() => _showProblem = true);
      return;
    }
    Navigator.of(context).pop(draft);
  }
}

/// The matcher as a dropdown.
///
/// A dropdown rather than segments: six options do not fit on a phone, and the
/// names are phrases ("Domain and subdomains") rather than words.
class _MatcherPicker extends StatelessWidget {
  const _MatcherPicker({required this.selected, required this.onChanged});

  final RuleMatcher selected;
  final ValueChanged<RuleMatcher> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
      decoration: BoxDecoration(
        color: palette.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: palette.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<RuleMatcher>(
          value: selected,
          isExpanded: true,
          dropdownColor: palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          icon: Icon(Icons.expand_more, size: 20, color: palette.muted),
          style: TextStyle(
            fontFamily: AppFonts.body,
            fontFamilyFallback: AppFonts.cjkFallback,
            fontSize: 13,
            color: palette.text,
          ),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
          items: [
            for (final matcher in RuleMatcher.values)
              DropdownMenuItem(
                value: matcher,
                child: Text(ruleMatcherText(l10n, matcher)),
              ),
          ],
        ),
      ),
    );
  }
}
