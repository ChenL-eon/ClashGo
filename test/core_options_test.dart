import 'dart:convert';
import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/l10n.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:clash_go/services/config_generator.dart';
import 'package:clash_go/ui/pages/settings_page.dart';
import 'package:clash_go/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:yaml/yaml.dart';

import 'support/fake_startup.dart';

/// 批次 1 回归：统一延迟、TCP 并发、Geo 低内存开关。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = '''
proxies:
  - {name: "HK 1", type: socks, server: 127.0.0.1, port: 7891}
rules:
  - MATCH,DIRECT
''';

  Map<String, dynamic> generate(AppSettings settings) {
    final text = const ConfigGenerator().generate(
      profile: profile,
      settings: settings,
      mode: 'rule',
    );
    return _plain(loadYaml(text))! as Map<String, dynamic>;
  }

  group('内核选项模型', () {
    test('默认开启，旧 settings.json 缺少字段时保持开启', () {
      final defaults = AppSettings.defaults();
      expect(defaults.unifiedDelay, isTrue);
      expect(defaults.tcpConcurrent, isTrue);
      expect(defaults.geoLowMemory, isTrue);

      final legacy = AppSettings.fromJson(
        defaults.toJson()
          ..remove('unifiedDelay')
          ..remove('tcpConcurrent')
          ..remove('geoLowMemory'),
      );
      expect(legacy.unifiedDelay, isTrue);
      expect(legacy.tcpConcurrent, isTrue);
      expect(legacy.geoLowMemory, isTrue);
    });

    test('关闭状态可 JSON 往返', () {
      final settings = AppSettings.defaults().copyWith(
        unifiedDelay: false,
        tcpConcurrent: false,
        geoLowMemory: false,
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.unifiedDelay, isFalse);
      expect(restored.tcpConcurrent, isFalse);
      expect(restored.geoLowMemory, isFalse);
    });
  });

  group('内核选项生成', () {
    test('默认写入原有行为', () {
      final map = generate(AppSettings.defaults());
      expect(map['unified-delay'], isTrue);
      expect(map['tcp-concurrent'], isTrue);
      expect(map['geodata-loader'], 'memconservative');
    });

    test('关闭后写入 false 与标准加载器', () {
      final map = generate(
        AppSettings.defaults().copyWith(
          unifiedDelay: false,
          tcpConcurrent: false,
          geoLowMemory: false,
        ),
      );
      expect(map['unified-delay'], isFalse);
      expect(map['tcp-concurrent'], isFalse);
      expect(map['geodata-loader'], 'standard');
    });
  });

  group('内核选项界面', () {
    late Directory support;
    late AppController controller;
    late L10n l10n;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('clashgo_core_options_');
      PathProviderPlatform.instance = _Temp(support.path);
      controller = AppController(
        await AppPaths.create(),
        startupService: FakeStartupService(),
      );
      await controller.initialize();
      l10n = controller.l10n;
    });

    tearDown(() async {
      controller.dispose();
      if (await support.exists()) await support.delete(recursive: true);
    });

    testWidgets('三个开关可见并落盘', (tester) async {
      await _openSettingsPage(tester, controller);
      await _openSettingsTile(tester, controller, 'settings.hub.clash');

      Finder inPage(Finder finder) =>
          find.descendant(of: find.byType(SettingsPage), matching: finder);

      for (final key in [
        'settings.unifiedDelay',
        'settings.tcpConcurrent',
        'settings.ipv6',
        'settings.geoLowMemory',
        'settings.coreOptionsHint',
      ]) {
        expect(inPage(find.text(l10n.get(key))), findsOneWidget, reason: key);
      }

      final unifiedSwitch = _switchFor(l10n, 'settings.unifiedDelay');
      expect(tester.widget<Switch>(unifiedSwitch).value, isTrue);
      await tester.tap(unifiedSwitch);
      await tester.pump();
      await _settleUi(tester);
      expect(controller.settings.unifiedDelay, isFalse);

      final geoswitch = _switchFor(l10n, 'settings.geoLowMemory');
      await tester.ensureVisible(geoswitch);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(geoswitch);
      await tester.pump();
      await _settleUi(tester);
      expect(controller.settings.geoLowMemory, isFalse);

      final saved = jsonDecode(
        controller.paths.settingsFile.readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(saved['unifiedDelay'], isFalse);
      expect(saved['tcpConcurrent'], isTrue);
      expect(saved['geoLowMemory'], isFalse);
    });
  });
}

Finder _switchFor(L10n l10n, String titleKey) {
  return find.descendant(
    of: find
        .ancestor(
          of: find.text(l10n.get(titleKey)),
          matching: find.byType(SettingRow),
        )
        .first,
    matching: find.byType(Switch),
  );
}

Future<void> _openSettingsPage(
  WidgetTester tester,
  AppController controller,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ClashGoApp(controller: controller));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.digit6);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await _settleUi(tester);
}

Future<void> _openSettingsTile(
  WidgetTester tester,
  AppController controller,
  String key,
) async {
  final tile = find
      .descendant(
        of: find.byType(SettingsPage),
        matching: find.text(controller.l10n.get(key)),
      )
      .first;
  await tester.ensureVisible(tile);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(tile);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await _settleUi(tester);
}

Future<void> _settleUi(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Object? _plain(Object? value) {
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString(): _plain(entry.value),
    };
  }
  if (value is List) return value.map(_plain).toList();
  return value;
}

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}
