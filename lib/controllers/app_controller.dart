import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/app_info.dart';
import '../core/app_paths.dart';
import '../core/core_log.dart';
import '../core/errors.dart';
import '../core/formatters.dart';
import '../core/l10n.dart';
import '../core/subscription_link.dart';
import '../data/local_store.dart';
import '../models/app_settings.dart';
import '../models/connection_info.dart';
import '../models/dns_config.dart';
import '../models/log_entry.dart';
import '../models/mihomo_version.dart';
import '../models/proxy_info.dart';
import '../models/subscription.dart';
import '../models/traffic_sample.dart';
import '../services/backup_service.dart';
import '../services/config_generator.dart';
import '../services/core_manager.dart';
import '../services/core_update_service.dart';
import '../services/json_socket.dart';
import '../services/mihomo_api.dart';
import '../services/network.dart';
import '../services/startup_service.dart';
import '../services/subscription_fetcher.dart';
import '../services/system_proxy.dart';
import '../services/update_service.dart';

enum CorePhase { stopped, starting, running, stopping }

class AppNotice {
  const AppNotice(this.message, {this.error = false});

  final String message;
  final bool error;
}

class AppController extends ChangeNotifier {
  AppController(
    this.paths, {
    StartupService? startupService,
    SubscriptionFetcher? fetcher,
    CoreManager? coreManager,
  }) : store = LocalStore(paths),
       api = MihomoApi(),
       fetcher = fetcher ?? SubscriptionFetcher(),
       systemProxy = SystemProxyService(paths),
       startup = startupService ?? StartupService(),
       core = coreManager ?? CoreManager(paths, CoreLog(paths.coreLogFile)) {
    core.onExit = _handleCoreExit;
    core.onExternalStop = _handleExternalStop;
  }

  final AppPaths paths;
  final LocalStore store;
  final MihomoApi api;
  final SubscriptionFetcher fetcher;
  final SystemProxyService systemProxy;
  final StartupService startup;
  final CoreManager core;
  final ConfigGenerator _configGenerator = const ConfigGenerator();
  final StreamController<AppNotice> _notices =
      StreamController<AppNotice>.broadcast();

  late AppSettings settings;
  List<Subscription> subscriptions = [];
  String? activeId;
  Map<String, Map<String, String>> selections = {};

  CorePhase phase = CorePhase.stopped;
  AppError? lastError;

  /// 上一次停止提权内核没得到监护进程确认：GUI 已经控制不了它，TUN 路由可能还挂着。
  /// 这时界面不能把「已停止」当成事实；下一次成功启动或确认停止后才清除。
  bool stopUnconfirmed = false;

  String? coreVersion;
  DateTime? startedAt;
  int? _exitCode;

  /// 内核启动时实际生效的分应用配置；与当前设置不一致时提示重启。
  String? _activeSplitSignature;

  ProxiesSnapshot proxySnapshot = const ProxiesSnapshot(
    proxies: {},
    groups: [],
  );
  bool loadingProxies = false;
  AppError? proxyError;
  final Set<String> testingGroups = {};
  final Set<String> testingNodes = {};

  /// 测速结果按订阅分开存：切换订阅时各自保留，切回来不会回到未测速状态。
  /// 当前订阅的结果由 [testedDelays] 暴露，离线预览与在线测速共用这一份。
  final Map<String, Map<String, int>> _delaysBySubscription = {};
  final Map<String, int> _orphanDelays = {};
  bool bulkTesting = false;

  ConnectionsSnapshot connectionsSnapshot = const ConnectionsSnapshot(
    connections: [],
    uploadTotal: 0,
    downloadTotal: 0,
  );
  AppError? connectionsError;

  int uploadSpeed = 0;
  int downloadSpeed = 0;
  int sessionUpload = 0;
  int sessionDownload = 0;
  int memoryInUse = 0;
  int memoryLimit = 0;
  final TrafficRing trafficHistory = TrafficRing(90);

  /// /traffic、/memory 这类每秒帧专用的一条通知线。主 notifier 会让整个首页重建，
  /// 而首页有三处 IntrinsicHeight（每个都要把子树量两遍），亮屏期间一秒两帧挂到主线
  /// 上就是持续的全页重排。只有曲线卡、速度卡、内存读数订阅这条线。
  final LiveTickNotifier live = LiveTickNotifier();

  final List<LogEntry> logs = [];
  int _logSequence = 0;
  bool logsActive = false;
  bool logsPaused = false;

  final Map<String, int?> latency = {
    for (final target in AppInfo.latencyTargets) target.label: null,
  };
  bool testingLatency = false;

  final Set<String> updatingSubscriptions = {};
  bool importingSubscription = false;
  bool updatingAll = false;

  /// Windows 内核更新：下载期间内核照常跑，进度 0–1 只用于更新对话框。
  bool checkingCoreUpdate = false;
  bool updatingCore = false;
  double coreUpdateProgress = 0;

  /// 当前磁盘上那个内核自己 `-v` 报出来的版本。内核没跑时关于页也靠它显示版本；
  /// 和 [coreVersion]（控制接口报的版本）不同，这个值在更新/回退后要重新探测。
  String? localCoreVersion;

  JsonSocket? _trafficSocket;
  JsonSocket? _memorySocket;
  JsonSocket? _logSocket;
  Timer? _connectionTimer;
  Timer? _proxyTimer;
  Timer? _latencyTimer;
  Timer? _autoUpdateTimer;
  Timer? _autoUpdateKick;
  Timer? _latencyDebounce;
  Timer? _startupUpdateTimer;
  Timer? _delaySaveTimer;
  bool _autoUpdating = false;
  bool _disposed = false;
  bool _systemProxyApplied = false;
  bool _foreground = true;
  bool _connectionsPolling = false;
  bool _proxiesPolling = false;
  // 默认值对齐 AppShell 的初始页（_index = 0 即主页）：主页可见、连接页不可见。
  bool _homeActive = true;
  bool _connectionsActive = false;
  bool _proxyActive = false;

  L10n get l10n => L10n(settings.language);

  Stream<AppNotice> get notices => _notices.stream;

  Subscription? get activeSubscription {
    if (activeId == null) return null;
    for (final sub in subscriptions) {
      if (sub.id == activeId) return sub;
    }
    return null;
  }

  Map<String, String> get activeSelections =>
      activeId == null ? const {} : (selections[activeId!] ?? const {});

  Map<String, int> get testedDelays {
    final id = activeId;
    if (id == null) return _orphanDelays;
    return _delaysBySubscription.putIfAbsent(id, () => <String, int>{});
  }

  bool get isRunning => phase == CorePhase.running;
  bool get isBusy => phase == CorePhase.starting || phase == CorePhase.stopping;

  bool get splitTunnelNeedsRestart {
    final active = _activeSplitSignature;
    return phase == CorePhase.running &&
        active != null &&
        active != settings.splitTunnelSignature;
  }

  String? get activeNode {
    final group = proxySnapshot.primaryGroup();
    return group?.now.isNotEmpty == true ? group!.now : null;
  }

  int? displayDelay(String name) {
    if (testingNodes.contains(name)) return null;
    return testedDelays[name] ?? proxySnapshot.proxies[name]?.delay;
  }

  String get coreLogTail => core.log.tail(30);

  String get coreBinary => core.binaryPath ?? '—';

  int get connectionCount => connectionsSnapshot.connections.length;

  Future<void> initialize() async {
    final preferChinese =
        PlatformDispatcher.instance.locale.languageCode == 'zh';
    // 老版本（或被手工改过）的 settings.json 里可能留着"两个都开"，那种状态下系统代理
    // 那个开关是假的：chip 亮着、toast 说已保存，注册表却一个字没写。启动时先归一化，
    // 下面那次 saveSettings 会顺手把修好的状态写回盘上。
    settings = _oneTakeover(
      await store.loadSettings(preferChinese: preferChinese),
    );
    subscriptions = await store.loadSubscriptions();
    activeId = await store.loadActiveId();
    if (activeId == null && subscriptions.isNotEmpty) {
      activeId = subscriptions.first.id;
    } else if (activeId != null && activeSubscription == null) {
      activeId = subscriptions.isEmpty ? null : subscriptions.first.id;
    }
    selections = await store.loadSelections();
    final validIds = subscriptions.map((sub) => sub.id).toSet();
    final storedDelays = await store.loadTestedDelays();
    _delaysBySubscription
      ..clear()
      ..addEntries(
        storedDelays.entries.where((entry) => validIds.contains(entry.key)),
      );
    await store.ensureCleanProfiles(validIds);
    api.configure(port: settings.apiPort, secret: settings.secret);
    try {
      await core.initializePlatform();
    } catch (_) {}
    await store.saveSettings(settings);
    await store.saveActiveId(activeId);
    try {
      await systemProxy.recoverIfStale(mixedPort: settings.mixedPort);
    } catch (_) {}
    try {
      startup.reconcile(settings.launchAtStartup);
    } catch (_) {}

    if (Platform.isAndroid) {
      try {
        final attached = await core.attachIfRunning(
          subscriptionId: activeId,
          apiPort: settings.apiPort,
        );
        if (attached != null) {
          phase = CorePhase.running;
          // 用 VpnService 实际启动时的分应用配置，而不是当前设置：进程重建后
          // 两者可能已经不同，沿用设置会把待重启提示吞掉。
          _activeSplitSignature =
              attached.splitSignature ?? settings.splitTunnelSignature;
          startedAt = attached.startedAt != null
              ? DateTime.fromMillisecondsSinceEpoch(attached.startedAt!)
              : DateTime.now();
          _startLiveFeeds();
          unawaited(refreshProxies(silent: true));
          unawaited(_applySavedSelections());
          try {
            coreVersion = (await api.version()).version;
          } catch (_) {}
        }
      } catch (_) {}
    }
    _notify();

    if (settings.autoStartCore &&
        activeSubscription != null &&
        phase == CorePhase.stopped) {
      unawaited(startCore(silent: true));
    }
    _startAutoUpdateTimer();
    // 句柄必须留着：这两条一次性定时器如果在启动后几秒内就把应用切到后台，
    // 没有句柄就没人能取消它们，后台仍会跑自动更新/联网检查。
    _autoUpdateKick = Timer(const Duration(seconds: 12), _runAutoUpdates);
    _startupUpdateTimer = Timer(
      const Duration(seconds: 5),
      _checkUpdatesOnStartup,
    );
  }

  Future<void> _checkUpdatesOnStartup() async {
    if (_disposed || !_foreground || !settings.checkUpdatesOnStartup) return;
    try {
      final release = await const UpdateService().latest(
        channel: settings.updateChannel,
        proxyPort: phase == CorePhase.running ? settings.mixedPort : null,
      );
      if (_disposed || release == null) return;
      if (UpdateService.isNewer(release.version, AppInfo.version)) {
        _notice(l10n.get('settings.updateStartupNotice', [release.version]));
      }
    } catch (_) {
      // 启动检查是静默的：没网、GitHub 被墙都不该打扰用户。
    }
  }

  // 后台只保留 VPN 前台服务与内核进程：停掉 UI 侧的 WebSocket、轮询与自动更新，
  // 回到前台时整体恢复，避免后台空转耗电。
  void setForeground(bool foreground) {
    if (_disposed || _foreground == foreground) return;
    _foreground = foreground;
    core.setMonitorEnabled(foreground);
    if (!foreground) {
      _autoUpdateTimer?.cancel();
      _autoUpdateTimer = null;
      _autoUpdateKick?.cancel();
      _autoUpdateKick = null;
      _stopLiveFeeds(clear: true);
      return;
    }
    _startAutoUpdateTimer();
    if (phase == CorePhase.running) {
      _startLiveFeeds();
      unawaited(refreshProxies(silent: true));
    }
    unawaited(_runAutoUpdates());
  }

  void _startAutoUpdateTimer() {
    _autoUpdateTimer?.cancel();
    _autoUpdateTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _runAutoUpdates(),
    );
  }

  // ------------------------------------------------------------------ settings

  Future<void> applySettings(AppSettings next, {bool announce = false}) async {
    final previous = settings;
    if (next.overrideYaml != previous.overrideYaml) {
      ConfigGenerator.validateOverride(next.overrideYaml);
    }
    // 改端口/主题/订阅这类保存走的是文件里现存的接管状态，不兜一下就会把"两个都开"
    // 重新写回盘上，把启动时刚归一化的结果又覆盖掉。
    next = _oneTakeover(
      next,
    ).copyWith(proxyBypass: AppSettings.normalizeProxyBypass(next.proxyBypass));
    final bypassChanged = previous.proxyBypass != next.proxyBypass;
    final coreFieldsChanged =
        previous.mixedPort != next.mixedPort ||
        previous.apiPort != next.apiPort ||
        previous.secret != next.secret ||
        previous.allowLan != next.allowLan ||
        previous.ipv6 != next.ipv6 ||
        previous.mode != next.mode;
    // DNS 覆写与 YAML 覆写都写进 config.yaml，重启一次才生效。
    final configFieldsChanged =
        previous.dns != next.dns ||
        previous.overrideYaml != next.overrideYaml;
    // 隧道参数写进 config.yaml，安卓还同时决定 VpnService.setMtu。系统代理模式
    // 下的 Windows 配置里没有 tun 段，改这两个值不该白白重启一次内核。
    final tunFieldsChanged =
        previous.tunMtu != next.tunMtu || previous.tunStack != next.tunStack;
    final tunInUse = Platform.isAndroid || next.tun;
    settings = next;
    api.configure(port: next.apiPort, secret: next.secret);
    await store.saveSettings(settings);
    _notify();
    if (previous.launchAtStartup != next.launchAtStartup) {
      try {
        startup.apply(next.launchAtStartup);
      } catch (error) {
        settings = settings.copyWith(launchAtStartup: previous.launchAtStartup);
        await store.saveSettings(settings);
        _notify();
        _notice(errorFrom(error).localized(l10n), error: true);
        rethrow;
      }
    }
    if (previous.systemProxy != next.systemProxy) {
      if (next.systemProxy) {
        if (phase == CorePhase.running) {
          try {
            await systemProxy.enable(next.mixedPort, bypass: next.proxyBypass);
            _systemProxyApplied = true;
          } catch (error) {
            settings = settings.copyWith(systemProxy: false);
            await store.saveSettings(settings);
            _notify();
            if (announce)
              _notice(errorFrom(error).localized(l10n), error: true);
            rethrow;
          }
        }
      } else {
        await systemProxy.disable();
        _systemProxyApplied = false;
      }
    } else if (bypassChanged && _systemProxyApplied) {
      // 绕过列表就是 ProxyOverride：系统代理正生效时改它要立刻重写。
      try {
        await systemProxy.enable(next.mixedPort, bypass: next.proxyBypass);
      } catch (error) {
        _notice(errorFrom(error).localized(l10n), error: true);
      }
    }
    if ((coreFieldsChanged ||
            configFieldsChanged ||
            (tunFieldsChanged && tunInUse)) &&
        phase == CorePhase.running) {
      await restartCore();
    }
    if (announce) _notice(l10n.get('settings.saved'));
  }

  Future<void> saveDnsConfig(DnsConfig next) async {
    await applySettings(settings.copyWith(dns: next), announce: true);
  }

  Future<void> saveOverrideYaml(String yaml) async {
    ConfigGenerator.validateOverride(yaml);
    await applySettings(settings.copyWith(overrideYaml: yaml), announce: true);
  }

  Future<void> setMode(String mode) async {
    if (!const ['rule', 'global', 'direct'].contains(mode)) return;
    settings = settings.copyWith(mode: mode);
    await store.saveSettings(settings);
    _notify();
    if (phase == CorePhase.running) {
      try {
        await api.patchConfigs({'mode': mode});
        _scheduleLatencyTest();
      } catch (error) {
        _notice(errorFrom(error).localized(l10n), error: true);
      }
    }
  }

  Future<void> regenerateSecret() async {
    final secret = AppSettings.generateSecret();
    await applySettings(settings.copyWith(secret: secret));
  }

  Future<void> resetSettings() async {
    if ((phase != CorePhase.stopped || stopUnconfirmed) &&
        !await stopCore()) {
      return;
    }
    settings = AppSettings.defaults(
      zh: settings.isZh,
      systemProxy: Platform.isWindows,
    );
    api.configure(port: settings.apiPort, secret: settings.secret);
    await store.saveSettings(settings);
    try {
      startup.apply(false);
    } catch (_) {}
    _notify();
    _notice(l10n.get('settings.resetDone'));
  }

  Future<void> clearSelections() async {
    selections.clear();
    testedDelays.clear();
    await store.saveSelections(selections);
    await _persistTestedDelays();
    _notify();
  }

  /// Windows 上接管方式只能有一个：系统代理和 TUN 同时开就是同一份流量两个入口，
  /// 一旦"看起来没走代理"，两条通路都脱不了干系（安卓同规矩——VPN 一开系统代理自然
  /// 轮不上）。冲突时谁赢取决于用户刚点的是哪个，所以点击路径各自让位（见 setTun 和
  /// setSystemProxy）；这里管的是没有点击语义的两处——启动读到的旧文件、设置页保存。
  /// 那种场合留下更强的 TUN：config.yaml 里的 tun 段是启动参数，已经在生效的那一个。
  static AppSettings _oneTakeover(AppSettings next) =>
      Platform.isWindows && next.tun && next.systemProxy
      ? next.copyWith(systemProxy: false)
      : next;

  Future<void> setSystemProxy(bool enabled) async {
    if (enabled && !SystemProxyService.supported)
      throw const AppError('unsupportedPlatform');
    // setTun 早就单向做了"开 TUN 就把系统代理让出来"，缺的是对称的这一半。不补的话：
    // 下面会把 systemProxy: true 存盘并弹"已保存"，而内核启动时 _enableSystemProxy 见
    // tun 还开着直接 return —— 点亮的是个假开关。
    // 让位的代价：tun 是启动参数，内核在跑时点这一下会重启一次内核（不再弹 UAC，
    // 关掉 TUN 之后走的是普通权限那条路）。
    if (enabled && Platform.isWindows && settings.tun) await setTun(false);
    try {
      if (enabled) {
        if (phase == CorePhase.running) {
          await systemProxy.enable(
            settings.mixedPort,
            bypass: settings.proxyBypass,
          );
          _systemProxyApplied = true;
        }
      } else {
        await systemProxy.disable();
        _systemProxyApplied = false;
      }
      settings = settings.copyWith(systemProxy: enabled);
      await store.saveSettings(settings);
      _notify();
      _notice(
        l10n.get(
          enabled
              ? 'settings.systemProxySaved'
              : 'settings.systemProxyDisabled',
        ),
      );
    } catch (error) {
      final appError = errorFrom(error);
      _notice(appError.localized(l10n), error: true);
      rethrow;
    }
  }

  /// Windows 专用。互斥的另一头（见 _oneTakeover / setSystemProxy）：开 TUN 就把系统代理
  /// 让出来，但关掉 TUN 时不把系统代理悄悄补回来——那是替用户做决定，界面上"直连"就是
  /// 直连。
  ///
  /// tun 是写进 config.yaml 的启动参数，内核在跑时必须重启才生效，而且会再弹一次
  /// UAC（提权进程没法就地改自己的配置）。失败不静默：UAC 被点"否"要立刻看到原因。
  Future<void> setTun(bool enabled) async {
    if (!Platform.isWindows) throw const AppError('unsupportedPlatform');
    if (settings.tun == enabled) return;
    // 上一次提权内核的停止没被确认：现在改接管方式就是在猜它到底还在不在。
    if (stopUnconfirmed) throw const AppError('tunStopUnconfirmed');
    final previous = settings;
    final wasRunning = phase == CorePhase.running;
    try {
      // 只撤销我们自己写进去的那一份：初始化时 recoverIfStale 已经把上一会话残留
      // 恢复干净了，所以 _systemProxyApplied 为假就说明这条设置不是我们动的，不能碰。
      if (enabled && _systemProxyApplied) {
        await systemProxy.disable();
        _systemProxyApplied = false;
      }
      settings = settings.copyWith(
        tun: enabled,
        systemProxy: enabled ? false : settings.systemProxy,
      );
      await store.saveSettings(settings);
      _notify();
      if (wasRunning) {
        if (!await stopCore(silent: true)) {
          throw const AppError('tunStopUnconfirmed');
        }
        await startCore();
      }
      _notice(l10n.get(enabled ? 'home.tunOn' : 'home.tunOff'));
    } catch (error) {
      final appError = errorFrom(error);
      // 启动失败时把开关恢复到实际能跑的那一档：TUN 起不来却留着 tun=true，
      // 下次点"停止"或重启都会拿一份没生效的设置继续往下走。
      if (settings.tun != previous.tun ||
          settings.systemProxy != previous.systemProxy) {
        settings = settings.copyWith(
          tun: previous.tun,
          systemProxy: previous.systemProxy,
        );
        try {
          await store.saveSettings(settings);
        } catch (_) {}
        if (previous.systemProxy && phase == CorePhase.running) {
          try {
            await systemProxy.enable(
              settings.mixedPort,
              bypass: settings.proxyBypass,
            );
            _systemProxyApplied = true;
          } catch (_) {}
        }
        _notify();
      }
      _notice(appError.localized(l10n), error: true);
      rethrow;
    }
  }

  Future<void> _enableSystemProxy() async {
    // 启动时已经归一化过一遍（_oneTakeover），这里再挡一次是便宜保险：这一行后面就是
    // 写注册表，两条通路同时生效的代价全落在那上面。
    if (Platform.isWindows && settings.tun) return;
    if (!settings.systemProxy || !SystemProxyService.supported) return;
    try {
      await systemProxy.enable(
        settings.mixedPort,
        bypass: settings.proxyBypass,
      );
      _systemProxyApplied = true;
    } catch (error) {
      _systemProxyApplied = false;
      _notice(errorFrom(error).localized(l10n), error: true);
    }
  }

  Future<void> _disableSystemProxy() async {
    if (!_systemProxyApplied) return;
    _systemProxyApplied = false;
    try {
      await systemProxy.disable();
    } catch (_) {}
  }

  // --------------------------------------------------------------------- core

  Future<void> startCore({bool silent = false}) async {
    if (phase != CorePhase.stopped) return;
    final sub = activeSubscription;
    if (subscriptions.isEmpty) {
      final error = const AppError('noSubscription');
      lastError = error;
      _notify();
      if (!silent) throw error;
      return;
    }
    if (sub == null) {
      final error = const AppError('noActiveSubscription');
      lastError = error;
      _notify();
      if (!silent) throw error;
      return;
    }
    if (!core.supported) {
      final error = const AppError('unsupportedPlatform');
      lastError = error;
      _notify();
      if (!silent) throw error;
      return;
    }
    if (core.binaryPath == null && Platform.isAndroid) {
      try {
        await core.initializePlatform();
      } catch (_) {}
    }
    if (core.binaryPath == null) {
      final error = const AppError('coreMissing');
      lastError = error;
      _notify();
      if (!silent) throw error;
      return;
    }

    phase = CorePhase.starting;
    lastError = null;
    _exitCode = null;
    startedAt = null;
    proxySnapshot = const ProxiesSnapshot(proxies: {}, groups: []);
    connectionsSnapshot = const ConnectionsSnapshot(
      connections: [],
      uploadTotal: 0,
      downloadTotal: 0,
    );
    trafficHistory.clear();
    uploadSpeed = 0;
    downloadSpeed = 0;
    sessionUpload = 0;
    sessionDownload = 0;
    memoryInUse = 0;
    testingNodes.clear();
    testingGroups.clear();
    // 测速结果不随内核重启清空：更新订阅/改端口/改 TUN 都会重启一次，
    // 那不该把用户刚测出来的一屏延迟退回“—”。
    latency.updateAll((key, value) => null);
    _notify();

    try {
      await ensureProfile(sub);
      final profile = await store.readProfile(sub.id);
      if (profile == null || profile.trim().isEmpty)
        throw const AppError('noProfile');
      final config = _configGenerator.generate(
        profile: profile,
        settings: settings,
        mode: settings.mode,
        androidTun: Platform.isAndroid,
        windowsTun: Platform.isWindows && settings.tun,
      );
      await core.start(
        config: config,
        mixedPort: settings.mixedPort,
        apiPort: settings.apiPort,
        subscriptionId: sub.id,
        ipv6: settings.ipv6,
        windowsTun: Platform.isWindows && settings.tun,
        notificationTitle: l10n.get('notification.vpnTitle'),
        notificationText: l10n.get('notification.vpnText'),
        notificationStop: l10n.get('notification.stop'),
        apiSecret: settings.secret,
        splitTunnelMode: settings.splitTunnelMode,
        splitTunnelPackages: settings.splitTunnelPackages,
        tunMtu: settings.tunMtu,
      );
      final version = await _waitForApi();
      coreVersion = version.version;
      phase = CorePhase.running;
      stopUnconfirmed = false;
      _activeSplitSignature = settings.splitTunnelSignature;
      startedAt = DateTime.now();
      _notify();
      await _enableSystemProxy();
      _startLiveFeeds();
      await refreshProxies(silent: true);
      await _applySavedSelections();
      unawaited(testLatency());
      if (!silent) _notice(l10n.get('toast.coreStarted'));
    } catch (error) {
      final appError = errorFrom(error);
      await core.stop();
      _stopLiveFeeds();
      phase = CorePhase.stopped;
      startedAt = null;
      lastError = appError;
      _notify();
      if (!silent) throw appError;
    }
  }

  /// 返回 false 表示停止请求没被提权监护进程确认。此时内核状态已经无法由
  /// 本进程控制，调用方绝不能再按"已经停机"继续启动、替换或切换接管方式。
  Future<bool> stopCore({bool silent = false}) async {
    if (phase == CorePhase.stopped) {
      if (!stopUnconfirmed) return true;
      final error = const AppError('tunStopUnconfirmed');
      lastError = error;
      _notify();
      if (!silent) _notice(error.localized(l10n), error: true);
      return false;
    }
    phase = CorePhase.stopping;
    _notify();
    _stopLiveFeeds();
    await _disableSystemProxy();
    final confirmed = await core.stop();
    phase = CorePhase.stopped;
    _activeSplitSignature = null;
    startedAt = null;
    proxySnapshot = const ProxiesSnapshot(proxies: {}, groups: []);
    connectionsSnapshot = const ConnectionsSnapshot(
      connections: [],
      uploadTotal: 0,
      downloadTotal: 0,
    );
    connectionsError = null;
    uploadSpeed = 0;
    downloadSpeed = 0;
    sessionUpload = 0;
    sessionDownload = 0;
    memoryInUse = 0;
    trafficHistory.clear();
    latency.updateAll((key, value) => null);
    stopUnconfirmed = !confirmed;
    if (!confirmed) {
      final error = const AppError('tunStopUnconfirmed');
      lastError = error;
      _notify();
      if (!silent) _notice(error.localized(l10n), error: true);
      return false;
    }
    if (lastError?.code == 'tunStopUnconfirmed') lastError = null;
    _notify();
    if (!silent) _notice(l10n.get('toast.coreStopped'));
    return true;
  }

  Future<void> restartCore({bool silent = false}) async {
    if (isBusy) return;
    final wasRunning = phase == CorePhase.running;
    if (wasRunning && !await stopCore(silent: true)) return;
    await startCore(silent: silent);
  }

  // --------------------------------------------------------------- core update

  bool get usingUpdatedCore =>
      Platform.isWindows && paths.coreOverrideFile.existsSync();

  /// 让当前磁盘上的内核自己报一次版本。内核没跑时关于页也用它显示版本；
  /// 更新/回退后这个值必须重新探测，不能沿用控制接口的旧值。
  Future<String?> probeCoreVersion() async {
    final path = core.binaryPath;
    if (path == null) {
      localCoreVersion = null;
    } else {
      final output = await CoreUpdateService.binaryVersion(path);
      localCoreVersion = output == null
          ? null
          : CoreUpdateService.versionFromOutput(output);
    }
    _notify();
    return localCoreVersion;
  }

  Future<CoreRelease?> checkCoreUpdate() async {
    if (checkingCoreUpdate) return null;
    checkingCoreUpdate = true;
    _notify();
    try {
      return await const CoreUpdateService().latest(
        proxyPort: _subscriptionProxyPort,
      );
    } finally {
      checkingCoreUpdate = false;
      _notify();
    }
  }

  /// 先下载、解压、用新 exe 跑 `-v` 校验版本，全部通过后才停内核替换文件。
  /// 下载期间内核照常工作；替换后如果它本来在跑就自动拉起来——TUN 模式除外，
  /// 那会再弹一次 UAC，授权决定交给用户。
  Future<void> installCoreUpdate(CoreRelease release) async {
    if (!Platform.isWindows) throw const AppError('unsupportedPlatform');
    if (updatingCore) return;
    if (isBusy) throw const AppError('generic', detail: 'Core is busy');

    updatingCore = true;
    coreUpdateProgress = 0;
    _notify();
    final service = const CoreUpdateService();
    final temp = File(
      p.join(paths.coreOverrideFile.parent.path, 'mihomo-update.exe'),
    );
    var wasRunning = false;
    var stoppedForReplace = false;
    try {
      final zip = await service.download(
        release,
        proxyPort: phase == CorePhase.running ? settings.mixedPort : null,
        onProgress: (received, total) {
          if (!updatingCore) return;
          coreUpdateProgress = total > 0
              ? (received / total).clamp(0.0, 1.0).toDouble()
              : 0;
          _notify();
        },
      );
      coreUpdateProgress = 1;
      _notify();

      final bytes = CoreUpdateService.extractCore(zip);
      await paths.coreOverrideFile.parent.create(recursive: true);
      await temp.writeAsBytes(bytes, flush: true);
      final output = await CoreUpdateService.binaryVersion(temp.path);
      final reported = output == null
          ? null
          : CoreUpdateService.versionFromOutput(output);
      if (reported == null ||
          UpdateService.compareVersions(reported, release.version) != 0) {
        throw AppError(
          'coreUpdateVerify',
          detail: reported == null
              ? 'The downloaded executable did not report a version'
              : 'Downloaded core reports $reported, expected ${release.version}',
        );
      }

      wasRunning = phase == CorePhase.running;
      if (phase != CorePhase.stopped || stopUnconfirmed) {
        stoppedForReplace = true;
        if (!await stopCore(silent: true)) {
          throw const AppError('tunStopUnconfirmed');
        }
        coreVersion = null;
      }
      // 同目录 rename 替换的是目录项本身：不会出现目标文件被截断到一半、
      // 进程恰好在这时启动而拿到一个坏内核的窗口。验证过的临时文件已经在同盘。
      await temp.rename(paths.coreOverrideFile.path);
      localCoreVersion = reported;
      _notice(
        l10n.get(
          wasRunning && settings.tun
              ? 'settings.coreUpdateTunHint'
              : 'settings.coreUpdateInstalled',
          [release.version],
        ),
      );
      if (wasRunning && !settings.tun) {
        await startCore(silent: true);
      }
    } catch (error) {
      if (stoppedForReplace && wasRunning && !settings.tun) {
        // 替换失败时至少把原来那个内核拉回来，别让一次更新把代理留在停机状态。
        await startCore(silent: true);
      }
      final appError = errorFrom(error);
      _notice(appError.localized(l10n), error: true);
      rethrow;
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
      updatingCore = false;
      coreUpdateProgress = 0;
      _notify();
    }
  }

  Future<void> restoreBundledCore() async {
    if (!Platform.isWindows) throw const AppError('unsupportedPlatform');
    if (updatingCore) return;
    if (!await paths.coreOverrideFile.exists()) return;
    if (isBusy) throw const AppError('generic', detail: 'Core is busy');

    updatingCore = true;
    _notify();
    var wasRunning = false;
    try {
      wasRunning = phase == CorePhase.running;
      if (phase != CorePhase.stopped || stopUnconfirmed) {
        if (!await stopCore(silent: true)) {
          throw const AppError('tunStopUnconfirmed');
        }
        coreVersion = null;
      }
      await paths.coreOverrideFile.delete();
      await probeCoreVersion();
      _notice(l10n.get('settings.coreRestoreDone'));
      if (wasRunning && !settings.tun) {
        await startCore(silent: true);
      }
    } catch (error) {
      final appError = errorFrom(error);
      _notice(appError.localized(l10n), error: true);
      rethrow;
    } finally {
      updatingCore = false;
      _notify();
    }
  }

  Future<void> _toggleCore() async {
    if (phase == CorePhase.stopped) {
      await startCore();
    } else if (phase == CorePhase.running) {
      await stopCore();
    }
  }

  Future<void> toggleCore() async {
    try {
      await _toggleCore();
    } catch (error) {
      final appError = errorFrom(error);
      lastError = appError;
      _notify();
      _notice(appError.localized(l10n), error: true);
    }
  }

  Future<MihomoVersion> _waitForApi() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    Object? lastFailure;
    while (DateTime.now().isBefore(deadline)) {
      if (_exitCode != null) {
        throw AppError(
          'coreExited',
          statusCode: _exitCode,
          detail: core.log.tail(14),
        );
      }
      try {
        return await api.version();
      } catch (error) {
        lastFailure = error;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    final reason = lastFailure?.toString() ?? 'unknown';
    throw AppError(
      'startTimeout',
      detail: '${api.baseUrl}: $reason\n${core.log.tail(14)}',
    );
  }

  void _handleCoreExit(int code) {
    _exitCode = code;
    if (_disposed) return;
    if (phase == CorePhase.running) {
      _resetRuntimeState();
      lastError = AppError(
        'coreExited',
        statusCode: code,
        detail: core.log.tail(10),
      );
      _notify();
      _notice(lastError!.localized(l10n), error: true);
    }
  }

  // Stopped from the Android notification or revoked by the system: an
  // intentional stop, so show it as stopped instead of an exit error.
  void _handleExternalStop() {
    if (_disposed) return;
    if (phase == CorePhase.running) {
      _resetRuntimeState();
      _notify();
      _notice(l10n.get('toast.coreStopped'));
    }
  }

  void _resetRuntimeState() {
    _stopLiveFeeds();
    unawaited(_disableSystemProxy());
    phase = CorePhase.stopped;
    _activeSplitSignature = null;
    startedAt = null;
    connectionsSnapshot = const ConnectionsSnapshot(
      connections: [],
      uploadTotal: 0,
      downloadTotal: 0,
    );
    uploadSpeed = 0;
    downloadSpeed = 0;
    sessionUpload = 0;
    sessionDownload = 0;
    memoryInUse = 0;
    trafficHistory.clear();
    latency.updateAll((key, value) => null);
  }

  void _startLiveFeeds() {
    _stopLiveFeeds(clear: false);
    if (!_foreground) return;
    _syncLogFeed();
    _syncProxyTimer();
    _latencyTimer = Timer.periodic(
      AppInfo.latencyProbeInterval,
      (_) => testLatency(),
    );
    _syncHomeFeeds();
    _syncConnectionTimer();
  }

  /// 日志页是 /logs 唯一的读者。内核按 log-level 每条连接、每条规则匹配都推一行，
  /// 每行都要解码、进环形缓冲、把 isolate 唤醒一次；用户停在别的页面时这些唤醒没有
  /// 任何人看得见，和当初 /traffic 常连是同一个问题源。所以走同一条规矩：日志页
  /// 不可见就整条断开。缓冲区不清空，切回来先看到离开前的尾巴，之后的实时接上。
  void _syncLogFeed() {
    final shouldRun = _foreground && logsActive && phase == CorePhase.running;
    if (!shouldRun) {
      _logSocket?.dispose();
      _logSocket = null;
      return;
    }
    if (_logSocket != null) return;
    _logSocket = JsonSocket(
      api: api,
      path: '/logs',
      // 档位必须和 config.yaml 里写的是同一个常量：两处各写各的，一旦内核调低
      // 一档，订阅还停在旧档位，日志页就会静默空白，而且看不出是谁的问题。
      query: () => const {'level': AppInfo.coreLogLevel},
      onData: (data) {
        final message = data['payload']?.toString() ?? '';
        if (message.isEmpty) return;
        logs.insert(
          0,
          LogEntry(
            time: DateTime.now(),
            level: data['type']?.toString() ?? 'info',
            message: message,
            sequence: _logSequence++,
          ),
        );
        if (logs.length > 600) logs.removeRange(600, logs.length);
        if (logsActive && !logsPaused) _notify();
      },
    )..start();
  }

  /// 流量和内存曲线只有主页在用。离开主页就把这两条 WebSocket 整个断开——
  /// 留着等于让内核每秒推一条、把 isolate 唤醒一次，却没有任何人看。
  void _syncHomeFeeds() {
    final shouldRun = _foreground && _homeActive && phase == CorePhase.running;
    if (!shouldRun) {
      _trafficSocket?.dispose();
      _trafficSocket = null;
      _memorySocket?.dispose();
      _memorySocket = null;
      return;
    }
    if (_trafficSocket != null) return;
    _trafficSocket = JsonSocket(
      api: api,
      path: '/traffic',
      onData: (data) {
        uploadSpeed = (data['up'] as num?)?.toInt() ?? 0;
        downloadSpeed = (data['down'] as num?)?.toInt() ?? 0;
        final upTotal = (data['upTotal'] as num?)?.toInt();
        final downTotal = (data['downTotal'] as num?)?.toInt();
        if (upTotal != null) sessionUpload = upTotal;
        if (downTotal != null) sessionDownload = downTotal;
        if (upTotal == null) sessionUpload += uploadSpeed;
        if (downTotal == null) sessionDownload += downloadSpeed;
        trafficHistory.add(
          TrafficSample(
            upload: uploadSpeed,
            download: downloadSpeed,
            uploadTotal: sessionUpload,
            downloadTotal: sessionDownload,
          ),
        );
        live.tick();
      },
    )..start();

    _memorySocket = JsonSocket(
      api: api,
      path: '/memory',
      onData: (data) {
        memoryInUse = (data['inuse'] as num?)?.toInt() ?? 0;
        memoryLimit = (data['oslimit'] as num?)?.toInt() ?? 0;
        live.tick();
      },
    )..start();
  }

  /// /connections 是唯一没有 WebSocket 通道、只能靠定时 HTTP 的数据源，
  /// 所以连接页不可见时必须把定时器整个停掉，降频是不够的。
  void _syncConnectionTimer() {
    _connectionTimer?.cancel();
    _connectionTimer = null;
    if (!_foreground || !_connectionsActive || phase != CorePhase.running)
      return;
    _connectionTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => refreshConnections(silent: true),
    );
    refreshConnections(silent: true);
  }

  /// 全量 /proxies 按可见性分档：代理页可见 8 秒，其他页 30 秒。
  /// 和连接页那种"不可见就整个停掉"不一样——节点表在别的页也有读者（主页的
  /// 当前节点、模式卡片），所以只能降频，不能断流。
  void _syncProxyTimer() {
    _proxyTimer?.cancel();
    _proxyTimer = null;
    if (!_foreground || phase != CorePhase.running) return;
    _proxyTimer = Timer.periodic(
      _proxyActive
          ? AppInfo.proxyPollVisibleInterval
          : AppInfo.proxyPollIdleInterval,
      (_) => refreshProxies(silent: true),
    );
    // 切到代理页时先把表拉回来，节点列表不该空着一个周期才填上。
    if (_proxyActive) refreshProxies(silent: true);
  }

  void setHomeActive(bool active) {
    if (_homeActive == active) return;
    _homeActive = active;
    _syncHomeFeeds();
    // 周期已经是 15 分钟一档，靠它等不回来：页面刚露出来时用户要看到的就是
    // 当前延迟，所以这里补测一次（900ms debounce 把连续切页合成一次探测）。
    if (active) _scheduleLatencyTest();
    _notify();
  }

  void setConnectionsActive(bool active) {
    if (_connectionsActive == active) return;
    _connectionsActive = active;
    _syncConnectionTimer();
  }

  /// 延迟探测的第二个消费者：代理页那排节点状态点。首页或代理页任意一个可见时
  /// 探测就值得跑，两个都不可见时结果没人看，一轮三次出网纯属浪费。
  /// 同一个标志还决定 /proxies 全量轮询走 8 秒还是 30 秒。
  void setProxyActive(bool active) {
    if (_proxyActive == active) return;
    _proxyActive = active;
    _syncProxyTimer();
    if (active) _scheduleLatencyTest();
  }

  void _stopLiveFeeds({bool clear = false}) {
    _trafficSocket?.dispose();
    _memorySocket?.dispose();
    _logSocket?.dispose();
    _trafficSocket = null;
    _memorySocket = null;
    _logSocket = null;
    _connectionTimer?.cancel();
    _proxyTimer?.cancel();
    _latencyTimer?.cancel();
    _latencyDebounce?.cancel();
    _connectionTimer = null;
    _proxyTimer = null;
    _latencyTimer = null;
    _latencyDebounce = null;
    if (clear) {
      uploadSpeed = 0;
      downloadSpeed = 0;
    }
  }

  // -------------------------------------------------------------------- proxy

  Future<void> refreshProxies({bool silent = false}) async {
    if (phase != CorePhase.running || _proxiesPolling) return;
    _proxiesPolling = true;
    loadingProxies = true;
    if (!silent) _notify();
    try {
      proxySnapshot = await api.proxies();
      proxyError = null;
    } catch (error) {
      proxyError = errorFrom(error);
    } finally {
      _proxiesPolling = false;
      loadingProxies = false;
      _notify();
    }
  }

  Future<void> _applySavedSelections() async {
    final saved = activeSelections;
    if (saved.isEmpty) return;
    var changed = false;
    for (final entry in saved.entries) {
      final group = proxySnapshot.proxies[entry.key];
      if (group == null || !group.isGroup || !group.all.contains(entry.value))
        continue;
      if (group.now == entry.value) continue;
      try {
        await api.selectProxy(entry.key, entry.value);
        changed = true;
      } catch (_) {}
    }
    if (changed) await refreshProxies(silent: true);
  }

  Future<void> selectProxy(ProxyInfo group, String node) async {
    if (phase != CorePhase.running) return;
    try {
      await api.selectProxy(group.name, node);
      if (activeId != null) {
        final map = Map<String, String>.from(selections[activeId!] ?? const {});
        map[group.name] = node;
        selections[activeId!] = map;
        await store.saveSelections(selections);
      }
      await refreshProxies(silent: true);
      _scheduleLatencyTest();
      _notice(l10n.get('toast.selectionApplied'));
    } catch (error) {
      final appError = errorFrom(error);
      _notice(appError.localized(l10n), error: true);
      rethrow;
    }
  }

  Future<void> saveSelectionOffline(ProxyInfo group, String node) async {
    final id = activeId;
    if (id == null) return;
    final map = Map<String, String>.from(selections[id] ?? const {});
    map[group.name] = node;
    selections[id] = map;
    await store.saveSelections(selections);
    _notify();
  }

  Future<void> testNode(String name) async {
    if (phase != CorePhase.running) return;
    testingNodes.add(name);
    _notify();
    try {
      final delay = await api.proxyDelay(name, url: settings.testUrl);
      _recordDelays({name: delay});
    } catch (_) {
      _recordDelays({name: -1});
    } finally {
      testingNodes.remove(name);
      _notify();
    }
  }

  Future<void> testGroup(ProxyInfo group) async {
    if (phase != CorePhase.running) return;
    testingGroups.add(group.name);
    _notify();
    try {
      final results = await api.groupDelay(
        group.name,
        url: settings.testUrl,
      );
      if (results.isEmpty) {
        // 整组超时：每个节点都应反映这次结果，而不是留着上一轮的旧数字。
        _recordDelays({for (final name in group.all) name: -1});
      } else {
        _recordDelays(results);
      }
    } catch (error) {
      _notice(errorFrom(error).localized(l10n), error: true);
    } finally {
      testingGroups.remove(group.name);
      _notify();
    }
  }

  Future<void> testAllGroups() async {
    if (phase != CorePhase.running || bulkTesting) return;
    bulkTesting = true;
    for (final group in proxySnapshot.groups) {
      testingGroups.add(group.name);
    }
    _notify();
    for (final group in proxySnapshot.groups) {
      try {
        final results = await api.groupDelay(
          group.name,
          url: settings.testUrl,
        );
        _recordDelays(results);
      } catch (_) {
        _recordDelays({for (final name in group.all) name: -1});
      }
      testingGroups.remove(group.name);
      _notify();
    }
    bulkTesting = false;
    _notify();
  }

  /// 离线预览页自己发起 TCP 测速，没有内核 API；结果同样记到当前订阅名下。
  void recordTestedDelay(String name, int delay) {
    testedDelays[name] = delay;
    _scheduleDelaySave();
    _notify();
  }

  void _recordDelays(Map<String, int> results) {
    if (results.isEmpty) return;
    testedDelays.addAll(results);
    _scheduleDelaySave();
  }

  void _scheduleDelaySave() {
    _delaySaveTimer?.cancel();
    _delaySaveTimer = Timer(const Duration(milliseconds: 500), () {
      _delaySaveTimer = null;
      unawaited(_persistTestedDelays());
    });
  }

  Future<void> _persistTestedDelays() async {
    try {
      await store.saveTestedDelays({
        for (final entry in _delaysBySubscription.entries)
          if (entry.value.isNotEmpty)
            entry.key: Map<String, int>.of(entry.value),
      });
    } catch (_) {}
  }

  // ---------------------------------------------------------------- connections

  Future<void> refreshConnections({bool silent = false}) async {
    if (phase != CorePhase.running || _connectionsPolling) return;
    _connectionsPolling = true;
    try {
      connectionsSnapshot = await api.connections();
      connectionsError = null;
    } catch (error) {
      connectionsError = errorFrom(error);
    } finally {
      _connectionsPolling = false;
    }
    _notify();
  }

  Future<void> closeConnection(String id) async {
    try {
      await api.closeConnection(id);
      await refreshConnections(silent: true);
      _notice(l10n.get('connections.closed'));
    } catch (error) {
      _notice(errorFrom(error).localized(l10n), error: true);
    }
  }

  Future<void> closeAllConnections() async {
    try {
      await api.closeAllConnections();
      await refreshConnections(silent: true);
      _notice(l10n.get('connections.allClosed'));
    } catch (error) {
      _notice(errorFrom(error).localized(l10n), error: true);
    }
  }

  // --------------------------------------------------------------------- logs

  /// 日志页的可见性直接决定 /logs 要不要连（见 _syncLogFeed）。这里没有
  /// /proxies 那种"别的页面也读"的例外：日志只有日志页一个读者。
  void setLogsActive(bool active) {
    if (logsActive == active) return;
    logsActive = active;
    _syncLogFeed();
    if (active) _notify();
  }

  void toggleLogsPaused() {
    logsPaused = !logsPaused;
    _notify();
  }

  void clearLogs() {
    logs.clear();
    _notify();
  }

  // ------------------------------------------------------------------ latency

  Future<void> testLatency() async {
    // 不可见不发起：首页和代理页都看不到时，那排状态点没有消费者，
    // 一轮探测却是三条经 mixed-port 的真实出网连接。
    if (!_foreground || phase != CorePhase.running || testingLatency) return;
    if (!_homeActive && !_proxyActive) return;
    testingLatency = true;
    _notify();
    final results = await Future.wait([
      for (final target in AppInfo.latencyTargets) _probe(target.url),
    ]);
    for (var i = 0; i < AppInfo.latencyTargets.length; i++) {
      latency[AppInfo.latencyTargets[i].label] = results[i];
    }
    testingLatency = false;
    _notify();
  }

  void _scheduleLatencyTest() {
    _latencyDebounce?.cancel();
    _latencyDebounce = Timer(const Duration(milliseconds: 900), testLatency);
  }

  Future<int> _probe(String url) async {
    final client = createHttpClient(
      proxyPort: settings.mixedPort,
      timeout: const Duration(seconds: 5),
    );
    final watch = Stopwatch()..start();
    try {
      final request = await client
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 6));
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'ClashGo/${AppInfo.version}',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );
      final elapsed = watch.elapsedMilliseconds;
      unawaited(response.drain<void>().catchError((_) {}));
      return response.statusCode < 500 ? elapsed : -1;
    } catch (_) {
      return -1;
    } finally {
      client.close(force: true);
    }
  }

  // --------------------------------------------------------------- subscriptions

  String _randomId() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
    ).join();
  }

  /// 外链兜底入口：clash://install-config?url=… 或直接订阅链接。
  /// 解析失败和导入失败都走通知而不是抛错——深链没有对话框承接异常。
  Future<void> handleIncomingLink(String raw) async {
    final url = subscriptionUrlFromLink(raw);
    if (url == null) {
      _notice(l10n.get('subscriptions.linkInvalid'), error: true);
      return;
    }
    try {
      await addSubscription(url: url);
    } catch (error) {
      _notice(errorFrom(error).localized(l10n), error: true);
    }
  }

  Future<Subscription> addSubscription({
    required String url,
    String? name,
    bool? autoUpdate,
    int? updateIntervalMinutes,
  }) async {
    if (importingSubscription)
      throw const AppError('generic', detail: 'Another import is in progress');
    importingSubscription = true;
    _notify();
    try {
      final fetched = await fetcher.fetchUrl(
        url.trim(),
        proxyPort: _subscriptionProxyPort,
      );
      fetcher.validateProfile(fetched.content);
      final subscription = await _createSubscription(
        content: fetched.content,
        url: url.trim(),
        isLocal: false,
        name: name,
        headers: fetched.headers,
        autoUpdate: autoUpdate,
        updateIntervalMinutes: updateIntervalMinutes,
      );
      _notice(l10n.get('subscriptions.addSuccess'));
      return subscription;
    } finally {
      importingSubscription = false;
      _notify();
    }
  }

  Future<Subscription> importLocalFile(File file) async {
    if (importingSubscription)
      throw const AppError('generic', detail: 'Another import is in progress');
    importingSubscription = true;
    _notify();
    try {
      final fetched = await fetcher.readFile(file);
      fetcher.validateProfile(fetched.content);
      final subscription = await _createSubscription(
        content: fetched.content,
        url: file.path,
        isLocal: true,
        name: fetched.headers.name,
        headers: fetched.headers,
      );
      _notice(l10n.get('subscriptions.addSuccess'));
      return subscription;
    } finally {
      importingSubscription = false;
      _notify();
    }
  }

  int? get _subscriptionProxyPort =>
      phase == CorePhase.running ? settings.mixedPort : null;

  Future<Subscription> _createSubscription({
    required String content,
    required String url,
    required bool isLocal,
    required SubscriptionHeaders headers,
    String? name,
    bool? autoUpdate,
    int? updateIntervalMinutes,
  }) async {
    final now = DateTime.now();
    final resolvedName = _resolveName(
      name: name,
      headers: headers,
      content: content,
      url: url,
    );
    // 添加对话框里显式指定的间隔优先；二维码导入等没有对话框的入口继续沿用
    // 订阅响应头（部分机场会下发），再退回 24 小时。
    final interval =
        (updateIntervalMinutes != null && updateIntervalMinutes > 0)
        ? updateIntervalMinutes
        : (headers.updateIntervalMinutes ?? 1440);
    final subscription = Subscription(
      id: _randomId(),
      name: resolvedName,
      url: url,
      isLocal: isLocal,
      createdAt: now,
      lastUpdatedAt: now,
      autoUpdate: !isLocal && interval > 0 && (autoUpdate ?? true),
      updateIntervalMinutes: interval,
      upload: headers.upload,
      download: headers.download,
      total: headers.total,
      expire: headers.expire,
      userAgent: AppInfo.defaultUserAgent,
    );
    await store.writeProfile(subscription.id, content);
    subscriptions = [...subscriptions, subscription];
    if (activeId == null) {
      activeId = subscription.id;
      await store.saveActiveId(activeId);
    }
    await store.saveSubscriptions(subscriptions);
    _notify();
    return subscription;
  }

  String _resolveName({
    String? name,
    required SubscriptionHeaders headers,
    required String content,
    required String url,
  }) {
    var candidate = name?.trim() ?? '';
    if (candidate.isEmpty) candidate = headers.name?.trim() ?? '';
    if (candidate.isEmpty) candidate = fetcher.nameFromProfile(content) ?? '';
    if (candidate.isEmpty) {
      final uri = Uri.tryParse(url);
      candidate = uri?.host.isNotEmpty == true
          ? uri!.host
          : l10n.get('subscriptions.unnamed');
    }
    candidate = candidate
        .replaceAll(RegExp(r'\.(ya?ml)$', caseSensitive: false), '')
        .trim();
    if (candidate.isEmpty)
      candidate = l10n.get('subscriptions.autoName', [
        subscriptions.length + 1,
      ]);
    return candidate;
  }

  Future<bool> updateSubscription(
    String id, {
    bool restartIfActive = true,
    bool silent = false,
  }) async {
    final index = subscriptions.indexWhere((sub) => sub.id == id);
    if (index < 0 || updatingSubscriptions.contains(id)) return false;
    final original = subscriptions[index];
    updatingSubscriptions.add(id);
    _notify();
    try {
      FetchedProfile fetched;
      if (original.isLocal) {
        fetched = await fetcher.readFile(File(original.url));
      } else {
        fetched = await fetcher.fetchUrl(
          original.url,
          userAgent: original.userAgent,
          proxyPort: _subscriptionProxyPort,
        );
      }
      fetcher.validateProfile(fetched.content);
      final now = DateTime.now();
      // 抓取期间用户可能删除、排序或编辑订阅：旧下标和旧快照都已失效，
      // 写入前必须按 id 重新定位，否则会覆盖别的订阅或把已删条目复活。
      var currentIndex = subscriptions.indexWhere((sub) => sub.id == id);
      if (currentIndex < 0) return false;
      await store.writeProfile(id, fetched.content);
      currentIndex = subscriptions.indexWhere((sub) => sub.id == id);
      if (currentIndex < 0) {
        // 写 profile 期间被删除：把刚写出的文件一起清掉。
        await store.deleteProfile(id);
        return false;
      }
      final current = subscriptions[currentIndex];
      final updated = current.copyWith(
        lastUpdatedAt: now,
        upload: fetched.headers.hasQuota
            ? fetched.headers.upload
            : current.upload,
        download: fetched.headers.hasQuota
            ? fetched.headers.download
            : current.download,
        total: fetched.headers.hasQuota
            ? fetched.headers.total
            : current.total,
        expire: fetched.headers.hasQuota
            ? fetched.headers.expire
            : current.expire,
        clearError: true,
      );
      subscriptions = List<Subscription>.from(subscriptions)
        ..[currentIndex] = updated;
      await store.saveSubscriptions(subscriptions);
      _notify();
      if (!silent) _notice(l10n.get('subscriptions.updateSuccess'));
      if (restartIfActive && activeId == id && phase == CorePhase.running) {
        await restartCore(silent: true);
      }
      return true;
    } catch (error) {
      final appError = errorFrom(error);
      final currentIndex = subscriptions.indexWhere((sub) => sub.id == id);
      if (currentIndex >= 0) {
        final failed = subscriptions[currentIndex].copyWith(
          lastError: appError.localized(l10n).replaceAll('\n', ' · '),
          lastErrorAt: DateTime.now(),
        );
        subscriptions = List<Subscription>.from(subscriptions)
          ..[currentIndex] = failed;
        await store.saveSubscriptions(subscriptions);
      }
      _notify();
      if (!silent) {
        _notice(appError.localized(l10n), error: true);
        rethrow;
      }
      return false;
    } finally {
      updatingSubscriptions.remove(id);
      _notify();
    }
  }

  Future<bool> hasCachedProfile(String id) async {
    final content = await store.readProfile(id);
    return content != null && content.trim().isNotEmpty;
  }

  /// 离线预览与启动内核都依赖 `subscriptions/profiles/<id>.yaml`。缓存缺失时补齐：
  /// 本地订阅直接重读原文件，远程订阅静默更新一次，否则两处都会以「无内容」失败。
  Future<bool> ensureProfile(Subscription sub) async {
    if (await hasCachedProfile(sub.id)) return true;
    if (sub.isLocal) {
      try {
        final fetched = await fetcher.readFile(File(sub.url));
        await store.writeProfile(sub.id, fetched.content);
        return true;
      } catch (_) {
        return false;
      }
    }
    return updateSubscription(sub.id, restartIfActive: false, silent: true);
  }

  Future<void> updateAllSubscriptions() async {
    if (updatingAll) return;
    updatingAll = true;
    _notify();
    var activeUpdated = false;
    var updated = 0;
    var failed = 0;
    for (final sub in List<Subscription>.from(subscriptions)) {
      final ok = await updateSubscription(
        sub.id,
        restartIfActive: false,
        silent: true,
      );
      if (!ok) {
        failed++;
        continue;
      }
      updated++;
      if (sub.id == activeId) activeUpdated = true;
    }
    updatingAll = false;
    _notify();
    if (activeUpdated && phase == CorePhase.running) {
      await restartCore(silent: true);
    }
    if (failed == 0) {
      _notice(l10n.get('subscriptions.updateAllDone'));
    } else if (updated == 0) {
      _notice(l10n.get('subscriptions.updateAllFailed'), error: true);
    } else {
      _notice(
        l10n.get('subscriptions.updateAllPartial', [updated, failed]),
        error: true,
      );
    }
  }

  Future<void> editSubscription(
    String id, {
    required String name,
    required String url,
    required bool autoUpdate,
    required int updateIntervalMinutes,
  }) async {
    final index = subscriptions.indexWhere((sub) => sub.id == id);
    if (index < 0) return;
    final sub = subscriptions[index];
    final updated = Subscription(
      id: sub.id,
      name: name.trim().isEmpty ? sub.name : name.trim(),
      url: url.trim().isEmpty ? sub.url : url.trim(),
      isLocal: sub.isLocal,
      createdAt: sub.createdAt,
      lastUpdatedAt: sub.lastUpdatedAt,
      autoUpdate: autoUpdate,
      updateIntervalMinutes: updateIntervalMinutes,
      upload: sub.upload,
      download: sub.download,
      total: sub.total,
      expire: sub.expire,
      lastError: sub.lastError,
      lastErrorAt: sub.lastErrorAt,
      userAgent: sub.userAgent,
    );
    subscriptions = List<Subscription>.from(subscriptions)..[index] = updated;
    await store.saveSubscriptions(subscriptions);
    _notify();
  }

  Future<void> setActiveSubscription(String id) async {
    if (activeId == id || !subscriptions.any((sub) => sub.id == id)) return;
    activeId = id;
    await store.saveActiveId(activeId);
    _notify();
    if (phase == CorePhase.running) {
      await restartCore(silent: true);
    }
    _notice(l10n.get('subscriptions.setActive'));
  }

  /// 手动排序只改列表顺序：当前订阅、选择状态、内核都不受影响。
  Future<void> reorderSubscriptions(List<String> orderedIds) async {
    if (orderedIds.length != subscriptions.length) return;
    final byId = {for (final sub in subscriptions) sub.id: sub};
    if (orderedIds.toSet().length != orderedIds.length) return;
    final next = <Subscription>[];
    for (final id in orderedIds) {
      final sub = byId[id];
      if (sub == null) return;
      next.add(sub);
    }
    var unchanged = true;
    for (var i = 0; i < next.length; i++) {
      if (next[i].id != subscriptions[i].id) {
        unchanged = false;
        break;
      }
    }
    if (unchanged) return;
    subscriptions = next;
    await store.saveSubscriptions(subscriptions);
    _notify();
    _notice(l10n.get('subscriptions.sortSaved'));
  }

  Future<void> deleteSubscription(String id) async {
    final wasActive = activeId == id;
    subscriptions = subscriptions.where((sub) => sub.id != id).toList();
    selections.remove(id);
    _delaysBySubscription.remove(id);
    await store.deleteProfile(id);
    if (wasActive) {
      activeId = subscriptions.isEmpty ? null : subscriptions.first.id;
      await store.saveActiveId(activeId);
    }
    await store.saveSubscriptions(subscriptions);
    await store.saveSelections(selections);
    await _persistTestedDelays();
    _notify();
    if (wasActive) {
      if (phase == CorePhase.running) {
        if (activeId == null) {
          await stopCore(silent: true);
        } else {
          await restartCore(silent: true);
        }
      }
      if (activeId == null && !stopUnconfirmed) {
        await core.clearRuntimeArtifacts();
      }
    }
    _notice(l10n.get('subscriptions.deleted'));
  }

  Future<void> _runAutoUpdates() async {
    if (_autoUpdating || _disposed) return;
    // 后台一律不跑：这条链路会读订阅缓存、发网络请求、写 profile，命中更新时还会
    // restartCore 拆掉重建隧道，是锁屏待机期间最重的一次开销。回到前台时
    // setForeground(true) 会补跑一次，不会漏更新。
    if (!_foreground) return;
    if (!settings.autoUpdateSubscriptions || subscriptions.isEmpty) return;
    if (phase == CorePhase.starting || phase == CorePhase.stopping) return;
    final now = DateTime.now();
    final due = <Subscription>[];
    for (final sub in subscriptions) {
      if (!sub.autoUpdate || sub.updateIntervalMinutes <= 0) continue;
      final next = sub.nextUpdateAt;
      final cached = await hasCachedProfile(sub.id);
      // 缓存缺失时即使没到期也补一次，否则离线页无节点可显示、内核也无法启动；
      // 刚失败过就等 10 分钟，避免订阅地址失效时每分钟重试一次。
      final failedRecently =
          sub.lastErrorAt != null &&
          now.difference(sub.lastErrorAt!) < const Duration(minutes: 10);
      if ((next != null && next.isBefore(now)) || (!cached && !failedRecently))
        due.add(sub);
    }
    if (due.isEmpty) return;
    _autoUpdating = true;
    var updated = 0;
    var activeUpdated = false;
    for (final sub in due) {
      final ok = await updateSubscription(
        sub.id,
        restartIfActive: false,
        silent: true,
      );
      if (ok) {
        updated++;
        if (sub.id == activeId) activeUpdated = true;
      }
    }
    _autoUpdating = false;
    if (updated > 0) {
      _notice(l10n.get('toast.subscriptionAutoUpdated', [updated]));
      if (activeUpdated && phase == CorePhase.running) {
        await restartCore(silent: true);
      }
    }
  }

  // ------------------------------------------------------------------ backup

  Future<Uint8List> exportBackup() async {
    final profiles = <String, String>{};
    for (final sub in subscriptions) {
      final content = await store.readProfile(sub.id);
      if (content != null && content.trim().isNotEmpty) {
        profiles[sub.id] = content;
      }
    }
    final delays = <String, Map<String, int>>{
      for (final entry in _delaysBySubscription.entries)
        if (entry.value.isNotEmpty) entry.key: Map<String, int>.of(entry.value),
    };
    return BackupService.encode(
      settings: settings,
      subscriptions: subscriptions,
      activeId: activeId,
      selections: selections,
      testedDelays: delays,
      profiles: profiles,
    );
  }

  BackupSnapshot readBackup(Uint8List bytes) => BackupService.decode(bytes);

  /// 恢复是整包替换：先停内核（端口、TUN、系统代理都可能被新设置改变），
  /// 再落盘。不自动重启——Windows TUN 会再弹一次 UAC，交给用户决定。
  Future<void> applyBackup(BackupSnapshot snapshot) async {
    if (isBusy) throw const AppError('generic', detail: 'Core is busy');
    final wasRunning = phase == CorePhase.running;
    if ((phase != CorePhase.stopped || stopUnconfirmed) &&
        !await stopCore(silent: true)) {
      throw const AppError('tunStopUnconfirmed');
    }

    settings = AppSettings.fromJson(snapshot.settings.toJson());
    settings = _oneTakeover(settings).copyWith(
      proxyBypass: AppSettings.normalizeProxyBypass(settings.proxyBypass),
    );
    subscriptions = snapshot.subscriptions;
    activeId = snapshot.activeId;
    selections = snapshot.selections;
    _delaysBySubscription
      ..clear()
      ..addEntries(
        snapshot.testedDelays.entries.map(
          (entry) => MapEntry(entry.key, Map<String, int>.of(entry.value)),
        ),
      );
    _orphanDelays.clear();

    api.configure(port: settings.apiPort, secret: settings.secret);
    await store.saveSettings(settings);
    await store.saveSubscriptions(subscriptions);
    await store.saveActiveId(activeId);
    await store.saveSelections(selections);
    await _persistTestedDelays();
    for (final entry in snapshot.profiles.entries) {
      await store.writeProfile(entry.key, entry.value);
    }
    final validIds = subscriptions.map((sub) => sub.id).toSet();
    await store.ensureCleanProfiles(validIds);
    try {
      startup.reconcile(settings.launchAtStartup);
    } catch (_) {}
    _notify();
    _notice(
      wasRunning
          ? l10n.get('settings.backupImportedRestart', [
              subscriptions.length,
              snapshot.profileCount,
            ])
          : l10n.get('settings.backupImported', [
              subscriptions.length,
              snapshot.profileCount,
            ]),
    );
  }

  // ------------------------------------------------------------------ misc

  String diagnostics() {
    final buffer = StringBuffer()
      ..writeln('${AppInfo.name} ${AppInfo.version}')
      ..writeln(
        'platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      )
      ..writeln('core phase: ${phase.name}')
      ..writeln('core version: ${coreVersion ?? '—'}')
      ..writeln('core binary: ${core.binaryPath ?? '—'}')
      ..writeln('mixed port: ${settings.mixedPort}')
      ..writeln('api port: ${settings.apiPort}')
      ..writeln('subscriptions: ${subscriptions.length}')
      ..writeln('active: ${activeSubscription?.name ?? '—'}')
      ..writeln('proxy groups: ${proxySnapshot.groups.length}')
      ..writeln('connections: ${connectionsSnapshot.connections.length}')
      ..writeln()
      ..writeln('--- core log ---')
      ..writeln(core.log.tail(60));
    return buffer.toString();
  }

  String formatTraffic(int bytes) => formatBytes(bytes);

  void clearLastError() {
    if (lastError == null) return;
    lastError = null;
    _notify();
  }

  void _notice(String message, {bool error = false}) {
    if (_disposed) return;
    if (!_notices.isClosed) _notices.add(AppNotice(message, error: error));
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  Future<void> shutdown() async {
    if (_disposed) return;
    _disposed = true;
    _autoUpdateTimer?.cancel();
    _autoUpdateKick?.cancel();
    _latencyTimer?.cancel();
    _latencyDebounce?.cancel();
    _startupUpdateTimer?.cancel();
    _delaySaveTimer?.cancel();
    _delaySaveTimer = null;
    _stopLiveFeeds();
    // 关窗前把还没落盘的测速结果写完，下次启动不用重测。
    await _persistTestedDelays();
    await _disableSystemProxy();
    await core.shutdown();
    await _notices.close();
  }

  @override
  void dispose() {
    _disposed = true;
    _autoUpdateTimer?.cancel();
    _autoUpdateKick?.cancel();
    _latencyTimer?.cancel();
    _latencyDebounce?.cancel();
    _startupUpdateTimer?.cancel();
    // 落盘只走 shutdown（关窗）与 500ms 防抖写入。dispose 里发起写入会跟
    // 数据目录清理/引擎退出抢文件句柄，收益也只有最后半秒以内的结果。
    _delaySaveTimer?.cancel();
    _delaySaveTimer = null;
    _stopLiveFeeds();
    // On Android the VpnService deliberately outlives the Flutter engine so the
    // tunnel keeps running in the background; only the UI stops here.
    if (!Platform.isAndroid) {
      unawaited(_disableSystemProxy());
      unawaited(core.stop());
    }
    unawaited(_notices.close());
    live.dispose();
    super.dispose();
  }
}

/// 每秒实时帧的中转通知器：ChangeNotifier.notifyListeners 是 protected，控制器这边
/// 需要一个显式入口把它推出去。
class LiveTickNotifier extends ChangeNotifier {
  void tick() => notifyListeners();
}
