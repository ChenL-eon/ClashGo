import 'dart:convert';
import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_info.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/models/subscription.dart';
import 'package:clash_go/ui/pages/dns_page.dart';
import 'package:clash_go/ui/pages/home_page.dart';
import 'package:clash_go/ui/shell/app_shell.dart';
import 'package:clash_go/ui/shell/navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/fake_startup.dart';

/// 可见性节流的回归用例：用一个进程内的假 mihomo 控制面，把"通道有没有连着"
/// 变成可以直接断言的东西（服务器侧活着的 WebSocket 数量 + 推进去的帧有没有落到
/// 环形缓冲里）。曲线冻结在用户眼里就是"每秒不再进新数据"，这里用同一个口径验证。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late AppController controller;
  late _FakeCore core;
  late _ProbeProxy proxy;

  setUp(() async {
    // flutter_test 默认把所有 dart:io HTTP 拦成 400，这里要真的连上假服务器。
    HttpOverrides.global = null;
    core = _FakeCore();
    final port = await core.start();
    // 延迟探测是按 settings.mixedPort 出网的，把这个端口接成一个只会数连接的探针，
    // "有没有发起探测"就变成了可以直接读的整数，而不是等异步结果落库。
    proxy = await _ProbeProxy.start();
    support = await Directory.systemTemp.createTemp('clashgo_visibility_');
    PathProviderPlatform.instance = _TempPathProvider(support.path);
    controller = AppController(await AppPaths.create(), startupService: FakeStartupService());
    await controller.initialize();
    controller.settings = controller.settings.copyWith(apiPort: port, secret: core.secret, mixedPort: proxy.port);
    await controller.store.saveSettings(controller.settings);
    controller.api.configure(port: port, secret: core.secret);
    // 相当于"VPN 已授权、隧道已起来"：控制器只会在这个档位挂实时通道。
    controller.phase = CorePhase.running;
  });

  tearDown(() async {
    await core.stop();
    await proxy.close();
    await support.delete(recursive: true);
  });

  /// WebSocket 的握手、收帧和 close 回调一半在真实事件循环、一半在 FakeAsync 的
  /// microtask 队列里，所以必须"真实等一会儿 → 冲一次帧"交替做，只看一头会漏。
  Future<void> flush(WidgetTester tester, {int rounds = 2}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(core.settle);
      await tester.pump();
    }
  }

  /// 走一遍真实的前台挂载：等价于"VPN 授权完成 / 从后台切回前台"。
  Future<void> boot(WidgetTester tester, {int root = 0}) async {
    if (root == 0) {
      // 桌面宽度：日志 Tab（索引 4）只在桌面侧栏里存在。
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1600, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      Container(key: ValueKey(root), child: ClashGoApp(controller: controller)),
    );
    // 根重建之后 shell 的 initState 已经重新标过可见性，这里只重挂数据通道。
    await tester.runAsync(() async {
      controller.setForeground(false);
      controller.setForeground(true);
      await core.settle();
    });
    await flush(tester);
  }

  /// 让内核往 /traffic 推 [frames] 帧，并把帧跑完所需的真实事件循环走完。
  Future<void> pushTraffic(WidgetTester tester, {int frames = 3}) async {
    await tester.runAsync(() async {
      for (var i = 1; i <= frames; i++) {
        core.pushTraffic(up: 1024 * i, down: 2048 * i);
        await core.settle();
      }
    });
    await flush(tester, rounds: 1);
  }

  Future<void> openTool(WidgetTester tester, AppTool tool) async {
    // 切页会顺带开 WebSocket / HTTP，这些都必须落在真实区，否则 FakeAsync 里会
    // 留下永远等不到完成的定时器，测试结束时被判 pending timer。
    await tester.runAsync(() async {
      AppNavigation.tool(tester.element(find.byType(HomePage, skipOffstage: false)), tool);
      await core.settle();
    });
    await tester.pumpAndSettle();
    expect(find.byType(ToolBackButton), findsOneWidget);
    await flush(tester);
  }

  Future<void> closeTool(WidgetTester tester) async {
    await tester.tap(find.byType(ToolBackButton));
    await tester.runAsync(core.settle);
    await tester.pumpAndSettle();
    expect(find.byType(ToolBackButton), findsNothing);
    await flush(tester);
  }

  Future<void> goTab(WidgetTester tester, int index) async {
    await tester.runAsync(() async {
      // 未选中的页在 IndexedStack 里是 offstage，取上下文时不能跳过它们。
      AppNavigation.goTab(tester.element(find.byType(HomePage, skipOffstage: false)), index);
      await core.settle();
    });
    await tester.pump();
    await flush(tester);
  }

  Future<void> quit(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  }

  testWidgets('T1 连上内核后 /traffic、/memory 两条通道都挂上，帧落进环形缓冲', (tester) async {
    await boot(tester);
    expect(core.live('/traffic'), 1);
    expect(core.live('/memory'), 1);
    // /logs 不在这条里：它跟着日志页的可见性走，首页不该为它订阅（见 D2）。
    expect(core.live('/logs'), 0);

    final before = controller.trafficHistory.length;
    await pushTraffic(tester);
    expect(controller.trafficHistory.length, before + 3);
    expect(controller.uploadSpeed, 3072, reason: '最后一帧 up=3072');
    expect(controller.downloadSpeed, 6144);
    expect(controller.sessionUpload, 3072, reason: '内核给的是 upTotal，不该走本地累加分支');
    await quit(tester);
  });

  testWidgets('D2 日志流只在日志页可见时订阅，离开就断开', (tester) async {
    await boot(tester);
    expect(core.live('/logs'), 0, reason: '首页没人读日志，不该为它订阅内核日志流');

    await goTab(tester, 4);
    expect(core.live('/logs'), 1, reason: '日志页可见才挂');
    expect(
      core.lastQuery('/logs')?['level'],
      AppInfo.coreLogLevel,
      reason: '订阅档位必须和 config.yaml 写的 log-level 同源，否则内核调档后日志页静默空白',
    );

    await goTab(tester, 0);
    expect(core.live('/logs'), 0, reason: '离开日志页，日志流不该继续占着');

    await goTab(tester, 4);
    expect(core.live('/logs'), 1, reason: '切回来要重新接上，不能留成死通道');
    await quit(tester);
  });

  testWidgets('T1b 每秒的流量/内存帧只走 live 通知线，不把首页整树重建', (tester) async {
    await boot(tester);
    var main = 0;
    var live = 0;
    void onMain() => main++;
    void onLive() => live++;
    controller.addListener(onMain);
    controller.live.addListener(onLive);

    await pushTraffic(tester, frames: 3);
    expect(controller.uploadSpeed, 3072, reason: '帧确实落进来了，不是没收到');
    expect(live, greaterThanOrEqualTo(3), reason: '只看曲线和速度的卡片挂在 live 上，必须收到');
    // 主 notifier 会让首页整树重排（三处 IntrinsicHeight）。/traffic 和 /memory 每秒
    // 各一帧，挂主线等于一秒两次全页重建。
    expect(main, 0, reason: '每秒帧不该惊动主 notifier');
    // 上面两条只证明通知线路由对了；这条证明挂在 live 上的卡片真的把新数字画出来了
    // ——否则就是改了个只会静默冻结读数的"优化"。
    expect(find.text('3 KB/s'), findsWidgets, reason: '速度读数要在没有主 notifier 的情况下自己刷新');
    expect(find.text('6 KB/s'), findsWidgets);
    // 控制器要先解绑再 dispose：带着监听者销毁 ChangeNotifier 会被 debug 断言抓住。
    controller.removeListener(onMain);
    controller.live.removeListener(onLive);
    await quit(tester);
  });

  testWidgets('B1 延迟探测：不可见不发起，进代理页立刻补测', (tester) async {
    // 周期线本身用常量钉住：boot 的 runAsync 让控制器定时器落在真实时钟上，
    // 用例里没有"把 15 分钟等过去"这种可靠做法，只能钉配置 + 直接驱动入口。
    expect(AppInfo.latencyProbeInterval, const Duration(minutes: 15), reason: '探测周期必须是 15 分钟');

    await boot(tester);
    await goTab(tester, 4); // 日志 Tab：首页和代理页都不可见

    // 探测走 mixed-port 出网，探针端口来一条连接就记一笔——
    // "有没有发起探测"于是变成一个可以直接读的整数，不用等异步结果落库。
    await tester.runAsync(() => controller.testLatency());
    expect(proxy.connects, 0, reason: '首页和代理页都不可见时不该发起外网探测');
    expect(controller.latency['Baidu'], isNull, reason: '被挡住的不只是连接，读数也不该被写脏');

    await goTab(tester, 1); // 代理页可见 → 补测一次，不干等下一个 15 分钟
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1600)));
    expect(proxy.connects, greaterThan(0), reason: '进入代理页要立刻补测，不能干等下一个周期');
    await quit(tester);
  });

  testWidgets('C1 /proxies 全量轮询只在代理页保持 8 秒', (tester) async {
    int proxiesHits() => core.restPaths.where((p) => p == '/proxies').length;

    await boot(tester);
    await goTab(tester, 4); // 日志 Tab：代理页不可见
    // 先让可能在飞的轮询落到计数里，再取基线，否则把上一轮的尾巴算成新档位的次数。
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    final before = proxiesHits();

    // 控制器里的周期定时器挂在真实时钟上（boot 的 runAsync 用的是真实区），
    // 用例没法把时钟拨过去，只能按真实时间量：9 秒窗口里旧档 8 秒必然打进来一次，
    // 降频档必须是 0 次。
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 9)));
    expect(proxiesHits() - before, 0, reason: '代理页不可见时不该继续按 8 秒拉全量节点表');
    expect(AppInfo.proxyPollVisibleInterval, const Duration(seconds: 8), reason: '代理页可见时仍走 8 秒');
    expect(AppInfo.proxyPollIdleInterval, const Duration(seconds: 30), reason: '其他页面降到 30 秒');

    await goTab(tester, 1); // 代理页可见 → 立刻补拉一次，不干等下一个 30 秒
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
    expect(proxiesHits() - before, greaterThan(0), reason: '进代理页要马上把节点表拉回来');
    await quit(tester);
  });

  testWidgets('T2 离开首页时流量通道整个断开，回到首页重新连上', (tester) async {
    await boot(tester);
    await goTab(tester, 3);
    expect(core.live('/traffic'), 0, reason: '连接页不该继续收流量推送');
    expect(core.live('/memory'), 0);

    final before = controller.trafficHistory.length;
    await pushTraffic(tester);
    expect(controller.trafficHistory.length, before, reason: '断开后推进去也不该进缓冲');

    await goTab(tester, 0);
    expect(core.live('/traffic'), 1);
    await pushTraffic(tester);
    expect(controller.trafficHistory.length, before + 3);
    await quit(tester);
  });

  testWidgets('T2 工具页压在首页上面时流量停止，关闭后恢复', (tester) async {
    await boot(tester);
    await openTool(tester, AppTool.dns);
    expect(find.byType(DnsPage), findsOneWidget);
    expect(core.live('/traffic'), 0);

    await closeTool(tester);
    expect(core.live('/traffic'), 1);
    final before = controller.trafficHistory.length;
    await pushTraffic(tester);
    expect(controller.trafficHistory.length, before + 3);
    await quit(tester);
  });

  testWidgets('T4 切主题引发根重建，通道不泄漏也不冻结', (tester) async {
    await boot(tester);
    await tester.runAsync(
      () => controller.applySettings(controller.settings.copyWith(themeMode: 'dark')),
    );
    await tester.pumpAndSettle();
    await flush(tester);
    expect(find.byType(AppShell), findsOneWidget);
    expect(core.live('/traffic'), 1, reason: '重建不能把旧通道留成僵尸，也不能一条都不连');
    expect(core.live('/memory'), 1);
    expect(core.live('/logs'), 0, reason: '停在首页，日志流本来就不该连着，重建后更不能凭空多一条');

    final before = controller.trafficHistory.length;
    await pushTraffic(tester);
    expect(controller.trafficHistory.length, before + 3);
    await quit(tester);
  });

  testWidgets('T4/D1 停在工具页那一态时整棵根树重新挂载，首页必须重新标成可见', (tester) async {
    await boot(tester);
    await openTool(tester, AppTool.dns);
    expect(core.live('/traffic'), 0);

    // 控制器活得比 shell 久：旧 shell 在"首页不可见"那一态被销毁，新 shell 必须
    // 把标志重新对齐，否则曲线永久停摆，没有任何自愈路径。
    await boot(tester, root: 1);
    expect(find.byType(AppShell), findsOneWidget);
    expect(core.live('/traffic'), 1);
    expect(core.live('/memory'), 1);

    final before = controller.trafficHistory.length;
    await pushTraffic(tester);
    expect(controller.trafficHistory.length, before + 3);
    await quit(tester);
  });

  testWidgets('T3/D2 日志 Tab 上关掉日志工具页后仍然保持激活', (tester) async {
    await boot(tester);
    await goTab(tester, 4);
    expect(controller.logsActive, isTrue);

    await openTool(tester, AppTool.logs);
    await closeTool(tester);
    expect(controller.logsActive, isTrue, reason: '还停在日志 Tab，不该被复位成 false');
    expect(core.live('/logs'), 1);

    await goTab(tester, 0);
    expect(controller.logsActive, isFalse);
    await quit(tester);
  });

  testWidgets('T5 后台期间三条通道全部断开，回前台再重建', (tester) async {
    await boot(tester);
    await pushTraffic(tester, frames: 2);
    final before = controller.trafficHistory.length;
    await tester.runAsync(() async {
      controller.setForeground(false);
      await core.settle();
    });
    await flush(tester);
    expect(core.live('/traffic'), 0);
    expect(core.live('/memory'), 0);
    expect(core.live('/logs'), 0);
    expect(controller.trafficHistory.length, before, reason: '退后台不清空历史，回前台曲线能接上');

    await tester.runAsync(() async {
      controller.setForeground(true);
      await core.settle();
    });
    await flush(tester);
    expect(core.live('/traffic'), 1);
    await quit(tester);
  });

  test('T12 退后台不更新，回到前台立刻补跑一次并提示', () async {
    // 内核在跑时订阅是走 mixed 端口的（_subscriptionProxyPort），测试里没有上游，
    // 这里只验前后台补跑逻辑，所以把档位放到 stopped。
    controller.phase = CorePhase.stopped;
    controller.settings = controller.settings.copyWith(autoUpdateSubscriptions: true);
    controller.subscriptions = [
      Subscription(
        id: 'sub-a',
        name: 'T12',
        url: 'http://127.0.0.1:${core.port}/sub',
        isLocal: false,
        createdAt: DateTime(2026),
        lastUpdatedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        autoUpdate: true,
        updateIntervalMinutes: 1,
      ),
    ];
    // 故意不是当前订阅：补跑只该刷新缓存，不该碰隧道。
    controller.activeId = null;
    final messages = <String>[];
    final listener = controller.notices.listen((notice) => messages.add(notice.message));

    controller.setForeground(false);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    controller.setForeground(true);
    await Future<void>.delayed(const Duration(milliseconds: 800));

    expect(core.subRequests, 1, reason: '回到前台补跑一次订阅更新');
    expect(messages, contains(controller.l10n.get('toast.subscriptionAutoUpdated', [1])));
    await listener.cancel();
    controller.dispose();
  });
}

/// 只用来让 updateSubscription 的链路跑通：一份能通过校验的最小订阅。
const _subYaml = '''
proxies:
  - {name: "HK 1", type: socks, server: 127.0.0.1, port: 7891}
''';

/// 假 mihomo 控制面：REST 只覆盖用例要走到的几个端点，WebSocket 按路径计数。
class _FakeCore {
  final String secret = 'fake-core-secret';
  final Map<String, List<WebSocket>> _sockets = {
    '/traffic': <WebSocket>[],
    '/memory': <WebSocket>[],
    '/logs': <WebSocket>[],
  };

  HttpServer? _server;
  final List<String> restPaths = [];
  int subRequests = 0;

  Future<int> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    server.listen(_handle);
    return server.port;
  }

  int get port => _server!.port;

  Future<void> stop() async {
    for (final list in _sockets.values) {
      for (final ws in list.toList()) {
        await ws.close();
      }
    }
    await server.close(force: true);
  }

  HttpServer get server => _server!;

  int live(String path) => _sockets[path]!.length;

  /// 每次升级时记下的查询串，按路径分组。"订阅档位是不是跟内核同源"只能从这里看，
  /// 连接数看不出参数差异。
  final Map<String, List<Map<String, String>>> socketQueries = {};

  Map<String, String>? lastQuery(String path) {
    final list = socketQueries[path];
    return (list == null || list.isEmpty) ? null : list.last;
  }

  /// 等一次真实事件循环，让 WebSocket 的连接/关闭回调跑完。
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 150));

  void pushTraffic({required int up, required int down}) {
    for (final ws in _sockets['/traffic']!) {
      ws.add(jsonEncode({'up': up, 'down': down, 'upTotal': up, 'downTotal': down}));
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      if (request.uri.queryParameters['token'] != secret) {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }
      final socket = await WebSocketTransformer.upgrade(request);
      socketQueries.putIfAbsent(path, () => <Map<String, String>>[]).add(Map<String, String>.from(request.uri.queryParameters));
      final bucket = _sockets.putIfAbsent(path, () => <WebSocket>[]);
      bucket.add(socket);
      socket.listen((_) {}, onDone: () => bucket.remove(socket), cancelOnError: true);
      return;
    }
    restPaths.add(path);
    if (path == '/sub') {
      subRequests++;
      request.response.write(_subYaml);
      await request.response.close();
      return;
    }
    request.response.headers.contentType = ContentType.json;
    final body = switch (path) {
      '/version' => '{"meta":true,"version":"v1.19.33"}',
      '/proxies' => '{"proxies":{}}',
      '/connections' => '{"connections":[],"uploadTotal":0,"downloadTotal":0}',
      '/memory' => '{"inuse":1,"oslimit":2}',
      _ => null,
    };
    if (body == null) {
      request.response.statusCode = HttpStatus.notFound;
    } else {
      request.response.write(body);
    }
    await request.response.close();
  }
}

/// 把 AppPaths 钉到临时目录，避免用例读到或写掉用户真实的 settings.json / 订阅缓存。
class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}

/// mixed-port 探针：来一个连接就记一笔然后掐断。延迟探测经这个端口出网，所以
/// 探测有没有被发起，在服务器这一侧是立刻可见的事件，不用等 Dart 侧的异步结果。
class _ProbeProxy {
  _ProbeProxy._(this._server);

  final ServerSocket _server;
  int connects = 0;

  static Future<_ProbeProxy> start() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = _ProbeProxy._(server);
    server.listen((socket) {
      proxy.connects++;
      socket.destroy();
    });
    return proxy;
  }

  int get port => _server.port;

  Future<void> close() => _server.close();
}
