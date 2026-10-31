class ProviderInfo {
  const ProviderInfo({
    required this.name,
    required this.type,
    required this.vehicleType,
    required this.updatedAt,
    required this.proxyCount,
    required this.upload,
    required this.download,
    required this.total,
    required this.expire,
  });

  factory ProviderInfo.fromJson(String key, Map<String, dynamic> json) {
    final proxies = json['proxies'];
    final subscriptionInfo = json['subscriptionInfo'] is Map
        ? Map<String, dynamic>.from(json['subscriptionInfo'] as Map)
        : const <String, dynamic>{};
    final updated = DateTime.tryParse(json['updatedAt'] as String? ?? '');
    return ProviderInfo(
      name: json['name'] as String? ?? key,
      type: json['type'] as String? ?? '',
      vehicleType: json['vehicleType'] as String? ?? '',
      updatedAt: updated != null && updated.year > 1970 ? updated : null,
      proxyCount: proxies is List ? proxies.length : 0,
      upload: (subscriptionInfo['Upload'] as num?)?.toInt() ?? (subscriptionInfo['upload'] as num?)?.toInt() ?? 0,
      download: (subscriptionInfo['Download'] as num?)?.toInt() ?? (subscriptionInfo['download'] as num?)?.toInt() ?? 0,
      total: (subscriptionInfo['Total'] as num?)?.toInt() ?? (subscriptionInfo['total'] as num?)?.toInt() ?? 0,
      expire: (subscriptionInfo['Expire'] as num?)?.toInt() ?? (subscriptionInfo['expire'] as num?)?.toInt() ?? 0,
    );
  }

  final String name;
  final String type;
  final String vehicleType;
  final DateTime? updatedAt;
  final int proxyCount;
  final int upload;
  final int download;
  final int total;
  final int expire;

  int get used => upload + download;

  bool get hasQuota => total > 0;

  double get usageRatio => total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
}
