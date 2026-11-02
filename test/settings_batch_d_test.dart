import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_info.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/errors.dart';
import 'package:clash_go/core/l10n.dart';
import 'package:clash_go/core/subscription_link.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:clash_go/models/subscription.dart';
import 'package:clash_go/services/backup_service.dart';
import 'package:clash_go/services/config_generator.dart';
import 'package:clash_go/services/core_update_service.dart';
import 'package:clash_go/services/deep_link_service.dart';
import 'package:clash_go/services/subscription_fetcher.dart';
import 'package:clash_go/ui/pages/settings_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:yaml/yaml.dart';

import 'support/fake_startup.dart';

/// 批次 D 回归：剪贴板/深链解析、备份整包恢复、Windows 内核更新、测速 URL 与 TUN 参数。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('设置字段', () {
    test('testUrl / tunMtu / tunStack 可 JSON 往返', () {
      final defaults = AppSettings.defaults();
      expect(defaults.testUrl, AppInfo.defaultTestUrl);
      expect(defaults.tunMtu, AppInfo.tunMtu);
      expect(defaults.tunStack, AppSettings.tunStackGvisor);

      final custom = defaults.copyWith(
        testUrl: 'https://example.com/generate_204',
        tunMtu: 1400,
        tunStack: AppSettings.tunStackMixed,
      );
      final restored = AppSettings.fromJson(custom.toJson());
      expect(restored.testUrl, 'https://example.com/generate_204');
      expect(restored.tunMtu, 1400);
      expect(restored.tunStack, AppSettings.tunStackMixed);

      // 旧版本 settings.json 没有这三个键：落在默认值上。
      final legacy = AppSettings.fromJson(
        defaults.toJson()
          ..remove('testUrl')
          ..remove('tunMtu')
          ..remove('tunStack'),
      );
      expect(legacy.testUrl, AppInfo.defaultTestUrl);
      expect(legacy.tunMtu, AppInfo.tunMtu);
      expect(legacy.tunStack, AppSettings.tunStackGvisor);
    });

    test('异常测速 URL 归一化到默认值', () {
      expect(
        AppSettings.normalizeTestUrl(' https://example.com/x '),
        'https://example.com/x',
      );
      for (final bad in [
        null,
        42,
        '',
        '   ',
        'not a url',
        'ftp://example.com/x',
        '/generate_204',
      ]) {
        expect(
          AppSettings.normalizeTestUrl(bad),
          AppInfo.defaultTestUrl,
          reason: '$bad',
        );
      }
    });

    test('TUN MTU 与协议栈只接受合法值', () {
      expect(AppSettings.normalizeTunMtu(1400), 1400);
      expect(AppSettings.normalizeTunMtu(1400.0), 1400);
      expect(AppSettings.normalizeTunMtu('1300'), 1300);
      expect(AppSettings.normalizeTunMtu(AppSettings.minTunMtu), 1280);
      expect(AppSettings.normalizeTunMtu(AppSettings.maxTunMtu), 9000);
      for (final bad in [null, 'abc', 1279, 9001, -1]) {
        expect(AppSettings.normalizeTunMtu(bad), AppInfo.tunMtu, reason: '$bad');
      }

      expect(
        AppSettings.normalizeTunStack(AppSettings.tunStackSystem),
        AppSettings.tunStackSystem,
      );
      expect(
        AppSettings.normalizeTunStack(AppSettings.tunStackMixed),
        AppSettings.tunStackMixed,
      );
      for (final bad in [null, '', 'random', 1]) {
        expect(
          AppSettings.normalizeTunStack(bad),
          AppSettings.tunStackGvisor,
          reason: '$bad',
        );
      }
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
''';

    test('自定义 MTU 与协议栈写进 tun 段', () {
      final settings = AppSettings.defaults().copyWith(
        tunMtu: 1400,
        tunStack: AppSettings.tunStackMixed,
      );
      final generated = const ConfigGenerator().generate(
        profile: profile,
        settings: settings,
        mode: 'rule',
        windowsTun: true,
      );
      final tun = (loadYaml(generated) as YamlMap)['tun'] as YamlMap;
      expect(tun['mtu'], 1400);
      expect(tun['stack'], AppSettings.tunStackMixed);
      expect(tun['device'], AppInfo.tunDeviceName);
      expect(tun['enable'], isTrue);
      expect(tun['auto-route'], isTrue);
    });

    test('安卓隧道同样使用同一份 MTU 与协议栈', () {
      final settings = AppSettings.defaults().copyWith(
        tunMtu: 1280,
        tunStack: AppSettings.tunStackSystem,
      );
      final generated = const ConfigGenerator().generate(
        profile: profile,
        settings: settings,
        mode: 'rule',
        androidTun: true,
      );
      final tun = (loadYaml(generated) as YamlMap)['tun'] as YamlMap;
      expect(tun['mtu'], 1280);
      expect(tun['stack'], AppSettings.tunStackSystem);
      expect(tun['file-descriptor'], '__TUN_FD__');
      expect(tun.containsKey('device'), isFalse);
    });
  });

  group('订阅链接解析', () {
    test('直接 http(s) 链接原样返回', () {
      expect(
        subscriptionUrlFromLink(' https://example.com/sub?token=a '),
        'https://example.com/sub?token=a',
      );
      expect(
        subscriptionUrlFromLink('http://example.com/sub'),
        'http://example.com/sub',
      );
    });

    test('clash:// 包装的 url / config 参数可解码', () {
      expect(
        subscriptionUrlFromLink(
          'clash://install-config?url=https%3A%2F%2Fexample.com%2Fsub',
        ),
        'https://example.com/sub',
      );
      expect(
        subscriptionUrlFromLink(
          'clash://install-config?config=http%3A%2F%2Fexample.com%2Fsub',
        ),
        'http://example.com/sub',
      );
      // 部分客户端不二次编码，参数原样带冒号与斜杠。
      expect(
        subscriptionUrlFromLink('clash://install-config?url=https://example.com/a'),
        'https://example.com/a',
      );
    });

    test('内嵌链接只解码一次，保留原有百分号转义', () {
      final inner = 'https://example.com/sub?token=abc%2Fdef';
      expect(
        subscriptionUrlFromLink(
          'clash://install-config?url=${Uri.encodeComponent(inner)}',
        ),
        inner,
      );
    });

    test('残缺百分号转义只返回结果而不抛异常', () {
      expect(
        () => subscriptionUrlFromLink(
          'clash://install-config?url=https://example.com/a%25b',
        ),
        returnsNormally,
      );
      expect(
        () => subscriptionUrlFromLink(
          'clash://install-config?url=https://example.com/%25',
        ),
        returnsNormally,
      );
    });

    test('无效输入返回 null', () {
      for (final raw in [
        '',
        '   ',
        'not a url',
        'hello',
        'ftp://example.com/sub',
        'clash://install-config',
        'clash://install-config?url=ftp%3A%2F%2Fexample.com%2Fsub',
      ]) {
        expect(subscriptionUrlFromLink(raw), isNull, reason: raw);
      }
    });
  });

  group('备份内容校验', () {
    test('拒绝会逃出 profiles 目录的订阅 id 与对应 profile', () {
      final snapshot = BackupService.decode(
        _backupBytes(
          subscriptions: [
            _backupSub('../../evil'),
            _backupSub('ok-1'),
          ],
          profiles: {
            '../../evil': 'proxies: []',
            'ok-1': 'proxies: []',
          },
        ),
      );
      expect(snapshot.subscriptions.map((sub) => sub.id), ['ok-1']);
      expect(snapshot.profiles.keys, ['ok-1']);
      expect(snapshot.activeId, 'ok-1');
    });

    test('拒绝非法覆写 YAML', () {
      for (final override in ['- a\n- b', 'tun:\n  enable: true', '=>bad']) {
        expect(
          () => BackupService.decode(
            _backupBytes(settings: {'overrideYaml': override}),
          ),
          throwsA(
            isA<AppError>().having((error) => error.code, 'code', 'backupInvalid'),
          ),
          reason: override,
        );
      }
    });

    test('拒绝越界或冲突的端口', () {
      for (final settings in [
        {'mixedPort': 0},
        {'apiPort': 70000},
        {'mixedPort': AppSettings.defaults().apiPort},
      ]) {
        expect(
          () => BackupService.decode(_backupBytes(settings: settings)),
          throwsA(
            isA<AppError>().having((error) => error.code, 'code', 'backupInvalid'),
          ),
          reason: settings.toString(),
        );
      }
    });

    test('拒绝空白名单的 allow 模式', () {
      expect(
        () => BackupService.decode(
          _backupBytes(
            settings: {
              'splitTunnelMode': AppSettings.splitTunnelAllow,
              'splitTunnelPackages': <String>[],
            },
          ),
        ),
        throwsA(
          isA<AppError>().having((error) => error.code, 'code', 'backupInvalid'),
        ),
      );
    });
  });

  group('Windows 启动参数深链', () {
    test('只认 clash / clashverge 协议，并去掉首尾引号', () {
      expect(
        DeepLinkService.linkFromArguments([
          '--autostart',
          'clash://install-config?url=https%3A%2F%2Fexample.com%2Fsub',
        ]),
        'clash://install-config?url=https%3A%2F%2Fexample.com%2Fsub',
      );
      expect(
        DeepLinkService.linkFromArguments([
          '"clash://install-config?url=http%3A%2F%2Fexample.com%2Fa"',
        ]),
        'clash://install-config?url=http%3A%2F%2Fexample.com%2Fa',
      );
      expect(
        DeepLinkService.linkFromArguments([
          'clashverge://install-config?url=http://example.com/sub',
        ]),
        'clashverge://install-config?url=http://example.com/sub',
      );
      expect(
        DeepLinkService.linkFromArguments([
          'https://example.com/sub',
          '--autostart',
        ]),
        isNull,
      );
      expect(DeepLinkService.linkFromArguments(const []), isNull);
    });
  });

  group('备份格式', () {
    BackupSnapshot roundTripPayload() {
      final settings = AppSettings.defaults().copyWith(
        testUrl: 'https://example.com/204',
        tunMtu: 1400,
        tunStack: AppSettings.tunStackMixed,
      );
      final subscriptions = [
        Subscription(
          id: 'sub-a',
          name: 'A',
          url: 'https://example.com/a',
          isLocal: false,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
        Subscription(
          id: 'sub-b',
          name: 'B',
          url: '',
          isLocal: true,
          createdAt: DateTime.utc(2026, 2, 1),
        ),
      ];
      final bytes = BackupService.encode(
        settings: settings,
        subscriptions: subscriptions,
        activeId: 'sub-b',
        selections: {
          'sub-a': {'Proxy': 'node-a'},
        },
        testedDelays: {
          'sub-a': {'node-a': 120},
        },
        profiles: {
          'sub-a': 'proxies:\n  - name: node-a\n',
          'sub-b': 'proxies:\n  - name: local\n',
        },
        exportedAt: DateTime.utc(2026, 11, 2, 10),
      );
      return BackupService.decode(bytes);
    }

    test('整包往返保留设置、订阅与选择', () {
      final snapshot = roundTripPayload();
      expect(snapshot.settings.testUrl, 'https://example.com/204');
      expect(snapshot.settings.tunMtu, 1400);
      expect(snapshot.settings.tunStack, AppSettings.tunStackMixed);
      expect(snapshot.subscriptions.map((sub) => sub.id), ['sub-a', 'sub-b']);
      expect(snapshot.activeId, 'sub-b');
      expect(snapshot.selections, {
        'sub-a': {'Proxy': 'node-a'},
      });
      expect(snapshot.testedDelays, {
        'sub-a': {'node-a': 120},
      });
      expect(snapshot.profileCount, 2);
      expect(snapshot.exportedAt, DateTime.utc(2026, 11, 2, 10));
    });

    test('坏记录被丢弃、孤儿数据不恢复', () {
      final payload = jsonDecode(
        utf8.decode(
          BackupService.encode(
            settings: AppSettings.defaults(),
            subscriptions: [
              Subscription(
                id: 'keep',
                name: 'Keep',
                url: 'https://example.com/keep',
                isLocal: false,
                createdAt: DateTime.utc(2026, 1, 1),
              ),
              Subscription(
                id: '',
                name: 'Missing id',
                url: 'https://example.com/x',
                isLocal: false,
                createdAt: DateTime.utc(2026, 1, 1),
              ),
              Subscription(
                id: 'keep',
                name: 'Duplicate',
                url: 'https://example.com/dup',
                isLocal: false,
                createdAt: DateTime.utc(2026, 1, 1),
              ),
            ],
            activeId: 'gone',
            selections: {
              'keep': {'Proxy': 'node-a'},
              'gone': {'Proxy': 'node-b'},
            },
            testedDelays: {
              'keep': {'node-a': 88},
              'gone': {'node-b': 99},
            },
            profiles: {
              'keep': 'proxies: []\n',
              'gone': 'proxies: []\n',
            },
          ),
        ),
      ) as Map<String, dynamic>;

      final snapshot = BackupService.decode(
        Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      );
      expect(snapshot.subscriptions.map((sub) => sub.id), ['keep']);
      expect(snapshot.activeId, 'keep', reason: '失效的 activeId 回退到第一个订阅');
      expect(snapshot.selections.keys, ['keep']);
      expect(snapshot.testedDelays.keys, ['keep']);
      expect(snapshot.profiles.keys, ['keep']);
    });

    test('非备份 JSON 一律按无效处理', () {
      Matcher invalid() => isA<AppError>().having(
        (error) => error.code,
        'code',
        'backupInvalid',
      );

      expect(
        () => BackupService.decode(Uint8List.fromList([0xff, 0x00, 0x12])),
        throwsA(invalid()),
      );
      expect(
        () => BackupService.decode(
          Uint8List.fromList(utf8.encode(jsonEncode({'format': 'other'}))),
        ),
        throwsA(invalid()),
      );
      expect(
        () => BackupService.decode(
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'format': BackupService.format,
                'formatVersion': 2,
                'settings': <String, dynamic>{},
              }),
            ),
          ),
        ),
        throwsA(invalid()),
      );
      expect(
        () => BackupService.decode(
          Uint8List.fromList(
            utf8.encode(
              jsonEncode({
                'format': BackupService.format,
                'formatVersion': 1,
              }),
            ),
          ),
        ),
        throwsA(invalid()),
      );
    });
  });

  group('内核更新', () {
    Uint8List zipOf(Map<String, List<int>> files) {
      final archive = Archive();
      files.forEach(
        (name, bytes) => archive.addFile(ArchiveFile.bytes(name, bytes)),
      );
      return Uint8List.fromList(ZipEncoder().encode(archive));
    }

    test('官方资产名里的 exe 能被取出', () {
      final bytes = CoreUpdateService.extractCore(
        zipOf({
          'mihomo-windows-amd64.exe': [1, 2, 3, 4],
          'README.md': [9],
        }),
      );
      expect(bytes, [1, 2, 3, 4]);
    });

    test('同时存在 mihomo.exe 时优先取它', () {
      final bytes = CoreUpdateService.extractCore(
        zipOf({
          'mihomo-windows-amd64.exe': [1, 2],
          'mihomo.exe': [7, 8, 9],
        }),
      );
      expect(bytes, [7, 8, 9]);
    });

    test('没有 exe、空 exe 或坏 zip 都报 coreUpdate', () {
      Matcher coreError() => isA<AppError>().having(
        (error) => error.code,
        'code',
        'coreUpdate',
      );

      expect(
        () => CoreUpdateService.extractCore(zipOf({'README.md': [1]})),
        throwsA(coreError()),
      );
      expect(
        () => CoreUpdateService.extractCore(zipOf({'mihomo.exe': <int>[]})),
        throwsA(coreError()),
      );
      expect(
        () => CoreUpdateService.extractCore(Uint8List.fromList([1, 2, 3])),
        throwsA(coreError()),
      );
    });

    test('从 -v 输出里取版本号', () {
      expect(
        CoreUpdateService.versionFromOutput(
          'Mihomo Meta v1.19.33 windows amd64 with go1.26.10',
        ),
        '1.19.33',
      );
      expect(
        CoreUpdateService.versionFromOutput('v1.20.0-alpha.1 linux arm64'),
        '1.20.0-alpha.1',
      );
      expect(CoreUpdateService.versionFromOutput('no version here'), isNull);
    });
  });

  group('文案', () {
    test('批次 D 新增 key 在中英文里都存在', () {
      const keys = [
        'subscriptions.importClipboard',
        'subscriptions.clipboardEmpty',
        'subscriptions.clipboardNoLink',
        'subscriptions.linkInvalid',
        'settings.testUrl',
        'settings.testUrlHint',
        'settings.testUrlTitle',
        'settings.testUrlInvalid',
        'settings.tunParams',
        'settings.tunMtu',
        'settings.tunMtuHint',
        'settings.tunMtuTitle',
        'settings.tunMtuInvalid',
        'settings.tunStack',
        'settings.tunStackHint',
        'settings.tunRestartHint',
        'settings.backupExport',
        'settings.backupExportHint',
        'settings.backupImport',
        'settings.backupImportHint',
        'settings.backupExportTitle',
        'settings.backupExportMessage',
        'settings.backupExportDone',
        'settings.backupExportFailed',
        'settings.backupImportTitle',
        'settings.backupImportMessage',
        'settings.backupImportInvalid',
        'settings.backupImported',
        'settings.backupImportedRestart',
        'settings.checkCoreUpdate',
        'settings.checkCoreUpdateHint',
        'settings.coreCheckFailed',
        'settings.coreUpdateLatest',
        'settings.coreUpdateAvailable',
        'settings.coreUpdateDialogTitle',
        'settings.coreUpdateDialogMessage',
        'settings.coreUpdateAction',
        'settings.coreUpdateProgress',
        'settings.coreUpdateInstalled',
        'settings.coreUpdateTunHint',
        'settings.coreRestore',
        'settings.coreRestoreHint',
        'settings.coreRestoreTitle',
        'settings.coreRestoreMessage',
        'settings.coreRestoreDone',
        'settings.coreSource',
        'settings.coreSourceBundled',
        'settings.coreSourceUpdated',
        'err.backupInvalid',
        'err.coreUpdate',
        'err.coreUpdateVerify',
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

  group('控制器整包恢复', () {
    late Directory support;
    late AppController controller;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('clashgo_batch_d_');
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

    test('导出的备份可在新实例里整包恢复并落盘', () async {
      controller.settings = AppSettings.defaults().copyWith(
        testUrl: 'https://example.com/204',
        tunMtu: 1400,
        tunStack: AppSettings.tunStackMixed,
      );
      await controller.store.saveSettings(controller.settings);
      controller.subscriptions = [
        Subscription(
          id: 'sub-a',
          name: 'A',
          url: 'https://example.com/a',
          isLocal: false,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
        Subscription(
          id: 'sub-b',
          name: 'B',
          url: 'https://example.com/b',
          isLocal: false,
          createdAt: DateTime.utc(2026, 2, 1),
        ),
      ];
      controller.activeId = 'sub-b';
      controller.selections = {
        'sub-a': {'Proxy': 'node-a'},
      };
      await controller.store.saveSubscriptions(controller.subscriptions);
      await controller.store.saveActiveId(controller.activeId);
      await controller.store.saveSelections(controller.selections);
      await controller.store.writeProfile('sub-a', 'proxies:\n  - name: node-a\n');

      final bytes = await controller.exportBackup();

      // 先把这个目录改成另一份数据，确认恢复是真的整包替换而不是叠加。
      controller.settings = AppSettings.defaults().copyWith(
        testUrl: 'https://other.example/x',
      );
      await controller.store.saveSettings(controller.settings);
      controller.subscriptions = [
        Subscription(
          id: 'sub-c',
          name: 'C',
          url: 'https://example.com/c',
          isLocal: false,
          createdAt: DateTime.utc(2026, 3, 1),
        ),
      ];
      controller.activeId = 'sub-c';
      controller.selections = {};
      await controller.store.saveSubscriptions(controller.subscriptions);
      await controller.store.saveActiveId(controller.activeId);
      await controller.store.saveSelections(controller.selections);

      final restored = AppController(
        await AppPaths.create(),
        startupService: FakeStartupService(),
      );
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.subscriptions.map((sub) => sub.id), ['sub-c']);

      final snapshot = restored.readBackup(bytes);
      expect(snapshot.subscriptions.length, 2);
      expect(snapshot.profileCount, 1);
      await restored.applyBackup(snapshot);

      expect(restored.settings.testUrl, 'https://example.com/204');
      expect(restored.settings.tunMtu, 1400);
      expect(restored.settings.tunStack, AppSettings.tunStackMixed);
      expect(restored.subscriptions.map((sub) => sub.id), ['sub-a', 'sub-b']);
      expect(restored.activeId, 'sub-b');
      expect(restored.selections, {
        'sub-a': {'Proxy': 'node-a'},
      });
      expect(
        await restored.store.readProfile('sub-a'),
        contains('node-a'),
      );

      final saved = jsonDecode(
        restored.paths.settingsFile.readAsStringSync(),
      ) as Map<String, dynamic>;
      expect(saved['testUrl'], 'https://example.com/204');
      expect(saved['tunMtu'], 1400);
      expect(saved['tunStack'], AppSettings.tunStackMixed);
    });

    test('无效深链只记提示，不导入订阅', () async {
      await controller.handleIncomingLink(
        'clash://install-config?url=ftp%3A%2F%2Fexample.com%2Fsub',
      );
      expect(controller.subscriptions, isEmpty);
    });

    testWidgets('网络页显示测速 URL 与 TUN 参数入口', (tester) async {
      await _openSettingsPage(tester, controller);
      await _openSettingsTile(tester, controller, 'settings.hub.clash');
      final l10n = controller.l10n;
      Finder inPage(Finder finder) => find.descendant(
        of: find.byType(SettingsPage),
        matching: finder,
      );
      expect(inPage(find.text(l10n.get('settings.testUrl'))), findsOneWidget);
      expect(inPage(find.text(l10n.get('settings.tunParams'))), findsOneWidget);
      expect(inPage(find.text(l10n.get('settings.tunMtu'))), findsOneWidget);
      expect(inPage(find.text(l10n.get('settings.tunStack'))), findsOneWidget);
    });

    testWidgets('数据页显示备份导出与导入入口', (tester) async {
      await _openSettingsPage(tester, controller);
      await _openSettingsTile(tester, controller, 'settings.hub.data');
      final l10n = controller.l10n;
      Finder inPage(Finder finder) => find.descendant(
        of: find.byType(SettingsPage),
        matching: finder,
      );
      expect(
        inPage(find.text(l10n.get('settings.backupExport'))),
        findsOneWidget,
      );
      expect(
        inPage(find.text(l10n.get('settings.backupImport'))),
        findsOneWidget,
      );
    });

    testWidgets('关于页显示内核来源与检查更新入口', (tester) async {
      await _openSettingsPage(tester, controller);
      await _openSettingsTile(tester, controller, 'settings.about');
      final l10n = controller.l10n;
      Finder inPage(Finder finder) => find.descendant(
        of: find.byType(SettingsPage),
        matching: finder,
      );
      expect(inPage(find.text(l10n.get('settings.coreSource'))), findsOneWidget);
      expect(
        inPage(find.text(l10n.get('settings.coreSourceBundled'))),
        findsOneWidget,
      );
      expect(
        inPage(find.text(l10n.get('settings.checkCoreUpdate'))),
        findsOneWidget,
      );
    });
  });

  group('订阅更新并发', () {
    late Directory support;
    late _GatedFetcher fetcher;
    late AppController controller;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('clashgo_update_');
      PathProviderPlatform.instance = _Temp(support.path);
      fetcher = _GatedFetcher();
      controller = AppController(
        await AppPaths.create(),
        startupService: FakeStartupService(),
        fetcher: fetcher,
      );
      await controller.initialize();
      controller.subscriptions = [
        _subscription('sub-a', 'A'),
        _subscription('sub-b', 'B'),
        _subscription('sub-c', 'C'),
      ];
      await controller.store.saveSubscriptions(controller.subscriptions);
    });

    tearDown(() async {
      controller.dispose();
      if (await support.exists()) await support.delete(recursive: true);
    });

    test('更新期间重排：结果按 id 落到正确条目', () async {
      final update = controller.updateSubscription(
        'sub-a',
        restartIfActive: false,
        silent: true,
      );
      await fetcher.started.future;
      await controller.reorderSubscriptions(['sub-c', 'sub-b', 'sub-a']);
      fetcher.release.complete();

      expect(await update, isTrue);
      expect(controller.subscriptions.map((sub) => sub.id), [
        'sub-c',
        'sub-b',
        'sub-a',
      ]);
      expect(controller.subscriptions[2].lastUpdatedAt, isNotNull);
      expect(controller.subscriptions[0].lastUpdatedAt, isNull);
      expect(controller.subscriptions[1].lastUpdatedAt, isNull);
    });

    test('更新期间删除：不复活条目也不留下 profile', () async {
      final update = controller.updateSubscription(
        'sub-a',
        restartIfActive: false,
        silent: true,
      );
      await fetcher.started.future;
      await controller.deleteSubscription('sub-a');
      fetcher.release.complete();

      expect(await update, isFalse);
      expect(controller.subscriptions.map((sub) => sub.id), ['sub-b', 'sub-c']);
      expect(await controller.store.readProfile('sub-a'), isNull);
    });

    test('更新期间编辑：保留新的名称与链接', () async {
      final update = controller.updateSubscription(
        'sub-a',
        restartIfActive: false,
        silent: true,
      );
      await fetcher.started.future;
      await controller.editSubscription(
        'sub-a',
        name: 'Renamed',
        url: 'https://example.com/new',
        autoUpdate: false,
        updateIntervalMinutes: 60,
      );
      fetcher.release.complete();

      expect(await update, isTrue);
      final sub = controller.subscriptions.first;
      expect(sub.name, 'Renamed');
      expect(sub.url, 'https://example.com/new');
      expect(sub.autoUpdate, isFalse);
      expect(sub.lastUpdatedAt, isNotNull);
    });
  });
}

Subscription _subscription(String id, String name) => Subscription(
  id: id,
  name: name,
  url: 'https://example.com/$id',
  isLocal: false,
  createdAt: DateTime.utc(2026, 1, 1),
);

class _GatedFetcher extends SubscriptionFetcher {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<FetchedProfile> fetchUrl(
    String url, {
    String userAgent = 'clash.meta',
    int? proxyPort,
  }) async {
    if (!started.isCompleted) started.complete();
    await release.future;
    return const FetchedProfile(
      content: 'proxies:\n  - name: node\n    type: direct\n',
      headers: SubscriptionHeaders(),
      sourceUrl: null,
    );
  }
}

Map<String, dynamic> _backupSub(String id) => {
  'id': id,
  'name': id,
  'url': 'https://example.com/$id',
  'isLocal': false,
  'createdAt': '2026-01-01T00:00:00.000Z',
};

Uint8List _backupBytes({
  Map<String, dynamic>? settings,
  List<Map<String, dynamic>> subscriptions = const [],
  Map<String, String> profiles = const {},
}) {
  final payload = <String, dynamic>{
    'format': BackupService.format,
    'formatVersion': BackupService.formatVersion,
    'app': AppInfo.name,
    'appVersion': AppInfo.version,
    'exportedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
    'settings': {...AppSettings.defaults().toJson(), ...?settings},
    'subscriptions': subscriptions,
    'activeId': null,
    'selections': <String, dynamic>{},
    'testedDelays': <String, dynamic>{},
    'profiles': profiles,
  };
  return Uint8List.fromList(utf8.encode(jsonEncode(payload)));
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

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}
