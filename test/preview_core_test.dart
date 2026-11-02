import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_info.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/core_log.dart';
import 'package:clash_go/core/errors.dart';
import 'package:clash_go/data/local_store.dart';
import 'package:clash_go/models/subscription.dart';
import 'package:clash_go/services/core_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/fake_startup.dart';

/// 预览内核的回归用例：窗口可见时起一个不接管流量的内核，隐藏就收掉。
/// 内核本身用假实现，只验证控制器的调度语义；真实的进程/端口行为由构建后的
/// 双端实测覆盖。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const subId = 'sub-a';

  late Directory support;
  late AppPaths paths;
  late _FakeApi api;
  late _FakeCoreManager core;
  late AppController controller;

  setUp(() async {
    // flutter_test 默认把所有 dart:io HTTP 拦成 400，预览启动要真的连上假控制面。
    HttpOverrides.global = null;
    support = await Directory.systemTemp.createTemp('clashgo_preview_');
    PathProviderPlatform.instance = _TempPathProvider(support.path);
    paths = await AppPaths.create();
    final store = LocalStore(paths);
    final now = DateTime(2026, 11, 2, 10);
    await store.saveSubscriptions([
      Subscription(
        id: subId,
        name: '订阅A',
        url: 'https://example.com/a',
        isLocal: false,
        createdAt: now,
        lastUpdatedAt: now,
        autoUpdate: false,
      ),
    ]);
    await store.saveActiveId(subId);
    await store.writeProfile(subId, _subYaml);
    api = await _FakeApi.start();
    core = _FakeCoreManager(paths, CoreLog(paths.coreLogFile));
    controller = AppController(
      paths,
      coreManager: core,
      startupService: FakeStartupService(),
    );
    await controller.initialize();
    controller.settings = controller.settings.copyWith(
      apiPort: api.port,
      mixedPort: api.port + 1,
      secret: 'preview-secret',
    );
    controller.api.configure(port: api.port, secret: 'preview-secret');
  });

  tearDown(() async {
    controller.dispose();
    await api.close();
    await support.delete(recursive: true);
  });

  /// 控制器内部全是真实事件循环上的异步链，必须用 runAsync + 轮询等状态落定。
  Future<void> waitFor(WidgetTester tester, bool Function() condition, String reason) async {
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) fail(reason);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      // 让 start 动作尾部（/proxies 刷新、选择恢复）也跑完再结束用例。
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
  }

  Future<void> showAndWaitPreview(WidgetTester tester) async {
    await tester.runAsync(() async {
      controller.setForeground(false);
      controller.setWindowVisible(true);
    });
    await waitFor(tester, () => controller.phase == CorePhase.preview, '预览内核没有启动');
  }

  testWidgets('窗口可见时启动预览内核，隐藏后停止', (tester) async {
    await showAndWaitPreview(tester);
    expect(core.previewFlags, [true]);
    expect(controller.isPreviewing, isTrue);
    expect(controller.isRunning, isFalse);
    expect(controller.coreOnline, isTrue);

    await tester.runAsync(() async {
      controller.setWindowVisible(false);
    });
    await waitFor(tester, () => controller.phase == CorePhase.stopped, '隐藏后预览内核没有停止');
    expect(controller.coreOnline, isFalse);
    expect(core.stops, 1);
    expect(core.previewFlags, [true]);
  });

  testWidgets('启动途中隐藏再显示，预览内核仍能重新起来', (tester) async {
    final gate = Completer<void>();
    core.startGate = gate;
    await tester.runAsync(() async {
      controller.setForeground(false);
      controller.setWindowVisible(true);
    });
    await waitFor(tester, () => core.starts == 1, '没有走到内核启动');

    await tester.runAsync(() async {
      controller.setWindowVisible(false);
      gate.complete();
      core.startGate = null;
    });
    await waitFor(tester, () => controller.phase == CorePhase.stopped, '取消后没有回到停止态');
    expect(core.stops, 1);

    await tester.runAsync(() async {
      controller.setWindowVisible(true);
    });
    await waitFor(tester, () => controller.phase == CorePhase.preview, '重新可见后预览内核没有重建');
    expect(core.starts, 2);
    expect(core.previewFlags, [true, true]);
  });

  testWidgets('接管启动失败后预览内核自动恢复', (tester) async {
    await showAndWaitPreview(tester);
    core.failTakeoverStart = true;

    await tester.runAsync(() => controller.startCore(silent: true));
    await waitFor(tester, () => controller.phase == CorePhase.preview, '接管失败后预览内核没有回来');

    expect(core.previewFlags, [true, false, true]);
    expect(controller.isRunning, isFalse);
  });

  testWidgets('停止接管后窗口仍可见，预览内核接上保持真实测速', (tester) async {
    await showAndWaitPreview(tester);

    await tester.runAsync(() => controller.startCore(silent: true));
    await waitFor(tester, () => controller.phase == CorePhase.running, '接管内核没有启动');
    expect(core.previewFlags, [true, false]);

    await tester.runAsync(() async {
      final stopped = await controller.stopCore(silent: true, keepPreview: true);
      expect(stopped, isTrue);
    });
    await waitFor(tester, () => controller.phase == CorePhase.preview, '停止接管后预览内核没有接上');

    expect(core.previewFlags, [true, false, true]);
    expect(controller.isRunning, isFalse);
    expect(controller.isPreviewing, isTrue);
  });
}

const _subYaml = '''
proxies:
  - {name: "HK 1", type: socks, server: 127.0.0.1, port: 7891}
''';

class _FakeCoreManager extends CoreManager {
  _FakeCoreManager(super.paths, super.log);

  final List<bool> previewFlags = [];
  int starts = 0;
  int stops = 0;
  bool failTakeoverStart = false;
  Completer<void>? startGate;

  @override
  bool get supported => true;

  @override
  String? get binaryPath => '/fake/mihomo';

  @override
  Future<void> initializePlatform() async {}

  @override
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
    bool preview = false,
  }) async {
    starts++;
    previewFlags.add(preview);
    final gate = startGate;
    if (gate != null) await gate.future;
    if (!preview && failTakeoverStart) {
      throw const AppError('startFailed', detail: 'fake takeover failure');
    }
  }

  @override
  Future<bool> stop({bool removePid = true}) async {
    stops++;
    return true;
  }

  @override
  Future<void> stopPreview() async {
    await stop();
  }
}

/// 预览内核起来后要拿 /version 和 /proxies；只实现这两条就够用例走完。
class _FakeApi {
  _FakeApi._(this._server);

  final HttpServer _server;

  int get port => _server.port;

  static Future<_FakeApi> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final api = _FakeApi._(server);
    server.listen(api._handle);
    return api;
  }

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    if (request.uri.path == '/version') {
      response.write(jsonEncode({'version': 'v1.19.0', 'meta': true}));
    } else if (request.uri.path == '/proxies') {
      response.write(jsonEncode({'proxies': <String, dynamic>{}}));
    } else {
      response.write('{}');
    }
    await response.close();
  }
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}
