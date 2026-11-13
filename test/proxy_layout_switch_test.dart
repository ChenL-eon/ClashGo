import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/data/local_store.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:clash_go/models/subscription.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/fake_startup.dart';

/// 显示选项里的「布局」必须真的改变节点列数：宽松 1 列、标准 2 列、紧凑 3 列。
/// 这里展开分组后打开菜单的布局子菜单（选项点完不收起），连续切换三档，
/// 通过每个节点卡的 GlobalObjectKey 数出第一行有几张卡，直接断言列数。
/// 窄屏也不能自动收列，否则标准和宽松看起来一样、像切换无效。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late AppController controller;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('clashgo_layout_switch_');
    PathProviderPlatform.instance = _Temp(support.path);
    final paths = await AppPaths.create();
    final store = LocalStore(paths);
    final now = DateTime(2026, 11, 2, 12);
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
    await store.writeProfile('sub-a', _profile);
    controller = AppController(paths, startupService: FakeStartupService());
    await controller.initialize();
    controller.settings = controller.settings.copyWith(
      language: 'zh',
      proxyStyle: AppSettings.styleList,
    );
  });

  tearDown(() async {
    controller.dispose();
    await support.delete(recursive: true);
  });

  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
  }

  Finder nodeCard([int index = 1]) => find.byWidgetPredicate(
        (widget) =>
            widget.key is GlobalObjectKey &&
            (widget.key as GlobalObjectKey).value == 'proxy-node:节点$index',
      );

  /// 数第一行（与节点1同顶边）放了几张卡，即当前布局档位的列数。
  int columnsOf(WidgetTester tester) {
    final first = tester.getRect(nodeCard(1));
    var count = 0;
    for (var i = 1; i <= 6; i++) {
      final finder = nodeCard(i);
      if (finder.evaluate().isEmpty) continue;
      if ((tester.getRect(finder).top - first.top).abs() < 1) count++;
    }
    return count;
  }

  /// 打开显示选项 → 布局子菜单；子菜单在 overlay 里就绪需要一点时间。
  Future<void> openLayoutSubmenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('显示选项'));
    await tester.pump(const Duration(milliseconds: 400));
    final layoutItem = find.ancestor(
      of: find.text('布局'),
      matching: find.byType(MenuItemButton),
    );
    expect(layoutItem, findsOneWidget);
    await tester.tap(layoutItem);
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('宽松').evaluate().isNotEmpty) break;
    }
    expect(find.text('宽松'), findsOneWidget);
  }

  Future<void> pickLayout(WidgetTester tester, String label) async {
    final option = find.text(label);
    expect(option, findsOneWidget, reason: '布局子菜单应已展开并包含「$label」');
    await tester.tap(option);
    await tester.pump(const Duration(milliseconds: 300));
    await settleIo(tester);
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('桌面列表风格：宽松1列/标准2列/紧凑3列', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ClashGoApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    await tester.tap(find.text('默认组'));
    await tester.pump(const Duration(milliseconds: 300));

    await openLayoutSubmenu(tester);
    await pickLayout(tester, '宽松');
    expect(columnsOf(tester), 1, reason: '宽松应是 1 列');
    await pickLayout(tester, '标准');
    expect(columnsOf(tester), 2, reason: '标准应是 2 列');
    await pickLayout(tester, '紧凑');
    expect(columnsOf(tester), 3, reason: '紧凑应是 3 列');
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机宽度：宽松1列/标准2列/紧凑3列', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(411, 891);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ClashGoApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('代理'));
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    await tester.tap(find.text('默认组'));
    await tester.pump(const Duration(milliseconds: 300));

    await openLayoutSubmenu(tester);
    await pickLayout(tester, '宽松');
    expect(columnsOf(tester), 1, reason: '宽松应是 1 列');
    await pickLayout(tester, '标准');
    expect(columnsOf(tester), 2, reason: '标准应是 2 列');
    await pickLayout(tester, '紧凑');
    expect(columnsOf(tester), 3, reason: '紧凑应是 3 列');
    expect(tester.takeException(), isNull);
  });

  testWidgets('窄屏 360dp 也不收列：标准2列、紧凑3列', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 780);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ClashGoApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('代理'));
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    await tester.tap(find.text('默认组'));
    await tester.pump(const Duration(milliseconds: 300));

    await openLayoutSubmenu(tester);
    await pickLayout(tester, '标准');
    expect(columnsOf(tester), 2, reason: '窄屏标准档仍是 2 列');
    await pickLayout(tester, '紧凑');
    expect(columnsOf(tester), 3, reason: '窄屏紧凑档仍是 3 列');
    expect(tester.takeException(), isNull);
  });
}

const _profile = '''
proxies:
  - {name: 节点1, type: ss, server: 127.0.0.1, port: 1080, cipher: aes-128-gcm, password: test}
  - {name: 节点2, type: ss, server: 127.0.0.1, port: 1081, cipher: aes-128-gcm, password: test}
  - {name: 节点3, type: ss, server: 127.0.0.1, port: 1082, cipher: aes-128-gcm, password: test}
  - {name: 节点4, type: ss, server: 127.0.0.1, port: 1083, cipher: aes-128-gcm, password: test}
  - {name: 节点5, type: ss, server: 127.0.0.1, port: 1084, cipher: aes-128-gcm, password: test}
  - {name: 节点6, type: ss, server: 127.0.0.1, port: 1085, cipher: aes-128-gcm, password: test}
proxy-groups:
  - name: 默认组
    type: select
    proxies: [节点1, 节点2, 节点3, 节点4, 节点5, 节点6]
rules:
  - MATCH,默认组
''';

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
