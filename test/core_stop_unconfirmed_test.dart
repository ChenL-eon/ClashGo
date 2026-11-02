import 'dart:io';

import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/core/core_log.dart';
import 'package:clash_go/core/errors.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:clash_go/services/core_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/fake_startup.dart';

/// 提权内核的停止请求没被监护进程确认时，GUI 既 kill 不动它，也看不到它。
/// 这种状态下唯一诚实的产出是：不当成"已停止"，把不确定明说，并且不许在
/// 这个前提上继续启动或切换接管方式。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late _StoppableCore core;
  late AppController controller;

  setUp(() async {
    HttpOverrides.global = null;
    support = await Directory.systemTemp.createTemp('clashgo_stop_unconfirmed_');
    PathProviderPlatform.instance = _TempPathProvider(support.path);
    final paths = await AppPaths.create();
    core = _StoppableCore(paths, CoreLog(paths.coreLogFile));
    controller = AppController(
      paths,
      coreManager: core,
      startupService: FakeStartupService(),
    );
    await controller.initialize();
    controller.settings = AppSettings.defaults(zh: true, systemProxy: false);
  });

  tearDown(() async {
    controller.dispose();
    await support.delete(recursive: true);
  });

  test('未确认的停止不会显示成"已停止"，也不弹成功提示', () async {
    core.confirmStop = false;
    controller.phase = CorePhase.running;
    final notices = <AppNotice>[];
    final subscription = controller.notices.listen(notices.add);
    addTearDown(subscription.cancel);

    final confirmed = await controller.stopCore();
    await Future<void>.delayed(Duration.zero);

    expect(confirmed, isFalse);
    expect(controller.phase, CorePhase.stopped, reason: 'GUI 已经控制不了它，回到 stopped 只是状态机口径');
    expect(controller.stopUnconfirmed, isTrue);
    expect(controller.lastError?.code, 'tunStopUnconfirmed');
    expect(notices.any((notice) => notice.error), isTrue, reason: '必须明说停止没被确认');
    expect(
      notices.any((notice) => notice.message.contains('内核已停止')),
      isFalse,
      reason: '没确认的停止不能弹"内核已停止"',
    );
  });

  test('停止未确认后 restartCore 不再拉起新内核', () async {
    core.confirmStop = false;
    controller.phase = CorePhase.running;

    await controller.restartCore(silent: true);

    expect(controller.phase, CorePhase.stopped);
    expect(
      controller.lastError?.code,
      'tunStopUnconfirmed',
      reason: '若继续走 startCore，这个错误会被 noSubscription 覆盖',
    );
  });

  test('停止未确认时不允许切换接管方式', () async {
    controller.stopUnconfirmed = true;

    await expectLater(
      controller.setTun(true),
      throwsA(
        isA<AppError>().having((error) => error.code, 'code', 'tunStopUnconfirmed'),
      ),
    );
    expect(controller.settings.tun, isFalse, reason: '在旧隧道状态未知时不能改接管方式');
  });

  test('下一次确认停止会清掉未确认标记与错误', () async {
    core.confirmStop = false;
    controller.phase = CorePhase.running;
    await controller.stopCore(silent: true);
    expect(controller.stopUnconfirmed, isTrue);

    core.confirmStop = true;
    controller.phase = CorePhase.running;
    final confirmed = await controller.stopCore(silent: true);

    expect(confirmed, isTrue);
    expect(controller.stopUnconfirmed, isFalse);
    expect(controller.lastError, isNull);
  });
}

class _StoppableCore extends CoreManager {
  _StoppableCore(super.paths, super.log);

  bool confirmStop = true;

  @override
  Future<bool> stop({bool removePid = true}) async => confirmStop;
}

class _TempPathProvider extends PathProviderPlatform {
  _TempPathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;

  @override
  Future<String?> getTemporaryPath() async => root;
}
