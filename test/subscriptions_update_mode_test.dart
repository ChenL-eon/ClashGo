import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/l10n.dart';
import 'package:clash_go/data/local_store.dart';
import 'package:clash_go/models/subscription.dart';
import 'package:clash_go/services/subscription_fetcher.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/fake_startup.dart';

/// 订阅更新方式回归：
/// 1. 新订阅默认直连，JSON 往返保留开关；
/// 2. 内核在线时只有勾选“更新走代理”的订阅才传混合端口；
/// 3. 添加/编辑订阅弹窗都能看到并保存该选项。
const _profile = '''
proxies:
  - name: 节点A
    type: ss
    server: 127.0.0.1
    port: 1080
    cipher: aes-128-gcm
    password: test
''';

Subscription _remote(String id, String name, {bool viaProxy = false}) => Subscription(
      id: id,
      name: name,
      url: 'https://example.com/$id',
      isLocal: false,
      createdAt: DateTime(2026, 11, 1),
      lastUpdatedAt: DateTime(2026, 11, 1, 10),
      updateViaProxy: viaProxy,
    );

class _RecordingFetcher extends SubscriptionFetcher {
  final List<int?> proxyPorts = [];

  @override
  Future<FetchedProfile> fetchUrl(
    String url, {
    String userAgent = 'clash.meta',
    int? proxyPort,
  }) async {
    proxyPorts.add(proxyPort);
    return const FetchedProfile(
      content: _profile,
      headers: SubscriptionHeaders(),
      sourceUrl: null,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('更新方式默认直连并随 JSON 往返', () {
    final direct = _remote('a', '直连机场');
    expect(direct.updateViaProxy, isFalse);

    final legacy = direct.toJson()..remove('updateViaProxy');
    expect(Subscription.fromJson(legacy).updateViaProxy, isFalse);

    final proxied = direct.copyWith(updateViaProxy: true);
    expect(proxied.toJson()['updateViaProxy'], isTrue);
    expect(Subscription.fromJson(proxied.toJson()).updateViaProxy, isTrue);
  });

  group('控制器按订阅分流', () {
    late Directory support;
    late AppController controller;
    late _RecordingFetcher fetcher;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('clashgo_update_mode_');
      PathProviderPlatform.instance = _Temp(support.path);
      final paths = await AppPaths.create();
      final store = LocalStore(paths);
      await store.saveSubscriptions([
        _remote('direct', '直连机场'),
        _remote('proxied', '代理机场', viaProxy: true),
      ]);
      await store.saveActiveId('direct');
      fetcher = _RecordingFetcher();
      controller = AppController(
        paths,
        startupService: FakeStartupService(),
        fetcher: fetcher,
      );
      await controller.initialize();
      // 预览内核同样算在线：用它验证直连订阅不被强制改走代理。
      controller.phase = CorePhase.preview;
    });

    tearDown(() async {
      controller.dispose();
      await support.delete(recursive: true);
    });

    test('直连订阅即使内核在线也不传代理端口', () async {
      expect(
        await controller.updateSubscription('direct', restartIfActive: false, silent: true),
        isTrue,
      );
      expect(fetcher.proxyPorts.last, isNull);
    });

    test('代理订阅在内核在线时传混合端口', () async {
      expect(
        await controller.updateSubscription('proxied', restartIfActive: false, silent: true),
        isTrue,
      );
      expect(fetcher.proxyPorts.last, controller.settings.mixedPort);
    });

    test('新订阅默认直连，显式开启才走代理', () async {
      await controller.addSubscription(url: 'https://example.com/new-direct');
      expect(controller.subscriptions.last.updateViaProxy, isFalse);
      expect(fetcher.proxyPorts.last, isNull);

      await controller.addSubscription(
        url: 'https://example.com/new-proxy',
        updateViaProxy: true,
      );
      expect(controller.subscriptions.last.updateViaProxy, isTrue);
      expect(fetcher.proxyPorts.last, controller.settings.mixedPort);
    });
  });

  group('订阅弹窗', () {
    late Directory support;
    late AppController controller;
    late L10n l10n;
    late _RecordingFetcher fetcher;

    setUp(() async {
      support = await Directory.systemTemp.createTemp('clashgo_update_mode_ui_');
      PathProviderPlatform.instance = _Temp(support.path);
      final paths = await AppPaths.create();
      final store = LocalStore(paths);
      await store.saveSubscriptions([
        _remote('proxied', '代理机场', viaProxy: true),
      ]);
      await store.saveActiveId('proxied');
      fetcher = _RecordingFetcher();
      controller = AppController(
        paths,
        startupService: FakeStartupService(),
        fetcher: fetcher,
      );
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

    Future<void> openSubscriptions(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(ClashGoApp(controller: controller));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await settleIo(tester);
      await tester.pump(const Duration(seconds: 1));
    }

    Finder dialogSwitches() =>
        find.descendant(of: find.byType(Dialog), matching: find.byType(Switch));

    testWidgets('添加订阅默认直连，可切换为走代理', (tester) async {
      await openSubscriptions(tester);
      await tester.tap(find.byTooltip(l10n.get('subscriptions.add')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(l10n.get('subscriptions.addByUrl')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(dialogSwitches(), findsNWidgets(2));
      expect(tester.widget<Switch>(dialogSwitches().at(0)).value, isTrue, reason: '自动更新默认开启');
      expect(tester.widget<Switch>(dialogSwitches().at(1)).value, isFalse, reason: '更新方式默认直连');

      await tester.tap(dialogSwitches().at(1));
      await tester.pump();
      expect(tester.widget<Switch>(dialogSwitches().at(1)).value, isTrue);

      final fields = find.descendant(of: find.byType(Dialog), matching: find.byType(TextField));
      await tester.enterText(fields.at(0), '代理导入');
      await tester.enterText(fields.at(1), 'https://example.com/imported');
      await tester.tap(find.widgetWithText(FilledButton, l10n.get('subscriptions.add')));
      await tester.pump();
      await settleIo(tester);
      await tester.pump(const Duration(milliseconds: 300));

      final added = controller.subscriptions.last;
      expect(added.name, '代理导入');
      expect(added.updateViaProxy, isTrue);
      expect(fetcher.proxyPorts.last, isNull, reason: '内核未运行，即使勾选走代理也只能直连');
    });

    testWidgets('编辑订阅回填并保存更新方式', (tester) async {
      await openSubscriptions(tester);
      await tester.tap(find.text('代理机场').last, buttons: kSecondaryMouseButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(l10n.get('common.edit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(dialogSwitches(), findsNWidgets(2));
      expect(tester.widget<Switch>(dialogSwitches().at(1)).value, isTrue);

      await tester.tap(dialogSwitches().at(1));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, l10n.get('common.save')));
      await tester.pump();
      await settleIo(tester);

      final edited = controller.subscriptions.firstWhere((sub) => sub.id == 'proxied');
      expect(edited.updateViaProxy, isFalse);
      final persisted = await tester.runAsync(() => controller.store.loadSubscriptions());
      expect(persisted!.firstWhere((sub) => sub.id == 'proxied').updateViaProxy, isFalse);
    });
  });
}

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
