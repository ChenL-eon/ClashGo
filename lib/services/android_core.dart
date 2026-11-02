import 'package:flutter/services.dart';

import '../core/app_info.dart';

class AndroidCoreInfo {
  const AndroidCoreInfo({
    required this.nativeLibraryDir,
    required this.binaryPath,
    required this.binaryExists,
  });

  final String nativeLibraryDir;
  final String binaryPath;
  final bool binaryExists;

  factory AndroidCoreInfo.fromMap(Map<Object?, Object?> map) {
    return AndroidCoreInfo(
      nativeLibraryDir: map['nativeLibraryDir'] as String? ?? '',
      binaryPath: map['binaryPath'] as String? ?? '',
      binaryExists: map['binaryExists'] as bool? ?? false,
    );
  }
}

class AndroidCoreStatus {
  const AndroidCoreStatus({
    required this.state,
    required this.pid,
    required this.serviceRunning,
    this.error,
    this.exitCode,
    this.apiPort,
    this.subscriptionId,
    this.startedAt,
    this.splitMode,
    this.splitPackages = const [],
  });

  final String state;
  final int pid;
  final bool serviceRunning;
  final String? error;
  final int? exitCode;
  final int? apiPort;
  final String? subscriptionId;
  final int? startedAt;
  final String? splitMode;
  final List<String> splitPackages;

  bool get isRunning => state == 'running' && pid > 0;
  bool get isStarting => state == 'starting';
  bool get isError => state == 'error';

  /// 与 AppSettings.splitTunnelSignature 同格式；旧版原生层没有这两个字段时为 null。
  String? get splitSignature {
    final mode = splitMode;
    if (mode == null) return null;
    final packages = [...splitPackages]..sort();
    return '$mode:${packages.join(',')}';
  }

  factory AndroidCoreStatus.fromMap(Map<Object?, Object?> map) {
    final rawPackages = map['splitPackages'];
    return AndroidCoreStatus(
      state: map['state'] as String? ?? 'stopped',
      pid: (map['pid'] as num?)?.toInt() ?? -1,
      serviceRunning: map['serviceRunning'] as bool? ?? false,
      error: map['error'] as String?,
      exitCode: (map['exitCode'] as num?)?.toInt(),
      apiPort: (map['apiPort'] as num?)?.toInt(),
      subscriptionId: map['subscriptionId'] as String?,
      startedAt: (map['startedAt'] as num?)?.toInt(),
      splitMode: map['splitMode'] as String?,
      splitPackages: rawPackages is List
          ? rawPackages.whereType<String>().toList(growable: false)
          : const [],
    );
  }
}

// Platform bridge to the native VpnService that owns the tun fd and the mihomo
// child process. Keeping this in Kotlin lets the tunnel outlive the Flutter engine.
class AndroidCore {
  static const MethodChannel _channel = MethodChannel(
    'com.clashgo.clash_go/core',
  );

  static Future<AndroidCoreInfo> info() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('getInfo');
    return AndroidCoreInfo.fromMap(map ?? const {});
  }

  static Future<bool> prepareVpn() async {
    final result = await _channel.invokeMethod<bool>('prepareVpn');
    return result ?? false;
  }

  static Future<void> start({
    required String configPath,
    required String runtimeDir,
    required String binaryPath,
    required String logPath,
    required int apiPort,
    required String? subscriptionId,
    required bool ipv6,
    required String notificationTitle,
    required String notificationText,
    required String notificationStop,
    String apiSecret = '',
    bool bypassPrivate = true,
    String splitTunnelMode = 'all',
    List<String> splitTunnelPackages = const [],
    int mtu = AppInfo.tunMtu,
  }) async {
    await _channel.invokeMethod<bool>('startVpn', {
      'configPath': configPath,
      'runtimeDir': runtimeDir,
      'binaryPath': binaryPath,
      'logPath': logPath,
      'apiPort': apiPort,
      'subscriptionId': subscriptionId,
      'ipv6': ipv6,
      'bypassPrivate': bypassPrivate,
      // all / allow / disallow 与设置模型里的常量同值，原生侧按字符串分派。
      'splitMode': splitTunnelMode,
      'splitPackages': splitTunnelPackages,
      // 通知栏要直接读 mihomo 的 /traffic、/proxies，接口需要同一个 secret。
      'apiSecret': apiSecret,
      // VpnService.setMtu 用的就是这一个值，和 config 里的 tun.mtu 同源。
      'mtu': mtu,
      'notificationTitle': notificationTitle,
      'notificationText': notificationText,
      'notificationStop': notificationStop,
    });
  }

  static Future<void> stop() async {
    await _channel.invokeMethod<bool>('stopVpn');
  }

  static Future<AndroidCoreStatus> status() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>('status');
    return AndroidCoreStatus.fromMap(map ?? const {});
  }

  // 预览内核不走 VpnService：只是应用进程里 fork 出来的 mihomo 子进程，
  // 没有 tun、没有前台服务通知，界面不可见时由 Dart 侧停掉。
  static Future<bool> startPreview({
    required String configPath,
    required String runtimeDir,
    required String binaryPath,
    required String logPath,
    required int apiPort,
    required String? subscriptionId,
  }) async {
    final result = await _channel.invokeMethod<bool>('startPreview', {
      'configPath': configPath,
      'runtimeDir': runtimeDir,
      'binaryPath': binaryPath,
      'logPath': logPath,
      'apiPort': apiPort,
      'subscriptionId': subscriptionId,
    });
    return result ?? false;
  }

  static Future<void> stopPreview() async {
    await _channel.invokeMethod<bool>('stopPreview');
  }

  static Future<AndroidCoreStatus> previewStatus() async {
    final map = await _channel.invokeMapMethod<Object?, Object?>(
      'previewStatus',
    );
    return AndroidCoreStatus.fromMap(map ?? const {});
  }

  static Future<void> cleanupPreview(String runtimeDir) async {
    await _channel.invokeMethod<bool>('cleanupPreview', {
      'runtimeDir': runtimeDir,
    });
  }
}
