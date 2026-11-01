import 'dart:math';

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
      secret: (json['secret'] as String?)?.isNotEmpty == true ? json['secret'] as String : defaults.secret,
      allowLan: json['allowLan'] as bool? ?? false,
      ipv6: json['ipv6'] as bool? ?? false,
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

  bool get isZh => language == 'zh';

  static const String channelStable = 'stable';
  static const String channelPreview = 'preview';

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
      systemProxy: systemProxy ?? this.systemProxy,
      tun: tun ?? this.tun,
      autoStartCore: autoStartCore ?? this.autoStartCore,
      autoUpdateSubscriptions: autoUpdateSubscriptions ?? this.autoUpdateSubscriptions,
      mode: mode ?? this.mode,
      proxyStyle: proxyStyle ?? this.proxyStyle,
      proxySort: proxySort ?? this.proxySort,
      proxyLayout: proxyLayout ?? this.proxyLayout,
      proxyNodeSize: proxyNodeSize ?? this.proxyNodeSize,
      hideTimeoutProxies: hideTimeoutProxies ?? this.hideTimeoutProxies,
      updateChannel: updateChannel ?? this.updateChannel,
      checkUpdatesOnStartup: checkUpdatesOnStartup ?? this.checkUpdatesOnStartup,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      closeToTray: closeToTray ?? this.closeToTray,
      proxyBypass: proxyBypass ?? this.proxyBypass,
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
      };

  static String generateSecret() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(20, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
