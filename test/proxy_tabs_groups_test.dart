import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/data/local_store.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:clash_go/models/subscription.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/fake_startup.dart';

/// 标签页风格下策略组多于一行时，标签必须换行展示而不是被单行滚动区裁掉。
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

  Future<void> expectAllTabsInsideViewport(
    WidgetTester tester,
    Size size,
  ) async {
    for (final name in groups) {
      final tab = find.text(name).first;
      expect(tab, findsOneWidget, reason: '缺少策略组标签：$name');
      final rect = tester.getRect(tab);
      expect(
        rect.right,
        lessThanOrEqualTo(size.width),
        reason: '$name 的标签横向超出视口',
      );
      expect(
        rect.bottom,
        lessThanOrEqualTo(size.height),
        reason: '$name 的标签纵向超出视口',
      );
    }
  }

  testWidgets('桌面宽度下 14 个策略组全部可见，最后一组可切换', (tester) async {
    const size = Size(1007, 700);
    await openProxy(tester, size);
    await expectAllTabsInsideViewport(tester, size);

    final last = groups.last;
    expect(find.text(last), findsOneWidget);
    await tester.tap(find.text(last));
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    expect(find.text('节点14'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('手机宽度下 14 个策略组换行展示且可切换', (tester) async {
    const size = Size(411, 891);
    await openProxy(tester, size);
    await expectAllTabsInsideViewport(tester, size);

    final last = groups.last;
    await tester.tap(find.text(last));
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    expect(find.text('节点14'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
