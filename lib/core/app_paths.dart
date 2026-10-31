import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppPaths {
  AppPaths._({
    required this.supportDir,
    required this.runtimeDir,
    required this.profilesDir,
    required this.subscriptionsDir,
  });

  final Directory supportDir;
  final Directory runtimeDir;
  final Directory profilesDir;
  final Directory subscriptionsDir;

  static Future<AppPaths> create() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(support.path);
    final runtime = Directory(p.join(root.path, 'runtime'));
    final profiles = Directory(p.join(root.path, 'subscriptions', 'profiles'));
    final subscriptions = Directory(p.join(root.path, 'subscriptions'));
    await Future.wait([
      root.create(recursive: true),
      runtime.create(recursive: true),
      profiles.create(recursive: true),
      subscriptions.create(recursive: true),
      Directory(p.join(root.path, 'proxies')).create(recursive: true),
    ]);
    return AppPaths._(
      supportDir: root,
      runtimeDir: runtime,
      profilesDir: profiles,
      subscriptionsDir: subscriptions,
    );
  }

  File get settingsFile => File(p.join(supportDir.path, 'settings.json'));
  File get subscriptionsFile => File(p.join(subscriptionsDir.path, 'subscriptions_list.json'));
  File get activeSubscriptionFile => File(p.join(subscriptionsDir.path, 'selection_state.json'));
  File get selectionsFile => File(p.join(supportDir.path, 'proxies', 'selection_state.json'));
  File get configFile => File(p.join(runtimeDir.path, 'config.yaml'));
  File get pidFile => File(p.join(runtimeDir.path, 'mihomo.pid'));
  File get coreLogFile => File(p.join(runtimeDir.path, 'core.log'));

  /// Windows TUN（提权内核）通路专用。提权进程的管道句柄继承不到普通权限的 GUI，
  /// 普通权限也 kill 不掉它，所以内核输出落文件、控制信号也走文件。
  File get elevatedStdoutFile => File(p.join(runtimeDir.path, 'mihomo.stdout.log'));
  File get elevatedStderrFile => File(p.join(runtimeDir.path, 'mihomo.stderr.log'));

  /// 监护进程自己的流水账。提权那一层的失败全是静默的——没有控制台、管道又接不过来，
  /// 内核退出码和 `Start-Process` 的异常只能靠它自己写下来才有人看得见。
  File get elevatedSupervisorFile => File(p.join(runtimeDir.path, 'mihomo.supervisor.log'));
  File get elevatedPidFile => File(p.join(runtimeDir.path, 'mihomo.elevated.pid'));
  File get stopFlagFile => File(p.join(runtimeDir.path, 'core-stop.flag'));
  File get elevatedFlagFile => File(p.join(runtimeDir.path, 'core-elevated.flag'));
  File get androidCoreLogFile => File(p.join(runtimeDir.path, 'mihomo.log'));

  static String? androidNativeLibraryDir;

  File profileFile(String id) => File(p.join(profilesDir.path, '$id.yaml'));

  String get executableDir => p.dirname(Platform.resolvedExecutable);

  String? get coreBinaryPath {
    if (Platform.isWindows) {
      final path = p.join(executableDir, 'core', 'mihomo.exe');
      return File(path).existsSync() ? path : null;
    }
    if (Platform.isAndroid) {
      final dir = androidNativeLibraryDir;
      if (dir == null || dir.isEmpty) return null;
      // The Android build packages the mihomo executable as a native library so
      // the installer extracts it into executable nativeLibraryDir storage.
      final path = p.join(dir, 'libmihomo.so');
      return File(path).existsSync() ? path : null;
    }
    return null;
  }

  String? get bundledGeodataDir {
    if (!Platform.isWindows) return null;
    final path = p.join(executableDir, 'core', 'geodata');
    return Directory(path).existsSync() ? path : null;
  }
}
