import 'package:clash_go/core/l10n.dart';
import 'package:clash_go/core/theme.dart';
import 'package:clash_go/ui/shell/window_title_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Windows 自绘标题栏回归：主题底色、无图标/名称、四枚窗口按钮与最大化状态。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('window_manager');
  late List<String> calls;
  late List<MethodCall> invocations;
  late bool maximized;

  setUp(() {
    calls = <String>[];
    invocations = <MethodCall>[];
    maximized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          invocations.add(call);
          if (call.method == 'isMaximized') return maximized;
          if (call.method == 'isFullScreen') return false;
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpBar(
    WidgetTester tester, {
    bool dark = false,
    bool pureBlack = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 240);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final accent = const Color(0xFF3B82F6);
    await tester.pumpWidget(
      L10nScope(
        l10n: const L10n('en'),
        child: MaterialApp(
          theme: dark
              ? AppTheme.build(
                  brightness: Brightness.dark,
                  accent: accent,
                  pureBlack: pureBlack,
                )
              : AppTheme.build(brightness: Brightness.light, accent: accent),
          home: const Scaffold(
            body: Column(
              children: [
                WindowTitleBar(),
                Expanded(child: SizedBox.expand()),
              ],
            ),
          ),
        ),
      ),
    );
    // MaterialApp 的主题切换有 200ms 过渡，等它走完再取色。
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder byLabel(String label) => find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );

  Color barColor(WidgetTester tester) {
    final container = tester.widget<Container>(
      find.byKey(const ValueKey('window-title-bar')),
    );
    return container.color!;
  }

  /// 最小化/还原过渡帧里 DWM 露出的窗口底色；标题栏本身透明，主题适配
  /// 只能从这里守。
  Color windowBackground() {
    final call = invocations.lastWhere(
      (call) => call.method == 'setBackgroundColor',
    );
    final args = call.arguments as Map;
    return Color.fromARGB(
      args['backgroundColorA'] as int,
      args['backgroundColorR'] as int,
      args['backgroundColorG'] as int,
      args['backgroundColorB'] as int,
    );
  }

  Future<void> emitWindowEvent(WidgetTester tester, String event) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'window_manager',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onEvent', <String, Object?>{'eventName': event}),
          ),
          (_) {},
        );
    await tester.pump();
  }

  testWidgets('标题栏透明、不画分隔线，窗口底色跟随浅色/深色/纯黑主题', (tester) async {
    const accent = Color(0xFF3B82F6);
    await pumpBar(tester);
    expect(
      tester.getSize(find.byKey(const ValueKey('window-title-bar'))).height,
      kWindowTitleBarHeight,
    );
    expect(barColor(tester), Colors.transparent);
    expect(windowBackground(), AppPalette.light(accent).background);
    expect(
      find.descendant(
        of: find.byType(WindowTitleBar),
        matching: find.byType(Text),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(WindowTitleBar),
        matching: find.byType(Image),
      ),
      findsNothing,
    );
    expect(byLabel('Minimize'), findsOneWidget);
    expect(byLabel('Maximize'), findsOneWidget);
    expect(byLabel('Close'), findsOneWidget);

    await pumpBar(tester, dark: true);
    expect(barColor(tester), Colors.transparent);
    expect(windowBackground(), AppPalette.dark(accent).background);

    await pumpBar(tester, dark: true, pureBlack: true);
    expect(barColor(tester), Colors.transparent);
    expect(
      windowBackground(),
      AppPalette.dark(accent, pureBlack: true).background,
    );
  });

  testWidgets('最小化/最大化/关闭走原生窗口调用，最大化后按钮切换为还原', (tester) async {
    await pumpBar(tester);

    await tester.tap(find.byKey(const ValueKey('window-minimize')));
    await tester.pump();
    expect(calls, contains('minimize'));

    await tester.tap(find.byKey(const ValueKey('window-maximize')));
    await tester.pump();
    expect(calls, contains('maximize'));

    maximized = true;
    await emitWindowEvent(tester, 'maximize');
    expect(byLabel('Restore'), findsOneWidget);
    expect(byLabel('Maximize'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('window-maximize')));
    await tester.pump();
    expect(calls, contains('unmaximize'));

    maximized = false;
    await emitWindowEvent(tester, 'unmaximize');
    expect(byLabel('Maximize'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('window-close')));
    await tester.pump();
    expect(calls, contains('close'));
  });

  testWidgets('WindowFrame 提供八向缩放热区，最大化后隐藏', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: WindowFrame(
            child: SizedBox.expand(key: ValueKey('frame-content')),
          ),
        ),
      ),
    );
    await tester.pump();

    const names = [
      'top',
      'bottom',
      'left',
      'right',
      'topLeft',
      'topRight',
      'bottomLeft',
      'bottomRight',
    ];
    for (final name in names) {
      expect(find.byKey(ValueKey('window-resize-$name')), findsOneWidget);
    }
    expect(
      tester.getSize(find.byKey(const ValueKey('window-resize-top'))).height,
      WindowFrame.edgeWidth,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('window-resize-topRight'))),
      const Size(WindowFrame.cornerSize, WindowFrame.cornerSize),
    );
    // 中间内容仍然是整窗尺寸，热区只是最外圈的一层覆盖。
    expect(
      tester.getSize(find.byKey(const ValueKey('frame-content'))),
      const Size(800, 600),
    );

    await tester.tap(find.byKey(const ValueKey('window-resize-topLeft')));
    await tester.pump();
    final resizes = invocations
        .where((call) => call.method == 'startResizing')
        .toList();
    expect(resizes, isNotEmpty);
    expect(
      (resizes.last.arguments as Map)['resizeEdge'],
      'topLeft',
    );

    maximized = true;
    await emitWindowEvent(tester, 'maximize');
    for (final name in names) {
      expect(find.byKey(ValueKey('window-resize-$name')), findsNothing);
    }

    maximized = false;
    await emitWindowEvent(tester, 'unmaximize');
    for (final name in names) {
      expect(find.byKey(ValueKey('window-resize-$name')), findsOneWidget);
    }
  });

  testWidgets('WindowChrome 把标题栏透明地叠在页面顶层，并补上缩放热区', (tester) async {
    WindowTitleBar.enabled = true;
    addTearDown(() => WindowTitleBar.enabled = false);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      L10nScope(
        l10n: const L10n('en'),
        child: const MaterialApp(
          home: Scaffold(
            body: WindowChrome(
              child: SizedBox.expand(key: ValueKey('chrome-content')),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final bar = find.byKey(const ValueKey('window-title-bar'));
    expect(bar, findsOneWidget);
    expect(tester.getTopLeft(bar), Offset.zero);
    expect(
      tester.getSize(bar),
      const Size(800, kWindowTitleBarHeight),
    );
    // 内容仍然占满整窗，标题栏只是盖在上面的一层；页面自己负责按 36px 避让。
    expect(
      tester.getSize(find.byKey(const ValueKey('chrome-content'))),
      const Size(800, 600),
    );
    expect(find.byKey(const ValueKey('window-resize-top')), findsOneWidget);
  });
}
