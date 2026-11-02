import 'dart:convert';
import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/errors.dart';
import 'package:clash_go/core/l10n.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:clash_go/models/dns_config.dart';
import 'package:clash_go/models/rule_provider_info.dart';
import 'package:clash_go/services/config_generator.dart';
import 'package:clash_go/ui/pages/rule_providers_page.dart';
import 'package:clash_go/ui/pages/settings_page.dart';
import 'package:clash_go/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:yaml/yaml.dart';

import 'support/fake_startup.dart';

/// 批次 C 回归：DNS 结构化配置、YAML 覆写、规则提供者解析与入口。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DnsConfig', () {
    test('默认值关闭且带可用解析器', () {
      const dns = DnsConfig.defaults;
      expect(dns.enabled, isFalse);
      expect(dns.enhancedMode, DnsConfig.fakeIp);
      expect(dns.fakeIpRange, '198.18.0.1/16');
      expect(dns.nameserver, DnsConfig.defaultPrimaryNameservers);
      expect(dns.fallback, isEmpty);
      expect(dns.defaultNameserver, DnsConfig.defaultBootstrapNameservers);
    });

    test('增强模式与 fake-ip 网段只接受合法值', () {
      expect(DnsConfig.normalizeEnhancedMode('redir-host'), 'redir-host');
      expect(DnsConfig.normalizeEnhancedMode(' fake-ip '), 'fake-ip');
      for (final bad in [null, '', 'redir', 1]) {
        expect(DnsConfig.normalizeEnhancedMode(bad), 'fake-ip', reason: '$bad');
      }

      expect(DnsConfig.normalizeFakeIpRange('10.0.0.0/8'), '10.0.0.0/8');
      expect(
        DnsConfig.normalizeFakeIpRange(' 198.18.0.1/16 '),
        '198.18.0.1/16',
      );
      for (final bad in [
        null,
        '',
        '198.18.0.1',
        '198.18.0.1/33',
        '999.1.1.1/16',
        'fd00::/8',
      ]) {
        expect(
          DnsConfig.normalizeFakeIpRange(bad),
          DnsConfig.defaultFakeIpRange,
          reason: '$bad',
        );
      }
    });

    test('解析器列表支持多行、逗号、去重并按需回落', () {
      expect(
        DnsConfig.normalizeServers(
          '1.1.1.1, 8.8.8.8\n1.1.1.1\r\ntls://9.9.9.9',
        ),
        ['1.1.1.1', '8.8.8.8', 'tls://9.9.9.9'],
      );
      expect(
        DnsConfig.normalizeServers(['udp://1.1.1.1', '  ', null, '8.8.8.8']),
        ['udp://1.1.1.1', '8.8.8.8'],
      );
      expect(DnsConfig.normalizeServers(''), isEmpty);
      expect(DnsConfig.normalizeServers('   ', fallback: const ['223.5.5.5']), [
        '223.5.5.5',
      ]);
    });

    test('JSON 往返与旧数据回落', () {
      final dns = DnsConfig.defaults.copyWith(
        enabled: true,
        enhancedMode: DnsConfig.redirHost,
        fakeIpRange: '10.10.0.0/16',
        nameserver: const ['https://dns.example/dns-query'],
        fallback: const ['tls://1.0.0.1:853'],
        defaultNameserver: const ['223.5.5.5'],
      );
      expect(DnsConfig.fromJson(dns.toJson()), dns);
      expect(DnsConfig.fromJson(null), DnsConfig.defaults);
      expect(DnsConfig.fromJson('broken'), DnsConfig.defaults);

      final legacy = DnsConfig.fromJson({
        'enabled': true,
        'enhancedMode': 'unknown',
        'fakeIpRange': 'nope',
        'nameserver': <String>[],
        'fallback': <String>[],
        'defaultNameserver': <String>[],
      });
      expect(legacy.enabled, isTrue);
      expect(legacy.enhancedMode, DnsConfig.fakeIp);
      expect(legacy.fakeIpRange, DnsConfig.defaultFakeIpRange);
      expect(legacy.nameserver, DnsConfig.defaultPrimaryNameservers);
      expect(legacy.defaultNameserver, DnsConfig.defaultBootstrapNameservers);
    });
  });

  group('AppSettings', () {
    test('dns / overrideYaml JSON 往返，旧文件落到默认值', () {
      final dns = DnsConfig.defaults.copyWith(
        enabled: true,
        nameserver: const ['udp://1.1.1.1'],
      );
      final settings = AppSettings.defaults().copyWith(
        dns: dns,
        overrideYaml: 'sniffer:\n  enable: true',
      );
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.dns, dns);
      expect(restored.overrideYaml, 'sniffer:\n  enable: true');

      final legacy = AppSettings.fromJson(
        AppSettings.defaults().toJson()
          ..remove('dns')
          ..remove('overrideYaml'),
      );
      expect(legacy.dns, DnsConfig.defaults);
      expect(legacy.overrideYaml, '');
    });
  });

  group('配置生成', () {
    const profile = '''
proxies:
  - name: node-a
    type: trojan
    server: example.com
    port: 443
    password: pass
dns:
  enable: false
  nameserver:
    - 1.1.1.1
  fallback:
    - 8.8.8.8
  fake-ip-range: 198.19.0.1/16
  listen: 0.0.0.0:1053
sniffer:
  enable: false
  force-dns-mapping: true
rules:
  - MATCH,DIRECT
''';

    Map<String, dynamic> generate(
      AppSettings settings, {
      bool windowsTun = false,
    }) {
      final generated = const ConfigGenerator().generate(
        profile: profile,
        settings: settings,
        mode: 'rule',
        windowsTun: windowsTun,
      );
      return _plain(loadYaml(generated))! as Map<String, dynamic>;
    }

    test('未开启自定义 DNS 时保持订阅 dns 原样', () {
      final map = generate(AppSettings.defaults());
      final dns = map['dns'] as Map<String, dynamic>;
      expect(dns['enable'], isFalse);
      expect(dns['nameserver'], ['1.1.1.1']);
      expect(dns['fallback'], ['8.8.8.8']);
      expect(dns['fake-ip-range'], '198.19.0.1/16');
      expect(dns['listen'], '0.0.0.0:1053');
    });

    test('开启后结构化覆盖订阅 dns，空 fallback 会移除', () {
      final dns = DnsConfig.defaults.copyWith(
        enabled: true,
        enhancedMode: DnsConfig.redirHost,
        fakeIpRange: '10.0.0.0/8',
        nameserver: const ['https://dns.example/dns-query'],
        defaultNameserver: const ['223.5.5.5'],
      );
      final map = generate(AppSettings.defaults().copyWith(dns: dns));
      final generated = map['dns'] as Map<String, dynamic>;
      expect(generated['enable'], isTrue);
      expect(generated['enhanced-mode'], DnsConfig.redirHost);
      expect(generated.containsKey('fake-ip-range'), isFalse);
      expect(generated['nameserver'], ['https://dns.example/dns-query']);
      expect(generated['default-nameserver'], ['223.5.5.5']);
      expect(generated.containsKey('fallback'), isFalse);
      // 非 TUN 下订阅自己的 listen 不动。
      expect(generated['listen'], '0.0.0.0:1053');
    });

    test('TUN 下自定义 DNS 保留，listen 被移除', () {
      final dns = DnsConfig.defaults.copyWith(
        enabled: true,
        fakeIpRange: '198.18.0.1/16',
        nameserver: const ['https://dns.example/dns-query'],
        fallback: const ['tls://1.0.0.1:853'],
        defaultNameserver: const ['223.5.5.5'],
      );
      final map = generate(
        AppSettings.defaults().copyWith(dns: dns),
        windowsTun: true,
      );
      final generated = map['dns'] as Map<String, dynamic>;
      expect(generated['enable'], isTrue);
      expect(generated.containsKey('listen'), isFalse);
      expect(generated['enhanced-mode'], DnsConfig.fakeIp);
      expect(generated['fake-ip-range'], '198.18.0.1/16');
      expect(generated['nameserver'], ['https://dns.example/dns-query']);
      expect(generated['fallback'], ['tls://1.0.0.1:853']);
      expect(generated['default-nameserver'], ['223.5.5.5']);
    });

    test('TUN 下未开启自定义 DNS 会补齐可用解析器', () {
      final map = generate(AppSettings.defaults(), windowsTun: true);
      final generated = map['dns'] as Map<String, dynamic>;
      expect(generated['enable'], isTrue);
      expect(generated.containsKey('listen'), isFalse);
      expect(generated['nameserver'], ['1.1.1.1']);
      expect(generated['default-nameserver'], ['223.5.5.5', '119.29.29.29']);
    });

    test('YAML 覆写深度合并映射并整体替换列表', () {
      final settings = AppSettings.defaults().copyWith(
        overrideYaml: '''
sniffer:
  enable: true
  extra:
    a: 1
rules:
  - MATCH,REJECT
''',
      );
      final map = generate(settings);
      final sniffer = map['sniffer'] as Map<String, dynamic>;
      expect(sniffer['enable'], isTrue);
      expect(sniffer['force-dns-mapping'], isTrue);
      expect(sniffer['extra'], {'a': 1});
      expect(map['rules'], ['MATCH,REJECT']);
    });

    test('受保护键与非法 YAML 都被拒绝', () {
      for (final key in ConfigGenerator.protectedOverrideKeys) {
        final settings = AppSettings.defaults().copyWith(
          overrideYaml: '$key: 1',
        );
        expect(
          () => const ConfigGenerator().generate(
            profile: profile,
            settings: settings,
            mode: 'rule',
          ),
          throwsA(
            isA<AppError>().having(
              (error) => error.code,
              'code',
              'overrideInvalid',
            ),
          ),
          reason: key,
        );
        expect(
          () => ConfigGenerator.validateOverride('$key: 1'),
          throwsA(isA<AppError>()),
          reason: key,
        );
      }

      for (final text in ['just a string', 'a: [1', '- 1\n- 2']) {
        expect(
          () => ConfigGenerator.validateOverride(text),
          throwsA(
            isA<AppError>().having(
              (error) => error.code,
              'code',
              'overrideInvalid',
            ),
          ),
          reason: text,
        );
      }
      ConfigGenerator.validateOverride('   ');
    });
  });

  group('RuleProviderInfo', () {
    test('解析名称、行为、类型、规则数与更新时间', () {
      final provider = RuleProviderInfo.fromJson('geosite-cn', {
        'name': 'geosite-cn',
        'behavior': 'domain',
        'type': 'http',
        'ruleCount': 1234,
        'updatedAt': '2026-01-02T03:04:05Z',
      });
      expect(provider.name, 'geosite-cn');
      expect(provider.behavior, 'domain');
      expect(provider.type, 'http');
      expect(provider.ruleCount, 1234);
      expect(provider.updatedAt, DateTime.utc(2026, 1, 2, 3, 4, 5));
    });

    test('缺字段时回落到键名与零值', () {
      final provider = RuleProviderInfo.fromJson('fallback-name', {
        'ruleCount': 'bad',
        'updatedAt': '1970-01-01T00:00:00Z',
      });
      expect(provider.name, 'fallback-name');
      expect(provider.behavior, '');
      expect(provider.type, '');
      expect(provider.ruleCount, 0);
      expect(provider.updatedAt, isNull);
    });
  });

  group('控制器', () {
    late Directory support;
    late AppController controller;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('clashgo_batch_c_');
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

    test('保存 DNS 配置会落盘并在新实例里恢复', () async {
      final next = DnsConfig.defaults.copyWith(
        enabled: true,
        enhancedMode: DnsConfig.redirHost,
        nameserver: const ['https://dns.example/dns-query'],
      );
      await controller.saveDnsConfig(next);
      expect(controller.settings.dns, next);

      final saved = jsonDecode(
        controller.paths.settingsFile.readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(saved['dns']['enabled'], isTrue);
      expect(saved['dns']['enhancedMode'], DnsConfig.redirHost);
      expect(saved['dns']['nameserver'], ['https://dns.example/dns-query']);

      final reopened = AppController(
        await AppPaths.create(),
        startupService: FakeStartupService(),
      );
      addTearDown(reopened.dispose);
      await reopened.initialize();
      expect(reopened.settings.dns, next);
    });

    test('覆写保存前校验，非法内容不落盘', () async {
      await controller.saveOverrideYaml('sniffer:\n  enable: true');
      expect(controller.settings.overrideYaml, 'sniffer:\n  enable: true');

      await expectLater(
        controller.saveOverrideYaml('mode: global'),
        throwsA(
          isA<AppError>().having(
            (error) => error.code,
            'code',
            'overrideInvalid',
          ),
        ),
      );
      expect(controller.settings.overrideYaml, 'sniffer:\n  enable: true');
      final saved = jsonDecode(
        controller.paths.settingsFile.readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(saved['overrideYaml'], 'sniffer:\n  enable: true');

      final reopened = AppController(
        await AppPaths.create(),
        startupService: FakeStartupService(),
      );
      addTearDown(reopened.dispose);
      await reopened.initialize();
      expect(reopened.settings.overrideYaml, 'sniffer:\n  enable: true');
    });
  });

  group('界面入口', () {
    late Directory support;
    late AppController controller;
    late L10n l10n;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('clashgo_batch_c_ui_');
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

    testWidgets('设置页高级配置可进入 DNS 与覆写视图', (tester) async {
      await _openSettingsPage(tester, controller);
      Finder inPage(Finder finder) =>
          find.descendant(of: find.byType(SettingsPage), matching: finder);

      expect(
        inPage(find.text(l10n.get('settings.group.advanced'))),
        findsOneWidget,
      );
      expect(inPage(find.text(l10n.get('settings.dns'))), findsOneWidget);
      expect(inPage(find.text(l10n.get('settings.override'))), findsOneWidget);

      await _openSettingsTile(tester, controller, 'settings.dns');
      expect(inPage(find.text(l10n.get('settings.dnsEnable'))), findsOneWidget);
      expect(
        inPage(find.text(l10n.get('settings.dnsDisabledHint'))),
        findsOneWidget,
      );
      expect(
        inPage(find.text(l10n.get('settings.dnsNameserver'))),
        findsNothing,
      );

      final toggle = _switchFor(l10n, 'settings.dnsEnable');
      expect(tester.widget<Switch>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pump();
      await _settleUi(tester);
      expect(controller.settings.dns.enabled, isTrue);
      expect(
        inPage(find.text(l10n.get('settings.dnsNameserver'))),
        findsOneWidget,
      );
    });

    testWidgets('覆写视图可编辑，受保护键给出错误', (tester) async {
      await _openSettingsPage(tester, controller);
      await _openSettingsTile(tester, controller, 'settings.override');
      Finder inPage(Finder finder) =>
          find.descendant(of: find.byType(SettingsPage), matching: finder);

      final apply = find.widgetWithText(
        FilledButton,
        l10n.get('settings.overrideApply'),
      );
      expect(apply, findsOneWidget);
      expect(tester.widget<FilledButton>(apply).onPressed, isNull);

      final field = find.descendant(
        of: find.byType(SettingsPage),
        matching: find.byType(TextField),
      );
      expect(field, findsOneWidget);
      await tester.enterText(field, 'mode: global');
      await tester.pump();
      expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
      await tester.tap(apply);
      await _settleUi(tester);

      expect(
        inPage(find.textContaining(l10n.get('err.overrideInvalid'))),
        findsOneWidget,
      );
      expect(controller.settings.overrideYaml, '');
    });

    testWidgets('首页工具入口可打开规则提供者页', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 900);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ClashGoApp(controller: controller));
      await tester.pump(const Duration(milliseconds: 400));
      await _settleUi(tester);

      final entry = find.text(l10n.get('tools.ruleProviders'));
      expect(entry, findsOneWidget);
      await tester.ensureVisible(entry);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await _settleUi(tester);

      expect(find.byType(RuleProvidersPage), findsOneWidget);
      expect(find.text(l10n.get('ruleProviders.notRunning')), findsOneWidget);
    });

    testWidgets('DNS 配置与覆写在手机宽度下不溢出', (tester) async {
      await _openSettingsPageAt(tester, controller, const Size(360, 800));
      final overflowed = await _captureOverflow(tester, () async {
        await _openSettingsTile(tester, controller, 'settings.dns');
        final toggle = _switchFor(l10n, 'settings.dnsEnable');
        await tester.tap(toggle);
        await tester.pump();
        await _settleUi(tester);
      });
      expect(overflowed, isEmpty, reason: overflowed.join('\n'));

      await tester.tap(find.byTooltip(l10n.get('common.back')));
      await tester.pump();
      await _settleUi(tester);
      final overrideOverflow = await _captureOverflow(tester, () async {
        await _openSettingsTile(tester, controller, 'settings.override');
      });
      expect(overrideOverflow, isEmpty, reason: overrideOverflow.join('\n'));
    });

    testWidgets('规则提供者页在手机宽度下不溢出', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(411, 891);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ClashGoApp(controller: controller));
      await tester.pump(const Duration(milliseconds: 400));
      await _settleUi(tester);

      final entry = find.text(l10n.get('tools.ruleProviders'));
      await tester.ensureVisible(entry);
      await tester.pump(const Duration(milliseconds: 200));
      final overflowed = await _captureOverflow(tester, () async {
        await tester.tap(entry);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await _settleUi(tester);
      });
      expect(find.byType(RuleProvidersPage), findsOneWidget);
      expect(overflowed, isEmpty, reason: overflowed.join('\n'));
    });
  });

  group('文案', () {
    test('批次 C 新增中英文键完整', () {
      const keys = [
        'settings.group.advanced',
        'settings.dns',
        'settings.dnsHint',
        'settings.dnsEnable',
        'settings.dnsEnableHint',
        'settings.dnsEnhanced',
        'settings.dnsEnhancedHint',
        'settings.dnsFakeIpRange',
        'settings.dnsFakeIpRangeHint',
        'settings.dnsNameserver',
        'settings.dnsNameserverHint',
        'settings.dnsFallback',
        'settings.dnsFallbackHint',
        'settings.dnsDefaultNameserver',
        'settings.dnsDefaultNameserverHint',
        'settings.dnsMode.fakeIp',
        'settings.dnsMode.redirHost',
        'settings.dnsRestartHint',
        'settings.dnsDisabledHint',
        'settings.dnsServersEmpty',
        'settings.dnsServersHint',
        'settings.dnsServersFormat',
        'settings.dnsInvalidRange',
        'settings.override',
        'settings.overrideHint',
        'settings.overrideEditorHint',
        'settings.overridePlaceholder',
        'settings.overrideApply',
        'settings.overrideApplying',
        'settings.overrideSaved',
        'settings.overrideClear',
        'settings.overrideClearTitle',
        'settings.overrideClearMessage',
        'settings.overrideCleared',
        'err.overrideInvalid',
        'nav.ruleProviders',
        'tools.ruleProviders',
        'tools.ruleProvidersSub',
        'ruleProviders.subtitle',
        'ruleProviders.count',
        'ruleProviders.updateAll',
        'ruleProviders.update',
        'ruleProviders.updated',
        'ruleProviders.rules',
        'ruleProviders.empty',
        'ruleProviders.emptyHint',
        'ruleProviders.updateSuccess',
        'ruleProviders.allUpdated',
        'ruleProviders.notRunning',
        'ruleProviders.failed',
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

Future<void> _openSettingsPage(WidgetTester tester, AppController controller) {
  return _openSettingsPageAt(tester, controller, const Size(1280, 900));
}

Future<void> _openSettingsPageAt(
  WidgetTester tester,
  AppController controller,
  Size size,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
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

Future<List<String>> _captureOverflow(
  WidgetTester tester,
  Future<void> Function() action,
) async {
  final prior = FlutterError.onError;
  final overflowed = <String>[];
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('RenderFlex overflowed')) overflowed.add(text);
  };
  try {
    await action();
  } finally {
    FlutterError.onError = prior;
  }
  return overflowed;
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

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}
