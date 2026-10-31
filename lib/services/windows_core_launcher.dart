import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../core/app_paths.dart';
import '../core/errors.dart';

/// Windows 的 TUN 必须管理员：建虚拟网卡、改路由表都是提权操作。
/// GUI 本身不提权（整个界面提权会连带拖拽、剪贴板和其他窗口交互一起变别扭），
/// 所以这里只把内核提权起来。
///
/// 两个绕不开的坑决定了这套"文件协议"的形状：
/// 1. `ShellExecuteExW(verb: runas)` 起来的进程拿不到可继承的管道句柄——普通权限的
///    GUI 没法读提权子进程的 stdout。所以内核输出只能落文件，再由 GUI 追着读。
/// 2. 普通权限进程 kill 不掉提权进程，`Process.kill()` 和 `taskkill` 都会吃 Access
///    Denied。所以停止信号也走文件：GUI 写 stop.flag，提权的监护进程自己轮到自己收手，
///    这样"关隧道"不需要第二次 UAC。
///
/// 监护进程用 powershell 而不是直接把 mihomo 提权，是因为还得有人写 pid、盯 stop.flag、
/// 在 mihomo 自己崩掉时把标志文件收干净。命令行用 -EncodedCommand（UTF-16LE 的 base64）
/// 传，路径里的引号和空格就都没有解释权，也顺带堵死命令注入。
class WindowsCoreLauncher {
  WindowsCoreLauncher(this.paths);

  final AppPaths paths;

  /// ShellExecuteEx 返回 FALSE 且 GetLastError=1223：用户在 UAC 上点了"否"。
  static const _errorCancelled = 1223;

  /// 监护进程等内核 PID 的上限；驱动首次安装会慢，但不能无限等。
  static const _pidTimeout = Duration(seconds: 12);

  /// 每个日志文件读到哪了。偏移量记在这里而不是调用方，因为"文件被截断"这个判断
  /// 只有知道上一轮位置的人才做得到，而这两个文件本来就是这套协议的一部分。
  final Map<String, int> _logOffsets = {};

  static String psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  /// 提权后真正跑起来的循环：起内核、报 PID、盯停止标志、收尾。
  ///
  /// 每一步都往 `$sup` 写一行流水账。提权那一层没有控制台、管道又继承不回来，
  /// `Start-Process` 抛的异常和内核的退出码如果不自己落盘，GUI 这边永远只能看到
  /// "没有网卡"这一个事实，分不清是没起来、起来了立刻死了，还是根本没执行到。
  static String supervisorScript({
    required String mihomoPath,
    required String runtimeDir,
    required String configPath,
    required String stdoutPath,
    required String stderrPath,
    required String pidPath,
    required String stopFlagPath,
    required String supervisorLogPath,
  }) {
    return '''
\$ErrorActionPreference='SilentlyContinue'
\$mihomo=${psQuote(mihomoPath)}
\$dir=${psQuote(runtimeDir)}
\$cfg=${psQuote(configPath)}
\$out=${psQuote(stdoutPath)}
\$err=${psQuote(stderrPath)}
\$pidFile=${psQuote(pidPath)}
\$stop=${psQuote(stopFlagPath)}
\$sup=${psQuote(supervisorLogPath)}
Remove-Item -LiteralPath \$stop -Force
Remove-Item -LiteralPath \$pidFile -Force
Remove-Item -LiteralPath \$sup -Force
function Write-Sup([string]\$message) {
  try { Add-Content -LiteralPath \$sup -Value ((Get-Date).ToString('o') + ' ' + \$message) } catch {}
}
Write-Sup "start mihomo=\$mihomo dir=\$dir cfg=\$cfg"
try {
  \$p=Start-Process -FilePath \$mihomo -ArgumentList '-d', \$dir, '-f', \$cfg -WorkingDirectory \$dir -NoNewWindow -RedirectStandardOutput \$out -RedirectStandardError \$err -PassThru
} catch {
  Write-Sup "Start-Process threw: \$(\$_.Exception.GetType().Name): \$(\$_.Exception.Message)"
  exit 1
}
if (-not \$p) { Write-Sup 'Start-Process returned no process object'; exit 1 }
Write-Sup "core pid=\$(\$p.Id)"
Set-Content -LiteralPath \$pidFile -Value \$p.Id -NoNewline
while (-not (Test-Path -LiteralPath \$stop)) {
  if (\$p.HasExited) {
    \$code='unavailable'
    try { \$code=\$p.ExitCode } catch {}
    \$info=Get-Item -LiteralPath \$out -ErrorAction SilentlyContinue
    Write-Sup "core exited on its own code=\$code stdoutBytes=\$(\$info.Length)"
    break
  }
  Start-Sleep -Milliseconds 250
}
if (-not \$p.HasExited) {
  Write-Sup 'stop requested, killing core'
  Stop-Process -Id \$p.Id -Force
  Write-Sup 'core killed'
}
Remove-Item -LiteralPath \$pidFile -Force
Remove-Item -LiteralPath \$stop -Force
Write-Sup 'supervisor done'
''';
  }

  /// `-EncodedCommand` 要的是 UTF-16LE 字节的 base64，不是 UTF-8。
  static String encodeCommand(String script) {
    final units = script.codeUnits;
    final bytes = Uint8List(units.length * 2);
    for (var i = 0; i < units.length; i++) {
      bytes[i * 2] = units[i] & 0xff;
      bytes[i * 2 + 1] = (units[i] >> 8) & 0xff;
    }
    return base64Encode(bytes);
  }

  static String _powershellPath() {
    final root = Platform.environment['SystemRoot'] ?? r'C:\Windows';
    final path = '$root\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
    return File(path).existsSync() ? path : 'powershell.exe';
  }

  /// 拉起提权的监护进程并返回内核 PID。
  Future<int> start({required String mihomoPath, required String configPath}) async {
    final runtimeDir = paths.runtimeDir.path;
    clearProtocolFiles();

    final script = supervisorScript(
      mihomoPath: mihomoPath,
      runtimeDir: runtimeDir,
      configPath: configPath,
      stdoutPath: paths.elevatedStdoutFile.path,
      stderrPath: paths.elevatedStderrFile.path,
      pidPath: paths.elevatedPidFile.path,
      stopFlagPath: paths.stopFlagFile.path,
      supervisorLogPath: paths.elevatedSupervisorFile.path,
    );
    final encoded = encodeCommand(script);
    final parameters = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle '
        'Hidden -EncodedCommand $encoded';

    // Arena 负责回收四个字符串；结构体本身用完立刻释放，免得提权窗口已经弹出来了
    // 还占着这块内存。
    final arena = Arena();
    try {
      final info = arena<SHELLEXECUTEINFO>();
      info.ref.cbSize = sizeOf<SHELLEXECUTEINFO>();
      // 不带 SEE_MASK_NOCLOSEPROCESS：那样 ShellExecuteEx 会交回一条提权进程句柄，
      // 而 GUI 这边根本不打算用它（内核 PID 由监护进程写文件），留着只会有个
      // 必须记得 CloseHandle 的裸句柄。
      info.ref.fMask = 0;
      info.ref.lpVerb = PWSTR('runas'.toNativeUtf16(allocator: arena));
      info.ref.lpFile = PWSTR(_powershellPath().toNativeUtf16(allocator: arena));
      info.ref.lpParameters = PWSTR(parameters.toNativeUtf16(allocator: arena));
      info.ref.lpDirectory = PWSTR(runtimeDir.toNativeUtf16(allocator: arena));
      info.ref.nShow = SW_HIDE;
      final result = ShellExecuteEx(info);
      if (!result.value) {
        if (result.error == _errorCancelled) throw const AppError('tunUacDenied');
        throw AppError('tunElevateFailed', detail: 'ShellExecuteEx error ${result.error}');
      }
    } finally {
      arena.releaseAll();
    }

    paths.elevatedFlagFile.writeAsStringSync('elevated');
    return _waitForCorePid();
  }

  Future<int> _waitForCorePid() async {
    final deadline = DateTime.now().add(_pidTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (paths.elevatedPidFile.existsSync()) {
        final value = int.tryParse(paths.elevatedPidFile.readAsStringSync().trim());
        // 监护进程写文件不是原子的，读到半截就再等一轮。
        if (value != null && value > 0) return value;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw const AppError(
      'tunElevateFailed',
      detail: '监护进程没有回报内核 PID：可能被安全软件拦下，也可能内核当场退出',
    );
  }

  /// 请监护进程收手，并等它把内核带走。普通权限这边能做的只有写文件。
  /// 返回 true 只有一种含义：监护进程自己把 PID 文件删了，也就是它确实接手了这次停止。
  /// 超时没等到说明那个提权进程已经不在了（崩溃后被系统回收，或压根没起来过），
  /// 这时候调用方不能当成"隧道已关"——路由可能还挂着。
  Future<bool> requestStop({Duration timeout = const Duration(seconds: 10)}) async {
    if (!paths.elevatedFlagFile.existsSync()) return false;
    try {
      paths.stopFlagFile.writeAsStringSync('stop');
    } catch (_) {
      return false;
    }
    var acknowledged = false;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!paths.elevatedPidFile.existsSync()) {
        acknowledged = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    // 超时分支意味着监护进程已经没了，stop.flag 留着只会让下一次启动误判，清掉。
    _tryDelete(paths.elevatedFlagFile);
    _tryDelete(paths.stopFlagFile);
    _tryDelete(paths.elevatedPidFile);
    return acknowledged;
  }

  /// 上一次崩溃留下的提权内核还在跑：先试文件协议，行就不必再弹 UAC。
  bool get hasStaleElevatedCore => paths.elevatedFlagFile.existsSync() && paths.elevatedPidFile.existsSync();

  /// 把上一轮的协议文件清干净。留着它们，这次的"等 PID"会立刻读到脏数据，
  /// 而残留的 stop.flag 更坏：监护进程一起来就看到停止请求，直接把自己收掉。
  void clearProtocolFiles() {
    _tryDelete(paths.elevatedPidFile);
    _tryDelete(paths.stopFlagFile);
    _tryDelete(paths.elevatedFlagFile);
    // 上一轮的流水账必须跟着清：偏移量一归零，留着旧文件就会把上一次的死因当成
    // 这一次的，而这两次往往根本不是同一个原因。
    _tryDelete(paths.elevatedStdoutFile);
    _tryDelete(paths.elevatedStderrFile);
    _tryDelete(paths.elevatedSupervisorFile);
    _logOffsets.clear();
  }

  /// 交回提权内核这两个文件里新写出来的整行——GUI 这边唯一能看到内核说了什么的地方。
  Future<List<String>> drainLogs() async => [
        ...await drainLogLines(paths.elevatedStdoutFile),
        ...await drainLogLines(paths.elevatedStderrFile),
        ...await drainLogLines(paths.elevatedSupervisorFile),
      ];

  /// 只按 0x0A 切行，而且只读到最后一个换行为止。半行留给下一轮：把一条错误日志
  /// 拆成两条，日志页上看到的就是一条不存在的报错。0x0A 不会出现在 UTF-8 多字节
  /// 序列中间，所以停在换行后面也不会截断中文。
  Future<List<String>> drainLogLines(File file) async {
    if (!await file.exists()) return const [];
    final raf = await file.open(mode: FileMode.read);
    try {
      final length = await raf.length();
      var offset = _logOffsets[file.path] ?? 0;
      // 监护进程每轮启动都重写这两个文件，长度比上次读到的位置还短就是被截断了。
      if (offset > length) offset = 0;
      final available = length - offset;
      if (available <= 0) {
        _logOffsets[file.path] = offset;
        return const [];
      }
      await raf.setPosition(offset);
      final bytes = await raf.read(available > 64 * 1024 ? 64 * 1024 : available);
      final lastBreak = bytes.lastIndexWhere((byte) => byte == 0x0A);
      if (lastBreak < 0) {
        _logOffsets[file.path] = offset;
        return const [];
      }
      final consumed = lastBreak + 1;
      _logOffsets[file.path] = offset + consumed;
      final text = utf8.decode(bytes.sublist(0, consumed), allowMalformed: true);
      return const LineSplitter().convert(text).where((line) => line.trim().isNotEmpty).toList();
    } finally {
      await raf.close();
    }
  }

  void _tryDelete(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}
