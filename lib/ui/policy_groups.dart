/// The rules page's policy groups: named exits, each with its own node.
///
/// A group on its own routes nothing; rules point traffic at it. So the section
/// sits above the user's rules, where the groups they can choose from are read
/// before the rules that use them.
library;

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/custom_rule.dart';
import '../models/node.dart';
import '../models/policy_group.dart';
import '../state/app_state.dart';
import 'theme.dart';
import 'widgets.dart';

class PolicyGroupsSection extends StatelessWidget {
  const PolicyGroupsSection({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final groups = state.policyGroups;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          l10n.rulesGroups,
          trailing: IconButton(
            onPressed: () => _addGroup(context, state),
            tooltip: l10n.rulesGroupsAdd,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 20),
          ),
        ),
        if (groups.isEmpty)
          _EmptyGroups(onAdd: () => _addGroup(context, state))
        else ...[
          for (final group in groups)
            _GroupRow(key: ValueKey(group.id), state: state, group: group),
          const SizedBox(height: Gap.xs),
          Text(
            l10n.rulesGroupsNote,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// A compact invitation rather than the full [EmptyState]: the section is an
/// optional extra on a page whose main content is below it.
class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    return Panel(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      child: Row(
        children: [
          Icon(Icons.call_split_rounded, size: 22, color: palette.violetSoft),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.rulesGroupsEmpty,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  l10n.rulesGroupsEmptyBody,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: Gap.sm),
          FilledButton(
            onPressed: onAdd,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              minimumSize: const Size(0, 40),
            ),
            child: Text(l10n.rulesGroupsAdd),
          ),
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({super.key, required this.state, required this.group});

  final AppState state;
  final PolicyGroup group;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final node = _nodeOf(state, group);
    final gone = group.nodeId != null && node == null;
    final rules = state.customRules
        .where((rule) =>
            rule.target == RuleTarget.group && rule.groupId == group.id)
        .length;
    final region = node?.regionCode;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Panel(
        onTap: () => _pickNode(context, state, group),
        padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.surface2,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: palette.border),
              ),
              child: node == null
                  ? Icon(Icons.bolt_rounded,
                      size: 20, color: palette.violetSoft)
                  : region == null
                      ? Icon(Icons.dns_outlined, size: 18, color: palette.muted)
                      : RegionFlag(
                          code: region,
                          size: 20,
                          fallbackStyle: monoStyle(
                            size: 12,
                            color: palette.muted,
                            weight: FontWeight.w500,
                          ),
                        ),
            ),
            const SizedBox(width: Gap.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    [
                      gone
                          ? l10n.rulesGroupNodeGone
                          : node?.name ?? l10n.nodesAuto,
                      l10n.rulesGroupRuleCount(rules),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: gone ? palette.amber : palette.muted,
                        ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: palette.faint),
            PopupMenuButton<_GroupAction>(
              tooltip: l10n.rulesGroupRename,
              icon: Icon(Icons.more_vert, size: 20, color: palette.faint),
              onSelected: (action) => switch (action) {
                _GroupAction.rename => _rename(context, state, group),
                _GroupAction.delete => _delete(context, state, group),
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: _GroupAction.rename,
                  child: Text(l10n.rulesGroupRename),
                ),
                PopupMenuItem(
                  value: _GroupAction.delete,
                  child: Text(
                    l10n.rulesGroupDelete,
                    style: TextStyle(color: palette.danger),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _GroupAction { rename, delete }

ProxyNode? _nodeOf(AppState state, PolicyGroup group) {
  for (final node in state.nodes) {
    if (node.id == group.nodeId) return node;
  }
  return null;
}

Future<void> _addGroup(BuildContext context, AppState state) async {
  final l10n = L10n.of(context);
  final name = await _askName(context, title: l10n.rulesGroupsAdd);
  if (name == null) return;
  final group = await state.addPolicyGroup(name);
  // Straight into choosing its node: a group without one is only half made.
  if (group != null && context.mounted) {
    await _pickNode(context, state, group);
  }
}

Future<void> _rename(
  BuildContext context,
  AppState state,
  PolicyGroup group,
) async {
  final name = await _askName(
    context,
    title: L10n.of(context).rulesGroupRename,
    initial: group.name,
  );
  if (name != null) await state.renamePolicyGroup(group.id, name);
}

Future<void> _delete(
  BuildContext context,
  AppState state,
  PolicyGroup group,
) async {
  final l10n = L10n.of(context);
  final danger = context.palette.danger;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.rulesGroupDelete),
      content: Text(l10n.rulesGroupDeleteBody(group.name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(backgroundColor: danger),
          child: Text(l10n.actionRemove),
        ),
      ],
    ),
  );
  if (confirmed == true) await state.removePolicyGroup(group.id);
}

/// A name, trimmed, or null when cancelled or left blank.
Future<String?> _askName(
  BuildContext context, {
  required String title,
  String initial = '',
}) async {
  final l10n = L10n.of(context);
  final controller = TextEditingController(text: initial);
  try {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: l10n.rulesGroupName,
            hintText: l10n.rulesGroupNameHint,
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );
    final trimmed = name?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  } finally {
    controller.dispose();
  }
}

/// The node list for one group: Auto first, then every node.
Future<void> _pickNode(
  BuildContext context,
  AppState state,
  PolicyGroup group,
) async {
  final picked = await showModalBottomSheet<_Pick>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .7,
      minChildSize: .4,
      maxChildSize: .92,
      builder: (context, controller) => _NodePicker(
        state: state,
        group: group,
        controller: controller,
      ),
    ),
  );
  if (picked != null) await state.selectGroupNode(group.id, picked.nodeId);
}

/// A choice in the picker; [nodeId] null is Auto.
class _Pick {
  const _Pick(this.nodeId);
  final String? nodeId;
}

class _NodePicker extends StatelessWidget {
  const _NodePicker({
    required this.state,
    required this.group,
    required this.controller,
  });

  final AppState state;
  final PolicyGroup group;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final palette = context.palette;
    final current = _nodeOf(state, group)?.id;
    final nodes = deduplicateProxyNodes(state.nodes);

    Widget option({
      required String? nodeId,
      required Widget leading,
      required String title,
      String? subtitle,
      Widget? trailing,
    }) {
      final selected = nodeId == current;
      return Material(
        color: selected
            ? palette.violetSoft.withValues(alpha: .08)
            : Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.pop(context, _Pick(nodeId)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Row(
              children: [
                SizedBox(width: 32, child: Center(child: leading)),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
                const SizedBox(width: Gap.sm),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked,
                  size: 20,
                  color: selected ? palette.violetSoft : palette.faint,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: Gap.md, bottom: Gap.md),
            decoration: BoxDecoration(
              color: palette.borderStrong,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, Gap.md),
          child: Text(
            l10n.rulesGroupSendVia(group.name),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        Expanded(
          child: ListView(
            controller: controller,
            children: [
              option(
                nodeId: null,
                leading: Icon(Icons.bolt_rounded, color: palette.violetSoft),
                title: l10n.nodesAuto,
                subtitle: l10n.nodesAutoBody,
              ),
              const Divider(height: 1),
              for (final node in nodes)
                option(
                  nodeId: node.id,
                  leading: node.regionCode == null
                      ? Icon(Icons.dns_outlined, size: 18, color: palette.muted)
                      : RegionFlag(
                          code: node.regionCode!,
                          size: 20,
                          fallbackStyle:
                              monoStyle(size: 12, color: palette.muted),
                        ),
                  title: node.name,
                  subtitle: node.protocol.label,
                  trailing: Text(
                    switch (node.latencyMs) {
                      null => l10n.latencyUnknown,
                      < 0 => l10n.latencyFail,
                      final value => '$value ms',
                    },
                    style: monoStyle(
                      size: 12,
                      color: latencyColor(palette, node.latencyMs),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
