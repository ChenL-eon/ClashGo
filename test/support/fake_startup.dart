import 'package:clash_go/services/startup_service.dart';

/// 测试绝不碰真实注册表：自启开关只记录调用，供断言控制器接线。
class FakeStartupService extends StartupService {
  final List<bool> applied = [];
  final List<bool> reconciled = [];

  @override
  void apply(bool enabled) => applied.add(enabled);

  @override
  void reconcile(bool enabled) => reconciled.add(enabled);
}
