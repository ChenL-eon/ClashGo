import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_info.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/ui/pages/settings_page.dart';
import 'package:clash_go/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/fake_startup.dart';

/// 设置页内核板块与关于页的回归：
/// 1. 「内核」板块只剩运行目录，版本/路径移到关于页，重启内核入口删除；
/// 2. 关于页按参考图改版：品牌头图 + 版本/许可证胶囊 + 检查更新按钮 + 更多分组；
/// 3. 设置搜索不再命中已删除的「重启内核」，但仍能命中运行目录并跳转。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late AppController controller;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('clashgo_about_');
    PathProviderPlatform.instance = _Temp(support.path);
    final paths = await AppPaths.create();
    controller = AppController(paths, startupService: FakeStartupService());
    await controller.initialize();
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

  Future<void> openSettings(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ClashGoApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await settleIo(tester);
  }

  Future<void> tapRow(WidgetTester tester, String label) async {
    final row = find.text(label);
    await tester.ensureVisible(row);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(row);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('关于页展示版本胶囊、简介、检查更新与更多分组', (tester) async {
    final l10n = controller.l10n;
    await openSettings(tester);
    await tapRow(tester, l10n.get('settings.about'));

    // 侧边栏底部也有应用名，断言都收在设置页内部。
    Finder inPage(Finder finder) => find.descendant(of: find.byType(SettingsPage), matching: finder);

    expect(inPage(find.text(AppInfo.name)), findsOneWidget);
    expect(inPage(find.text('v${AppInfo.version}')), findsOneWidget);
    expect(inPage(find.text(l10n.get('about.tagline'))), findsOneWidget);
    expect(
      inPage(find.ancestor(
        of: find.text(l10n.get('settings.checkUpdates')),
        matching: find.bySubtype<OutlinedButton>(),
      )),
      findsOneWidget,
    );
    // 许可证：头图胶囊 + 更多分组副标题各一处。
    expect(inPage(find.text(AppInfo.license)), findsNWidgets(2));
    expect(inPage(find.text(AppInfo.repository)), findsOneWidget);
    expect(inPage(find.text(AppInfo.mihomoRepository)), findsOneWidget);
    // 内核停止时版本行如实显示未运行，路径仍可复制。
    expect(inPage(find.text(l10n.get('about.coreStopped'))), findsOneWidget);
    expect(inPage(find.text(l10n.get('settings.coreBinary'))), findsOneWidget);
  });

  testWidgets('设置页内核板块只保留运行目录', (tester) async {
    final l10n = controller.l10n;
    await openSettings(tester);
    await tapRow(tester, l10n.get('settings.hub.clash'));

    Finder inPage(Finder finder) => find.descendant(of: find.byType(SettingsPage), matching: finder);

    expect(inPage(find.text(l10n.get('settings.core'))), findsOneWidget);
    expect(inPage(find.text(l10n.get('settings.runtimeDir'))), findsOneWidget);
    expect(inPage(find.text(l10n.get('settings.coreVersion'))), findsNothing);
    expect(inPage(find.text(l10n.get('settings.coreBinary'))), findsNothing);
  });

  testWidgets('搜索不再命中重启内核，运行目录仍可跳转', (tester) async {
    final l10n = controller.l10n;
    await openSettings(tester);
    final search = find.byType(TextField).first;

    await tester.enterText(search, '重启内核');
    await tester.pump();
    expect(find.text(l10n.get('settings.noResults')), findsOneWidget);

    await tester.enterText(search, l10n.get('settings.runtimeDir'));
    await tester.pump();
    // 输入框里也有同样的字符串，结果行要按 SettingRow 定位。
    final result = find.descendant(of: find.byType(SettingRow), matching: find.text(l10n.get('settings.runtimeDir')));
    expect(result, findsOneWidget);
    await tester.tap(result);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(l10n.get('settings.runtimeDir')), findsOneWidget);
    expect(find.text(l10n.get('settings.coreVersion')), findsNothing);
  });
}

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
