/// Local persistence for nodes, subscriptions, settings, and selection.
///
/// Preferences hold presentation settings; credentials live in the OS vault.
library;

import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_settings.dart';
import '../models/custom_rule.dart';
import '../models/node.dart';
import '../models/policy_group.dart';
import '../models/node_sort.dart';
import '../models/subscription.dart';
import 'secret_store.dart';

class Storage {
  Storage._(this._prefs, this._secrets);

  final SharedPreferences _prefs;
  final SecretStore _secrets;
  final _secretCache = <String, String>{};
  Future<void> _writeTail = Future<void>.value();

  static const _kNodes = 'nodes.v1';
  static const _kSubscriptions = 'subscriptions.v1';
  static const _kSettings = 'settings.v1';
  static const _kSelectedNode = 'selected_node.v1';
  static const _kCollapsedSources = 'collapsed_sources.v1';
  static const _kClashSecret = 'clash_secret.v1';
  static const _kProxySecret = 'proxy_secret.v1';
  static const _kVaultInitialized = 'vault_initialized.v1';
  static const _kNodeSort = 'node_sort.v1';
  static const _kCustomRules = 'custom_rules.v1';
  static const _kPolicyGroups = 'policy_groups.v1';
  static const _kUpdateCheckedAt = 'update_checked_at.v1';
  static const _kUpdateDismissed = 'update_dismissed.v1';

  static Future<Storage> open({SecretStore? secrets}) async {
    final storage = Storage._(
      await SharedPreferences.getInstance(),
      secrets ?? const PlatformSecretStore(),
    );
    await storage._migrateSecrets();
    return storage;
  }

  Future<void> _migrateSecrets() async {
    const keys = [_kNodes, _kSubscriptions, _kClashSecret, _kProxySecret];
    try {
      // Complete and verify EVERY write before removing any legacy value.
      // A crash halfway through is resumable: the vault is authoritative for
      // keys already copied, and untouched legacy keys are still available.
      for (final key in keys) {
        var value = await _secrets.read(key);
        if (value == null) {
          if (_prefs.getBool(_kVaultInitialized) == true) {
            throw const SecureStorageUnavailable();
          }
          value = _prefs.getString(key) ??
              (key == _kNodes || key == _kSubscriptions ? '[]' : _newSecret());
          _validateSecret(key, value);
          await _secrets.write(key, value);
        }
        _validateSecret(key, value);
        if (await _secrets.read(key) != value) {
          throw const SecureStorageUnavailable();
        }
        _secretCache[key] = value;
      }
      if (!await _prefs.setBool(_kVaultInitialized, true)) {
        throw const SecureStorageUnavailable();
      }
      for (final key in keys) {
        if (_prefs.containsKey(key) && !await _prefs.remove(key)) {
          throw const SecureStorageUnavailable();
        }
      }
    } on Object {
      throw const SecureStorageUnavailable();
    }
  }

  static void _validateSecret(String key, String value) {
    if (key == _kNodes || key == _kSubscriptions) {
      final decoded = jsonDecode(value);
      if (decoded is! List) throw const SecureStorageUnavailable();
      for (final item in decoded) {
        final data = Map<String, dynamic>.from(item as Map);
        if (key == _kNodes) {
          ProxyNode.fromJson(data);
        } else {
          Subscription.fromJson(data);
        }
      }
    } else if (value.isEmpty) {
      throw const SecureStorageUnavailable();
    }
  }

  static String _newSecret() {
    final random = Random.secure();
    return base64UrlEncode(List.generate(32, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }

  Future<void> _writeSecret(String key, String value) {
    final operation = _writeTail.then((_) async {
      try {
        await _secrets.write(key, value);
        if (await _secrets.read(key) != value) {
          throw const SecureStorageUnavailable();
        }
        _secretCache[key] = value;
      } on Object {
        throw const SecureStorageUnavailable();
      }
    });
    // A failed write must not prevent retrying after the keyring is unlocked.
    _writeTail = operation.catchError((Object _) {});
    return operation;
  }

  List<ProxyNode> readNodes() {
    final raw = _secretCache[_kNodes];
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((item) => ProxyNode.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on Object {
      // Corrupt payload: start clean rather than blocking app start.
      return const [];
    }
  }

  Future<void> writeNodes(List<ProxyNode> nodes) => _writeSecret(
        _kNodes,
        jsonEncode(nodes.map((node) => node.toJson()).toList()),
      );

  /// The user's own routing rules, in the order they will be matched.
  ///
  /// Order is data here, not presentation: sing-box takes the first rule that
  /// matches, so the list order decides the behaviour and a read that reordered
  /// them would change what the tunnel does.
  List<CustomRule> readCustomRules() {
    final raw = _prefs.getString(_kCustomRules);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((item) => CustomRule.fromJson(Map<String, dynamic>.from(item)))
          // A record with no id cannot be edited or removed through the UI,
          // which keys on it. Dropping it beats showing a row that ignores every
          // button on it.
          .where((rule) => rule.id.isNotEmpty)
          .toList();
    } on Object {
      // Corrupt payload: start clean rather than blocking app start.
      return const [];
    }
  }

  Future<void> writeCustomRules(List<CustomRule> rules) => _prefs.setString(
        _kCustomRules,
        jsonEncode(rules.map((rule) => rule.toJson()).toList()),
      );

  /// The user's policy groups, in the order they were made.
  List<PolicyGroup> readPolicyGroups() {
    final raw = _prefs.getString(_kPolicyGroups);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((item) => PolicyGroup.fromJson(Map<String, dynamic>.from(item)))
          // No id means no stable outbound tag; such a record cannot be
          // rendered or edited.
          .where((group) => group.id.isNotEmpty)
          .toList();
    } on Object {
      return const [];
    }
  }

  Future<void> writePolicyGroups(List<PolicyGroup> groups) => _prefs.setString(
        _kPolicyGroups,
        jsonEncode(groups.map((group) => group.toJson()).toList()),
      );

  List<Subscription> readSubscriptions() {
    final raw = _secretCache[_kSubscriptions];
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((item) => Subscription.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on Object {
      return const [];
    }
  }

  Future<void> writeSubscriptions(List<Subscription> subscriptions) =>
      _writeSecret(
        _kSubscriptions,
        jsonEncode(subscriptions.map((item) => item.toJson()).toList()),
      );

  AppSettings readSettings() {
    final raw = _prefs.getString(_kSettings);
    if (raw == null || raw.isEmpty) return const AppSettings();
    try {
      return AppSettings.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } on Object {
      return const AppSettings();
    }
  }

  Future<void> writeSettings(AppSettings settings) =>
      _prefs.setString(_kSettings, jsonEncode(settings.toJson()));

  String? readSelectedNodeId() => _prefs.getString(_kSelectedNode);

  Future<void> writeSelectedNodeId(String? id) async {
    if (id == null) {
      await _prefs.remove(_kSelectedNode);
    } else {
      await _prefs.setString(_kSelectedNode, id);
    }
  }

  /// Source ids whose node list the user folded away on the nodes page.
  ///
  /// Persisted rather than held in the page's [State] so that folding a source
  /// away survives leaving the tab and restarting: it is work the user did, and
  /// a long list would have to be folded again on every visit.
  Set<String> readCollapsedSources() =>
      _prefs.getStringList(_kCollapsedSources)?.toSet() ?? const {};

  Future<void> writeCollapsedSources(Set<String> ids) =>
      _prefs.setStringList(_kCollapsedSources, ids.toList());

  /// How the nodes page orders rows within a source.
  ///
  /// Kept here rather than in [AppSettings] because it changes nothing about the
  /// tunnel: settings go through `applySettings`, which reloads a running
  /// config, and reordering a list is no reason to drop connections.
  /// When the app last asked for a newer release, or null if it never has.
  DateTime? readUpdateCheckedAt() {
    final ms = _prefs.getInt(_kUpdateCheckedAt);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> writeUpdateCheckedAt(DateTime at) =>
      _prefs.setInt(_kUpdateCheckedAt, at.millisecondsSinceEpoch);

  /// The release tag whose prompt the user closed; it is not shown again.
  String? readDismissedUpdate() => _prefs.getString(_kUpdateDismissed);

  Future<void> writeDismissedUpdate(String tag) =>
      _prefs.setString(_kUpdateDismissed, tag);

  NodeSort readNodeSort() => NodeSort.fromKey(_prefs.getString(_kNodeSort));

  Future<void> writeNodeSort(NodeSort sort) =>
      _prefs.setString(_kNodeSort, sort.key);

  /// The bearer token the running config's Clash API listener requires.
  ///
  /// Persisted rather than regenerated per run so that a token handed to
  /// anything outside the app keeps working, and so a reload mid-session cannot
  /// change it out from under a live listener. Generated once, then never shown
  /// or logged — this is a credential like any node's password.
  String readClashSecret() => _secretCache[_kClashSecret]!;

  String readProxySecret() => _secretCache[_kProxySecret]!;

  Future<void> writeClashSecret(String secret) =>
      _writeSecret(_kClashSecret, secret);
}
