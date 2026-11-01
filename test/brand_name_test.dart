import 'dart:io';

import 'package:clash_go/core/app_info.dart';
import 'package:clash_go/core/l10n.dart';
import 'package:flutter_test/flutter_test.dart';

/// 品牌名统一为无空格的 ClashGo：界面文案、Android 通知/桌面名称和 Windows
/// 窗口标题都不再出现带空格的写法。
void main() {
  test('应用名与品牌文案统一为 ClashGo', () {
    expect(AppInfo.name, 'ClashGo');
    for (final code in L10n.supported) {
      final l10n = L10n(code);
      for (final key in const [
        'settings.aboutApp',
        'tray.quit',
        'notification.vpnTitle',
      ]) {
        final text = l10n.get(key);
        expect(text, contains('ClashGo'), reason: '$code $key');
        expect(text, isNot(contains('Clash Go')), reason: '$code $key');
      }
    }
  });

  test('用户可见源码里没有带空格的 Clash Go', () {
    const roots = ['lib', 'android/app/src/main', 'windows/runner'];
    const extensions = {'.dart', '.kt', '.xml', '.cpp', '.h', '.rc'};
    final offenders = <String>[];
    for (final root in roots) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File) continue;
        if (!extensions.any(entity.path.endsWith)) continue;
        if (entity.readAsStringSync().contains('Clash Go')) {
          offenders.add(entity.path);
        }
      }
    }
    expect(offenders, isEmpty, reason: '这些文件仍有带空格的 Clash Go：$offenders');
  });
}
