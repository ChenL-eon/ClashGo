import 'dart:convert';
import 'dart:io';

import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/fake_startup.dart';

/// TUN 开关的三条纪律：改设置要落盘、和系统代理互斥、内核没在跑时不许起提权进程。
/// 最后一条尤其要紧——这条路径真的会去碰 UAC，测试里绝不能在内核跑着的时候调它，
/// 所以用例全程把 phase 钉在 stopped。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late AppController controller;

  setUp(() async {
    HttpOverrides.global = null;
    support = await Directory.systemTemp.createTemp('clashgo_tun_toggle_');
    PathProviderPlatform.instance = _TempPathProvider(support.path);
    controller = AppController(await AppPaths.create(), startupService: FakeStartupService());
    await controller.initialize();
    controller.settings = AppSettings.defaults().copyWith(systemProxy: false, tun: false);
    await controller.store.saveSettings(controller.settings);
    controller.phase = CorePhase.stopped;
  });

  tearDown(() async {
    controller.dispose();
    await support.delete(recursive: true);
  });

  Map<String, dynamic> savedSettings() =>
      Map<String, dynamic>.from(jsonDecode(controller.paths.settingsFile.readAsStringSync()) as Map);

  test('开 TUN：写进设置文件，且不会去起内核', () async {
    await controller.setTun(true);

    expect(controller.settings.tun, isTrue);
    expect(savedSettings()['tun'], isTrue, reason: '只改内存里的对象不算持久化');
    expect(controller.phase, CorePhase.stopped, reason: '内核停着时开开关不该触发提权启动');
  });

  test('TUN 和系统代理互斥：开 TUN 就把系统代理让出来', () async {
    // 系统代理标记为"想开"但从未真正写入注册表（内核没跑），这里只验让位这件事本身，
    // 不碰注册表。
    controller.settings = controller.settings.copyWith(systemProxy: true);
    await controller.store.saveSettings(controller.settings);

    await controller.setTun(true);

    expect(controller.settings.tun, isTrue);
    expect(controller.settings.systemProxy, isFalse);
    expect(savedSettings()['systemProxy'], isFalse, reason: '让位也必须落在盘上，重启后不能又两个都开');
  });

  test('关 TUN 不把系统代理悄悄补回来', () async {
    await controller.setTun(true);
    await controller.setTun(false);

    // 少一个接管方式就是少一个，不替用户决定"那就用系统代理吧"。
    expect(controller.settings.tun, isFalse);
    expect(controller.settings.systemProxy, isFalse);
  });

  test('重复设同一个值不产生任何写入', () async {
    final before = controller.paths.settingsFile.statSync().modified;
    await controller.setTun(false);
    expect(controller.paths.settingsFile.statSync().modified, before, reason: '值没变就不该重写文件');
  });

  test('开系统代理就把 TUN 让出来（对称的那一半）', () async {
    // 反方向（开 TUN 关代理）一直是对的，缺的是这一半：以前点系统代理会把
    // systemProxy: true 照样存盘，而内核启动时 _enableSystemProxy 见 tun 开着直接
    // return —— chip 亮着、toast 说"已保存"，注册表一个字没写，是个假开关。
    controller.settings = controller.settings.copyWith(tun: true);
    await controller.store.saveSettings(controller.settings);

    await controller.setSystemProxy(true);

    expect(controller.settings.systemProxy, isTrue);
    expect(controller.settings.tun, isFalse, reason: '接管方式只能有一个，刚点的那个赢');
    expect(savedSettings()['tun'], isFalse, reason: '让位必须落盘，否则重启后又回到两个都开');
    expect(savedSettings()['systemProxy'], isTrue);
  });

  test('设置页保存不许把"两个都开"写回盘上', () async {
    // applySettings 是另一条写盘的路（改端口/主题/订阅都会走它），走的是文件里
    // 现存的 settings 对象，所以同一条规矩也得在这儿兜住。
    controller.settings = controller.settings.copyWith(tun: true, systemProxy: true);

    await controller.applySettings(controller.settings.copyWith(mixedPort: 17890));

    expect(controller.settings.tun, isTrue, reason: '没有点击语义时保留更强的 TUN');
    expect(controller.settings.systemProxy, isFalse);
    expect(savedSettings()['systemProxy'], isFalse);
  });

  test('启动读到"两个都开"的旧文件会当场归一化', () async {
    // 真实存在过的状态：老版本留下的 settings.json 就是两个都 true。
    controller.settings = controller.settings.copyWith(tun: true, systemProxy: true);
    await controller.store.saveSettings(controller.settings);

    final reopened = AppController(await AppPaths.create(), startupService: FakeStartupService());
    await reopened.initialize();
    addTearDown(reopened.dispose);

    expect(reopened.settings.tun, isTrue);
    expect(reopened.settings.systemProxy, isFalse);
    expect(savedSettings()['systemProxy'], isFalse, reason: '归一化要写回盘，不能只修内存');
  });
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}
