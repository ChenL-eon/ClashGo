import 'dart:convert';
import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/l10n.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:clash_go/services/config_generator.dart';
import 'package:clash_go/ui/pages/settings_page.dart';
import 'package:clash_go/ui/widgets/dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:yaml/yaml.dart';

import 'support/fake_startup.dart';

/// 批次 2 回归：Hosts 覆盖的模型、配置生成与设置页增删改。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = '''
proxies:
  - {name: "HK 1", type: socks, server: 127.0.0.1, port: 7891}
hosts:
  keep.example: 10.0.0.1
  override.example: 10.0.0.2
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

  group('Hosts 模型', () {
    test('默认与旧 settings.json 都是空映射', () {
      expect(AppSettings.defaults().hosts, isEmpty);
      final legacy = AppSettings.fromJson(
        AppSettings.defaults().toJson()..remove('hosts'),
      );
      expect(legacy.hosts, isEmpty);
    });

    test('JSON 往返并归一化大小写、空项与非法值', () {
      final settings = AppSettings.defaults().copyWith(
        hosts: const {
          '  Example.COM ': ' 10.0.0.1 ',
          '*.Wild.Example': 'LOCAL.Example.COM',
          'empty.example': '   ',
          'bad domain': '10.0.0.2',
          'bad-target.example': 'not valid!',
          'v6.example': '::1',
        },
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.hosts, {
        'example.com': '10.0.0.1',
        '*.wild.example': 'local.example.com',
        'v6.example': '::1',
      });
    });

    test('校验规则接受通配符与 IPv6，拒绝带空格或协议的输入', () {
      expect(AppSettings.isValidHostDomain('*.example.com'), isTrue);
      expect(AppSettings.isValidHostDomain('+.example.com'), isTrue);
      expect(AppSettings.isValidHostDomain('例子.com'), isFalse);
      expect(AppSettings.isValidHostDomain('bad domain'), isFalse);
      expect(AppSettings.isValidHostTarget('127.0.0.1'), isTrue);
      expect(AppSettings.isValidHostTarget('local.example.com'), isTrue);
      expect(AppSettings.isValidHostTarget('2001:db8::1'), isTrue);
      expect(AppSettings.isValidHostTarget('https://example.com'), isFalse);
      expect(AppSettings.isValidHostTarget('1.1.1.1, 8.8.8.8'), isFalse);
    });
  });

  group('Hosts 生成', () {
    test('UI 条目覆盖同名订阅/YAML 项，其余项保留', () {
      final map = generate(
        AppSettings.defaults().copyWith(
          overrideYaml: '''
hosts:
  override.example: 10.0.0.9
  yaml-only.example: 10.0.0.10
''',
          hosts: const {
            'override.example': '10.0.0.3',
            'ui-only.example': '10.0.0.4',
            '*.wild.example': '10.0.0.5',
            'v6.example': '2001:db8::1',
            'loop.example': '::1',
          },
        ),
      );
      expect(map['hosts'], {
        'keep.example': '10.0.0.1',
        'override.example': '10.0.0.3',
        'yaml-only.example': '10.0.0.10',
        'ui-only.example': '10.0.0.4',
        '*.wild.example': '10.0.0.5',
        'v6.example': '2001:db8::1',
        'loop.example': '::1',
      });
    });

    test('UI 为空时完全保持订阅与 YAML 覆写里的 hosts', () {
      final map = generate(
        AppSettings.defaults().copyWith(
          overrideYaml: '''
hosts:
  override.example: 10.0.0.9
''',
        ),
      );
      expect(map['hosts'], {
        'keep.example': '10.0.0.1',
        'override.example': '10.0.0.9',
      });
    });

    test('hosts 可被 YAML 覆写，不受保护键限制', () {
      expect(ConfigGenerator.protectedOverrideKeys, isNot(contains('hosts')));
      ConfigGenerator.validateOverride('hosts:\n  example.com: 1.1.1.1');
    });
  });

  group('Hosts 设置页', () {
    late Directory support;
    late AppController controller;
    late L10n l10n;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('clashgo_hosts_');
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

    testWidgets('添加、编辑、删除并落盘', (tester) async {
      await _openSettingsPage(tester, controller);
      await _openSettingsTile(tester, controller, 'settings.hosts');
      expect(
        find.descendant(
          of: find.byType(SettingsPage),
          matching: find.text(l10n.get('settings.hostsEmpty')),
        ),
        findsOneWidget,
      );

      await _openHostDialog(tester, l10n);
      await tester.enterText(_dialogField(tester, 0), 'Example.COM');
      await tester.enterText(_dialogField(tester, 1), '127.0.0.1');
      await _tapDialogSave(tester, l10n);
      expect(controller.settings.hosts, {'example.com': '127.0.0.1'});
      expect(
        find.descendant(
          of: find.byType(SettingsPage),
          matching: find.text('example.com'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(SettingsPage),
          matching: find.text('example.com'),
        ),
      );
      await _settleUi(tester);
      await tester.enterText(_dialogField(tester, 1), '10.0.0.8');
      await _tapDialogSave(tester, l10n);
      expect(controller.settings.hosts, {'example.com': '10.0.0.8'});

      final saved = jsonDecode(
        controller.paths.settingsFile.readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(saved['hosts'], {'example.com': '10.0.0.8'});

      await tester.tap(find.byTooltip(l10n.get('common.delete')));
      await _settleUi(tester);
      expect(controller.settings.hosts, isEmpty);
      expect(
        find.descendant(
          of: find.byType(SettingsPage),
          matching: find.text(l10n.get('settings.hostsEmpty')),
        ),
        findsOneWidget,
      );
    });
  });
}

Future<void> _openHostDialog(WidgetTester tester, L10n l10n) async {
  final add = find.text(l10n.get('settings.hostsAdd'));
  await tester.ensureVisible(add);
  await tester.pump(const Duration(milliseconds: 200));
  await tester.tap(add);
  await _settleUi(tester);
}

Finder _dialogField(WidgetTester tester, int index) {
  return find
      .descendant(
        of: find.byType(AppDialog),
        matching: find.byType(TextField),
      )
      .at(index);
}

Future<void> _tapDialogSave(WidgetTester tester, L10n l10n) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppDialog),
      matching: find.text(l10n.get('common.save')),
    ),
  );
  await _settleUi(tester);
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
