/// User-defined policy groups: named exits that rules can send traffic to.
///
/// The main selector answers "which node does my traffic leave through". A
/// policy group asks the same question for a slice of traffic — AI services
/// through a US node, streaming through Hong Kong, everything else through the
/// main choice — and a [CustomRule] with [RuleTarget.group] is how a slice is
/// cut. Each group renders as its own sing-box `selector`, so its node can be
/// switched live, independently of the main one.
library;

class PolicyGroup {
  const PolicyGroup({required this.id, required this.name, this.nodeId});

  final String id;

  /// What the user called it. Display only: the outbound tag comes from [id],
  /// so a rename never touches the config.
  final String name;

  /// The node this group sends through, or null to let the engine's `urltest`
  /// group pick. A node that has since disappeared is treated as null.
  final String? nodeId;

  PolicyGroup copyWith({String? name, String? Function()? nodeId}) =>
      PolicyGroup(
        id: id,
        name: name ?? this.name,
        nodeId: nodeId == null ? this.nodeId : nodeId(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (nodeId != null) 'node': nodeId,
      };

  static PolicyGroup fromJson(Map<String, dynamic> json) => PolicyGroup(
        id: json['id'] as String? ?? '',
        name: (json['name'] as String? ?? '').trim(),
        nodeId: json['node'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is PolicyGroup &&
      other.id == id &&
      other.name == name &&
      other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(id, name, nodeId);
}
