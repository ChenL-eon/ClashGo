import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/l10n.dart';
import 'package:clash_go/models/subscription.dart';
import 'package:clash_go/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/fake_startup.dart';

/// 手机宽度下订阅页的布局回归：
/// 1. 卡片高度必须一致（有没有到期日期、有没有流量信息都不能改变外框高度）；
/// 2. 切换订阅只靠点卡片，头部不再有“使用”按钮；
/// 3. 底部胶囊导航按参考图收窄到 280×56（360dp 宽屏幕）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late AppController controller;
  late L10n l10n;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('clashgo_subs_mobile_');
    PathProviderPlatform.instance = _Temp(support.path);
    controller = AppController(await AppPaths.create(), startupService: FakeStartupService());
    await controller.initialize();
    l10n = controller.l10n;
    final now = DateTime(2026, 11, 1, 9, 50);
    controller.subscriptions = [
      Subscription(
        id: 'a',
        name: '机场A',
        url: 'https://example.com/a',
        isLocal: false,
        createdAt: DateTime(2026),
        total: 200 * 1024 * 1024 * 1024,
        download: 10 * 1024 * 1024 * 1024,
        expire: DateTime(2027, 2, 18).millisecondsSinceEpoch ~/ 1000,
        updateIntervalMinutes: 60,
        lastUpdatedAt: now,
      ),
      Subscription(
        id: 'b',
        name: '机场B',
        url: 'https://example.com/b',
        isLocal: false,
        createdAt: DateTime(2026),
        total: 1000 * 1024 * 1024 * 1024,
        download: 10 * 1024 * 1024 * 1024,
        updateIntervalMinutes: 60,
        lastUpdatedAt: now,
      ),
      Subscription(
        id: 'c',
        name: '本地C',
        url: '',
        isLocal: true,
        createdAt: DateTime(2026),
        updateIntervalMinutes: 1440,
        lastUpdatedAt: now,
      ),
    ];
    controller.activeId = 'a';
  });

  tearDown(() async {
    controller.dispose();
    await support.delete(recursive: true);
  });

  Future<void> openSubscriptions(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ClashGoApp(controller: controller));
    // 首页有常驻动画，pumpAndSettle 不会停；按固定时长推进即可。
    await tester.pump(const Duration(milliseconds: 400));
    // 首页快捷入口里也有 “Subscriptions”，只在底部导航范围内找标签。
    await tester.tap(find.descendant(
      of: find.byType(BackdropFilter),
      matching: find.text(l10n.get('nav.subscriptions')),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 点卡片后的 activeId 是同步写入的，落盘要走真实事件循环，避免留下的写文件
  /// Future 和 tearDown 删目录撞车。
  Future<void> settleIo(WidgetTester tester) async {
    // 一次写文件要跨好几轮真实 IO（建目录 → 写临时文件 → 删除 → 改名），
    // 每轮都要"真实等一会儿 + 冲一次帧"才能推进到 notify。
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  Future<void> drainNotices(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('订阅卡片高度一致且不再有“使用”按钮', (tester) async {
    await openSubscriptions(tester);
    final cards = <Finder>[
      for (final name in const ['机场A', '机场B', '本地C'])
        find.ancestor(of: find.text(name), matching: find.byType(SurfaceCard)),
    ];
    for (final card in cards) {
      expect(card, findsOneWidget);
    }
    final heights = cards.map((card) => tester.getSize(card).height).toList();
    expect(heights.toSet(), hasLength(1), reason: '卡片高度不一致：$heights');

    expect(find.text(l10n.get('subscriptions.use')), findsNothing);
    expect(find.text(l10n.get('subscriptions.active')), findsOneWidget);
    // 没有到期日期的订阅也要占住这一行，卡片才不会塌一行。
    expect(
      find.text(l10n.get('home.expireAt', [l10n.get('subscriptions.unknown')])),
      findsNWidgets(2),
    );
  });

  testWidgets('点击非当前订阅卡片即可切换', (tester) async {
    await openSubscriptions(tester);

    await tester.tap(find.text('机场B'));
    await tester.pump();
    expect(controller.activeId, 'b');
    await settleIo(tester);
    final cardB = find.ancestor(of: find.text('机场B'), matching: find.byType(SurfaceCard));
    expect(
      find.descendant(of: cardB, matching: find.text(l10n.get('subscriptions.active'))),
      findsOneWidget,
      reason: '切换后“使用中”标记要跟着卡片走',
    );

    await tester.tap(find.text('本地C'));
    await tester.pump();
    expect(controller.activeId, 'c');
    await settleIo(tester);

    await tester.tap(find.text('机场A'));
    await tester.pump();
    expect(controller.activeId, 'a');
    await settleIo(tester);
    await drainNotices(tester);
  });

  testWidgets('底部导航按参考尺寸收窄', (tester) async {
    await openSubscriptions(tester);
    final pill = find.ancestor(
      of: find.byType(BackdropFilter),
      matching: find.byType(ClipRRect),
    );
    expect(pill, findsOneWidget);
    final size = tester.getSize(pill);
    expect(size, const Size(280, 56));
  });
}

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
