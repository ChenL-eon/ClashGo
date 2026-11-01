import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/l10n.dart';
import 'package:clash_go/data/local_store.dart';
import 'package:clash_go/models/subscription.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/fake_startup.dart';

/// 订阅页头部回归：
/// 1. 桌面端「更新全部订阅」是独立图标按钮，不再是撑宽的胶囊；
/// 2. 桌面/移动端都有手动排序入口，保存后的顺序写回 subscriptions_list.json。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late AppPaths paths;
  late AppController controller;
  late L10n l10n;

  Subscription sub(String id, String name, DateTime now) => Subscription(
        id: id,
        name: name,
        url: 'https://example.com/$id',
        isLocal: false,
        createdAt: now,
        lastUpdatedAt: now,
        autoUpdate: false,
      );

  setUp(() async {
    support = await Directory.systemTemp.createTemp('clashgo_sub_sort_');
    PathProviderPlatform.instance = _Temp(support.path);
    paths = await AppPaths.create();
    final store = LocalStore(paths);
    final now = DateTime(2026, 11, 1, 10);
    await store.saveSubscriptions([
      sub('a', '机场A', now),
      sub('b', '机场B', now),
      sub('c', '机场C', now),
    ]);
    await store.saveActiveId('a');
    controller = AppController(paths, startupService: FakeStartupService());
    await controller.initialize();
    l10n = controller.l10n;
  });

  tearDown(() async {
    controller.dispose();
    await support.delete(recursive: true);
  });

  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
  }

  Future<void> openSubscriptions(WidgetTester tester, {required bool desktop}) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = desktop ? const Size(1280, 800) : const Size(360, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ClashGoApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 400));
    if (desktop) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    } else {
      await tester.tap(find.descendant(
        of: find.byType(BackdropFilter),
        matching: find.text(l10n.get('nav.subscriptions')),
      ));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
    // 离开首页会排一个 900ms 的延迟测速定时器；离线时它不发请求，但要走完。
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> moveFirstDownAndSave(WidgetTester tester) async {
    await tester.tap(find.byTooltip(l10n.get('subscriptions.sort')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.get('subscriptions.sortTitle')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('reorder-down-a')));
    await tester.pump();
    await tester.tap(find.text(l10n.get('common.save')));
    await tester.pump();
    await settleIo(tester);
  }

  Future<void> drainNotices(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('桌面端更新全部改为独立图标按钮', (tester) async {
    await openSubscriptions(tester, desktop: true);

    expect(find.byTooltip(l10n.get('subscriptions.updateAll')), findsOneWidget);
    expect(find.text(l10n.get('subscriptions.updateAll')), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('桌面端可以手动排序订阅并落盘', (tester) async {
    await openSubscriptions(tester, desktop: true);
    expect(find.byTooltip(l10n.get('subscriptions.sort')), findsOneWidget);

    await moveFirstDownAndSave(tester);
    expect(controller.subscriptions.map((item) => item.id).toList(), ['b', 'a', 'c']);

    final stored = await tester.runAsync(() => controller.store.loadSubscriptions());
    expect(stored!.map((item) => item.id).toList(), ['b', 'a', 'c']);
    await drainNotices(tester);
  });

  testWidgets('移动端也可以手动排序订阅', (tester) async {
    await openSubscriptions(tester, desktop: false);
    expect(find.byTooltip(l10n.get('subscriptions.sort')), findsOneWidget);

    await moveFirstDownAndSave(tester);
    expect(controller.subscriptions.map((item) => item.id).toList(), ['b', 'a', 'c']);
    await drainNotices(tester);
  });
}

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
