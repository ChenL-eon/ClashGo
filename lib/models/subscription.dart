class Subscription {
  Subscription({
    required this.id,
    required this.name,
    required this.url,
    required this.isLocal,
    required this.createdAt,
    this.lastUpdatedAt,
    this.autoUpdate = true,
    this.updateIntervalMinutes = 1440,
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.expire = 0,
    this.lastError,
    this.lastErrorAt,
    this.userAgent = 'clash.meta',
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      url: json['url'] as String? ?? '',
      isLocal: json['isLocal'] as bool? ?? false,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      lastUpdatedAt: DateTime.tryParse(json['lastUpdatedAt'] as String? ?? ''),
      autoUpdate: json['autoUpdate'] as bool? ?? true,
      updateIntervalMinutes: (json['updateIntervalMinutes'] as num?)?.toInt() ?? 1440,
      upload: (json['upload'] as num?)?.toInt() ?? 0,
      download: (json['download'] as num?)?.toInt() ?? 0,
      total: (json['total'] as num?)?.toInt() ?? 0,
      expire: (json['expire'] as num?)?.toInt() ?? 0,
      lastError: json['lastError'] as String?,
      lastErrorAt: DateTime.tryParse(json['lastErrorAt'] as String? ?? ''),
      userAgent: json['userAgent'] as String? ?? 'clash.meta',
    );
  }

  final String id;
  final String name;
  final String url;
  final bool isLocal;
  final DateTime createdAt;
  final DateTime? lastUpdatedAt;
  final bool autoUpdate;
  final int updateIntervalMinutes;
  final int upload;
  final int download;
  final int total;
  final int expire;
  final String? lastError;
  final DateTime? lastErrorAt;
  final String userAgent;

  int get used => upload + download;

  bool get hasQuota => total > 0;

  int get remaining => total > 0 ? (total - used).clamp(0, total) : 0;

  double get usageRatio => total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;

  bool get hasExpiry => expire > 0;

  bool get isExpired => expire > 0 && DateTime.fromMillisecondsSinceEpoch(expire * 1000).isBefore(DateTime.now());

  DateTime? get nextUpdateAt {
    if (!autoUpdate || updateIntervalMinutes <= 0) return null;
    final base = lastUpdatedAt ?? createdAt;
    return base.add(Duration(minutes: updateIntervalMinutes));
  }

  String get host {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    return uri.host;
  }

  Subscription copyWith({
    String? name,
    String? url,
    DateTime? lastUpdatedAt,
    bool? autoUpdate,
    int? updateIntervalMinutes,
    int? upload,
    int? download,
    int? total,
    int? expire,
    String? lastError,
    bool clearError = false,
    DateTime? lastErrorAt,
    String? userAgent,
  }) {
    return Subscription(
      id: id,
      name: name ?? this.name,
      url: url ?? this.url,
      isLocal: isLocal,
      createdAt: createdAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      autoUpdate: autoUpdate ?? this.autoUpdate,
      updateIntervalMinutes: updateIntervalMinutes ?? this.updateIntervalMinutes,
      upload: upload ?? this.upload,
      download: download ?? this.download,
      total: total ?? this.total,
      expire: expire ?? this.expire,
      lastError: clearError ? null : (lastError ?? this.lastError),
      lastErrorAt: clearError ? null : (lastErrorAt ?? this.lastErrorAt),
      userAgent: userAgent ?? this.userAgent,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'isLocal': isLocal,
        'createdAt': createdAt.toIso8601String(),
        'lastUpdatedAt': lastUpdatedAt?.toIso8601String(),
        'autoUpdate': autoUpdate,
        'updateIntervalMinutes': updateIntervalMinutes,
        'upload': upload,
        'download': download,
        'total': total,
        'expire': expire,
        'lastError': lastError,
        'lastErrorAt': lastErrorAt?.toIso8601String(),
        'userAgent': userAgent,
      };
}

class SubscriptionHeaders {
  const SubscriptionHeaders({
    this.upload = 0,
    this.download = 0,
    this.total = 0,
    this.expire = 0,
    this.name,
    this.updateIntervalMinutes,
  });

  final int upload;
  final int download;
  final int total;
  final int expire;
  final String? name;
  final int? updateIntervalMinutes;

  bool get hasQuota => upload > 0 || download > 0 || total > 0 || expire > 0;

  int get used => upload + download;

  double get usageRatio => total > 0 ? (used / total).clamp(0.0, 1.0) : 0.0;
}
