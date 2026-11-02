import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../controllers/app_controller.dart';
import '../core/app_info.dart';
import '../core/l10n.dart';

/// Windows 托盘常驻：关闭窗口时隐藏到这里，托盘菜单负责唤回与真正退出。
class TrayService {
  TrayService(this.controller, {this.onQuit});

  final AppController controller;
  final Future<void> Function()? onQuit;

  TrayIcon? _tray;
  Menu? _menu;
  MenuItem? _showItem;
  MenuItem? _exitItem;
  String? _menuLanguage;
  bool _ready = false;
  bool _quitting = false;

  bool get isReady => _ready && _tray != null;

  Future<bool> initialize() async {
    if (!Platform.isWindows || _ready) return isReady;
    try {
      // ImageAsset 只按资产路径拼文件名，图标真不存在时就会得到一张空图标。
      final iconPath = p.join(
        p.dirname(Platform.resolvedExecutable),
        'data',
        'flutter_assets',
        'assets',
        'brand',
        'app_icon.ico',
      );
      if (!File(iconPath).existsSync()) return false;
      final icon = ImageAsset.fromAsset('assets/brand/app_icon.ico');
      final tray = TrayIcon.createWithIdentifier('clashgo');
      if (icon == null || tray == null) {
        tray?.dispose();
        return false;
      }
      tray.icon = icon;
      tray.setTooltip(AppInfo.name);
      tray.setContextMenuTrigger(ContextMenuTrigger.rightClicked);
      tray.addListener((event) {
        if (event is TrayIconClickedEvent || event is TrayIconDoubleClickedEvent) {
          unawaited(showWindow());
        }
      });
      _tray = tray;
      _rebuildMenu();
      // 图标没真正显示出来时不能算就绪：否则关窗后没有托盘入口，窗口会被藏死。
      if (!tray.setVisible(true)) {
        dispose();
        return false;
      }
      _ready = true;
      controller.addListener(_syncMenuLanguage);
      return true;
    } catch (_) {
      _tray?.dispose();
      _tray = null;
      _ready = false;
      return false;
    }
  }

  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
    controller.setWindowVisible(true);
  }

  Future<void> hideToTray() async {
    await windowManager.hide();
    controller.setWindowVisible(false);
  }

  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    final quitAction = onQuit;
    if (quitAction != null) {
      await quitAction();
      return;
    }
    dispose();
    await windowManager.destroy();
  }

  void _syncMenuLanguage() {
    if (!isReady || _menuLanguage == controller.settings.language) return;
    _rebuildMenu();
  }

  void _rebuildMenu() {
    final tray = _tray;
    if (tray == null) return;
    final l10n = L10n(controller.settings.language);
    final show = MenuItem.createWithLabelAndType(l10n.get('tray.showWindow'), MenuItemType.normal);
    final exit = MenuItem.createWithLabelAndType(l10n.get('tray.quit'), MenuItemType.normal);
    show?.addListener((event) {
      if (event is MenuItemClickedEvent) unawaited(showWindow());
    });
    exit?.addListener((event) {
      if (event is MenuItemClickedEvent) unawaited(quit());
    });
    final menu = Menu.create();
    menu?.addItem(show);
    menu?.addSeparator();
    menu?.addItem(exit);
    tray.setContextMenu(menu);

    final oldMenu = _menu;
    final oldShow = _showItem;
    final oldExit = _exitItem;
    _menu = menu;
    _showItem = show;
    _exitItem = exit;
    _menuLanguage = controller.settings.language;
    oldMenu?.dispose();
    oldShow?.dispose();
    oldExit?.dispose();
  }

  void dispose() {
    controller.removeListener(_syncMenuLanguage);
    _tray?.dispose();
    _menu?.dispose();
    _showItem?.dispose();
    _exitItem?.dispose();
    _tray = null;
    _menu = null;
    _showItem = null;
    _exitItem = null;
    _ready = false;
  }
}
