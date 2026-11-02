/// 内核 /providers/rules 返回的一条规则集来源。
class RuleProviderInfo {
  const RuleProviderInfo({
    required this.name,
    required this.behavior,
    required this.type,
    required this.ruleCount,
    required this.updatedAt,
  });

  factory RuleProviderInfo.fromJson(String key, Map<String, dynamic> json) {
    final rawUpdated = json['updatedAt'];
    final updated = rawUpdated is String ? DateTime.tryParse(rawUpdated) : null;
    final rawCount = json['ruleCount'];
    return RuleProviderInfo(
      name: json['name'] is String ? json['name'] as String : key,
      behavior: json['behavior'] is String ? json['behavior'] as String : '',
      type: json['type'] is String ? json['type'] as String : '',
      ruleCount: rawCount is num ? rawCount.toInt() : 0,
      updatedAt: updated != null && updated.year > 1970 ? updated : null,
    );
  }

  final String name;
  final String behavior;
  final String type;
  final int ruleCount;
  final DateTime? updatedAt;
}
