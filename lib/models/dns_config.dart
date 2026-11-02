/// 结构化 DNS 覆写：开启后写入生成配置的 dns 段，压过订阅自带的解析器。
/// 关闭时不动订阅的 dns，TUN 模式下仍由 ConfigGenerator 补足可用解析器。
class DnsConfig {
  const DnsConfig({
    required this.enabled,
    required this.enhancedMode,
    required this.fakeIpRange,
    required this.nameserver,
    required this.fallback,
    required this.defaultNameserver,
  });

  static const String fakeIp = 'fake-ip';
  static const String redirHost = 'redir-host';
  static const String defaultFakeIpRange = '198.18.0.1/16';
  static const List<String> defaultPrimaryNameservers = [
    'https://doh.pub/dns-query',
    'tls://223.5.5.5:853',
  ];
  static const List<String> defaultBootstrapNameservers = [
    '223.5.5.5',
    '119.29.29.29',
  ];

  static const DnsConfig defaults = DnsConfig(
    enabled: false,
    enhancedMode: fakeIp,
    fakeIpRange: defaultFakeIpRange,
    nameserver: defaultPrimaryNameservers,
    fallback: <String>[],
    defaultNameserver: defaultBootstrapNameservers,
  );

  factory DnsConfig.fromJson(Object? json) {
    if (json is! Map) return defaults;
    final map = Map<String, dynamic>.from(json);
    return DnsConfig(
      enabled: map['enabled'] as bool? ?? false,
      enhancedMode: normalizeEnhancedMode(map['enhancedMode']),
      fakeIpRange: normalizeFakeIpRange(map['fakeIpRange']),
      nameserver: normalizeServers(
        map['nameserver'],
        fallback: defaultPrimaryNameservers,
      ),
      fallback: normalizeServers(map['fallback']),
      defaultNameserver: normalizeServers(
        map['defaultNameserver'],
        fallback: defaultBootstrapNameservers,
      ),
    );
  }

  final bool enabled;
  final String enhancedMode;
  final String fakeIpRange;
  final List<String> nameserver;
  final List<String> fallback;
  final List<String> defaultNameserver;

  DnsConfig copyWith({
    bool? enabled,
    String? enhancedMode,
    String? fakeIpRange,
    List<String>? nameserver,
    List<String>? fallback,
    List<String>? defaultNameserver,
  }) {
    return DnsConfig(
      enabled: enabled ?? this.enabled,
      enhancedMode: enhancedMode ?? this.enhancedMode,
      fakeIpRange: fakeIpRange ?? this.fakeIpRange,
      nameserver: nameserver ?? this.nameserver,
      fallback: fallback ?? this.fallback,
      defaultNameserver: defaultNameserver ?? this.defaultNameserver,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'enhancedMode': enhancedMode,
    'fakeIpRange': fakeIpRange,
    'nameserver': nameserver,
    'fallback': fallback,
    'defaultNameserver': defaultNameserver,
  };

  static String normalizeEnhancedMode(Object? value) {
    final text = value is String ? value.trim() : '';
    return const [fakeIp, redirHost].contains(text) ? text : fakeIp;
  }

  static String normalizeFakeIpRange(Object? value) {
    final text = value is String ? value.trim() : '';
    final match = RegExp(
      r'^((25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}'
      r'(25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)/(3[0-2]|[12]?\d)$',
    ).hasMatch(text);
    return match ? text : defaultFakeIpRange;
  }

  /// 对话框里允许一行一条，也允许逗号分隔；空项与重复项直接丢掉。
  /// nameserver / default-nameserver 清空后回落到默认值，避免生成无解析器的配置。
  static List<String> normalizeServers(
    Object? value, {
    List<String> fallback = const [],
  }) {
    final entries = <String>[];
    final seen = <String>{};
    void add(String raw) {
      final item = raw.trim();
      if (item.isEmpty || !seen.add(item)) return;
      entries.add(item);
    }

    if (value is List) {
      for (final item in value) {
        if (item == null) continue;
        for (final part in '$item'.split(RegExp(r'[,\r\n]+'))) {
          add(part);
        }
      }
    } else if (value is String) {
      for (final part in value.split(RegExp(r'[,\r\n]+'))) {
        add(part);
      }
    }
    return entries.isEmpty ? List<String>.of(fallback) : entries;
  }

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    return other is DnsConfig &&
        other.enabled == enabled &&
        other.enhancedMode == enhancedMode &&
        other.fakeIpRange == fakeIpRange &&
        _sameList(other.nameserver, nameserver) &&
        _sameList(other.fallback, fallback) &&
        _sameList(other.defaultNameserver, defaultNameserver);
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    enhancedMode,
    fakeIpRange,
    Object.hashAll(nameserver),
    Object.hashAll(fallback),
    Object.hashAll(defaultNameserver),
  );
}
