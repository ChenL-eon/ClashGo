import 'dart:convert';
import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/l10n.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:clash_go/models/dns_config.dart';
import 'package:clash_go/services/config_generator.dart';
import 'package:clash_go/ui/pages/settings_page.dart';
import 'package:clash_go/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:yaml/yaml.dart';

import 'support/fake_startup.dart';

/// 批次 3 回归：追加系统 DNS 只改启用中的 dns.nameserver，不重复、不越权。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = '''
proxies:
  - {name: node-a, type: socks, server: 127.0.0.1, port: 7891}
dns:
  enable: true
  nameserver:
    - 1.1.1.1
rules:
  - MATCH,DIRECT
''';

  const profileDnsOff = '''
proxies:
  - {name: node-a, type: socks, server: 127.0.0.1, port: 7891}
dns:
  enable: false
  nameserver:
    - 1.1.1.1
rules:
  - MATCH,DIRECT
''';

  const profileNoDns = '''
proxies:
  - {name: node-a, type: socks, server: 127.0.0.1, port: 7891}
rules:
  - MATCH,DIRECT
''';

  Map<String, dynamic> generate(
    AppSettings settings, {
    String source = profile,
    bool windowsTun = false,
  }) {
    final text = const ConfigGenerator().generate(
      profile: source,
      settings: settings,
      mode: 'rule',
      windowsTun: windowsTun,
    );
    return _plain(loadYaml(text))! as Map<String, dynamic>;
  }

  group('追加系统 DNS 模型', () {
    test('默认关闭，旧 settings.json 缺少字段时保持关闭', () {
      expect(AppSettings.defaults().appendSystemDns, isFalse);

      final legacy = AppSettings.fromJson(
        AppSettings.defaults().toJson()..remove('appendSystemDns'),
      );
      expect(legacy.appendSystemDns, isFalse);
    });

    test('开启状态可 JSON 往返', () {
      final settings = AppSettings.defaults().copyWith(appendSystemDns: true);
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.appendSystemDns, isTrue);
      expect(
        (jsonDecode(jsonEncode(settings.toJson()))
            as Map<String, dynamic>)['appendSystemDns'],
        isTrue,
      );
    });
  });

  group('追加系统 DNS 生成', () {
    test('关闭时不改动订阅的 nameserver', () {
      final dns =
          generate(AppSettings.defaults())['dns'] as Map<String, dynamic>;
      expect(dns['nameserver'], ['1.1.1.1']);
    });

    test('开启后追加到自定义 DNS 列表末尾', () {
      final custom = DnsConfig.defaults.copyWith(
        enabled: true,
        nameserver: const [
          'https://dns.example/dns-query',
          'tls://223.5.5.5:853',
        ],
      );
      final map = generate(
        AppSettings.defaults().copyWith(dns: custom, appendSystemDns: true),
      );
      final dns = map['dns'] as Map<String, dynamic>;
      expect(dns['enable'], isTrue);
      expect(dns['nameserver'], [
        'https://dns.example/dns-query',
        'tls://223.5.5.5:853',
        'system://',
      ]);
      expect(dns['default-nameserver'], DnsConfig.defaultBootstrapNameservers);
    });

    test('自定义 DNS 关闭但订阅 DNS 启用时同样追加', () {
      final map = generate(
        AppSettings.defaults().copyWith(appendSystemDns: true),
      );
      expect((map['dns'] as Map)['nameserver'], ['1.1.1.1', 'system://']);
    });

    test('DNS 未启用时不写入无效追加', () {
      final map = generate(
        AppSettings.defaults().copyWith(appendSystemDns: true),
        source: profileDnsOff,
      );
      final dns = map['dns'] as Map<String, dynamic>;
      expect(dns['enable'], isFalse);
      expect(dns['nameserver'], ['1.1.1.1']);
    });

    test('没有 dns 段且未开 TUN 时不创建 dns', () {
      final map = generate(
        AppSettings.defaults().copyWith(appendSystemDns: true),
        source: profileNoDns,
      );
      expect(map.containsKey('dns'), isFalse);
    });

    test('TUN 下追加到订阅解析器末尾', () {
      final map = generate(
        AppSettings.defaults().copyWith(appendSystemDns: true),
        windowsTun: true,
      );
      final dns = map['dns'] as Map<String, dynamic>;
      expect(dns['enable'], isTrue);
      expect(dns['nameserver'], ['1.1.1.1', 'system://']);
    });

    test('已有 system 或 system:// 时不重复追加', () {
      final dotSlash = DnsConfig.defaults.copyWith(
        enabled: true,
        nameserver: const ['system://'],
      );
      var map = generate(
        AppSettings.defaults().copyWith(dns: dotSlash, appendSystemDns: true),
      );
      expect((map['dns'] as Map)['nameserver'], ['system://']);

      final bare = DnsConfig.defaults.copyWith(
        enabled: true,
        nameserver: const ['system'],
      );
      map = generate(
        AppSettings.defaults().copyWith(dns: bare, appendSystemDns: true),
      );
      expect((map['dns'] as Map)['nameserver'], ['system']);
    });
  });

  group('追加系统 DNS 持久化', () {
    late Directory support;
    late AppController controller;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('clashgo_append_dns_');
      PathProviderPlatform.instance = _Temp(support.path);
      controller = AppController(
        await AppPaths.create(),
        startupService: FakeStartupService(),
      );
      await controller.initialize();
    });

    tearDown(() async {
      controller.dispose();
      if (await support.exists()) await support.delete(recursive: true);
    });

    test('保存后写入 settings.json，新实例可恢复', () async {
      await controller.applySettings(
        controller.settings.copyWith(appendSystemDns: true),
      );
      expect(controller.settings.appendSystemDns, isTrue);

      final saved = jsonDecode(
        controller.paths.settingsFile.readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(saved['appendSystemDns'], isTrue);

      final reopened = AppController(
        await AppPaths.create(),
        startupService: FakeStartupService(),
      );
      addTearDown(reopened.dispose);
      await reopened.initialize();
      expect(reopened.settings.appendSystemDns, isTrue);
    });
  });

  group('追加系统 DNS 界面', () {
    late Directory support;
    late AppController controller;
    late L10n l10n;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('clashgo_append_dns_ui_');
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

    testWidgets('DNS 页开关可见、可切换并落盘', (tester) async {
      await _openSettingsPage(tester, controller);
      await _openSettingsTile(tester, controller, 'settings.dns');

      Finder inPage(Finder finder) =>
          find.descendant(of: find.byType(SettingsPage), matching: finder);

      expect(
        inPage(find.text(l10n.get('settings.appendSystemDns'))),
        findsOneWidget,
      );
      expect(
        inPage(find.text(l10n.get('settings.appendSystemDnsHint'))),
        findsOneWidget,
      );

      final toggle = _switchFor(l10n, 'settings.appendSystemDns');
      expect(tester.widget<Switch>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pump();
      await _settleUi(tester);
      expect(controller.settings.appendSystemDns, isTrue);

      final saved = jsonDecode(
        controller.paths.settingsFile.readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(saved['appendSystemDns'], isTrue);
    });

    testWidgets('设置搜索能命中追加系统 DNS', (tester) async {
      await _openSettingsPage(tester, controller);
      final field = find.descendant(
        of: find.byType(SettingsPage),
        matching: find.byType(TextField),
      );
      expect(field, findsOneWidget);
      await tester.enterText(field, '系统 DNS');
      await tester.pump();
      await _settleUi(tester);
      expect(find.text(l10n.get('settings.dns')), findsOneWidget);
    });
  });

  group('追加系统 DNS 文案', () {
    test('中英文键完整', () {
      const keys = [
        'settings.appendSystemDns',
        'settings.appendSystemDnsHint',
        'settings.dnsDisabledHint',
      ];
      for (final code in const ['zh', 'en']) {
        final l10n = L10n(code);
        for (final key in keys) {
          expect(l10n.contains(key), isTrue, reason: '$code $key');
          expect(l10n.get(key), isNot(key), reason: '$code $key');
        }
      }
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
