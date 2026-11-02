import 'dart:io';

import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/l10n.dart';
import 'package:clash_go/core/theme.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:clash_go/services/android_apps.dart';
import 'package:clash_go/services/android_core.dart';
import 'package:clash_go/ui/pages/settings_page.dart';
import 'package:clash_go/ui/widgets/split_tunnel_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';

import 'support/fake_startup.dart';

/// 批次 B 回归：安卓分应用代理的设置持久化、原生通道契约与设置页交互。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const appsChannel = MethodChannel(AndroidApps.channelName);
  late Directory support;
  late AppController controller;

  // 控制器初始化要读真实 settings.json，必须放在 setUp 的真实异步区；
  // 在 testWidgets 的 FakeAsync 区里 await 会永远不返回。
  setUp(() async {
    support = await Directory.systemTemp.createTemp('clashgo_batch_b_');
    PathProviderPlatform.instance = _Temp(support.path);
    controller = AppController(
      await AppPaths.create(),
      startupService: FakeStartupService(),
    );
    await controller.initialize();
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(appsChannel, null);
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.clashgo.clash_go/core'),
      null,
    );
    controller.dispose();
    if (await support.exists()) await support.delete(recursive: true);
  });

  test('分应用字段可 JSON 往返，异常值被清洗', () {
    final defaults = AppSettings.defaults();
    expect(defaults.splitTunnelMode, AppSettings.splitTunnelAll);
    expect(defaults.splitTunnelPackages, isEmpty);

    final custom = defaults.copyWith(
      splitTunnelMode: AppSettings.splitTunnelAllow,
      splitTunnelPackages: ['com.example.browser', 'com.example.chat'],
    );
    final restored = AppSettings.fromJson(custom.toJson());
    expect(restored.splitTunnelMode, AppSettings.splitTunnelAllow);
    expect(restored.splitTunnelPackages, [
      'com.example.browser',
      'com.example.chat',
    ]);

    // 旧版本 settings.json 没有这两个键：落在默认值上，不触发迁移。
    final legacy = AppSettings.fromJson(
      defaults.toJson()
        ..remove('splitTunnelMode')
        ..remove('splitTunnelPackages'),
    );
    expect(legacy.splitTunnelMode, AppSettings.splitTunnelAll);
    expect(legacy.splitTunnelPackages, isEmpty);

    final malformed = AppSettings.fromJson({
      ...defaults.toJson(),
      'splitTunnelMode': 'random',
      'splitTunnelPackages': [' com.a ', '', 'com.a', 42, 'com.b'],
    });
    expect(malformed.splitTunnelMode, AppSettings.splitTunnelAll);
    expect(malformed.splitTunnelPackages, ['com.a', 'com.b']);
  });

  test('分流签名不受选择顺序影响', () {
    final a = AppSettings.defaults().copyWith(
      splitTunnelMode: AppSettings.splitTunnelAllow,
      splitTunnelPackages: ['com.b', 'com.a'],
    );
    final b = AppSettings.defaults().copyWith(
      splitTunnelMode: AppSettings.splitTunnelAllow,
      splitTunnelPackages: ['com.a', 'com.b'],
    );
    expect(a.splitTunnelSignature, b.splitTunnelSignature);
    expect(
      a.splitTunnelSignature,
      isNot(a.copyWith(splitTunnelPackages: ['com.a']).splitTunnelSignature),
    );
  });

  test('AndroidApps.list 只解析元数据并排序', () async {
    messenger.setMockMethodCallHandler(appsChannel, (call) async {
      expect(call.method, 'list');
      return [
        {
          'package': 'com.example.zeta',
          'label': 'Zeta',
          'system': false,
          // 旧原生实现会顺带塞图标；列表现在不读它，也不该再为它承担传输体积。
          'icon': Uint8List.fromList([1, 2, 3]),
        },
        {'package': 'com.example.alpha', 'label': 'alpha', 'system': true},
        {'label': 'missing package'},
      ];
    });

    final apps = await AndroidApps.list();
    expect(apps.map((app) => app.packageName), [
      'com.example.alpha',
      'com.example.zeta',
    ]);
    expect(apps.first.system, isTrue);
    expect(apps.last.label, 'Zeta');
  });

  test('AndroidApps.icons 按 16 个一批请求并合并结果', () async {
    final batches = <List<String>>[];
    messenger.setMockMethodCallHandler(appsChannel, (call) async {
      expect(call.method, 'icons');
      final batch = (call.arguments as List).cast<String>();
      batches.add(batch);
      return {
        for (final name in batch) name: Uint8List.fromList(name.codeUnits),
      };
    });

    final packages = [for (var i = 0; i < 40; i++) 'com.example.app$i'];
    final icons = await AndroidApps.icons(packages);

    expect(batches.map((batch) => batch.length), [16, 16, 8]);
    expect(batches.expand((batch) => batch).toList(), packages);
    expect(icons, hasLength(40));
    expect(
      icons['com.example.app0'],
      Uint8List.fromList('com.example.app0'.codeUnits),
    );
  });

  test('AndroidApps.icons 某一批失败不影响其它批次', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(appsChannel, (call) async {
      calls++;
      if (calls == 2) throw PlatformException(code: 'binder_full');
      final batch = (call.arguments as List).cast<String>();
      return {for (final name in batch) name: Uint8List.fromList([calls])};
    });

    final packages = [for (var i = 0; i < 40; i++) 'com.example.app$i'];
    final icons = await AndroidApps.icons(packages);

    expect(calls, 3);
    expect(icons, hasLength(24));
    expect(icons.containsKey('com.example.app15'), isTrue);
    expect(icons.containsKey('com.example.app16'), isFalse);
    expect(icons.containsKey('com.example.app32'), isTrue);
  });

  testWidgets('分应用列表加载完成后按包名请求图标', (tester) async {
    final apps = <AndroidAppInfo>[
      const AndroidAppInfo(
        packageName: 'com.example.chrome',
        label: 'Chrome',
        system: false,
      ),
      const AndroidAppInfo(
        packageName: 'com.example.youtube',
        label: 'YouTube',
        system: false,
      ),
    ];
    List<String>? requested;

    await tester.pumpWidget(
      _Harness(
        controller: controller,
        child: SingleChildScrollView(
          child: SplitTunnelSection(
            controller: controller,
            loadApps: () async => apps,
            loadIcons: (packageNames) async {
              requested = packageNames;
              return const {};
            },
          ),
        ),
      ),
    );
    await _pumpUi(tester);

    expect(requested, ['com.example.chrome', 'com.example.youtube']);
  });

  test('AndroidCore.start 把分应用参数递给原生通道', () async {
    Map<Object?, Object?>? captured;
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.clashgo.clash_go/core'),
      (call) async {
        if (call.method == 'startVpn') {
          captured = call.arguments as Map<Object?, Object?>;
          return true;
        }
        return null;
      },
    );

    await AndroidCore.start(
      configPath: '/tmp/config.yaml',
      runtimeDir: '/tmp/run',
      binaryPath: '/tmp/mihomo',
      logPath: '/tmp/core.log',
      apiPort: 19090,
      subscriptionId: 'sub-1',
      ipv6: true,
      notificationTitle: 'ClashGo',
      notificationText: 'VPN',
      notificationStop: 'Stop',
      splitTunnelMode: AppSettings.splitTunnelAllow,
      splitTunnelPackages: const ['com.example.chat'],
    );

    expect(captured?['splitMode'], AppSettings.splitTunnelAllow);
    expect(captured?['splitPackages'], ['com.example.chat']);
  });

  test('AndroidCoreStatus 暴露实际分应用签名用于重启判断', () {
    final running = AndroidCoreStatus.fromMap({
      'state': 'running',
      'pid': 123,
      'serviceRunning': true,
      'apiPort': 19090,
      'splitMode': AppSettings.splitTunnelAllow,
      'splitPackages': ['com.example.zeta', 'com.example.alpha'],
    });
    expect(running.splitSignature, 'allow:com.example.alpha,com.example.zeta');

    // 旧版原生层没有这两个字段：返回 null，让调用方退回设置里的签名。
    final legacy = AndroidCoreStatus.fromMap({
      'state': 'running',
      'pid': 123,
      'serviceRunning': true,
    });
    expect(legacy.splitSignature, isNull);
  });

  testWidgets('桌面宿主不显示分应用代理入口', (tester) async {
    await tester.pumpWidget(
      _Harness(controller: controller, child: const SettingsPage()),
    );
    await _pumpUi(tester);
    expect(
      find.text(controller.l10n.get('settings.splitTunnel')),
      findsNothing,
    );
  });

  testWidgets('安卓宿主显示入口并完成模式与选择持久化', (tester) async {
    final l10n = controller.l10n;
    final apps = <AndroidAppInfo>[
      const AndroidAppInfo(
        packageName: 'com.example.chrome',
        label: 'Chrome',
        system: false,
      ),
      const AndroidAppInfo(
        packageName: 'com.example.youtube',
        label: 'YouTube',
        system: false,
      ),
      const AndroidAppInfo(
        packageName: 'com.android.settings',
        label: '设置',
        system: true,
      ),
    ];
    await tester.pumpWidget(
      _Harness(
        controller: controller,
        child: SettingsPage(
          androidOverride: true,
          appsLoader: () async => apps,
        ),
      ),
    );
    await _pumpUi(tester);

    final entry = find.text(l10n.get('settings.splitTunnel'));
    await tester.ensureVisible(entry);
    await _pumpUi(tester);
    await tester.tap(entry);
    await _pumpUi(tester);

    expect(find.byType(SplitTunnelSection), findsOneWidget);
    expect(find.text('Chrome'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(find.text(l10n.get('settings.split.count', [0])), findsOneWidget);

    // 未选应用时「仅代理所选」是锁定的。
    final allowMode = find.text(l10n.get('settings.split.mode.allow'));
    await tester.ensureVisible(allowMode);
    await _pumpUi(tester);
    await tester.tap(allowMode);
    await _pumpUi(tester);
    expect(controller.settings.splitTunnelMode, AppSettings.splitTunnelAll);

    final youtube = find.text('YouTube');
    await tester.ensureVisible(youtube);
    await _pumpUi(tester);
    await tester.tap(youtube);
    await _settleIo(tester);
    expect(controller.settings.splitTunnelPackages, ['com.example.youtube']);

    await tester.ensureVisible(allowMode);
    await _pumpUi(tester);
    await tester.tap(allowMode);
    await _settleIo(tester);
    expect(controller.settings.splitTunnelMode, AppSettings.splitTunnelAllow);
    expect(controller.settings.splitTunnelPackages, ['com.example.youtube']);
    expect(find.text(l10n.get('settings.split.count', [1])), findsOneWidget);
  });

  testWidgets('搜索过滤后全选只作用于当前列表', (tester) async {
    final l10n = controller.l10n;
    final apps = <AndroidAppInfo>[
      const AndroidAppInfo(
        packageName: 'com.example.chrome',
        label: 'Chrome',
        system: false,
      ),
      const AndroidAppInfo(
        packageName: 'com.example.youtube',
        label: 'YouTube',
        system: false,
      ),
    ];

    await tester.pumpWidget(
      _Harness(
        controller: controller,
        child: SingleChildScrollView(
          child: SplitTunnelSection(
            controller: controller,
            loadApps: () async => apps,
          ),
        ),
      ),
    );
    await _pumpUi(tester);

    await tester.enterText(find.byType(TextField), 'you');
    await _pumpUi(tester);
    expect(find.text('Chrome'), findsNothing);
    expect(find.text('YouTube'), findsOneWidget);

    final selectAll = find.text(l10n.get('settings.split.selectAll'));
    await tester.ensureVisible(selectAll);
    await _pumpUi(tester);
    await tester.tap(selectAll);
    await _settleIo(tester);
    expect(controller.settings.splitTunnelPackages, ['com.example.youtube']);
  });

  testWidgets('仅代理所选模式下不能移除最后一个应用', (tester) async {
    final l10n = controller.l10n;
    final apps = <AndroidAppInfo>[
      const AndroidAppInfo(
        packageName: 'com.example.chrome',
        label: 'Chrome',
        system: false,
      ),
      const AndroidAppInfo(
        packageName: 'com.example.youtube',
        label: 'YouTube',
        system: false,
      ),
    ];

    await tester.pumpWidget(
      _Harness(
        controller: controller,
        child: Scaffold(
          body: SingleChildScrollView(
            child: SplitTunnelSection(
              controller: controller,
              loadApps: () async => apps,
            ),
          ),
        ),
      ),
    );
    await _pumpUi(tester);

    final youtube = find.text('YouTube');
    await tester.tap(youtube);
    await _settleIo(tester);
    expect(controller.settings.splitTunnelPackages, ['com.example.youtube']);

    final allowMode = find.text(l10n.get('settings.split.mode.allow'));
    await tester.tap(allowMode);
    await _settleIo(tester);
    expect(controller.settings.splitTunnelMode, AppSettings.splitTunnelAllow);

    // allow 模式下清空列表会让内核无法启动，最后一次取消必须被拦住。
    await tester.tap(youtube);
    await _settleIo(tester);
    expect(controller.settings.splitTunnelMode, AppSettings.splitTunnelAllow);
    expect(controller.settings.splitTunnelPackages, ['com.example.youtube']);
    expect(find.text(l10n.get('settings.split.allowKeepOne')), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('手机宽度下分应用代理页不溢出', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final apps = <AndroidAppInfo>[
      const AndroidAppInfo(
        packageName: 'com.example.very.long.package.name',
        label: '一个名字很长的测试应用',
        system: true,
      ),
      const AndroidAppInfo(
        packageName: 'com.example.youtube',
        label: 'YouTube',
        system: false,
      ),
    ];

    await tester.pumpWidget(
      _Harness(
        controller: controller,
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SplitTunnelSection(
                controller: controller,
                loadApps: () async => apps,
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpUi(tester);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await _settleIo(tester);
}

Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

class _Harness extends StatelessWidget {
  const _Harness({required this.controller, required this.child});

  final AppController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.build(
      brightness: Brightness.light,
      accent: const Color(0xFF3B82F6),
    );
    return ChangeNotifierProvider<AppController>.value(
      value: controller,
      child: L10nScope(
        l10n: controller.l10n,
        child: MaterialApp(
          theme: theme,
          home: Scaffold(body: child),
        ),
      ),
    );
  }
}

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
