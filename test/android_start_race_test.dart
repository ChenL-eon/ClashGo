import 'dart:io';

import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/core_log.dart';
import 'package:clash_go/core/errors.dart';
import 'package:clash_go/services/core_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// VpnService 的启动状态由原生侧异步登记：Dart 在 startVpn 返回后立刻
/// 轮询 status 时，可能先读到初始的 stopped/false。这组用例锁住"初始快照
/// 不能被当成内核启动失败"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.clashgo.clash_go/core');

  late Directory temp;
  late AppPaths paths;
  late List<Map<String, Object?>> statusReplies;
  late int statusCalls;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('clashgo_android_start_');
    PathProviderPlatform.instance = _TempPathProvider(temp.path);
    paths = await AppPaths.create();
    statusCalls = 0;
    statusReplies = const [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'prepareVpn':
          return true;
        case 'startVpn':
          return true;
        case 'status':
          final index = statusCalls < statusReplies.length
              ? statusCalls
              : statusReplies.length - 1;
          statusCalls++;
          return statusReplies[index];
        case 'stopVpn':
          return true;
      }
      return null;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    // Windows 上临时目录偶尔被杀软/索引占住，删不掉不影响用例结论。
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await temp.delete(recursive: true);
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  test('首次 status 仍是初始 stopped 时继续等待，不误报启动失败', () async {
    statusReplies = [
      {'state': 'stopped', 'pid': -1, 'serviceRunning': false},
      {'state': 'running', 'pid': 4321, 'serviceRunning': true},
    ];
    final manager = _AndroidCoreManager(paths, CoreLog(paths.coreLogFile))
      ..setMonitorEnabled(false);
    final mixedPort = await _freePort();
    final apiPort = await _freePort();

    await manager.start(
      config: 'mixed-port: $mixedPort\n',
      mixedPort: mixedPort,
      apiPort: apiPort,
      tunMtu: 1400,
    );

    expect(statusCalls, 2);
    expect(manager.pid, 4321);
  });

  test('服务始终不出现时，宽限期后报服务未启动', () async {
    statusReplies = [
      {'state': 'stopped', 'pid': -1, 'serviceRunning': false},
    ];
    final manager = _AndroidCoreManager(paths, CoreLog(paths.coreLogFile))
      ..setMonitorEnabled(false);
    final mixedPort = await _freePort();
    final apiPort = await _freePort();

    await expectLater(
      manager.start(
        config: 'mixed-port: $mixedPort\n',
        mixedPort: mixedPort,
        apiPort: apiPort,
        tunMtu: 1400,
      ),
      throwsA(
        isA<AppError>()
            .having((error) => error.code, 'code', 'startFailed')
            .having((error) => error.detail, 'detail', contains('did not start')),
      ),
    );
  });
}

Future<int> _freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

class _AndroidCoreManager extends CoreManager {
  _AndroidCoreManager(super.paths, super.log);

  @override
  bool get isAndroidPlatform => true;

  @override
  String? get binaryPath => '/fake/mihomo';
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}
