import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/l10n.dart';
import 'package:clash_go/data/local_store.dart';
import 'package:clash_go/models/subscription.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/fake_startup.dart';

/// 订阅自动更新与卡片菜单回归：
/// 1. 添加订阅默认开启自动更新、间隔 1440 分钟，可关闭或改成自定义分钟；
/// 2. 卡片上的间隔按 分钟/小时/天 三档展示；
/// 3. 右键订阅卡片弹出「更多」菜单，且不会顺带切换订阅。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late AppController controller;
  late L10n l10n;

  Subscription remote(String id, String name, {int interval = 1440}) => Subscription(
        id: id,
        name: name,
        url: 'https://example.com/$id',
        isLocal: false,
        createdAt: DateTime(2026, 11, 1),
        lastUpdatedAt: DateTime(2026, 11, 1, 10),
        autoUpdate: true,
        updateIntervalMinutes: interval,
      );

  setUp(() async {
    support = await Directory.systemTemp.createTemp('clashgo_sub_auto_');
    PathProviderPlatform.instance = _Temp(support.path);
    final paths = await AppPaths.create();
    final store = LocalStore(paths);
    await store.saveSubscriptions([
      remote('a', '机场A', interval: 90),
      remote('b', '机场B', interval: 1440),
      remote('c', '机场C', interval: 120),
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
    await tester.pump(const Duration(seconds: 1));
  }

  Future<void> openAddDialog(WidgetTester tester) async {
    await tester.tap(find.byTooltip(l10n.get('subscriptions.add')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(l10n.get('subscriptions.addByUrl')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Finder dialogFields() =>
      find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));

  Finder dialogSwitch() =>
      find.descendant(of: find.byType(Dialog), matching: find.byType(Switch));

  testWidgets('添加订阅默认开启自动更新并预填 1440 分钟', (tester) async {
    await openSubscriptions(tester, desktop: false);
    await openAddDialog(tester);

    expect(find.text(l10n.get('subscriptions.addTitle')), findsWidgets);
    expect(tester.widget<Switch>(dialogSwitch()).value, isTrue);
    expect(dialogFields(), findsNWidgets(3));
    expect(find.widgetWithText(TextField, '1440'), findsOneWidget);

    // 关掉自动更新后不再要求填间隔；重新打开再填回默认值。
    await tester.tap(dialogSwitch());
    await tester.pump();
    expect(tester.widget<Switch>(dialogSwitch()).value, isFalse);
    expect(dialogFields(), findsNWidgets(2));
    expect(find.text('1440'), findsNothing);

    await tester.tap(dialogSwitch());
    await tester.pump();
    expect(dialogFields(), findsNWidgets(3));
    expect(find.text('1440'), findsOneWidget);
  });

  testWidgets('分钟间隔按 60–43200 校验', (tester) async {
    await openSubscriptions(tester, desktop: false);
    await openAddDialog(tester);

    await tester.enterText(dialogFields().at(1), 'https://example.com/test');
    await tester.enterText(dialogFields().at(2), '30');
    await tester.tap(find.widgetWithText(FilledButton, l10n.get('subscriptions.add')));
    await tester.pump();
    expect(find.text(l10n.get('subscriptions.intervalInvalid')), findsOneWidget);

    await tester.enterText(dialogFields().at(2), '43201');
    await tester.tap(find.widgetWithText(FilledButton, l10n.get('subscriptions.add')));
    await tester.pump();
    expect(find.text(l10n.get('subscriptions.intervalInvalid')), findsOneWidget);
    // 校验拦在发请求之前，订阅列表没有被改动。
    expect(controller.subscriptions, hasLength(3));
  });

  testWidgets('卡片间隔按分钟/小时/天展示', (tester) async {
    await openSubscriptions(tester, desktop: true);

    expect(find.text(l10n.get('subscriptions.intervalMinutes', [90])), findsOneWidget);
    expect(find.text(l10n.get('subscriptions.intervalDays', [1])), findsOneWidget);
    expect(find.text(l10n.get('subscriptions.intervalHours', [2])), findsOneWidget);
  });

  testWidgets('右键桌面卡片弹出更多菜单并进入编辑', (tester) async {
    await openSubscriptions(tester, desktop: true);

    await tester.tap(find.text('机场B'), buttons: kSecondaryMouseButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.get('common.edit')), findsOneWidget);
    expect(find.text(l10n.get('common.delete')), findsOneWidget);
    expect(controller.activeId, 'a', reason: '右键只开菜单，不切换订阅');

    await tester.tap(find.text(l10n.get('common.edit')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l10n.get('subscriptions.editTitle')), findsOneWidget);
    // 编辑对话框按分钟回填，1440 不再折算成小时。
    expect(find.widgetWithText(TextField, '1440'), findsOneWidget);
  });

  testWidgets('右键移动端卡片也能打开更多菜单', (tester) async {
    await openSubscriptions(tester, desktop: false);

    await tester.tap(find.text('机场A'), buttons: kSecondaryMouseButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(l10n.get('common.edit')), findsOneWidget);
    expect(controller.activeId, 'a');
  });
}

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
