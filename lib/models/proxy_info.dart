class ProxyInfo {
  const ProxyInfo({
    required this.name,
    required this.type,
    required this.alive,
    required this.now,
    required this.all,
    required this.delay,
    required this.udp,
    required this.xudp,
    required this.tfo,
    this.provider,
  });

  factory ProxyInfo.fromJson(String key, Map<String, dynamic> json) {
    final history = json['history'];
    int? delay;
    if (history is List && history.isNotEmpty) {
      final last = history.last;
      if (last is Map) {
        final value = (last['delay'] as num?)?.toInt();
        if (value != null) delay = value > 0 ? value : -1;
      }
    }
    return ProxyInfo(
      name: json['name'] as String? ?? key,
      type: json['type'] as String? ?? '',
      alive: json['alive'] as bool? ?? true,
      now: json['now'] as String? ?? '',
      all: (json['all'] as List?)?.whereType<String>().toList(growable: false) ?? const [],
      delay: delay,
      udp: json['udp'] as bool? ?? false,
      xudp: json['xudp'] as bool? ?? false,
      tfo: json['tfo'] as bool? ?? false,
      provider: json['provider'] as String?,
    );
  }

  final String name;
  final String type;
  final bool alive;
  final String now;
  final List<String> all;
  final int? delay;
  final bool udp;
  final bool xudp;
  final bool tfo;
  final String? provider;

  bool get isGroup => all.isNotEmpty;

  bool get isSelector {
    final value = type.toLowerCase();
    return value == 'selector' || value == 'select';
  }

  String get groupTypeKey {
    switch (type.toLowerCase()) {
      case 'selector':
      case 'select':
        return 'proxy.groupType.selector';
      case 'urltest':
      case 'url-test':
        return 'proxy.groupType.urltest';
      case 'fallback':
        return 'proxy.groupType.fallback';
      case 'loadbalance':
      case 'load-balance':
        return 'proxy.groupType.loadbalance';
      case 'relay':
        return 'proxy.groupType.relay';
      default:
        return 'proxy.groupType.selector';
    }
  }

  static const specialNames = {'GLOBAL', 'DIRECT', 'REJECT', 'REJECT-DROP', 'PASS', 'COMPATIBLE'};
}

class ProxiesSnapshot {
  const ProxiesSnapshot({required this.proxies, required this.groups});

  factory ProxiesSnapshot.fromJson(Map<String, dynamic> json) {
    final raw = json['proxies'];
    final proxies = <String, ProxyInfo>{};
    if (raw is Map) {
      raw.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          proxies[key.toString()] = ProxyInfo.fromJson(key.toString(), value);
        } else if (value is Map) {
          proxies[key.toString()] = ProxyInfo.fromJson(key.toString(), Map<String, dynamic>.from(value));
        }
      });
    }
    final groups = proxies.values
        .where((proxy) => proxy.isGroup && proxy.name != 'GLOBAL')
        .toList(growable: false);
    return ProxiesSnapshot(proxies: proxies, groups: groups);
  }

  final Map<String, ProxyInfo> proxies;
  final List<ProxyInfo> groups;

  /// 内核 /proxies 的 JSON 来自 Go map，键顺序是字典序而不是订阅里的顺序；
  /// 按 profile 解析出的分组顺序稳定重排，未知分组保持原有先后排在末尾。
  ProxiesSnapshot orderedBy(List<String> order) {
    if (order.isEmpty || groups.isEmpty) return this;
    final rank = <String, int>{};
    for (var i = 0; i < order.length; i++) {
      rank.putIfAbsent(order[i], () => i);
    }
    final indexed = [
      for (var i = 0; i < groups.length; i++)
        (rank[groups[i].name] ?? order.length, i, groups[i]),
    ]..sort((a, b) {
        final byRank = a.$1.compareTo(b.$1);
        return byRank != 0 ? byRank : a.$2.compareTo(b.$2);
      });
    return ProxiesSnapshot(
      proxies: proxies,
      groups: [for (final entry in indexed) entry.$3],
    );
  }

  ProxyInfo? primaryGroup() {
    if (groups.isEmpty) return null;
    for (final group in groups) {
      if (group.isSelector && group.now.isNotEmpty) return group;
    }
    return groups.first;
  }

  String? activeNodeName() {
    final group = primaryGroup();
    if (group == null) return null;
    return group.now.isNotEmpty ? group.now : null;
  }

  int? delayOf(String name) => proxies[name]?.delay;
}
