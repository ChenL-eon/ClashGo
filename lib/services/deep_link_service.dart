import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

/// clash:// 外链桥。安卓由 MainActivity 的 intent-filter 收下链接，
/// 再通过这个通道交给 Dart；冷启动时先暂存在原生侧，等 Flutter 就绪后取走。
class DeepLinkService {
  DeepLinkService._();

  static const channelName = 'com.clashgo.clash_go/deeplink';

  static Future<void> initialize(Future<void> Function(String) onLink) async {
    if (!Platform.isAndroid) return;
    final channel = MethodChannel(channelName);
    channel.setMethodCallHandler((call) async {
      if (call.method == 'link' && call.arguments is String) {
        unawaited(onLink(call.arguments as String));
      }
    });
    try {
      final initial = await channel.invokeMethod<String>('consumeInitial');
      if (initial != null && initial.isNotEmpty) unawaited(onLink(initial));
    } on MissingPluginException {
      // 测试宿主或旧安装包里没有这一侧的原生实现。
    } on PlatformException {
      // 冷启动取链接失败不该拦住应用启动；用户仍可从剪贴板导入。
    }
  }

  /// Windows 没有自动抢注协议：clash:// 通常已被 Clash Verge 一类客户端占用，
  /// 悄悄改写注册表会让用户单击浏览器里的链接时落到一个没预期的应用。
  /// 这里只消费启动参数，用户自行建立关联或从快捷方式传入时同样能导入。
  static String? linkFromArguments(List<String> args) {
    for (final raw in args) {
      final text = raw.trim().replaceAll(RegExp(r'^"+|"+$'), '');
      final uri = Uri.tryParse(text);
      if (uri == null) continue;
      if (uri.scheme == 'clash' || uri.scheme == 'clashverge') return text;
    }
    return null;
  }
}
