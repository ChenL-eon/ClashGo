import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/data/local_store.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:clash_go/models/subscription.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/fake_startup.dart';

/// 标签页风格参考 FlClash：分组标签是单行横向滚动的胶囊条。分组多时左右滚动
/// 而不是换行铺开，末组要能滚到并切换；这里守住「可滚动 + 可切换 + 不溢出」。
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
    bool lastVisible() {
      final finder = find.text(groups.last);
      if (finder.evaluate().isEmpty) return false;
      final rect = tester.getRect(finder.first);
      return rect.left >= 0 && rect.right <= size.width && rect.top >= 0;
    }

    for (var i = 0; i < 40 && !lastVisible(); i++) {
      await tester.drag(horizontalTabBar(), const Offset(-160, 0));
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(lastVisible(), isTrue, reason: '横向滚动后末组标签应进入视口');

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
}

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
  buffer.writeln('proxy-groups:');
  for (var i = 0; i < groups.length; i++) {
    buffer.writeln('''
  - name: ${groups[i]}
    type: select
    proxies:
      - 节点${i + 1}''');
  }
  return buffer.toString();
}

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
