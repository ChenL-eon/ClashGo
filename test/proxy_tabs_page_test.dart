import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/l10n.dart';
import 'package:clash_go/data/local_store.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:clash_go/models/subscription.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/fake_startup.dart';

/// 标签页风格的分组面板只保留节点列表：分组级测速只在列表风格的分组卡片里。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const node = '节点A';
  const group = 'PROXY';

  late Directory support;
  late AppPaths paths;
  late AppController controller;
  late L10n l10n;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('clashgo_tabs_');
    PathProviderPlatform.instance = _Temp(support.path);
    paths = await AppPaths.create();
    final store = LocalStore(paths);
    final now = DateTime(2026, 11, 1, 10);
    await store.saveSubscriptions([
      Subscription(
        id: 'sub-a',
        name: '订阅A',
        url: 'https://example.com/a',
        isLocal: false,
        createdAt: now,
        lastUpdatedAt: now,
        autoUpdate: false,
      ),
    ]);
    await store.saveActiveId('sub-a');
    await store.writeProfile('sub-a', '''
proxies:
  - name: $node
    type: ss
    server: 127.0.0.1
    port: 1080
    cipher: aes-128-gcm
    password: test
proxy-groups:
  - name: $group
    type: select
    proxies:
      - $node
''');
    controller = AppController(paths, startupService: FakeStartupService());
    await controller.initialize();
    controller.settings = controller.settings.copyWith(proxyStyle: AppSettings.styleTabs);
    l10n = controller.l10n;
  });

  tearDown(() async {
    controller.dispose();
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
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ClashGoApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 400));
    // 桌面端导航在侧栏，直接走 Ctrl+2 快捷键切到代理页。
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('标签页风格不显示“测速本组”，列表风格保留', (tester) async {
    await openProxy(tester);

    // 页面确实渲染了标签页面板：头部的「测速全部」在。
    expect(find.byTooltip(l10n.get('proxy.testAll')), findsOneWidget);
    expect(find.text(l10n.get('proxy.testGroup')), findsNothing);

    await tester.runAsync(
      () => controller.applySettings(controller.settings.copyWith(proxyStyle: AppSettings.styleList)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text(group));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l10n.get('proxy.testGroup')), findsOneWidget);
  });
}

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
