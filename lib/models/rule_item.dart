class RuleItem {
  const RuleItem({required this.type, required this.payload, required this.proxy});

  factory RuleItem.fromJson(Map<String, dynamic> json) {
    return RuleItem(
      type: json['type'] as String? ?? '',
      payload: json['payload'] as String? ?? '',
      proxy: json['proxy'] as String? ?? '',
    );
  }

  static const _typeLabels = {
    'IPCIDR': 'IP-CIDR',
    'SrcIPCIDR': 'SRC-IP-CIDR',
    'SrcPort': 'SRC-PORT',
    'DstPort': 'DST-PORT',
    'RuleSet': 'RULE-SET',
    'DomainSuffix': 'DOMAIN-SUFFIX',
    'DomainKeyword': 'DOMAIN-KEYWORD',
    'DomainRegex': 'DOMAIN-REGEX',
    'ProcessPath': 'PROCESS-PATH',
    'ProcessName': 'PROCESS-NAME',
  };

  final String type;
  final String payload;
  final String proxy;

  String get displayType => _typeLabels[type] ?? type.toUpperCase();

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return type.toLowerCase().contains(q) ||
        displayType.toLowerCase().contains(q) ||
        payload.toLowerCase().contains(q) ||
        proxy.toLowerCase().contains(q);
  }
}
