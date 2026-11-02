import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/app_info.dart';
import '../core/app_paths.dart';
import '../core/core_log.dart';
import '../core/errors.dart';
import 'android_core.dart';
import 'tun_readiness.dart';
import 'windows_core_launcher.dart';

class CoreManager {
  CoreManager(this.paths, this.log);

  final AppPaths paths;
  final CoreLog log;
  Process? _process;
  Timer? _androidMonitor;
  bool _androidRunning = false;
  bool _androidStopping = false;
  bool _androidPolling = false;
  bool _monitorEnabled = true;
  int? _androidPid;

  // Windows TUN：内核跑在提权上下文里，这边既拿不到它的句柄也 kill 不掉它，
  // 存活与日志全靠"文件协议 + 轮询"，形状和安卓那条 VpnService 通路最像。
  Timer? _elevatedMonitor;
  int? _elevatedPid;
  bool _elevatedStopping = false;
  bool _elevatedPolling = false;
  WindowsCoreLauncher? _elevatedLauncher;
  final TunReadiness _tun = TunReadiness();

  void Function(int code)? onExit;
  void Function()? onExternalStop;

  WindowsCoreLauncher get _elevated =>
      _elevatedLauncher ??= WindowsCoreLauncher(paths);

  Process? get process => _process;
  int? get pid => _process?.pid ?? _androidPid ?? _elevatedPid;
  String? get binaryPath => paths.coreBinaryPath;
  bool get supported => Platform.isWindows || Platform.isAndroid;
  String get runtimeDir => paths.runtimeDir.path;

  Future<void> initializePlatform() async {
    if (!Platform.isAndroid) return;
    final info = await AndroidCore.info();
    AppPaths.androidNativeLibraryDir = info.nativeLibraryDir;
    if (!info.binaryExists) {
      log.append('mihomo binary is missing at ${info.binaryPath}');
    }
  }

  Future<void> prepareRuntime() async {
    final source = paths.bundledGeodataDir;
    if (source == null) return;
    for (final name in const [
      'geoip.metadb',
      'geosite.dat',
      'GeoIP.dat',
      'ASN.mmdb',
    ]) {
      final src = File(p.join(source, name));
      if (!await src.exists()) continue;
      final dst = File(p.join(paths.runtimeDir.path, name));
      final needsCopy =
          !await dst.exists() || await dst.length() != await src.length();
      if (!needsCopy) continue;
      try {
        await src.copy(dst.path);
        log.append('Prepared geodata $name');
      } catch (error) {
        log.append('Failed to copy geodata $name: $error');
      }
    }
  }

  Future<bool> isPortAvailable(int port) async {
    ServerSocket? socket;
    try {
      socket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      return true;
    } on SocketException {
      return false;
    } finally {
      await socket?.close();
    }
  }

  Future<bool> waitPortAvailable(int port, {int attempts = 6}) async {
    for (var i = 0; i < attempts; i++) {
      if (await isPortAvailable(port)) return true;
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    return false;
  }

  Future<void> writeConfig(String content) async {
    try {
      await paths.configFile.writeAsString(content, flush: true);
    } catch (error) {
      throw AppError('saveConfig', detail: error.toString());
    }
  }

  Future<void> start({
    required String config,
    required int mixedPort,
    required int apiPort,
    String? subscriptionId,
    bool ipv6 = false,
    bool windowsTun = false,
    String? notificationTitle,
    String? notificationText,
    String? notificationStop,
    String apiSecret = '',
    String splitTunnelMode = 'all',
    List<String> splitTunnelPackages = const [],
    int tunMtu = AppInfo.tunMtu,
  }) async {
    if (Platform.isAndroid) {
      await _startAndroid(
        config: config,
        mixedPort: mixedPort,
        apiPort: apiPort,
        subscriptionId: subscriptionId,
        ipv6: ipv6,
        notificationTitle: notificationTitle,
        notificationText: notificationText,
        notificationStop: notificationStop,
        apiSecret: apiSecret,
        splitTunnelMode: splitTunnelMode,
        splitTunnelPackages: splitTunnelPackages,
        tunMtu: tunMtu,
      );
      return;
    }
    if (!Platform.isWindows) throw const AppError('unsupportedPlatform');
    final exe = binaryPath;
    if (exe == null) throw const AppError('coreMissing');

    await prepareRuntime();
    await writeConfig(config);
    // 先清掉上次崩溃留下的内核：它往往正占着 mixed/api 端口，先探测端口
    // 会把"自己的旧进程"误报成 portInUse，永远起不来。
    await killStale();
    if (!await waitPortAvailable(mixedPort))
      throw AppError('portInUse', statusCode: mixedPort);
    if (!await waitPortAvailable(apiPort))
      throw AppError('portInUse', statusCode: apiPort);

    log.reset();
    log.append('Using core $exe');
    log.append('Runtime ${paths.runtimeDir.path}');
    log.append('Mixed port $mixedPort, API port $apiPort');

    if (windowsTun) {
      await _startWindowsElevated(exe);
      return;
    }

    try {
      final process = await Process.start(exe, [
        '-d',
        paths.runtimeDir.path,
        '-f',
        paths.configFile.path,
      ], workingDirectory: paths.runtimeDir.path);
      _process = process;
      await paths.pidFile.writeAsString('${process.pid}');
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(log.append);
      process.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(log.append);
      unawaited(
        process.exitCode.then((code) {
          if (identical(_process, process)) {
            _process = null;
            log.append('Core exited with code $code');
            onExit?.call(code);
          }
        }),
      );
    } on AppError {
      rethrow;
    } catch (error) {
      throw AppError('startFailed', detail: error.toString());
    }
  }

  /// Windows 的 TUN 通路：内核必须以管理员身份跑（建虚拟网卡、改路由表、劫持 53），
  /// 所以这里起的不是进程而是一套文件协议——提权的监护进程负责起内核并把 PID 写回来。
  ///
  /// 和普通权限直接 `Process.start` 的区别全都来自"跨不过的完整性级别"：
  /// - stdout 管道继承不过来 → 输出落文件，这边按偏移量追着读；
  /// - `process.kill()` 打不动高完整性进程 → 停止靠写 stop.flag；
  /// - `OpenProcess` 连查询权限都拿不到 → 存活只能看监护进程留下的 PID 文件还在不在。
  ///   监护进程自己每 250ms 盯一次内核退出，退出时会把 PID 文件删掉，所以它的消失
  ///   就是"内核没了"的信号；代价是监护进程被人为杀死时这里会误报存活——
  ///   那种情况下端口和控制接口也一起没了，`_waitForApi` 与后续请求会把真实故障带回来。
  Future<void> _startWindowsElevated(String exe) async {
    final pid = await _elevated.start(
      mihomoPath: exe,
      configPath: paths.configFile.path,
    );
    _elevatedPid = pid;
    log.append('Elevated core started (pid $pid)');
    // 就绪探测排在存活轮询之前：这几十秒里日志由下面这个循环自己追读，
    // 而内核如果真在探测期间掉了，探测那一侧的超时/日志判据会先给出原因。
    final problem = await _tun.wait(
      timeout: AppInfo.tunReadyTimeout,
      pollLogs: _ingestElevatedLogs,
    );
    if (problem != null) {
      // 不留下"看起来在跑"的状态：调用方接住这个错误就会走 core.stop()，
      // 提权内核和它的标志文件一起收掉。
      log.append('TUN is not ready: $problem');
      throw AppError('tunNotReady', detail: problem);
    }
    log.append('TUN interface is up');
    _startElevatedMonitor();
  }

  void _startElevatedMonitor() {
    _elevatedMonitor?.cancel();
    if (!_monitorEnabled) return;
    _elevatedMonitor = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollElevatedCore(),
    );
  }

  Future<void> _pollElevatedCore() async {
    if (_elevatedPid == null || _elevatedPolling) return;
    _elevatedPolling = true;
    try {
      await _ingestElevatedLogs();
      if (paths.elevatedPidFile.existsSync()) return;
      if (_elevatedStopping) return;
      _elevatedPid = null;
      _elevatedMonitor?.cancel();
      _elevatedMonitor = null;
      log.append('Elevated core is gone');
      onExit?.call(-1);
    } finally {
      _elevatedPolling = false;
    }
  }

  /// 提权内核的输出只存在于文件里（管道跨不过完整性级别），补进 CoreLog 之后
  /// 日志页和启动失败时的 tail 提示才有东西可显示。切行和偏移量都在 launcher 里。
  Future<List<String>> _ingestElevatedLogs() async {
    final lines = await _elevated.drainLogs();
    for (final line in lines) {
      log.append(line);
    }
    return lines;
  }

  Future<void> _startAndroid({
    required String config,
    required int mixedPort,
    required int apiPort,
    required String? subscriptionId,
    required bool ipv6,
    required String? notificationTitle,
    required String? notificationText,
    required String? notificationStop,
    required String apiSecret,
    required String splitTunnelMode,
    required List<String> splitTunnelPackages,
    required int tunMtu,
  }) async {
    final exe = binaryPath;
    if (exe == null) throw const AppError('coreMissing');
    if (!await waitPortAvailable(mixedPort))
      throw AppError('portInUse', statusCode: mixedPort);
    if (!await waitPortAvailable(apiPort))
      throw AppError('portInUse', statusCode: apiPort);

    await prepareRuntime();
    await writeConfig(config);
    try {
      if (await paths.androidCoreLogFile.exists()) {
        await paths.androidCoreLogFile.writeAsString('', flush: true);
      }
    } catch (_) {}

    log.reset();
    log.append('Using core $exe');
    log.append('Runtime ${paths.runtimeDir.path}');
    log.append('Mixed port $mixedPort, API port $apiPort');

    final prepared = await AndroidCore.prepareVpn();
    if (!prepared) throw const AppError('vpnPermissionDenied');

    await AndroidCore.start(
      configPath: paths.configFile.path,
      runtimeDir: paths.runtimeDir.path,
      binaryPath: exe,
      logPath: paths.androidCoreLogFile.path,
      apiPort: apiPort,
      subscriptionId: subscriptionId,
      ipv6: ipv6,
      notificationTitle: notificationTitle ?? 'ClashGo',
      notificationText: notificationText ?? 'VPN connected',
      notificationStop: notificationStop ?? 'Stop',
      apiSecret: apiSecret,
      splitTunnelMode: splitTunnelMode,
      splitTunnelPackages: splitTunnelPackages,
      mtu: tunMtu,
    );

    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      final status = await AndroidCore.status();
      if (status.isRunning) {
        _androidRunning = true;
        _androidPid = status.pid;
        log.append('mihomo started (pid ${status.pid})');
        await _ingestAndroidLog();
        _startAndroidMonitor();
        return;
      }
      if (status.isError) {
        await _ingestAndroidLog();
        throw AppError(
          'startFailed',
          detail: _androidFailureDetail(status.error),
        );
      }
      if (status.state == 'stopped' && !status.serviceRunning) {
        await _ingestAndroidLog();
        throw AppError('startFailed', detail: _androidFailureDetail(null));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await _ingestAndroidLog();
    throw const AppError(
      'startTimeout',
      detail: 'Android VPN service did not report a running core',
    );
  }

  String _androidFailureDetail(String? message) {
    final parts = <String>[
      if (message != null && message.trim().isNotEmpty) message.trim(),
      log.tail(14),
    ];
    return parts.where((part) => part.isNotEmpty && part != '—').join('\n');
  }

  Future<void> _ingestAndroidLog() async {
    try {
      final lines = await _readLogTail(paths.androidCoreLogFile);
      for (final line in lines) {
        if (line.trim().isNotEmpty) log.append(line);
      }
    } catch (_) {}
  }

  Future<List<String>> _readLogTail(
    File file, {
    int maxBytes = 64 * 1024,
    int maxLines = 160,
  }) async {
    if (!await file.exists()) return const [];
    final raf = await file.open(mode: FileMode.read);
    try {
      final length = await raf.length();
      if (length <= 0) return const [];
      final start = length > maxBytes ? length - maxBytes : 0;
      await raf.setPosition(start);
      final bytes = await raf.read(length - start);
      final text = utf8.decode(bytes, allowMalformed: true);
      final lines = const LineSplitter().convert(text);
      if (start > 0 && lines.isNotEmpty) lines.removeAt(0);
      if (lines.length > maxLines) {
        return lines.sublist(lines.length - maxLines);
      }
      return lines;
    } finally {
      await raf.close();
    }
  }

  // 应用在后台时暂停内核状态轮询，回到前台后立即补一次状态再恢复轮询。
  void setMonitorEnabled(bool enabled) {
    if (_monitorEnabled == enabled) return;
    _monitorEnabled = enabled;
    if (!enabled) {
      _androidMonitor?.cancel();
      _androidMonitor = null;
      // 提权内核没有句柄可以等退出事件，只能轮询——那这条轮询线也必须跟着后台停，
      // 否则最小化之后每两秒仍要唤醒一次去做同一次"文件在不在"的检查。
      _elevatedMonitor?.cancel();
      _elevatedMonitor = null;
      return;
    }
    if (_androidRunning) {
      _startAndroidMonitor();
      unawaited(_pollAndroidStatus());
    }
    if (_elevatedPid != null) {
      _startElevatedMonitor();
      unawaited(_pollElevatedCore());
    }
  }

  void _startAndroidMonitor() {
    _androidMonitor?.cancel();
    if (!_monitorEnabled) return;
    _androidMonitor = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollAndroidStatus(),
    );
  }

  Future<void> _pollAndroidStatus() async {
    if (!_androidRunning || _androidPolling || _androidStopping) return;
    _androidPolling = true;
    try {
      final status = await AndroidCore.status();
      if (status.isRunning) {
        _androidPid = status.pid;
        return;
      }
      if (status.state == 'stopping' || status.state == 'starting') return;
      _androidRunning = false;
      _androidPid = null;
      _androidMonitor?.cancel();
      _androidMonitor = null;
      await _ingestAndroidLog();
      if (_androidStopping) return;
      if (status.isError) {
        onExit?.call(status.exitCode ?? -1);
      } else {
        onExternalStop?.call();
      }
    } catch (_) {
      // Keep polling; a transient platform-channel failure is not a core exit.
    } finally {
      _androidPolling = false;
    }
  }

  Future<AndroidCoreStatus?> attachIfRunning({
    required String? subscriptionId,
    required int apiPort,
  }) async {
    if (!Platform.isAndroid) return null;
    AndroidCoreStatus status;
    try {
      status = await AndroidCore.status();
    } catch (_) {
      return null;
    }
    if (!status.isRunning) {
      if (status.isError) {
        try {
          await AndroidCore.stop();
        } catch (_) {}
      }
      return null;
    }
    if (status.apiPort != apiPort || status.subscriptionId != subscriptionId) {
      log.append(
        'Stopping stale Android core (subscription=${status.subscriptionId}, apiPort=${status.apiPort})',
      );
      try {
        await AndroidCore.stop();
      } catch (_) {}
      return null;
    }
    _androidRunning = true;
    _androidPid = status.pid;
    log.append('Attached to running Android core (pid ${status.pid})');
    await _ingestAndroidLog();
    _startAndroidMonitor();
    return status;
  }

  /// 返回 false 只有一个含义：提权内核的停止请求没被监护进程确认。
  /// 普通进程既 kill 不动它也看不到它，调用方不能把这次停止当成成功——
  /// 系统里的 TUN 路由和 DNS 劫持可能还挂着。
  Future<bool> stop({bool removePid = true}) async {
    if (Platform.isAndroid) {
      await _stopAndroid(removePid: removePid);
      return true;
    }
    final process = _process;
    _process = null;
    if (process != null) {
      log.append('Stopping core (pid ${process.pid})');
      try {
        process.kill();
      } catch (_) {}
      try {
        await process.exitCode.timeout(const Duration(seconds: 6));
      } on TimeoutException {
        await _killTree(process.pid);
      } catch (_) {
        await _killTree(process.pid);
      }
    }
    if (removePid) await _removePidFile();
    return _stopElevated();
  }

  /// 关隧道不能再来一次 UAC：这边只写停止标志，提权的监护进程自己看到、自己把内核带走。
  Future<bool> _stopElevated() async {
    if (_elevatedPid == null && !paths.elevatedFlagFile.existsSync()) return true;
    final pid = _elevatedPid;
    _elevatedStopping = true;
    _elevatedMonitor?.cancel();
    _elevatedMonitor = null;
    log.append(
      'Requesting elevated core stop${pid == null ? '' : ' (pid $pid)'}',
    );
    final acknowledged = await _elevated.requestStop();
    log.append(
      acknowledged
          ? 'Elevated core stopped'
          : 'Elevated supervisor did not acknowledge the stop request',
    );
    await _ingestElevatedLogs();
    _elevatedPid = null;
    _elevatedStopping = false;
    return acknowledged;
  }

  Future<void> _stopAndroid({required bool removePid}) async {
    _androidStopping = true;
    _androidMonitor?.cancel();
    _androidMonitor = null;
    await _androidStoppingGranted();
    _androidRunning = false;
    _androidPid = null;
    _androidStopping = false;
    if (removePid) await _removePidFile();
  }

  Future<void> _androidStoppingGranted() async {
    AndroidCoreStatus? status;
    try {
      status = await AndroidCore.status();
    } catch (_) {}
    if (status == null) return;
    final wasRunning =
        _androidRunning ||
        status.isRunning ||
        status.state == 'starting' ||
        status.state == 'stopping' ||
        status.serviceRunning;
    if (!wasRunning) return;
    log.append('Stopping Android core (pid ${status.pid})');
    try {
      await AndroidCore.stop();
    } catch (error) {
      log.append('Failed to stop Android core: $error');
    }
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final current = await AndroidCore.status();
        if (!current.serviceRunning || current.state == 'stopped') break;
      } catch (_) {
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await _ingestAndroidLog();
  }

  Future<void> killStale() async {
    await _killStaleElevated();
    if (!await paths.pidFile.exists()) return;
    int? pid;
    try {
      pid = int.tryParse((await paths.pidFile.readAsString()).trim());
    } catch (_) {}
    if (pid == null || !Platform.isWindows) {
      await _removePidFile();
      return;
    }
    try {
      final result = await Process.run('tasklist', [
        '/FI',
        'PID eq $pid',
        '/FO',
        'CSV',
        '/NH',
      ]);
      final output = '${result.stdout}'.toLowerCase();
      if (output.contains('mihomo')) {
        log.append('Killing stale core process (pid $pid)');
        await _killTree(pid);
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
    } catch (_) {}
    await _removePidFile();
  }

  /// 上次崩溃留下的提权内核：普通权限 kill 不动它，只能靠监护进程接手。
  /// 监护进程自己也没了的时候（它被任务管理器杀掉、或随上一次会话一起崩掉），
  /// 这里等不到 PID 文件消失——只能如实记一行，路由和 DNS 得由用户自己收尾，
  /// 不能假装关掉：那样界面上的"已停止"和系统里那条默认路由是两回事。
  Future<void> _killStaleElevated() async {
    if (!_elevated.hasStaleElevatedCore) return;
    log.append('Stopping stale elevated core');
    final acknowledged = await _elevated.requestStop(
      timeout: const Duration(seconds: 6),
    );
    if (!acknowledged) {
      log.append(
        'Stale elevated core is still running: its supervisor is gone, '
        'and a non-elevated process cannot kill it. Kill mihomo from an elevated terminal.',
      );
    }
  }

  Future<void> _killTree(int pid) async {
    if (!Platform.isWindows) {
      try {
        Process.killPid(pid);
      } catch (_) {}
      return;
    }
    try {
      await Process.run('taskkill', ['/PID', '$pid', '/T', '/F']);
    } catch (_) {}
  }

  Future<void> _removePidFile() async {
    try {
      if (await paths.pidFile.exists()) await paths.pidFile.delete();
    } catch (_) {}
  }

  Future<void> clearRuntimeArtifacts() async {
    try {
      if (await paths.configFile.exists()) await paths.configFile.delete();
    } catch (error) {
      log.append('Failed to remove generated config: $error');
    }
    final providers = Directory(p.join(paths.runtimeDir.path, 'providers'));
    try {
      if (await providers.exists()) await providers.delete(recursive: true);
    } catch (error) {
      log.append('Failed to remove provider cache: $error');
    }
  }

  Future<void> shutdown() async {
    await stop();
    await log.flush();
  }
}
