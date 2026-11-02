import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/core_log.dart';
import 'package:clash_go/services/core_manager.dart';
import 'package:clash_go/services/windows_core_launcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// Windows TUN 的提权通路要真的点一次 UAC 才能验完，那一步只能在用户机器上发生。
/// 但它底下这套"文件协议"是纯逻辑，可以在这里钉死三件事：
/// 命令行怎么编码（会不会被注入）、监护脚本长什么样（内核输出落到哪、谁删 PID 文件）、
/// 以及停止请求的返回值到底代不代表"隧道已经关掉"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('windows tun supervisor script', () {
    test('paths are single-quoted and embedded quotes doubled', () {
      expect(WindowsCoreLauncher.psQuote(r"C:\a b\mihomo.exe"), r"'C:\a b\mihomo.exe'");
      // PowerShell 里单引号串中想放一个单引号只能写两个；漏了这一步，
      // 带 ' 的路径会把字符串提前闭合，后面就是别人的命令。
      expect(WindowsCoreLauncher.psQuote(r"C:\it's\mihomo.exe"), r"'C:\it''s\mihomo.exe'");
    });

    test('script carries the whole protocol and never a bare path', () {
      final script = WindowsCoreLauncher.supervisorScript(
        mihomoPath: r'C:\app\core\mihomo.exe',
        runtimeDir: r'C:\app\runtime',
        configPath: r'C:\app\runtime\config.yaml',
        stdoutPath: r'C:\app\runtime\mihomo.stdout.log',
        stderrPath: r'C:\app\runtime\mihomo.stderr.log',
        pidPath: r'C:\app\runtime\mihomo.elevated.pid',
        stopFlagPath: r'C:\app\runtime\core-stop.flag',
        supervisorLogPath: r'C:\app\runtime\mihomo.supervisor.log',
      );

      // 提权进程的 stdout 管道传不回普通权限的 GUI，所以内核输出必须先变成文件。
      expect(script, contains('-RedirectStandardOutput'));
      expect(script, contains('-RedirectStandardError'));
      // 监护进程自己也要留流水账：提权那一层没有控制台，Start-Process 抛的异常和
      // 内核退出码只能靠它自己写下来才有人看得见。
      expect(script, contains(r'Add-Content -LiteralPath $sup'));
      expect(script, contains(r'$p.ExitCode'));
      expect(script, contains(r"Write-Sup 'supervisor done'"));
      // 谁写 PID、谁盯停止标志、谁负责把内核带走。
      expect(script, contains(r"'C:\app\runtime\mihomo.elevated.pid'"));
      expect(script, contains(r'Set-Content -LiteralPath $pidFile'));
      expect(script, contains(r'Test-Path -LiteralPath $stop'));
      expect(script, contains(r'Stop-Process -Id $p.Id -Force'));
      // 内核自己崩了也要有人把标志文件收干净，否则下一次启动会被当成有残留。
      expect(script, contains(r'-not $p.HasExited'));
      // 每一个路径都在引号里：出现裸路径意味着某个地方漏了 psQuote。
      for (final path in [
        r'C:\app\core\mihomo.exe',
        r'C:\app\runtime\config.yaml',
        r'C:\app\runtime\core-stop.flag',
      ]) {
        expect(script.contains(path), isTrue);
        expect(script.contains('= $path'), isFalse, reason: '$path 没有以引用形式写进脚本');
      }
    });

    test('encoded command is base64 of UTF-16LE', () {
      // -EncodedCommand 认的是 UTF-16LE 字节。写成 UTF-8 的话 powershell 会在
      // 解码那一步直接报错，而错误发生在提权窗口里——这边只会看到"没有回报 PID"。
      const script = "Write-Output '你好 A';\n";
      final encoded = WindowsCoreLauncher.encodeCommand(script);
      final bytes = base64Decode(encoded);
      expect(bytes.length, script.codeUnits.length * 2);
      final round = String.fromCharCodes([
        for (var i = 0; i < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8),
      ]);
      expect(round, script);
    });

    test('command line is passed encoded, never interpolated', () {
      final encoded = WindowsCoreLauncher.encodeCommand("x'; Format-Volume -DriveLetter C #");
      final parameters = '-NoProfile -EncodedCommand $encoded';
      // 注入串进了 -EncodedCommand 之后只是 base64 里的一段数据。
      expect(parameters.contains('Format-Volume'), isFalse);
    });
  });

  group('windows tun stop protocol', () {
    late Directory temp;
    late AppPaths paths;
    late WindowsCoreLauncher launcher;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('clashgo_tun_proto_');
      PathProviderPlatform.instance = _TempPathProvider(temp.path);
      paths = await AppPaths.create();
      launcher = WindowsCoreLauncher(paths);
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('nothing to stop when no elevated core was ever started', () async {
      expect(launcher.hasStaleElevatedCore, isFalse);
      expect(await launcher.requestStop(timeout: const Duration(milliseconds: 100)), isFalse);
      // 没有提权内核时不能凭空留下一个停止标志——下一次启动会把它当成上次的残留。
      expect(paths.stopFlagFile.existsSync(), isFalse);
    });

    test('acknowledged when the supervisor takes the pid file with it', () async {
      paths.elevatedFlagFile.writeAsStringSync('elevated');
      expect(launcher.hasStaleElevatedCore, isFalse, reason: '只有一半的标志不算有残留');

      paths.elevatedPidFile.writeAsStringSync('4242');
      expect(launcher.hasStaleElevatedCore, isTrue);

      // 模拟监护进程自己收手：看到 stop.flag 之后 kill 内核，然后删掉 PID 文件。
      final acknowledge = Timer(const Duration(milliseconds: 300), () {
        if (paths.stopFlagFile.existsSync()) paths.elevatedPidFile.deleteSync();
      });
      final acknowledged = await launcher.requestStop(timeout: const Duration(seconds: 2));
      acknowledge.cancel();

      expect(acknowledged, isTrue);
      expect(paths.elevatedPidFile.existsSync(), isFalse);
      expect(paths.elevatedFlagFile.existsSync(), isFalse);
      expect(paths.stopFlagFile.existsSync(), isFalse);
    });

    test('pid file alone is enough to ask the supervisor to stop', () async {
      // elevated.flag 只是 GUI 自己记的"这一轮起过提权内核"；清理工具或上一条
      // 失败分支可能先把它删掉，而监护进程和内核都还活着。PID 文件在，就该试。
      paths.elevatedPidFile.writeAsStringSync('4242');

      final acknowledge = Timer(const Duration(milliseconds: 300), () {
        if (paths.stopFlagFile.existsSync()) paths.elevatedPidFile.deleteSync();
      });
      final acknowledged = await launcher.requestStop(timeout: const Duration(seconds: 2));
      acknowledge.cancel();

      expect(acknowledged, isTrue);
      expect(paths.elevatedPidFile.existsSync(), isFalse);
      expect(paths.stopFlagFile.existsSync(), isFalse);
    });

    test('unacknowledged stop is reported as failure, not as a closed tunnel', () async {
      paths.elevatedFlagFile.writeAsStringSync('elevated');
      paths.elevatedPidFile.writeAsStringSync('4242');

      // 监护进程被杀掉了，只剩一个没人读的 stop.flag 和一条 kill 不动的内核。
      // 这种情况返回 false：界面上不能显示"隧道已关闭"，系统里的路由其实还挂着。
      final acknowledged = await launcher.requestStop(timeout: const Duration(milliseconds: 500));
      expect(acknowledged, isFalse);
      // 标志文件仍然要清干净，否则下一次启动会以为还有人能接手停止请求。
      expect(paths.elevatedFlagFile.existsSync(), isFalse);
      expect(paths.stopFlagFile.existsSync(), isFalse);
    });

    test('start clears leftovers from the previous session', () async {
      // 这里只验证"清空"这一半：真的 ShellExecuteEx 会弹 UAC，不能在用例里跑。
      paths.elevatedPidFile.writeAsStringSync('9999');
      paths.stopFlagFile.writeAsStringSync('stop');
      paths.elevatedFlagFile.writeAsStringSync('elevated');

      launcher.clearProtocolFiles();

      expect(paths.elevatedPidFile.existsSync(), isFalse);
      expect(paths.stopFlagFile.existsSync(), isFalse);
      expect(paths.elevatedFlagFile.existsSync(), isFalse);
    });

    test('a stale core whose supervisor is gone is reported as still running', () async {
      // 监护进程和提权内核是两条命：前者被杀掉之后，后者普通权限 kill 不动，
      // 而它的默认路由和 DNS 劫持还挂在系统里。这时界面上任何"已停止"都是假话，
      // 唯一诚实的产出是日志里那句"它还在跑，去管理员终端收掉它"。
      // （requestStop 内部等满 6 秒才认失败，所以这条用例本身就要花 6 秒。）
      paths.elevatedFlagFile.writeAsStringSync('elevated');
      paths.elevatedPidFile.writeAsStringSync('4242');
      final log = CoreLog(File(p.join(temp.path, 'core.log')));

      await CoreManager(paths, log).killStale();

      final text = log.recent.join('\n');
      await log.flush();
      expect(text, contains('Stopping stale elevated core'));
      expect(text, contains('supervisor is gone'));
      expect(text, contains('Kill mihomo from an elevated terminal'));
      // 协议文件仍然要清干净：留着它们，下一次启动会误以为有人能接手停止请求。
      expect(paths.stopFlagFile.existsSync(), isFalse);
      expect(paths.elevatedFlagFile.existsSync(), isFalse);
      expect(paths.elevatedPidFile.existsSync(), isFalse);
    });

    test('a clean boot says nothing about a stale core', () async {
      final log = CoreLog(File(p.join(temp.path, 'core.log')));

      await CoreManager(paths, log).killStale();

      expect(log.recent.join('\n'), isNot(contains('stale elevated core')));
    });

    test('log ingest only commits whole lines', () async {
      // 提权内核的输出是 GUI 这边唯一的日志来源，读到半行会把一条错误拆成两条。
      final file = paths.elevatedStdoutFile..writeAsStringSync('', flush: true);
      Future<void> append(String text) async =>
          file.writeAsString('${await file.readAsString()}$text', flush: true);

      await append('first line\n');
      expect(await launcher.drainLogLines(file), ['first line']);

      await append('time=1 level=error ');
      expect(await launcher.drainLogLines(file), isEmpty, reason: '半行必须留给下一轮');

      await append('msg="tun denied"\n');
      expect(await launcher.drainLogLines(file), ['time=1 level=error msg="tun denied"']);

      // 监护进程重启会截断文件；偏移量比长度大时必须退回 0，否则这条错误永远读不到。
      await file.writeAsString('fresh\n', flush: true);
      expect(await launcher.drainLogLines(file), ['fresh']);
    });

    test('the generated command line really runs end to end', () async {
      // Windows PowerShell 才是生产里真正解释这条命令行的那个人。脚本里任何一个引号
      // 或语法错在 Dart 侧都不会留下痕迹，只会表现为"监护进程没有回报内核 PID"；
      // 所以这条用例把整条文件协议在普通权限下真跑一遍：起假内核、读到它的日志、
      // 写停止标志、确认它真的被带走。唯一没法在这里验的还是 UAC 那一下。
      if (!Platform.isWindows) markTestSkipped('needs Windows PowerShell');

      // 假内核要满足三个条件：真 PE（Start-Process 带重定向时走 CreateProcess，
      // .bat 会被"系统找不到指定的文件"挡掉）、参数随便吃（-d/-f 必须原样送到内核
      // 手里才算验过那条 ArgumentList）、以及自己不生子——子进程会继承 runtime 当工作
      // 目录，用例结束时那份临时目录删不掉。用系统自带的 csc 现编一个只会打印两行
      // 然后睡 20 秒的小 exe；机器上没有 .NET Framework 编译器就跳过。
      final csc = File(r'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe');
      if (!csc.existsSync()) markTestSkipped('no csc.exe on this machine');

      // 目录名里带空格：路径带空格是 Windows 上的常态，引号方案必须在这种路径上验过。
      final coreDir = Directory(p.join(temp.path, 'fake core'))..createSync();
      final coreExe = File(p.join(coreDir.path, 'fake-core.exe'));
      final source = File(p.join(coreDir.path, 'fake-core.cs'))
        ..writeAsStringSync('using System;\n'
            'class FakeCore{static void Main(string[] a){\n'
            '  Console.WriteLine("time=\\"2026-10-31\\" level=info msg=\\"fake core started\\" args=" + a.Length);\n'
            '  Console.WriteLine("time=\\"2026-10-31\\" level=warning msg=\\"Start TUN listening error: configure tun interface: Access is denied.\\"");\n'
            '  Console.Out.Flush();\n'
            '  System.Threading.Thread.Sleep(20000);\n'
            '}}\n');
      final compiled = await Process.run(csc.path, [
        '-nologo',
        '-target:exe',
        '-out:${coreExe.path}',
        source.path,
      ]);
      expect(compiled.exitCode, 0, reason: '${compiled.stdout}\n${compiled.stderr}');
      expect(coreExe.existsSync(), isTrue);

      final script = WindowsCoreLauncher.supervisorScript(
        mihomoPath: coreExe.path,
        runtimeDir: paths.runtimeDir.path,
        configPath: paths.configFile.path,
        stdoutPath: paths.elevatedStdoutFile.path,
        stderrPath: paths.elevatedStderrFile.path,
        pidPath: paths.elevatedPidFile.path,
        stopFlagPath: paths.stopFlagFile.path,
        supervisorLogPath: paths.elevatedSupervisorFile.path,
      );
      final supervisor = await Process.start('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-WindowStyle',
        'Hidden',
        '-EncodedCommand',
        WindowsCoreLauncher.encodeCommand(script),
      ], workingDirectory: paths.runtimeDir.path);
      // 语法错只会出现在监护进程自己的 stderr 上：不接住它，失败就只剩下"等不到 PID"。
      final supervisorError = StringBuffer();
      supervisor.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen(supervisorError.write);

      int? corePid;
      try {
        corePid = await _waitForCorePid(paths.elevatedPidFile);
        expect(corePid, isNotNull, reason: '监护进程报错：$supervisorError');

        // 追几轮：内核的输出是一行一行冒出来的，第一次读未必两条都写完了。
        final lines = <String>[];
        for (var i = 0; i < 8 && lines.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          lines.addAll(await launcher.drainLogs());
        }
        // -d <dir> -f <config> 四个参数原样到达，说明那条 ArgumentList 没被拆坏。
        // 判"集合里有"而不是"第一行是"：drainLogs 现在也会带出监护进程自己的流水账，
        // 而那句 "start mihomo=..." 本来就写在内核第一行输出之前。
        expect(lines.join('\n'), contains('args=4'), reason: lines.join('\n'));
        expect(lines.join('\n'), contains('start mihomo='), reason: '监护进程的流水账没进日志');
        // 这条正是非管理员启动 TUN 时内核说的话——日志页必须能把它显示出来。
        expect(lines.join('\n'), contains('Start TUN listening error'),
            reason: '提权内核的输出没能补进日志');

        // GUI 这边"提权内核在跑"的状态就是 start() 写下的这个标志文件。
        paths.elevatedFlagFile.writeAsStringSync('elevated');
        final stopped = await launcher.requestStop(timeout: const Duration(seconds: 8));
        expect(stopped, isTrue, reason: '监护进程没有接手停止请求：$supervisorError');
        expect(await _isProcessAlive(corePid!), isFalse,
            reason: '停止请求 ack 了，内核进程却还活着');
        expect(paths.elevatedPidFile.existsSync(), isFalse);
        expect(paths.stopFlagFile.existsSync(), isFalse);
        // 流水账是提权那一层唯一的眼睛：内核死了要有退出码，停止要留痕。
        final transcript = paths.elevatedSupervisorFile.readAsStringSync();
        expect(transcript, contains('core pid=$corePid'));
        expect(transcript, contains('stop requested, killing core'));
        expect(transcript, contains('supervisor done'));
      } finally {
        // 断言中途失败时内核还没人管；留着它，那份临时目录连同用户的 %TEMP% 一起脏。
        if (corePid != null) await Process.run('taskkill', ['/PID', '$corePid', '/F']);
        supervisor.kill();
        await supervisor.exitCode;
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

Future<int?> _waitForCorePid(File pidFile) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    if (pidFile.existsSync()) {
      final value = int.tryParse(pidFile.readAsStringSync().trim());
      if (value != null && value > 0) return value;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return null;
}

Future<bool> _isProcessAlive(int pid) async {
  final result = await Process.run('tasklist', ['/FI', 'PID eq $pid', '/FO', 'CSV', '/NH']);
  return '${result.stdout}'.contains('$pid');
}

/// 把 AppPaths 钉到临时目录：这套协议写的都是 runtime/ 下的真实文件名，
/// 不能落在用户正在用的那份 ClashGo 数据目录里。
class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}
