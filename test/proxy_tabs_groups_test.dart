import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/data/local_store.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:clash_go/models/subscription.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/fake_startup.dart';

/// 标签页风格参考 FlClash：分组标签是单行横向滚动的胶囊条。分组多时左右滚动
/// 而不是换行铺开，右端下箭头弹出全部策略组菜单；这里守住「可滚动 + 可切换 + 菜单可用」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const groups = [
    '微软服务',
    '宝可梦',
    '故障转移',
    '自动选择',
    '苹果服务',
    '游戏平台',
    '漏网之鱼',
    '谷歌服务',
    '社交媒体',
    '电视直播',
    '电报消息',
    '在线会议',
    '下载加速',
    '国内直连',
  ];

  late Directory support;
  late AppController controller;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('clashgo_tabs_groups_');
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
    await store.writeProfile('sub-a', _profile(groups));
    controller = AppController(paths, startupService: FakeStartupService());
    await controller.initialize();
    controller.settings = controller.settings.copyWith(
      proxyStyle: AppSettings.styleTabs,
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

  Future<void> openProxy(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
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
    await tester.pump(const Duration(seconds: 1));
  }

  // 胶囊标签条是页面里唯一的水平滚动区（节点区是纵向 Wrap）。桌面面板里的搜索
  // TextField 也会产生一个水平 editable 滚动区，所以用标签条的 key 精确定位。
  Finder horizontalTabBar() => find.descendant(
        of: find.byKey(const ValueKey('proxy-group-tab-bar')),
        matching: find.byType(Scrollable),
      );

  Future<void> expectScrollToLastAndSelect(WidgetTester tester, Size size) async {
    expect(horizontalTabBar(), findsOneWidget, reason: '标签条应是单行横向滚动区');
    // 首组标签在视口内。桌面端组名还会出现在面板标题里，取第一个（标签条在前）。
    final first = tester.getRect(find.text(groups.first).first);
    expect(first.right, lessThanOrEqualTo(size.width), reason: '首组标签横向超出视口');
    expect(first.bottom, lessThanOrEqualTo(size.height), reason: '首组标签纵向超出视口');

    // 末组初始不在视口内，横向滚动直到它完全进入视口（证明是滚动而非换行铺开）。
    // 横向滚动区内的标签会按完整宽度布局，边缘被视口裁掉时 getRect 仍算「在窗口内」，
    // 所以这里以滚动区自身的可视矩形为准。
    final viewport = tester.getRect(horizontalTabBar());
    bool lastVisible() {
      final finder = find.text(groups.last);
      if (finder.evaluate().isEmpty) return false;
      final rect = tester.getRect(finder.first);
      return rect.left >= viewport.left && rect.right <= viewport.right;
    }

    for (var i = 0; i < 40 && !lastVisible(); i++) {
      await tester.drag(horizontalTabBar(), const Offset(-160, 0));
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(lastVisible(), isTrue, reason: '横向滚动后末组标签应进入视口');

    // 贴边的标签可能仍被裁一部分，点之前先完整滚进视口。
    await tester.ensureVisible(find.text(groups.last).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(groups.last).first);
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    expect(find.text('节点14'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }

  testWidgets('桌面宽度下标签条单行横滚，可滚到末组并切换', (tester) async {
    const size = Size(1007, 700);
    await openProxy(tester, size);
    await expectScrollToLastAndSelect(tester, size);
  });

  testWidgets('手机宽度下标签条单行横滚，可滚到末组并切换', (tester) async {
    const size = Size(411, 891);
    await openProxy(tester, size);
    await expectScrollToLastAndSelect(tester, size);
  });

  testWidgets('桌面标签条右端菜单列出全部策略组并可切换', (tester) async {
    const size = Size(1007, 700);
    await openProxy(tester, size);
    // 单组模式下只有首组节点。
    expect(find.text('节点1'), findsOneWidget);
    expect(find.text('节点14'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('proxy-group-menu-button')));
    await tester.pumpAndSettle();

    // 浮层一次列出全部 14 个分组，当前分组行带勾选。
    for (final group in groups) {
      expect(find.byKey(ValueKey('proxy-group-menu-$group')), findsOneWidget, reason: '菜单缺少分组 $group');
    }

    // 菜单高于可视区时可滚动；滚到末组再点选。
    final lastRow = find.byKey(ValueKey('proxy-group-menu-${groups.last}'));
    await tester.ensureVisible(lastRow);
    await tester.pumpAndSettle();
    await tester.tap(lastRow);
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    await tester.pumpAndSettle();

    expect(find.text('节点14'), findsOneWidget);
    expect(find.text('节点1'), findsNothing);

    // 选中后标签条把该组标签滚进视口。
    final chip = find.descendant(
      of: find.byKey(const ValueKey('proxy-group-tab-bar')),
      matching: find.text(groups.last),
    );
    expect(chip, findsOneWidget);
    final rect = tester.getRect(chip);
    expect(rect.left, greaterThanOrEqualTo(0), reason: '选中分组后标签未滚入视口');
    expect(rect.right, lessThanOrEqualTo(size.width), reason: '选中分组后标签未滚入视口');
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机标签条右端菜单列出全部策略组并可切换', (tester) async {
    const size = Size(411, 891);
    await openProxy(tester, size);
    expect(find.text('节点1'), findsOneWidget);
    expect(find.text('节点14'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('proxy-group-menu-button')));
    await tester.pumpAndSettle();
    for (final group in groups) {
      expect(find.byKey(ValueKey('proxy-group-menu-$group')), findsOneWidget, reason: '菜单缺少分组 $group');
    }

    final lastRow = find.byKey(ValueKey('proxy-group-menu-${groups.last}'));
    await tester.ensureVisible(lastRow);
    await tester.pumpAndSettle();
    await tester.tap(lastRow);
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    await tester.pumpAndSettle();

    expect(find.text('节点14'), findsOneWidget);
    expect(find.text('节点1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面标签条支持鼠标拖动横滚', (tester) async {
    const size = Size(1007, 700);
    await openProxy(tester, size);
    final bar = horizontalTabBar();
    final position = tester.state<ScrollableState>(bar).position;
    expect(position.pixels, 0);

    await tester.drag(bar, const Offset(-420, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0), reason: 'PC 端鼠标拖拽应能横向滚动分组标签条');
  });
}

const _sharedNode = '共享节点';

String _profile(List<String> groups) {
  final buffer = StringBuffer('proxies:\n');
  for (var i = 0; i < groups.length; i++) {
    buffer.writeln('''
  - name: 节点${i + 1}
    type: ss
    server: 127.0.0.1
    port: ${1080 + i}
    cipher: aes-128-gcm
    password: test''');
  }
  buffer.writeln('''
  - name: $_sharedNode
    type: ss
    server: 127.0.0.1
    port: 2099
    cipher: aes-128-gcm
    password: test''');
  buffer.writeln('proxy-groups:');
  for (var i = 0; i < groups.length; i++) {
    buffer.writeln('''
  - name: ${groups[i]}
    type: select
    proxies:
      - 节点${i + 1}
      - $_sharedNode''');
  }
  return buffer.toString();
}

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
