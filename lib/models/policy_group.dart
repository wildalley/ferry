/// User-defined policy groups: named exits that rules can send traffic to.
///
/// The main selector answers "which node does my traffic leave through". A
/// policy group asks the same question for a slice of traffic — AI services
/// through a US node, streaming through Hong Kong, everything else through the
/// main choice — and a [CustomRule] with [RuleTarget.group] is how a slice is
/// cut. Each group renders as its own sing-box `selector`, so its node can be
/// switched live, independently of the main one.
///
/// A group can also carry rule-sets: whole lists of sites (a geosite category
/// such as `openai`, a geoip country, or any compiled `.srs` file) that go
/// through it, so a slice needs no domain typed out by hand.
library;

class PolicyGroup {
  const PolicyGroup({
    required this.id,
    required this.name,
    this.nodeId,
    this.ruleSets = const [],
  });

  final String id;

  /// What the user called it. Display only: the outbound tag comes from [id],
  /// so a rename never touches the config.
  final String name;

  /// The node this group sends through, or null to let the engine's `urltest`
  /// group pick. A node that has since disappeared is treated as null.
  final String? nodeId;

  /// [RuleSetSource.entry] strings, in the order they were added.
  final List<String> ruleSets;

  PolicyGroup copyWith({
    String? name,
    String? Function()? nodeId,
    List<String>? ruleSets,
  }) =>
      PolicyGroup(
        id: id,
        name: name ?? this.name,
        nodeId: nodeId == null ? this.nodeId : nodeId(),
        ruleSets: ruleSets ?? this.ruleSets,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (nodeId != null) 'node': nodeId,
        if (ruleSets.isNotEmpty) 'rule_sets': ruleSets,
      };

  static PolicyGroup fromJson(Map<String, dynamic> json) => PolicyGroup(
        id: json['id'] as String? ?? '',
        name: (json['name'] as String? ?? '').trim(),
        nodeId: json['node'] as String?,
        ruleSets: [
          for (final entry in json['rule_sets'] as List? ?? const [])
            if (RuleSetSource.parse('$entry') case final source?) source.entry,
        ],
      );

  @override
  bool operator ==(Object other) =>
      other is PolicyGroup &&
      other.id == id &&
      other.name == name &&
      other.nodeId == nodeId &&
      _sameList(other.ruleSets, ruleSets);

  @override
  int get hashCode => Object.hash(id, name, nodeId, Object.hashAll(ruleSets));

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

enum RuleSetKind { geosite, geoip, url }

/// Where one of a group's rule-sets comes from.
///
/// Typed as `openai` or `geosite:openai` (a geosite category), `geoip:jp` (a
/// country's addresses), or an https link to a compiled `.srs` file. The
/// categories come from the same SagerNet repositories as the bundled lists.
class RuleSetSource {
  const RuleSetSource._(this.kind, this.value);

  final RuleSetKind kind;

  /// The category or country name, or the URL.
  final String value;

  static final _name = RegExp(r'^[a-z0-9][a-z0-9!@._-]*$');

  /// [input] as a source, or null when it is none of the accepted forms.
  static RuleSetSource? parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;
    if (text.startsWith('https://')) {
      final uri = Uri.tryParse(text);
      return uri == null || uri.host.isEmpty
          ? null
          : RuleSetSource._(RuleSetKind.url, text);
    }
    final lower = text.toLowerCase();
    final (kind, name) = lower.startsWith('geoip:')
        ? (RuleSetKind.geoip, lower.substring(6))
        : lower.startsWith('geosite:')
            ? (RuleSetKind.geosite, lower.substring(8))
            : (RuleSetKind.geosite, lower);
    return _name.hasMatch(name) ? RuleSetSource._(kind, name) : null;
  }

  /// The canonical text stored on the group: `geosite:openai`, `geoip:jp` or
  /// the URL.
  String get entry => switch (kind) {
        RuleSetKind.geosite => 'geosite:$value',
        RuleSetKind.geoip => 'geoip:$value',
        RuleSetKind.url => value,
      };

  /// What the user reads: the bare category, `geoip:jp`, or the URL's file.
  String get label => switch (kind) {
        RuleSetKind.geosite => value,
        RuleSetKind.geoip => 'geoip:$value',
        RuleSetKind.url => Uri.parse(value).pathSegments.lastWhere(
              (s) => s.isNotEmpty,
              orElse: () => value,
            ),
      };

  /// The rule-set's tag in the rendered config, and its file's name stem.
  /// Prefixed so it can never collide with a bundled list's tag.
  String get tag => switch (kind) {
        RuleSetKind.geosite => 'ext-geosite-$value',
        RuleSetKind.geoip => 'ext-geoip-$value',
        RuleSetKind.url => 'ext-url-${_hash(value)}',
      };

  /// Where it is downloaded from. [base] is the SagerNet root, overridable so
  /// tests can serve the same paths locally.
  Uri url({required String base}) => switch (kind) {
        RuleSetKind.geosite =>
          Uri.parse('$base/sing-geosite/rule-set/geosite-$value.srs'),
        RuleSetKind.geoip =>
          Uri.parse('$base/sing-geoip/rule-set/geoip-$value.srs'),
        RuleSetKind.url => Uri.parse(value),
      };

  static String _hash(String text) {
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
