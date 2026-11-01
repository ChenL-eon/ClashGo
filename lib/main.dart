import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'controllers/app_controller.dart';
import 'core/app_info.dart';
import 'core/app_paths.dart';
import 'services/startup_service.dart';
import 'services/tray_service.dart';
import 'ui/shell/window_title_bar.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final paths = await AppPaths.create();
  final controller = AppController(paths);
  await controller.initialize();

  TrayService? tray;
  var quitting = false;
  Future<void> quitApp() async {
    if (quitting) return;
    quitting = true;
    await controller.shutdown();
    tray?.dispose();
    await windowManager.destroy();
  }

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    // 系统标题栏隐藏与自绘标题栏必须成对启用，否则窗口没有拖动区。
    WindowTitleBar.enabled = true;
    await windowManager.setPreventClose(true);
    final service = TrayService(controller, onQuit: quitApp);
    tray = service;
    await service.initialize();
    windowManager.addListener(
      _AppWindowListener(
        controller: controller,
        tray: service,
        onQuit: quitApp,
      ),
    );
  }

  runApp(ClashGoApp(controller: controller));

  if (Platform.isWindows) {
    // 开机自启带 --autostart：托盘可用时直接驻留后台，不弹主窗口。
    final startHidden =
        args.contains(StartupService.autostartFlag) && (tray?.isReady ?? false);
    // 不再用 TitleBarStyle.hidden：插件会把客户区左右下各缩 8px 留给系统
    // 缩放边，那圈非客户区在无标题栏时是透明的。改成 runner 里接
    // WM_NCCALCSIZE 让客户区铺满窗口，缩放热区由 WindowFrame 绘制。
    const options = WindowOptions(
      size: Size(1220, 800),
      minimumSize: Size(400, 560),
      center: true,
      title: AppInfo.name,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.setTitle(AppInfo.name);
      if (startHidden) return;
      await windowManager.show();
      await windowManager.focus();
    });
  }
}

class _AppWindowListener extends WindowListener {
  _AppWindowListener({
    required this.controller,
    required this.tray,
    required this.onQuit,
  });

  final AppController controller;
  final TrayService tray;
  final Future<void> Function() onQuit;

  @override
  void onWindowClose() async {
    // 托盘没起来时不能藏窗口，否则应用会变成没有入口的后台进程。
    if (tray.isReady && controller.settings.closeToTray) {
      await tray.hideToTray();
      return;
    }
    await onQuit();
  }
}
