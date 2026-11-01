// 首页头部行在窄窗口下的横向溢出回归用例。
//
// flutter test 会把文字换成方格测试字体，Latin 一个字符约 1em 宽，比 Windows 上
// 真实渲染（DirectWrite + Microsoft YaHei UI）宽近一倍。同一段文字两边实测：
//   "Active subscription" 15px SemiBold → 测试字体 245px / 真字体 144.8px
//   "Network traffic"     15px SemiBold → 测试字体 228.8px / 真字体 115.6px
//   "Cloudflare"          11px SemiBold → 测试字体 112.5px / 真字体  57.5px
// 汉字两边都是 1em，不放大。所以这里跑出来的结果比线上严格：测试字体不溢出，
// 真机字体更不会溢出。
//
// 反过来也成立：测试字体报出的溢出（历史上是首页流量卡标题 +14px、延迟条标签
// +7.5px）不一定真，需要按上面这组比例换算后再决定改不改。真字体下延迟条每格
// 67.5px、360 宽可用 98px，只有系统字号调到 ~1.5 倍才逼近边界——所以压缩只加在
// 延迟条（安卓会跟随系统字号），桌面流量卡不加。
import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/fake_startup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late AppController controller;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('clashgo_overflow_');
    PathProviderPlatform.instance = _Temp(support.path);
    controller = AppController(await AppPaths.create(), startupService: FakeStartupService());
    await controller.initialize();
  });

  tearDown(() async {
    await support.delete(recursive: true);
  });

  for (final size in const <Size>[Size(1000, 900), Size(1120, 900), Size(1280, 900), Size(1600, 900)]) {
    testWidgets('首页在 ${size.width.toInt()} 宽度下不发生横向溢出', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prior = FlutterError.onError;
      final overflowed = <String>[];
      FlutterError.onError = (details) {
        final text = details.exceptionAsString();
        if (text.contains('RenderFlex overflowed')) overflowed.add(text);
      };
      await tester.pumpWidget(ClashGoApp(controller: controller));
      // SVG 图标是异步解码的：不给真实时间它们还是零尺寸，溢出根本暴露不出来。
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
      await tester.pump();
      FlutterError.onError = prior;

      expect(overflowed, isEmpty, reason: '${size.width.toInt()} px 下首页存在横向溢出');
    });
  }

  // 手机宽度单独一组：安卓会真的按系统字号缩放（桌面 embedder 不会），窄屏 + 大字号
  // 才是延迟条这类三列布局的极限工况。
  for (final size in const <Size>[Size(360, 800), Size(411, 891)]) {
    testWidgets('首页在 ${size.width.toInt()}x${size.height.toInt()} 手机宽度下不发生横向溢出', (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final prior = FlutterError.onError;
      final overflowed = <String>[];
      FlutterError.onError = (details) {
        final text = details.exceptionAsString();
        if (text.contains('RenderFlex overflowed')) overflowed.add(text);
      };
      await tester.pumpWidget(ClashGoApp(controller: controller));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
      await tester.pump();
      FlutterError.onError = prior;

      expect(overflowed, isEmpty, reason: '${size.width.toInt()} px 手机宽度下首页存在横向溢出：\n${overflowed.join('\n')}');
    });
  }
}

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
