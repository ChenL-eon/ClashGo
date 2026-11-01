import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:clash_go/ui/pages/settings_page.dart';
import 'package:clash_go/ui/widgets/common.dart';
import 'package:clash_go/ui/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'support/fake_startup.dart';

/// 批次 A 回归：开机自启 / 关闭到托盘 / 系统代理绕过列表。
/// 测试里自启走 FakeStartupService，绝不写真实注册表。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late FakeStartupService startup;
  late AppController controller;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('clashgo_batch_a_');
    PathProviderPlatform.instance = _Temp(support.path);
    startup = FakeStartupService();
    controller = AppController(await AppPaths.create(), startupService: startup);
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

  int ruleCount(String value) {
    final normalized = AppSettings.normalizeProxyBypass(value);
    return normalized.isEmpty ? 0 : normalized.split(';').length;
  }

  test('normalizeProxyBypass 去空、去重并统一分号', () {
    expect(
      AppSettings.normalizeProxyBypass(' localhost ;10.*\r\n10.*; ; 192.168.* '),
      'localhost;10.*;192.168.*',
    );
    expect(AppSettings.normalizeProxyBypass(''), '');
    expect(AppSettings.normalizeProxyBypass('; ;'), '');
  });

  test('新字段可 JSON 往返且有默认值', () {
    final defaults = AppSettings.defaults();
    expect(defaults.launchAtStartup, isFalse);
    expect(defaults.closeToTray, isTrue);
    expect(defaults.proxyBypass, AppSettings.defaultProxyBypass);

    final custom = defaults.copyWith(
      launchAtStartup: true,
      closeToTray: false,
      proxyBypass: 'localhost;10.*',
    );
    final restored = AppSettings.fromJson(custom.toJson());
    expect(restored.launchAtStartup, isTrue);
    expect(restored.closeToTray, isFalse);
    expect(restored.proxyBypass, 'localhost;10.*');

    // 旧版本 settings.json 没有这些键：自动落在默认值上。
    final legacy = AppSettings.fromJson(defaults.toJson()
      ..remove('launchAtStartup')
      ..remove('closeToTray')
      ..remove('proxyBypass'));
    expect(legacy.launchAtStartup, isFalse);
    expect(legacy.closeToTray, isTrue);
    expect(legacy.proxyBypass, AppSettings.defaultProxyBypass);
  });

  testWidgets('绕过列表可编辑并即时归一化', (tester) async {
    final l10n = controller.l10n;
    await openSettings(tester);
    await tapRow(tester, l10n.get('settings.hub.clash'));

    Finder inPage(Finder finder) => find.descendant(of: find.byType(SettingsPage), matching: finder);

    expect(inPage(find.text(l10n.get('settings.proxyBypass'))), findsOneWidget);
    expect(
      inPage(find.text(l10n.get('settings.proxyBypassCount', [ruleCount(controller.settings.proxyBypass)]))),
      findsOneWidget,
    );

    await tester.tap(inPage(find.text(l10n.get('settings.proxyBypass'))).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final dialog = find.byType(AppDialog);
    final field = find.descendant(of: dialog, matching: find.byType(TextField));
    expect(field, findsOneWidget);
    await tester.enterText(field, 'localhost\n10.*\n10.*\n\n192.168.*');
    await tester.tap(find.descendant(of: dialog, matching: find.text(l10n.get('common.save'))));
    await settleIo(tester);

    expect(controller.settings.proxyBypass, 'localhost;10.*;192.168.*');
    expect(inPage(find.text(l10n.get('settings.proxyBypassCount', [3]))), findsOneWidget);
    // widget test 的 FakeAsync 不跑真实文件 I/O，落盘断言必须走 runAsync。
    final stored = await tester.runAsync(() => controller.store.loadSettings(preferChinese: true));
    expect(stored!.proxyBypass, 'localhost;10.*;192.168.*');
  });

  testWidgets('开机自启与关闭到托盘开关持久化', (tester) async {
    final l10n = controller.l10n;
    await openSettings(tester);
    await tapRow(tester, l10n.get('settings.hub.behavior'));

    Finder rowOf(String title) => find.ancestor(
          of: find.text(title),
          matching: find.byType(SettingRow),
        );
    Finder switchOf(String title) => find.descendant(of: rowOf(title), matching: find.byType(Switch));

    await tester.ensureVisible(switchOf(l10n.get('settings.launchAtStartup')));
    await tester.tap(switchOf(l10n.get('settings.launchAtStartup')));
    await settleIo(tester);
    expect(controller.settings.launchAtStartup, isTrue);
    expect(startup.applied, [true]);

    await tester.ensureVisible(switchOf(l10n.get('settings.closeToTray')));
    await tester.tap(switchOf(l10n.get('settings.closeToTray')));
    await settleIo(tester);
    expect(controller.settings.closeToTray, isFalse);
    expect(startup.applied, [true], reason: '关闭到托盘只落盘，不应碰注册表');

    final stored = await tester.runAsync(() => controller.store.loadSettings(preferChinese: true));
    expect(stored!.launchAtStartup, isTrue);
    expect(stored.closeToTray, isFalse);
  });

  test('启动时按设置对账自启', () async {
    await controller.applySettings(controller.settings.copyWith(launchAtStartup: true));
    final reopenedStartup = FakeStartupService();
    final reopened = AppController(await AppPaths.create(), startupService: reopenedStartup);
    await reopened.initialize();
    expect(reopened.settings.launchAtStartup, isTrue);
    expect(reopenedStartup.reconciled, [true]);
    reopened.dispose();
  });
}

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
