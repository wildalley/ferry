part of 'app_state.dart';

// See AppStateConnection for why ChangeNotifier lint is intentionally scoped.
// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member

extension _AppStateConfig on AppState {
  // ------------------------------------------------------------------ config

  /// The config that would be sent to the runtime, for the diagnostics screen.
  ///
  /// Rendered with the Clash API secret masked. The sheet this feeds is one tap
  /// from the clipboard and from there into a bug report, and the token has no
  /// diagnostic value beyond being present.
  String _previewConfig() =>
      ConfigBuilder.encode(_buildConfig(clashSecret: _maskedSecret));

  Map<String, dynamic> _buildConfig({String? clashSecret}) =>
      ConfigBuilder.build(
        nodes: _nodes,
        selectedNodeId: selectedNode?.id,
        settings: _settings,
        clashSecret: clashSecret ?? _clashSecret,
        clashApiPort: _clashApiPort,
        localProxyPort: _localProxyPort,
        customRules: _customRules,
        policyGroups: _policyGroups,
        groupRuleSets: _groupRuleSetTags(),
        ruleSetDir: _ruleSetDir,
      );

  /// The config to hand a runtime, validated on the way out.
  ///
  /// Every platform's config leaves through here, which is the point: the
  /// desktop controllers used to be the only ones that checked their input, and
  /// they check it *after* the boundary — so an unusable config reached Android's
  /// libbox unexamined and surfaced as whatever the engine made of it. Validating
  /// here means one gate, and it fails before a process starts or a VPN service
  /// comes up rather than as a control-API timeout seconds later.
  ///
  /// Throws [FormatException]. The messages name fields, never values: this
  /// config holds the node credentials and the Clash API token.
  String _renderConfig() {
    final config = _buildConfig();
    // The decoded map, not the encoded string: the desktop path parses the JSON
    // again on the far side, and there is nothing to learn from doing it twice.
    ConfigFacts.fromMap(config);
    // Every config that reaches a runtime leaves through here, which is why the
    // record of what the engine is running is taken here too. An outbound tag is
    // derived from the node's *name*, so a subscription that renames a node
    // changes every tag under it while the live engine keeps the old ones — and
    // `selectOutbound` would then name a member that does not exist. See
    // [AppState._liveOutboundTags].
    // Deduplicated the same way the builder does, so this holds exactly the
    // members the rendered selector lists and nothing that was collapsed out.
    _liveOutboundTags = {
      for (final node in deduplicateProxyNodes(_nodes))
        ConfigBuilder.outboundTag(node),
    };
    _liveGroupTags = {
      for (final group in _policyGroups) ConfigTags.group(group.id),
    };
    return ConfigBuilder.encode(config);
  }

  // ------------------------------------------------------------ custom rules

  /// Appends a rule and applies it.
  ///
  /// Appended rather than prepended: rules are matched in order, and a user
  /// adding a rule expects it after the ones already there, not silently ahead
  /// of them.
  Future<void> _addCustomRuleIntent(CustomRule rule) =>
      _enqueue(() => _writeCustomRules([..._customRules, rule]));

  /// Replaces the rule with the same id, or does nothing if it is gone.
  Future<void> _updateCustomRuleIntent(CustomRule rule) async {
    final index = _customRules.indexWhere((item) => item.id == rule.id);
    if (index < 0) return;
    final next = [..._customRules]..[index] = rule;
    await _enqueue(() => _writeCustomRules(next));
  }

  Future<void> _removeCustomRuleIntent(String id) => _enqueue(
        () => _writeCustomRules(
          _customRules.where((rule) => rule.id != id).toList(),
        ),
      );

  /// Moves the rule at [from] to [to], because order is behaviour.
  Future<void> _moveCustomRuleIntent(int from, int to) async {
    if (from < 0 || from >= _customRules.length) return;
    if (to < 0 || to >= _customRules.length || from == to) return;
    final next = [..._customRules];
    next.insert(to, next.removeAt(from));
    await _enqueue(() => _writeCustomRules(next));
  }

  /// A fresh rule with an id, ready to be edited. Not persisted until added.
  ///
  /// Same id scheme as nodes and subscriptions: a base-36 microsecond stamp,
  /// which cannot collide within one process.
  CustomRule _newCustomRule() => CustomRule(
        id: _newId(),
        matcher: RuleMatcher.domainSuffix,
        value: '',
        target: RuleTarget.proxy,
      );

  /// Persists [rules] and pushes them to a running tunnel.
  ///
  /// The reload is the point. Unlike the bundled rule-sets — which the engine
  /// reads off disk at start, so a download only applies at the next connect —
  /// route rules are part of the config, and reloading is the only way a rule the
  /// user just typed takes effect now. It costs the live connections, which is
  /// the honest price of changing where traffic goes.
  Future<void> _writeCustomRules(List<CustomRule> rules) async {
    _customRules = rules;
    await _storage.writeCustomRules(rules);
    notifyListeners();

    if (!isConnected) return;
    final operationId = _runtimeOperationId;
    try {
      await _controller.reload(_renderConfig());
    } on FormatException catch (error) {
      // The rules are already persisted, so this reports that they are not live
      // yet rather than that they are lost — the same distinction the settings
      // reload draws.
      if (_runtimeOperationId == operationId) {
        _notify(
          AppNotice.error(NoticeKind.configInvalid, detail: error.message),
        );
      }
    } on Object catch (error) {
      if (_runtimeOperationId == operationId) {
        _notify(
            AppNotice.error(NoticeKind.reloadFailed, detail: _short(error)));
      }
    }
  }
}

extension _AppStatePolicyGroups on AppState {
  // ----------------------------------------------------------- policy groups

  /// Makes a group on the engine's own pick, and puts it in a running config
  /// so a rule can use it straight away. Returns null for a blank name.
  Future<PolicyGroup?> _addPolicyGroupIntent(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;
    final group = PolicyGroup(id: _newId(), name: trimmed);
    await _enqueue(() async {
      _policyGroups = [..._policyGroups, group];
      await _storage.writePolicyGroups(_policyGroups);
      notifyListeners();
      // Nothing points at a new group yet, but a rule made next will, and the
      // live engine has to know the selector before it can route to it.
      if (isConnected) await _reloadLive();
    });
    return group;
  }

  /// Renames a group. Display only: the selector's tag comes from the id, so
  /// the running config is already right.
  Future<void> _renamePolicyGroupIntent(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _enqueue(() async {
      _policyGroups = [
        for (final group in _policyGroups)
          group.id == id ? group.copyWith(name: trimmed) : group,
      ];
      await _storage.writePolicyGroups(_policyGroups);
      notifyListeners();
    });
  }

  /// Deletes a group, and moves the rules that used it to the main exit.
  ///
  /// Moved explicitly rather than left to the builder's fallback: a rule still
  /// saying "group" with nothing to name would show a target the user cannot
  /// find anywhere on the page.
  Future<void> _removePolicyGroupIntent(String id) => _enqueue(() async {
        if (!_policyGroups.any((group) => group.id == id)) return;
        _policyGroups = _policyGroups.where((group) => group.id != id).toList();
        await _storage.writePolicyGroups(_policyGroups);
        final rules = [
          for (final rule in _customRules)
            rule.target == RuleTarget.group && rule.groupId == id
                ? rule.copyWith(target: RuleTarget.proxy)
                : rule,
        ];
        // Persists the rules and reloads a running engine, which also drops
        // the deleted selector from it.
        await _writeCustomRules(rules);
      });

  /// Points a group at a node, live when connected.
  ///
  /// The same commit-after-confirm rule as the main selector: while connected,
  /// the choice is saved only once the engine reports it took. A group or node
  /// the running config does not have yet is reached by reloading instead.
  Future<void> _selectGroupNodeIntent(String groupId, String? nodeId) =>
      _enqueue(() async {
        final group = policyGroup(groupId);
        if (group == null) return;
        ProxyNode? node;
        for (final candidate in _nodes) {
          if (candidate.id == nodeId) node = candidate;
        }
        // A node that vanished between the sheet opening and the tap means
        // the engine's pick, which is also what the config would render.
        final member =
            node == null ? ConfigTags.auto : ConfigBuilder.outboundTag(node);
        final next = group.copyWith(nodeId: () => node?.id);

        Future<void> commit() async {
          _policyGroups = [
            for (final item in _policyGroups) item.id == groupId ? next : item,
          ];
          await _storage.writePolicyGroups(_policyGroups);
          notifyListeners();
        }

        if (!isConnected) return commit();

        final tag = ConfigTags.group(groupId);
        final live = (_liveGroupTags?.contains(tag) ?? false) &&
            (node == null || (_liveOutboundTags?.contains(member) ?? false));
        if (!live) {
          await commit();
          await _reloadLive();
          return;
        }
        try {
          await _controller.selectGroupOutbound(tag, member);
          await commit();
        } on Object catch (error) {
          _notify(
            AppNotice.error(NoticeKind.switchFailed, detail: _short(error)),
          );
        }
      });
}

extension _AppStateGroupRuleSets on AppState {
  // ------------------------------------------------- policy group rule-sets

  File? _ruleSetFile(String entry) {
    final dir = _ruleSetDir;
    final source = RuleSetSource.parse(entry);
    if (dir == null || source == null) return null;
    return File('$dir/${BundledRuleSets.fileName(source.tag)}');
  }

  /// Each group's rule-set tags whose files are on disk. One still to be
  /// downloaded is left out of the config rather than named as a missing file.
  Map<String, List<String>> _groupRuleSetTags() => {
        for (final group in _policyGroups)
          group.id: [
            for (final entry in group.ruleSets)
              if (_ruleSetFile(entry)?.existsSync() ?? false)
                RuleSetSource.parse(entry)!.tag,
          ],
      };

  Future<bool> _addGroupRuleSetIntent(String groupId, String input) async {
    final source = RuleSetSource.parse(input);
    final group = policyGroup(groupId);
    if (source == null || group == null) return false;
    if (group.ruleSets.contains(source.entry)) return false;
    await _enqueue(() async {
      _policyGroups = [
        for (final item in _policyGroups)
          item.id == groupId
              ? item.copyWith(ruleSets: [...item.ruleSets, source.entry])
              : item,
      ];
      await _storage.writePolicyGroups(_policyGroups);
      notifyListeners();
    });
    // Another group may already have downloaded the same list.
    if (isRuleSetDownloaded(source.entry)) {
      if (isConnected) await _enqueue(_reloadLive);
      return true;
    }
    await _downloadRuleSets([source], report: true);
    return true;
  }

  Future<void> _removeGroupRuleSetIntent(String groupId, String entry) async {
    final wasRendered = isRuleSetDownloaded(entry);
    await _enqueue(() async {
      _policyGroups = [
        for (final item in _policyGroups)
          item.id == groupId
              ? item.copyWith(
                  ruleSets: item.ruleSets.where((e) => e != entry).toList(),
                )
              : item,
      ];
      await _storage.writePolicyGroups(_policyGroups);
      notifyListeners();
      if (wasRendered && isConnected) await _reloadLive();
      // The file goes once no group lists it, so the directory does not
      // collect every list ever tried.
      if (!_policyGroups.any((g) => g.ruleSets.contains(entry))) {
        try {
          _ruleSetFile(entry)?.deleteSync();
        } on Object {
          // Already gone, or held open; either way it no longer renders.
        }
      }
    });
  }

  Future<void> _retryGroupRuleSet(String entry) async {
    final source = RuleSetSource.parse(entry);
    if (source != null) await _downloadRuleSets([source], report: true);
  }

  /// Downloads [sources], through the tunnel when it is up, and puts the new
  /// rules into a running engine. Outside the operation queue on purpose: a
  /// slow download must not hold up a connect or a node switch.
  Future<void> _downloadRuleSets(
    List<RuleSetSource> sources, {
    required bool report,
  }) async {
    final dir = _ruleSetDir;
    if (dir == null || !_acceptingWork) return;
    final fresh =
        sources.where((s) => !_downloadingRuleSets.contains(s.entry)).toList();
    if (fresh.isEmpty) return;
    _downloadingRuleSets.addAll(fresh.map((s) => s.entry));
    notifyListeners();

    var landed = false;
    final failed = <String>[];
    for (final source in fresh) {
      try {
        await _ruleSetUpdater.fetchSource(
          Directory(dir),
          source,
          viaLocalProxy: isConnected,
          localProxyPort: _localProxyPort,
        );
        landed = true;
      } on Object {
        failed.add(source.label);
      } finally {
        _downloadingRuleSets.remove(source.entry);
      }
    }
    if (_disposed) return;
    if (report && failed.isNotEmpty) {
      _notice = AppNotice.error(
        NoticeKind.ruleSetDownloadFailed,
        detail: failed.join(', '),
      );
    }
    _notifyUnlessDisposed();
    if (landed && isConnected) await _enqueue(_reloadLive);
  }

  /// Every group's rule-sets, refreshed beside the bundled lists. Like those,
  /// a refreshed file takes effect at the next start; one downloaded for the
  /// first time is new to the config, so that does reload.
  Future<void> _refreshGroupRuleSets() async {
    final sources = <String, RuleSetSource>{
      for (final group in _policyGroups)
        for (final entry in group.ruleSets)
          if (RuleSetSource.parse(entry) case final source?) entry: source,
    };
    if (sources.isEmpty) return;
    await _downloadRuleSets(sources.values.toList(), report: false);
  }
}

const _maskedSecret = '<hidden>';
