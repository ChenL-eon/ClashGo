import 'dart:convert';

import 'package:yaml/yaml.dart';

import '../core/app_info.dart';
import '../core/errors.dart';
import '../models/app_settings.dart';
import '../models/dns_config.dart';

class ConfigGenerator {
  const ConfigGenerator();

  static const _removedKeys = [
    'port',
    'socks-port',
    'redir-port',
    'tproxy-port',
    'mixed-port',
    'external-controller',
    'external-controller-tls',
    'external-controller-unix',
    'external-controller-pipe',
    'external-ui',
    'external-ui-name',
    'external-ui-url',
    'secret',
    'authentication',
    'listeners',
    'tun',
  ];

  static const String _systemDnsServer = 'system://';

  /// 这些键由 ClashGo 自己接管：端口、控制接口、隧道形态和页面上的开关
  /// 都是生成配置时写死的。允许覆写只会让界面和实际运行状态对不上。
  static const protectedOverrideKeys = <String>{
    'port',
    'socks-port',
    'redir-port',
    'tproxy-port',
    'mixed-port',
    'external-controller',
    'external-controller-tls',
    'external-controller-unix',
    'external-controller-pipe',
    'external-ui',
    'external-ui-name',
    'external-ui-url',
    'secret',
    'authentication',
    'listeners',
    'tun',
    'mode',
    'log-level',
    'ipv6',
    'allow-lan',
    'bind-address',
    'profile',
    'unified-delay',
    'tcp-concurrent',
  };

  String generate({
    required String profile,
    required AppSettings settings,
    required String mode,
    bool androidTun = false,
    bool windowsTun = false,
  }) {
    dynamic document;
    try {
      document = loadYaml(profile);
    } catch (error) {
      throw AppError('profileInvalid', detail: _shorten(error.toString()));
    }
    if (document is! Map) throw const AppError('profileInvalid', detail: 'Top level must be a mapping');

    final map = _convertMap(document);
    final proxies = map['proxies'];
    final providers = map['proxy-providers'];
    final hasProxies = proxies is List && proxies.whereType<Map>().isNotEmpty;
    final hasProviders = providers is Map && providers.isNotEmpty;
    if (!hasProxies && !hasProviders) throw const AppError('noNodes');

    for (final key in _removedKeys) {
      map.remove(key);
    }

    final override = _parseOverride(settings.overrideYaml);
    if (override != null) _mergeInto(map, override);

    map['mixed-port'] = settings.mixedPort;
    map['allow-lan'] = settings.allowLan;
    map['bind-address'] = settings.allowLan ? '*' : '127.0.0.1';
    map['mode'] = mode;
    map['log-level'] = AppInfo.coreLogLevel;
    map['ipv6'] = settings.ipv6;
    map['external-controller'] = '127.0.0.1:${settings.apiPort}';
    map['secret'] = settings.secret;
    map['unified-delay'] = settings.unifiedDelay;
    map['tcp-concurrent'] = settings.tcpConcurrent;
    map['geodata-loader'] = settings.geoLowMemory
        ? 'memconservative'
        : 'standard';

    // 订阅和 YAML 覆写里的 hosts 先保留，界面上的条目同名覆盖、其余不动：
    // 这样用户只改自己关心的域名，不会把订阅自带的映射整段抹掉。
    if (settings.hosts.isNotEmpty) {
      final hosts = map['hosts'] is Map
          ? _convertMap(map['hosts'] as Map)
          : <String, dynamic>{};
      hosts.addAll(settings.hosts);
      map['hosts'] = hosts;
    }

    final profileSection = map['profile'] is Map ? _convertMap(map['profile'] as Map) : <String, dynamic>{};
    profileSection['store-selected'] = true;
    profileSection['store-fake-ip'] = true;
    map['profile'] = profileSection;

    if (settings.dns.enabled) _applyDnsConfig(map, settings.dns);

    if (androidTun || windowsTun) {
      map['tun'] = <String, dynamic>{
        'enable': true,
        'stack': settings.tunStack,
        if (androidTun)
          // Replaced with the real descriptor by CoreVpnService right before exec.
          // Windows 没有 fd 可传：它自己建 ztun 适配器。
          'file-descriptor': '__TUN_FD__',
        // 网卡名钉成常量：就绪探测要能在系统网卡列表里稳定认出刚起的这张卡，
        // 而内核不写 device 时用的是自己的默认名（这台机器实测 Meta）。
        // FlClash 走的也是这条路（device: "FlClash"）。
        if (windowsTun) 'device': AppInfo.tunDeviceName,
        // 同一个设置值也会作为 startVpn 的 mtu 参数交给 VpnService.setMtu，
        // 内核设备 MTU 与用户态协议栈切片 MTU 必须一致。
        'mtu': settings.tunMtu,
        // 安卓由 VpnService 负责寻址和路由，内核自己再动一次路由表就是叠加；
        // Windows 则是反过来——没有 auto-route 就没有任何流量会进隧道。
        'auto-route': windowsTun,
        'auto-detect-interface': windowsTun,
        // strict-route 会把局域网流量也吞进来，Windows 上等于把同机打印、
        // 局域网发现和 allow-lan 反向访问一起打断，所以两端都关。
        'strict-route': false,
        // any:53 同时覆盖 v4/v6 的 53 端口劫持；安卓那侧只有 fd 上来的 v4 查询。
        'dns-hijack': [windowsTun ? 'any:53' : '0.0.0.0:53'],
        // 不写 inet4-address：这个内核（v1.19.33）压根不解析它（config.go:285 的
        // yaml tag 是注释掉的），网卡地址一律由 dns.fake-ip-range 的首地址加 /30
        // 推出来（config.go:1688-1706），真机实测网卡拿到 198.18.0.1/30。写了只会
        // 让人以为地址是我们定的。inet6-address 相反，它是照单全收的（:1707）。
        // 就绪判据因此不看地址（见 TunReadiness）。
        if (settings.ipv6) 'inet6-address': ['fdfe:dcba:9876::1/126'],
      };
      _applyTunDns(map);
    }

    if (settings.appendSystemDns) _appendSystemDns(map);

    final rules = map['rules'];
    if (rules is! List || rules.isEmpty) {
      final groups = map['proxy-groups'];
      String? firstGroup;
      if (groups is List) {
        for (final group in groups) {
          if (group is Map && group['name'] is String && (group['name'] as String).isNotEmpty) {
            firstGroup = group['name'] as String;
            break;
          }
        }
      }
      map['rules'] = [firstGroup == null ? 'MATCH,DIRECT' : 'MATCH,$firstGroup'];
    }

    return _YamlWriter.write(map);
  }

  /// 内核 /proxies 返回的分组顺序是 JSON map 的字典序，和订阅里 proxy-groups
  /// 的书写顺序无关；这里按生成配置时的同一套解析（profile + YAML 覆写）取出
  /// 分组名顺序，供控制器重排 /proxies 结果。解析失败返回空列表，退回原顺序。
  List<String> groupOrder({required String profile, String? overrideYaml}) {
    try {
      final document = loadYaml(profile);
      if (document is! Map) return const [];
      final map = _convertMap(document);
      final override = _parseOverride(overrideYaml ?? '');
      if (override != null) _mergeInto(map, override);
      final groups = map['proxy-groups'];
      if (groups is! List) return const [];
      final order = <String>[];
      for (final group in groups) {
        if (group is! Map) continue;
        final name = group['name'];
        if (name is String && name.isNotEmpty && !order.contains(name)) {
          order.add(name);
        }
      }
      return List.unmodifiable(order);
    } catch (_) {
      return const [];
    }
  }

  /// 覆写文本在保存时和生成时都会校验：保存时给用户明确报错，生成时兜住
  /// 手改 settings.json 的情况。空文本表示不启用覆写。
  static void validateOverride(String text) {
    _parseOverride(text);
  }

  static Map<String, dynamic>? _parseOverride(String text) {
    if (text.trim().isEmpty) return null;
    dynamic document;
    try {
      document = loadYaml(text);
    } catch (error) {
      throw AppError('overrideInvalid', detail: _shorten(error.toString()));
    }
    if (document is! Map) {
      throw const AppError('overrideInvalid', detail: 'Top level must be a mapping');
    }
    final map = _convertMap(document);
    for (final key in map.keys) {
      if (protectedOverrideKeys.contains(key)) {
        throw AppError(
          'overrideInvalid',
          detail: 'Key "$key" is managed by ClashGo',
        );
      }
    }
    return map;
  }

  /// 映射逐层合并，列表与标量整体替换——和常见 Merge 配置的直觉一致。
  static void _mergeInto(Map<String, dynamic> target, Map<String, dynamic> patch) {
    patch.forEach((key, value) {
      final existing = target[key];
      if (existing is Map && value is Map) {
        final nested = _convertMap(existing);
        _mergeInto(nested, _convertMap(value));
        target[key] = nested;
      } else {
        target[key] = value;
      }
    });
  }

  static void _applyDnsConfig(Map<String, dynamic> map, DnsConfig config) {
    final dns = map['dns'] is Map ? _convertMap(map['dns'] as Map) : <String, dynamic>{};
    dns['enable'] = true;
    dns['enhanced-mode'] = config.enhancedMode;
    if (config.enhancedMode == DnsConfig.fakeIp) {
      dns['fake-ip-range'] = config.fakeIpRange;
    } else {
      dns.remove('fake-ip-range');
    }
    dns['nameserver'] = List<String>.of(config.nameserver);
    dns['default-nameserver'] = List<String>.of(config.defaultNameserver);
    if (config.fallback.isEmpty) {
      dns.remove('fallback');
    } else {
      dns['fallback'] = List<String>.of(config.fallback);
    }
    map['dns'] = dns;
  }

  /// 隧道模式下 DNS 只能由内核回答：查询是从 tun 设备/ fd 进来的，
  /// 再让 dns 段自己 listen 53 端口既没必要，还会撞上已经被占用的 53。
  /// profile 里没写解析器时补一组国内可用的，避免"连上隧道却解析不动"。
  void _applyTunDns(Map<String, dynamic> map) {
    final dns = map['dns'] is Map ? _convertMap(map['dns'] as Map) : <String, dynamic>{};
    dns['enable'] = true;
    dns.remove('listen');
    final nameServer = dns['nameserver'];
    if (nameServer is! List || nameServer.isEmpty) {
      dns['nameserver'] = ['https://doh.pub/dns-query', 'tls://223.5.5.5:853'];
    }
    final defaultNameServer = dns['default-nameserver'];
    if (defaultNameServer is! List || defaultNameServer.isEmpty) {
      dns['default-nameserver'] = ['223.5.5.5', '119.29.29.29'];
    }
    map['dns'] = dns;
  }

  /// 追加系统 DNS 改的是最终生效的 dns 段：订阅、YAML 覆写与 TUN 补全都先落完，
  /// 再把 system:// 接到 nameserver 末尾，所以界面开关不会被覆写内容盖掉。
  /// DNS 未启用时追加不会生效，直接跳过，避免在禁用配置里留下误导项。
  static void _appendSystemDns(Map<String, dynamic> map) {
    final dns = map['dns'];
    if (dns is! Map || dns['enable'] != true) return;
    final nameserver = dns['nameserver'];
    final servers = nameserver is List
        ? List<Object?>.of(nameserver)
        : <Object?>[];
    final hasSystem = servers.any((server) {
      final text = server?.toString().trim().toLowerCase();
      return text == 'system' || text == _systemDnsServer;
    });
    if (hasSystem) return;
    servers.add(_systemDnsServer);
    dns['nameserver'] = servers;
  }

  static Map<String, dynamic> _convertMap(Map source) {
    final result = <String, dynamic>{};
    source.forEach((key, value) {
      result[key.toString()] = _convert(value);
    });
    return result;
  }

  static Object? _convert(Object? value) {
    if (value is Map) return _convertMap(value);
    if (value is List) return value.map(_convert).toList();
    if (value is YamlScalar) return value.value;
    return value;
  }

  static String _shorten(String text) {
    final singleLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return singleLine.length > 220 ? '${singleLine.substring(0, 220)}…' : singleLine;
  }
}

class _YamlWriter {
  static String write(Object? value) {
    final buffer = StringBuffer();
    if (value is Map) {
      _writeMap(buffer, value, 0);
    } else if (value is List) {
      _writeList(buffer, value, 0);
    } else {
      buffer.writeln(_scalar(value));
    }
    return buffer.toString();
  }

  static void _writeMap(StringBuffer buffer, Map map, int indent) {
    map.forEach((key, value) {
      buffer.write(' ' * indent);
      buffer.write(_scalarKey(key.toString()));
      buffer.write(':');
      _writeValueAfterKey(buffer, value, indent);
    });
  }

  static void _writeValueAfterKey(StringBuffer buffer, Object? value, int keyIndent) {
    if (value is Map) {
      if (value.isEmpty) {
        buffer.writeln(' {}');
        return;
      }
      buffer.writeln();
      _writeMap(buffer, value, keyIndent + 2);
    } else if (value is List) {
      if (value.isEmpty) {
        buffer.writeln(' []');
        return;
      }
      buffer.writeln();
      _writeList(buffer, value, keyIndent + 2);
    } else {
      buffer.writeln(' ${_scalar(value)}');
    }
  }

  static void _writeList(StringBuffer buffer, List list, int indent) {
    for (final item in list) {
      if (item is Map) {
        if (item.isEmpty) {
          buffer.writeln('${' ' * indent}- {}');
          continue;
        }
        var first = true;
        item.forEach((key, value) {
          buffer.write(first ? '${' ' * indent}- ' : ' ' * (indent + 2));
          buffer.write(_scalarKey(key.toString()));
          buffer.write(':');
          if (value is Map || value is List) {
            if ((value is Map && value.isEmpty) || (value is List && value.isEmpty)) {
              buffer.writeln(value is Map ? ' {}' : ' []');
            } else {
              buffer.writeln();
              if (value is Map) {
                _writeMap(buffer, value, indent + 4);
              } else {
                _writeList(buffer, value as List, indent + 4);
              }
            }
          } else {
            buffer.writeln(' ${_scalar(value)}');
          }
          first = false;
        });
      } else if (item is List) {
        buffer.writeln('${' ' * indent}-');
        _writeList(buffer, item, indent + 2);
      } else {
        buffer.writeln('${' ' * indent}- ${_scalar(item)}');
      }
    }
  }

  static String _scalar(Object? value) {
    if (value == null) return 'null';
    if (value is bool || value is num) return value.toString();
    final text = value.toString();
    if (_plainSafe(text)) return text;
    return jsonEncode(text);
  }

  static String _scalarKey(String key) {
    if (_plainSafe(key) && !key.contains(':')) return key;
    return jsonEncode(key);
  }

  static bool _plainSafe(String text) {
    if (text.isEmpty) return false;
    if (text == '~' || text == 'null' || text == 'true' || text == 'false') return false;
    if (num.tryParse(text) != null) return false;
    if (!RegExp(r'^[A-Za-z0-9_./:=?&%@+~-]+$').hasMatch(text)) return false;
    if (text.startsWith('-') || text.startsWith('?') || text.startsWith(':') || text.endsWith(':')) return false;
    return true;
  }
}
