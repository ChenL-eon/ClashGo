import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/core_log.dart';
import 'package:clash_go/data/local_store.dart';
import 'package:clash_go/models/subscription.dart';
import 'package:clash_go/services/core_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/fake_startup.dart';

/// 节点测速去重与防重入回归：
/// 1. 「测速全部」收集所有分组下的唯一叶子节点，每个节点只测一次（节点常同属多组）；
/// 2. testNode / testGroup 在已有同一目标在测时直接跳过，不发重复请求。
/// 内核与 API 都用假实现，只验证控制器的调度语义。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const subId = 'sub-a';

  late Directory support;
  late AppPaths paths;
  late _FakeApi api;
  late _FakeCoreManager core;
  late AppController controller;

  setUp(() async {
    HttpOverrides.global = null;
    support = await Directory.systemTemp.createTemp('clashgo_dedup_');
    PathProviderPlatform.instance = _TempPathProvider(support.path);
    paths = await AppPaths.create();
    final store = LocalStore(paths);
    final now = DateTime(2026, 11, 12, 10);
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
    await store.writeProfile(subId, 'proxies:\n  - {name: HK1, type: socks, server: 127.0.0.1, port: 7891}\n');
    api = await _FakeApi.start();
    core = _FakeCoreManager(paths, CoreLog(paths.coreLogFile));
    controller = AppController(paths, coreManager: core, startupService: FakeStartupService());
    await controller.initialize();
    controller.settings = controller.settings.copyWith(apiPort: api.port, mixedPort: api.port + 1, secret: 's');
    controller.api.configure(port: api.port, secret: 's');
  });

  tearDown(() async {
    controller.dispose();
    await api.close();
    await support.delete(recursive: true);
  });

  Future<void> waitOnline(WidgetTester tester) async {
    await tester.runAsync(() async {
      controller.setForeground(false);
      controller.setWindowVisible(true);
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!controller.coreOnline || controller.proxySnapshot.groups.isEmpty) {
        if (DateTime.now().isAfter(deadline)) fail('预览内核没有上线或节点表为空');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });
  }

  testWidgets('测速全部对重叠分组的唯一叶子节点各测一次', (tester) async {
    await waitOnline(tester);
    api.delayCalls.clear();
    api.groupCalls.clear();

    await tester.runAsync(() => controller.testAllGroups());

    // Auto / HK / PROXY 三个组共享 HK1、HK2、JP1；DIRECT 是特殊名不计。
    expect(api.delayCalls.toSet(), {'HK1', 'HK2', 'JP1'});
    expect(api.delayCalls.length, 3, reason: '每个唯一节点只应测一次，实际：${api.delayCalls}');
    expect(api.groupCalls, isEmpty, reason: '批量测速不应再按组逐组调用');
    expect(controller.bulkTesting, isFalse);
    expect(controller.testingNodes, isEmpty);
    expect(controller.testingGroups, isEmpty);
  });

  testWidgets('同一节点在测时再次 testNode 被跳过', (tester) async {
    await waitOnline(tester);
    await tester.runAsync(() async {
      api.gate = Completer<void>();
      api.delayCalls.clear();
      final first = controller.testNode('HK1');
      final second = controller.testNode('HK1');
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(api.delayCalls.where((n) => n == 'HK1').length, 1);
      api.gate!.complete();
      await first;
      await second;
      expect(api.delayCalls.where((n) => n == 'HK1').length, 1);
      expect(controller.testingNodes, isEmpty);
    });
  });

  testWidgets('同一分组在测时再次 testGroup 被跳过', (tester) async {
    await waitOnline(tester);
    await tester.runAsync(() async {
      api.gate = Completer<void>();
      api.groupCalls.clear();
      final group = controller.proxySnapshot.groups.firstWhere((g) => g.name == 'Auto');
      final first = controller.testGroup(group);
      final second = controller.testGroup(group);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(api.groupCalls.where((n) => n == 'Auto').length, 1);
      api.gate!.complete();
      await first;
      await second;
      expect(api.groupCalls.where((n) => n == 'Auto').length, 1);
      expect(controller.testingGroups, isEmpty);
    });
  });
}

class _FakeCoreManager extends CoreManager {
  _FakeCoreManager(super.paths, super.log);

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
    int tunMtu = 1500,
    bool preview = false,
  }) async {}

  @override
  Future<bool> stop({bool removePid = true}) async => true;

  @override
  Future<void> stopPreview() async => stop();
}

class _FakeApi {
  _FakeApi._(this._server);

  final HttpServer _server;
  final List<String> delayCalls = [];
  final List<String> groupCalls = [];
  Completer<void>? gate;

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
    final path = request.uri.path;
    if (path == '/version') {
      response.write(jsonEncode({'version': 'v1.19.0', 'meta': true}));
    } else if (path == '/proxies') {
      response.write(jsonEncode(_proxiesJson));
    } else if (path.startsWith('/proxies/') && path.endsWith('/delay')) {
      final name = Uri.decodeComponent(path.substring('/proxies/'.length, path.length - '/delay'.length));
      delayCalls.add(name);
      final gate = this.gate;
      if (gate != null) await gate.future;
      response.write(jsonEncode({'delay': 100}));
    } else if (path.startsWith('/group/') && path.endsWith('/delay')) {
      final name = Uri.decodeComponent(path.substring('/group/'.length, path.length - '/delay'.length));
      groupCalls.add(name);
      final gate = this.gate;
      if (gate != null) await gate.future;
      response.write(jsonEncode({
        'HK1': {'delay': 100},
        'HK2': {'delay': 100},
        'JP1': {'delay': 100},
      }));
    } else {
      response.write('{}');
    }
    await response.close();
  }
}

const _proxiesJson = {
  'proxies': {
    'HK1': {'name': 'HK1', 'type': 'ss', 'alive': true, 'now': '', 'all': [], 'history': []},
    'HK2': {'name': 'HK2', 'type': 'ss', 'alive': true, 'now': '', 'all': [], 'history': []},
    'JP1': {'name': 'JP1', 'type': 'ss', 'alive': true, 'now': '', 'all': [], 'history': []},
    'DIRECT': {'name': 'DIRECT', 'type': 'Direct', 'alive': true, 'now': '', 'all': []},
    'Auto': {'name': 'Auto', 'type': 'url-test', 'alive': true, 'now': 'HK1', 'all': ['HK1', 'HK2', 'JP1']},
    'HK': {'name': 'HK', 'type': 'url-test', 'alive': true, 'now': 'HK1', 'all': ['HK1', 'HK2']},
    'PROXY': {'name': 'PROXY', 'type': 'selector', 'alive': true, 'now': 'Auto', 'all': ['Auto', 'HK', 'DIRECT']},
  },
};

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}