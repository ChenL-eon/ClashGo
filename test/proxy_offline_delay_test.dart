import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/l10n.dart';
import 'package:clash_go/data/local_store.dart';
import 'package:clash_go/models/subscription.dart';
import 'package:clash_go/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/fake_startup.dart';

/// 回归：节点测速结果不能“回到未测试状态”。
/// 1. 离线预览测速后，页面 State 重建（窗口跨断点/外壳重建）仍显示延迟；
/// 2. 关闭再启动应用（同一数据目录）仍显示上次结果；
/// 3. 切换订阅再切回来，各自的测速结果都还在。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const node = '节点A';
  const activeId = 'sub-a';
  const otherId = 'sub-b';

  late Directory support;
  late AppPaths paths;
  late LocalStore store;
  late AppController controller;
  late ServerSocket server;
  late L10n l10n;

  String profile(int port) => '''
proxies:
  - name: $node
    type: ss
    server: 127.0.0.1
    port: $port
    cipher: aes-128-gcm
    password: test
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - $node
''';

  setUp(() async {
    support = await Directory.systemTemp.createTemp('clashgo_delay_');
    PathProviderPlatform.instance = _Temp(support.path);
    paths = await AppPaths.create();
    store = LocalStore(paths);
    // 真监听：Socket.connect 成功，离线测速拿到一个有效延迟。
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) => socket.destroy());
    final now = DateTime(2026, 11, 1, 10);
    await store.saveSubscriptions([
      Subscription(
        id: activeId,
        name: '订阅A',
        url: 'https://example.com/a',
        isLocal: false,
        createdAt: now,
        lastUpdatedAt: now,
        autoUpdate: false,
      ),
      Subscription(
        id: otherId,
        name: '订阅B',
        url: 'https://example.com/b',
        isLocal: false,
        createdAt: now,
        lastUpdatedAt: now,
        autoUpdate: false,
      ),
    ]);
    await store.saveActiveId(activeId);
    await store.writeProfile(activeId, profile(server.port));
    await store.writeProfile(otherId, profile(server.port));
    controller = AppController(paths, startupService: FakeStartupService());
    await controller.initialize();
    l10n = controller.l10n;
  });

  tearDown(() async {
    controller.dispose();
    await server.close();
    await support.delete(recursive: true);
  });

  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  Future<void> openProxy(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ClashGoApp(controller: controller));
    // 首页有常驻动画，pumpAndSettle 不会停；按固定时长推进即可。
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.descendant(
      of: find.byType(BackdropFilter),
      matching: find.text(l10n.get('nav.proxy')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    // 切到代理页会排一个 900ms 的延迟测速定时器；离线时它不发请求，但要走完。
    await tester.pump(const Duration(seconds: 1));
  }

  Finder nodeCard() => find.ancestor(of: find.text(node), matching: find.byType(SurfaceCard));

  Future<void> testNodeInUi(WidgetTester tester) async {
    expect(find.text(node), findsOneWidget);
    final dash = find.descendant(of: nodeCard(), matching: find.text('—'));
    expect(dash, findsOneWidget);
    await tester.tap(dash);
    await settleIo(tester);
    expect(find.descendant(of: nodeCard(), matching: find.textContaining('ms')), findsOneWidget);
    // 触发 500ms 防抖落盘，并等真实文件 IO 完成，测试结束时不留下挂起的 Timer。
    await tester.pump(const Duration(milliseconds: 600));
    await settleIo(tester);
  }

  testWidgets('页面重建后测速结果不丢', (tester) async {
    await openProxy(tester);
    await testNodeInUi(tester);

    // 窗口跨断点或外壳重建会丢掉代理页 State，结果必须还在控制器里。
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await openProxy(tester);

    expect(
      find.descendant(of: nodeCard(), matching: find.text('—')),
      findsNothing,
      reason: '页面重建后节点回到了未测试延迟时的状态',
    );
    expect(find.descendant(of: nodeCard(), matching: find.textContaining('ms')), findsOneWidget);
  });

  testWidgets('重启应用后测速结果仍在', (tester) async {
    await openProxy(tester);
    await testNodeInUi(tester);
    final delay = controller.displayDelay(node);
    expect(delay, isNotNull);

    // 正常关窗走 shutdown：这里模拟一次完整重启。文件 IO 必须走 runAsync，
    // 否则会被 testWidgets 的 fake async 挂住。
    await tester.runAsync(() => controller.shutdown());
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.runAsync(() async {
      controller = AppController(paths, startupService: FakeStartupService());
      await controller.initialize();
    });
    l10n = controller.l10n;
    await openProxy(tester);

    expect(
      find.descendant(of: nodeCard(), matching: find.textContaining('ms')),
      findsOneWidget,
      reason: '重启后测速结果丢失',
    );
  });

  testWidgets('切换订阅不清掉各自的测速结果', (tester) async {
    await openProxy(tester);
    await testNodeInUi(tester);
    final delay = controller.displayDelay(node);
    expect(delay, isNotNull);

    await tester.runAsync(() => controller.setActiveSubscription(otherId));
    await tester.pump();
    await settleIo(tester);
    expect(controller.displayDelay(node), isNull, reason: '另一个订阅还没测过');

    await tester.runAsync(() => controller.setActiveSubscription(activeId));
    await tester.pump();
    await settleIo(tester);
    expect(controller.displayDelay(node), delay, reason: '切回来结果丢了');
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
  });
}

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
