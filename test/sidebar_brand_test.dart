import 'dart:io';

import 'package:clash_go/app.dart';
import 'package:clash_go/controllers/app_controller.dart';
import 'package:clash_go/core/app_info.dart';
import 'package:clash_go/core/app_paths.dart';
import 'package:clash_go/ui/shell/window_title_bar.dart';
import 'package:clash_go/ui/widgets/app_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'support/fake_startup.dart';

/// 桌面侧边栏顶部的品牌块：图标和名称放大后仍要单行放下，不把版本号挤掉。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory support;
  late AppController controller;

  setUp(() async {
    support = await Directory.systemTemp.createTemp('clashgo_sidebar_brand_');
    PathProviderPlatform.instance = _Temp(support.path);
    controller = AppController(await AppPaths.create(), startupService: FakeStartupService());
    await controller.initialize();
  });

  tearDown(() async {
    controller.dispose();
    await support.delete(recursive: true);
  });

  testWidgets('侧边栏品牌图标 46、名称 18，版本号仍在', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ClashGoApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 400));

    final mark = find.byType(BrandMark);
    expect(mark, findsOneWidget);
    expect(tester.getSize(mark), const Size(46, 46));

    final name = tester.widget<Text>(find.text(AppInfo.name));
    expect(name.style?.fontSize, 18);
    expect(name.style?.fontWeight, FontWeight.w700);

    expect(find.text('v${AppInfo.version}'), findsOneWidget);
  });

  testWidgets('标题栏与侧栏品牌块、页面标题之间的留白收紧', (tester) async {
    WindowTitleBar.enabled = true;
    addTearDown(() => WindowTitleBar.enabled = false);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ClashGoApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 400));

    final bar = find.byKey(const ValueKey('window-title-bar'));
    expect(bar, findsOneWidget);
    final barBottom = tester.getBottomLeft(bar).dy;
    expect(barBottom, kWindowTitleBarHeight);

    final brandGap = tester.getTopLeft(find.byType(BrandMark)).dy - barBottom;
    expect(brandGap, inInclusiveRange(8, 18), reason: '侧栏品牌块离标题栏太远：$brandGap');

    final titleGap =
        tester.getTopLeft(find.text(controller.l10n.get('home.dashboard'))).dy - barBottom;
    expect(titleGap, inInclusiveRange(8, 22), reason: '页面标题离标题栏太远：$titleGap');
  });
}

class _Temp extends PathProviderPlatform {
  _Temp(this.root);

  final String root;

  @override
  Future<String?> getApplicationSupportPath() async => root;
}
