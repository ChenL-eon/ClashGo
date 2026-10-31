import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'controllers/app_controller.dart';
import 'core/app_info.dart';
import 'core/app_paths.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = await AppPaths.create();
  final controller = AppController(paths);
  await controller.initialize();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
    windowManager.addListener(_AppWindowListener(controller));
  }

  runApp(ClashGoApp(controller: controller));

  if (Platform.isWindows) {
    // 不要设置 WindowOptions.backgroundColor：window_manager 会注入 DWM accent，
    // 导致 Windows 11 标题栏的最小化/最大化/关闭按钮白字白底不可见。
    const options = WindowOptions(
      size: Size(1220, 800),
      minimumSize: Size(400, 560),
      center: true,
      title: AppInfo.name,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setTitle(AppInfo.name);
      await windowManager.show();
      await windowManager.focus();
    });
  }
}

class _AppWindowListener extends WindowListener {
  _AppWindowListener(this.controller);

  final AppController controller;
  bool _closing = false;

  @override
  void onWindowClose() async {
    if (_closing) return;
    _closing = true;
    await controller.shutdown();
    await windowManager.destroy();
  }
}
