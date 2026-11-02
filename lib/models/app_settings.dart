import 'dart:math';

import '../core/app_info.dart';
import 'dns_config.dart';

class AppSettings {
  AppSettings({
    required this.language,
    required this.themeMode,
    required this.accentIndex,
    required this.pureBlack,
    required this.mixedPort,
    required this.apiPort,
    required this.secret,
    required this.allowLan,
    required this.ipv6,
    required this.systemProxy,
    required this.tun,
    required this.autoStartCore,
    required this.autoUpdateSubscriptions,
    required this.mode,
    this.proxyStyle,
    this.proxySort,
    this.proxyLayout,
    this.proxyNodeSize,
    this.hideTimeoutProxies = false,
    this.updateChannel = channelStable,
    this.checkUpdatesOnStartup = false,
    this.launchAtStartup = false,
    this.closeToTray = true,
    this.proxyBypass = defaultProxyBypass,
    this.splitTunnelMode = splitTunnelAll,
    this.splitTunnelPackages = const [],
    this.testUrl = AppInfo.defaultTestUrl,
    this.tunMtu = AppInfo.tunMtu,
    this.tunStack = tunStackGvisor,
    this.dns = DnsConfig.defaults,
    this.appendSystemDns = false,
    this.overrideYaml = '',
    this.unifiedDelay = true,
    this.tcpConcurrent = true,
    this.geoLowMemory = true,
    this.hosts = const <String, String>{},
  });

  factory AppSettings.defaults({bool zh = true, bool systemProxy = true}) {
    return AppSettings(
      language: zh ? 'zh' : 'en',
      themeMode: 'system',
      accentIndex: 0,
      pureBlack: false,
      mixedPort: 17890,
      apiPort: 19090,
      secret: generateSecret(),
      allowLan: false,
      ipv6: false,
      systemProxy: systemProxy,
      tun: false,
      autoStartCore: false,
      autoUpdateSubscriptions: true,
      mode: 'rule',
      updateChannel: channelStable,
      checkUpdatesOnStartup: false,
    );
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final defaults = AppSettings.defaults();
    return AppSettings(
      language: json['language'] as String? ?? defaults.language,
      themeMode: json['themeMode'] as String? ?? defaults.themeMode,
      accentIndex: (json['accentIndex'] as num?)?.toInt() ?? 0,
      pureBlack: json['pureBlack'] as bool? ?? false,
      mixedPort: (json['mixedPort'] as num?)?.toInt() ?? defaults.mixedPort,
      apiPort: (json['apiPort'] as num?)?.toInt() ?? defaults.apiPort,
      secret: (json['secret'] as String?)?.isNotEmpty == true
          ? json['secret'] as String
          : defaults.secret,
      allowLan: json['allowLan'] as bool? ?? false,
      ipv6: json['ipv6'] as bool? ?? false,
      unifiedDelay: json['unifiedDelay'] as bool? ?? true,
      tcpConcurrent: json['tcpConcurrent'] as bool? ?? true,
      geoLowMemory: json['geoLowMemory'] as bool? ?? true,
      systemProxy: json['systemProxy'] as bool? ?? false,
      tun: json['tun'] as bool? ?? false,
      autoStartCore: json['autoStartCore'] as bool? ?? false,
      autoUpdateSubscriptions: json['autoUpdateSubscriptions'] as bool? ?? true,
      mode: json['mode'] as String? ?? 'rule',
      proxyStyle: json['proxyStyle'] as String?,
      proxySort: json['proxySort'] as String?,
      proxyLayout: json['proxyLayout'] as String?,
      proxyNodeSize: json['proxyNodeSize'] as String?,
      hideTimeoutProxies: json['hideTimeoutProxies'] as bool? ?? false,
      updateChannel: json['updateChannel'] as String? ?? channelStable,
      checkUpdatesOnStartup: json['checkUpdatesOnStartup'] as bool? ?? false,
      launchAtStartup: json['launchAtStartup'] as bool? ?? false,
      closeToTray: json['closeToTray'] as bool? ?? true,
      proxyBypass: json['proxyBypass'] as String? ?? defaultProxyBypass,
      splitTunnelMode: normalizeSplitTunnelMode(
        json['splitTunnelMode'] as String?,
      ),
      splitTunnelPackages: normalizeSplitTunnelPackages(
        json['splitTunnelPackages'],
      ),
      testUrl: normalizeTestUrl(json['testUrl']),
      tunMtu: normalizeTunMtu(json['tunMtu']),
      tunStack: normalizeTunStack(json['tunStack']),
      dns: DnsConfig.fromJson(json['dns']),
      appendSystemDns: json['appendSystemDns'] as bool? ?? false,
      overrideYaml: json['overrideYaml'] is String
          ? json['overrideYaml'] as String
          : '',
      hosts: normalizeHosts(json['hosts']),
    );
  }

  String language;
  String themeMode;
  int accentIndex;
  bool pureBlack;
  int mixedPort;
  int apiPort;
  String secret;
  bool allowLan;
  bool ipv6;
  bool unifiedDelay;
  bool tcpConcurrent;
  bool geoLowMemory;
  bool systemProxy;

  /// Windows 专用：true 时内核以提权方式跑 TUN 接管（建网卡 + 改路由 + 劫持 53）。
  /// 安卓不看这个字段——那边隧道就是 VpnService 本身，没有第二种形态。
  bool tun;
  bool autoStartCore;
  bool autoUpdateSubscriptions;
  String mode;

  // 代理页显示偏好。null 表示用户未显式选择，按平台默认渲染。
  String? proxyStyle;
  String? proxySort;
  String? proxyLayout;
  String? proxyNodeSize;
  bool hideTimeoutProxies;

  // 更新渠道只影响"检查更新"看哪条 release：稳定版走 GitHub 的 latest
  // 重定向（GitHub 自己排除 draft/prerelease），预览版取 releases.atom 的第一条。
  String updateChannel;
  bool checkUpdatesOnStartup;

  /// Windows 专用：登录系统后由注册表 Run 项自动启动，并且启动参数让它直接收进托盘。
  bool launchAtStartup;

  /// Windows 专用：点窗口关闭按钮时隐藏到托盘，而不是退出并停内核。
  bool closeToTray;

  /// Windows 系统代理的 ProxyOverride，分号分隔，支持 `*` 与 `<local>`。
  String proxyBypass;

  /// 安卓分应用代理：all 全部应用、allow 仅所选应用、disallow 排除所选应用。
  String splitTunnelMode;
  List<String> splitTunnelPackages;

  /// 节点/分组测速的目标地址。内核的 /proxies/{name}/delay 会经代理访问它，
  /// 所以留空或写坏都会让整页延迟停在超时；写入前统一校验。
  String testUrl;

  /// 隧道参数：VpnService.setMtu 与 tun.mtu 必须同值，见 config_generator。
  int tunMtu;
  String tunStack;

  /// 开启后覆盖订阅里的 dns 段；关闭则保持订阅原样（TUN 仍会自动补缺）。
  DnsConfig dns;

  /// 只要最终生效的 dns 段是启用的，就把系统解析器 system:// 追加到主列表末尾。
  /// 独立于自定义 DNS 开关：订阅自带 DNS 或 TUN 补全的解析器也会被追加。
  bool appendSystemDns;

  /// 全局 YAML 覆写：深度合并进生成配置，受保护的控制项不允许改。
  String overrideYaml;

  /// 顶层 hosts：域名到 IP/目标域名的本地映射，生成配置时覆盖同名订阅条目。
  Map<String, String> hosts;

  bool get isZh => language == 'zh';

  static const String channelStable = 'stable';
  static const String channelPreview = 'preview';

  static const String tunStackGvisor = 'gvisor';
  static const String tunStackSystem = 'system';
  static const String tunStackMixed = 'mixed';
  static const int minTunMtu = 1280;
  static const int maxTunMtu = 9000;

  static const String splitTunnelAll = 'all';
  static const String splitTunnelAllow = 'allow';
  static const String splitTunnelDisallow = 'disallow';

  /// 供内核重启判断用：成员的顺序不影响分流结果，签名里排序后再拼。
  String get splitTunnelSignature {
    final packages = [...splitTunnelPackages]..sort();
    return '$splitTunnelMode:${packages.join(',')}';
  }

  static const String defaultProxyBypass =
      'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;<local>';

  /// 用户在对话框里可以用换行代替分号；空项与重复项直接丢掉。
  static String normalizeProxyBypass(String value) {
    final seen = <String>{};
    final entries = <String>[];
    for (final part in value.split(RegExp(r'[;\r\n]+'))) {
      final item = part.trim();
      if (item.isEmpty || !seen.add(item)) continue;
      entries.add(item);
    }
    return entries.join(';');
  }

  static String normalizeSplitTunnelMode(String? value) {
    return const [
          splitTunnelAll,
          splitTunnelAllow,
          splitTunnelDisallow,
        ].contains(value)
        ? value!
        : splitTunnelAll;
  }

  /// 手改过的 settings.json 可能混进空串、重复包名或非字符串；启动前统一清掉，
  /// 免得把无效包名递到 VpnService.Builder 里，一次启动失败还找不到原因。
  static List<String> normalizeSplitTunnelPackages(Object? value) {
    if (value is! List) return <String>[];
    final seen = <String>{};
    final entries = <String>[];
    for (final item in value) {
      if (item is! String) continue;
      final packageName = item.trim();
      if (packageName.isEmpty || !seen.add(packageName)) continue;
      entries.add(packageName);
    }
    return entries;
  }

  static String normalizeTestUrl(Object? value) {
    if (value is! String) return AppInfo.defaultTestUrl;
    final text = value.trim();
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return AppInfo.defaultTestUrl;
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return AppInfo.defaultTestUrl;
    }
    return text;
  }

  static int normalizeTunMtu(Object? value) {
    final mtu = value is num ? value.toInt() : int.tryParse('${value ?? ''}');
    if (mtu == null || mtu < minTunMtu || mtu > maxTunMtu) return AppInfo.tunMtu;
    return mtu;
  }

  static String normalizeTunStack(Object? value) {
    final text = value is String ? value : '';
    return const [
          tunStackGvisor,
          tunStackSystem,
          tunStackMixed,
        ].contains(text)
        ? text
        : tunStackGvisor;
  }

  static final RegExp _hostDomainPattern = RegExp(r'^[A-Za-z0-9_*+.-]+$');
  static final RegExp _hostTargetPattern = RegExp(r'^[A-Za-z0-9_.-]+$');
  static final RegExp _hostIpv6Pattern = RegExp(r'^[0-9A-Fa-f:.]+$');

  static bool isValidHostDomain(Object? value) {
    final text = value is String ? value.trim() : '';
    if (text.isEmpty || text.length > 253) return false;
    if (!_hostDomainPattern.hasMatch(text)) return false;
    return !text.contains('..');
  }

  static bool isValidHostTarget(Object? value) {
    final text = value is String ? value.trim() : '';
    if (text.isEmpty || text.length > 253) return false;
    if (text.contains(':')) return _hostIpv6Pattern.hasMatch(text);
    if (!_hostTargetPattern.hasMatch(text)) return false;
    return !text.contains('..');
  }

  /// 手改 settings.json、旧备份或对话框输入统一走这里：丢掉无效项，
  /// 域名与目标都小写化，同名键以后出现的为准。
  static Map<String, String> normalizeHosts(Object? value) {
    if (value is! Map) return <String, String>{};
    final hosts = <String, String>{};
    value.forEach((key, item) {
      if (key is! String || item is! String) return;
      final domain = key.trim().toLowerCase();
      final target = item.trim().toLowerCase();
      if (!isValidHostDomain(domain) || !isValidHostTarget(target)) return;
      hosts[domain] = target;
    });
    return hosts;
  }

  static const String styleTabs = 'tabs';
  static const String styleList = 'list';
  static const String sizeLoose = 'loose';
  static const String sizeStandard = 'standard';
  static const String sizeCompact = 'compact';

  String resolvedProxyStyle({required bool desktop}) =>
      proxyStyle ?? (desktop ? styleList : styleTabs);

  String resolvedProxyLayout({required bool desktop}) =>
      proxyLayout ?? (desktop ? sizeLoose : sizeStandard);

  String resolvedProxyNodeSize() => proxyNodeSize ?? sizeStandard;

  AppSettings copyWith({
    String? language,
    String? themeMode,
    int? accentIndex,
    bool? pureBlack,
    int? mixedPort,
    int? apiPort,
    String? secret,
    bool? allowLan,
    bool? ipv6,
    bool? unifiedDelay,
    bool? tcpConcurrent,
    bool? geoLowMemory,
    bool? systemProxy,
    bool? tun,
    bool? autoStartCore,
    bool? autoUpdateSubscriptions,
    String? mode,
    String? proxyStyle,
    String? proxySort,
    String? proxyLayout,
    String? proxyNodeSize,
    bool? hideTimeoutProxies,
    String? updateChannel,
    bool? checkUpdatesOnStartup,
    bool? launchAtStartup,
    bool? closeToTray,
    String? proxyBypass,
    String? splitTunnelMode,
    List<String>? splitTunnelPackages,
    String? testUrl,
    int? tunMtu,
    String? tunStack,
    DnsConfig? dns,
    bool? appendSystemDns,
    String? overrideYaml,
    Map<String, String>? hosts,
  }) {
    return AppSettings(
      language: language ?? this.language,
      themeMode: themeMode ?? this.themeMode,
      accentIndex: accentIndex ?? this.accentIndex,
      pureBlack: pureBlack ?? this.pureBlack,
      mixedPort: mixedPort ?? this.mixedPort,
      apiPort: apiPort ?? this.apiPort,
      secret: secret ?? this.secret,
      allowLan: allowLan ?? this.allowLan,
      ipv6: ipv6 ?? this.ipv6,
      unifiedDelay: unifiedDelay ?? this.unifiedDelay,
      tcpConcurrent: tcpConcurrent ?? this.tcpConcurrent,
      geoLowMemory: geoLowMemory ?? this.geoLowMemory,
      systemProxy: systemProxy ?? this.systemProxy,
      tun: tun ?? this.tun,
      autoStartCore: autoStartCore ?? this.autoStartCore,
      autoUpdateSubscriptions:
          autoUpdateSubscriptions ?? this.autoUpdateSubscriptions,
      mode: mode ?? this.mode,
      proxyStyle: proxyStyle ?? this.proxyStyle,
      proxySort: proxySort ?? this.proxySort,
      proxyLayout: proxyLayout ?? this.proxyLayout,
      proxyNodeSize: proxyNodeSize ?? this.proxyNodeSize,
      hideTimeoutProxies: hideTimeoutProxies ?? this.hideTimeoutProxies,
      updateChannel: updateChannel ?? this.updateChannel,
      checkUpdatesOnStartup:
          checkUpdatesOnStartup ?? this.checkUpdatesOnStartup,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      closeToTray: closeToTray ?? this.closeToTray,
      proxyBypass: proxyBypass ?? this.proxyBypass,
      splitTunnelMode: splitTunnelMode ?? this.splitTunnelMode,
      splitTunnelPackages: splitTunnelPackages ?? this.splitTunnelPackages,
      testUrl: testUrl ?? this.testUrl,
      tunMtu: tunMtu ?? this.tunMtu,
      tunStack: tunStack ?? this.tunStack,
      dns: dns ?? this.dns,
      appendSystemDns: appendSystemDns ?? this.appendSystemDns,
      overrideYaml: overrideYaml ?? this.overrideYaml,
      hosts: hosts ?? this.hosts,
    );
  }

  Map<String, dynamic> toJson() => {
    'language': language,
    'themeMode': themeMode,
    'accentIndex': accentIndex,
    'pureBlack': pureBlack,
    'mixedPort': mixedPort,
    'apiPort': apiPort,
    'secret': secret,
    'allowLan': allowLan,
    'ipv6': ipv6,
    'unifiedDelay': unifiedDelay,
    'tcpConcurrent': tcpConcurrent,
    'geoLowMemory': geoLowMemory,
    'systemProxy': systemProxy,
    'tun': tun,
    'autoStartCore': autoStartCore,
    'autoUpdateSubscriptions': autoUpdateSubscriptions,
    'mode': mode,
    if (proxyStyle != null) 'proxyStyle': proxyStyle,
    if (proxySort != null) 'proxySort': proxySort,
    if (proxyLayout != null) 'proxyLayout': proxyLayout,
    if (proxyNodeSize != null) 'proxyNodeSize': proxyNodeSize,
    'hideTimeoutProxies': hideTimeoutProxies,
    'updateChannel': updateChannel,
    'checkUpdatesOnStartup': checkUpdatesOnStartup,
    'launchAtStartup': launchAtStartup,
    'closeToTray': closeToTray,
    'proxyBypass': proxyBypass,
    'splitTunnelMode': splitTunnelMode,
    'splitTunnelPackages': splitTunnelPackages,
    'testUrl': testUrl,
    'tunMtu': tunMtu,
    'tunStack': tunStack,
    'dns': dns.toJson(),
    'appendSystemDns': appendSystemDns,
    'overrideYaml': overrideYaml,
    'hosts': hosts,
  };

  static String generateSecret() {
    const chars =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(20, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
