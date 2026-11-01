import 'package:clash_go/core/l10n.dart';
import 'package:clash_go/core/theme.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:clash_go/ui/pages/proxy_page.dart';
import 'package:clash_go/ui/widgets/app_icon.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 嵌套显示菜单的行为验证：浮层结构、子菜单选项回调、以及哪些项点完收起。
void main() {
  const l10n = L10n('zh');

  late List<String> log;

  Future<void> pumpMenu(
    WidgetTester tester, {
    String style = AppSettings.styleTabs,
    NodeSort sort = NodeSort.original,
    String layout = AppSettings.sizeStandard,
    String size = AppSettings.sizeStandard,
    bool hideTimeout = false,
  }) async {
    log = [];
    await tester.pumpWidget(
      L10nScope(
        l10n: l10n,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(brightness: Brightness.light, accent: accentPresets.first.color),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: DisplayMenu(
                style: style,
                sort: sort,
                layout: layout,
                size: size,
                hideTimeout: hideTimeout,
                onStyle: (v) => log.add('style=$v'),
                onSort: (v) => log.add('sort=${nodeSortKey(v)}'),
                onLayout: (v) => log.add('layout=$v'),
                onSize: (v) => log.add('size=$v'),
                onHideTimeout: () => log.add('hideTimeout'),
                onScrollToSelected: () => log.add('scroll'),
                builder: (context, toggle) => TextButton(
                  key: const Key('trigger'),
                  onPressed: toggle,
                  child: const Text('详情'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('trigger')));
    await tester.pumpAndSettle();
  }

  group('node sort keys', () {
    test('round-trip and unknown fallback', () {
      expect(nodeSortKey(NodeSort.original), 'default');
      expect(nodeSortKey(NodeSort.delay), 'delay');
      expect(nodeSortKey(NodeSort.name), 'name');
      expect(nodeSortFromKey('delay'), NodeSort.delay);
      expect(nodeSortFromKey('name'), NodeSort.name);
      expect(nodeSortFromKey(null), NodeSort.original);
      expect(nodeSortFromKey('bogus'), NodeSort.original);
    });
  });

  group('display menu', () {
    testWidgets('root shows six entries in two groups', (tester) async {
      tester.view.physicalSize = const Size(840, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpMenu(tester);

      expect(find.text(l10n.get('proxy.menu.scrollToSelected')), findsOneWidget);
      expect(find.text(l10n.get('proxy.menu.style')), findsOneWidget);
      expect(find.text(l10n.get('proxy.menu.sort')), findsOneWidget);
      expect(find.text(l10n.get('proxy.menu.layout')), findsOneWidget);
      expect(find.text(l10n.get('proxy.menu.size')), findsOneWidget);
      expect(find.text(l10n.get('proxy.menu.hideTimeout')), findsOneWidget);
      // 分组细线：滚动到已选 | 四个子菜单 | 隐藏超时代理。
      expect(find.byType(Divider), findsNWidgets(2));
      // 未展开的子菜单不参与构建，所以此刻没有勾选标记。
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.name == 'check-line'), findsNothing);
      expect(find.text(l10n.get('proxy.style.list')), findsNothing);
    });

    testWidgets('style option fires and keeps the submenu open', (tester) async {
      await pumpMenu(tester);

      await tester.tap(find.text(l10n.get('proxy.menu.style')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.get('proxy.style.tabs')), findsOneWidget);
      // 当前选中的 标签页 带勾选标记。
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.name == 'check-line'), findsOneWidget);

      await tester.tap(find.text(l10n.get('proxy.style.list')));
      await tester.pumpAndSettle();
      expect(log, ['style=${AppSettings.styleList}']);
      // closeOnActivate 为 false：点完选项浮层仍在，方便连续预览。
      expect(find.text(l10n.get('proxy.menu.size')), findsOneWidget);
      expect(find.text(l10n.get('proxy.style.list')), findsOneWidget);
    });

    testWidgets('layout and size options map to their own callbacks', (tester) async {
      await pumpMenu(tester, style: AppSettings.styleList);

      await tester.tap(find.text(l10n.get('proxy.menu.layout')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.get('proxy.size.compact')));
      await tester.pumpAndSettle();
      expect(log, ['layout=${AppSettings.sizeCompact}']);

      log.clear();
      await tester.tap(find.text(l10n.get('proxy.menu.size')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.get('proxy.size.loose')));
      await tester.pumpAndSettle();
      expect(log, ['size=${AppSettings.sizeLoose}']);
    });

    testWidgets('sort option converts the label back into NodeSort', (tester) async {
      await pumpMenu(tester);

      await tester.tap(find.text(l10n.get('proxy.menu.sort')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.get('proxy.sort.delay')));
      await tester.pumpAndSettle();
      expect(log, ['sort=delay']);
    });

    testWidgets('hovering other rows keeps the submenu open', (tester) async {
      await pumpMenu(tester);
      await tester.tap(find.text(l10n.get('proxy.menu.style')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.get('proxy.style.list')), findsOneWidget);

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await tester.pump();

      // 悬停到相邻的一级子菜单行：不应顶掉已展开的二级菜单。
      await mouse.moveTo(tester.getCenter(find.text(l10n.get('proxy.menu.sort'))));
      await tester.pumpAndSettle();
      expect(find.text(l10n.get('proxy.style.list')), findsOneWidget);

      // 悬停到页面空白处也不收起。
      await mouse.moveTo(const Offset(24, 560));
      await tester.pumpAndSettle();
      expect(find.text(l10n.get('proxy.style.list')), findsOneWidget);
      expect(find.text(l10n.get('proxy.menu.style')), findsOneWidget);
    });

    testWidgets('opening another submenu replaces the current one', (tester) async {
      await pumpMenu(tester);
      await tester.tap(find.text(l10n.get('proxy.menu.style')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.get('proxy.style.list')), findsOneWidget);

      await tester.tap(find.text(l10n.get('proxy.menu.sort')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.get('proxy.style.list')), findsNothing);
      expect(find.text(l10n.get('proxy.sort.delay')), findsOneWidget);
    });

    testWidgets('tapping outside closes the whole menu', (tester) async {
      await pumpMenu(tester);
      await tester.tap(find.text(l10n.get('proxy.menu.style')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.get('proxy.style.list')), findsOneWidget);

      await tester.tapAt(const Offset(24, 560));
      await tester.pumpAndSettle();
      expect(find.text(l10n.get('proxy.style.list')), findsNothing);
      expect(find.text(l10n.get('proxy.menu.style')), findsNothing);
    });

    testWidgets('scroll to selected closes the popup', (tester) async {
      await pumpMenu(tester);

      await tester.tap(find.text(l10n.get('proxy.menu.scrollToSelected')));
      await tester.pumpAndSettle();
      expect(log, ['scroll']);
      expect(find.text(l10n.get('proxy.menu.hideTimeout')), findsNothing);
    });

    testWidgets('hide timeout is a checked toggle', (tester) async {
      await pumpMenu(tester);
      await tester.tap(find.text(l10n.get('proxy.menu.hideTimeout')));
      await tester.pumpAndSettle();
      expect(log, ['hideTimeout']);
      // 与子菜单选项一致：切换不收起浮层。
      expect(find.text(l10n.get('proxy.menu.style')), findsOneWidget);
    });

    testWidgets('checked state renders a tick on the toggle row', (tester) async {
      await pumpMenu(tester, hideTimeout: true);
      expect(find.text(l10n.get('proxy.menu.hideTimeout')), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is AppIcon && w.name == 'check-line'), findsOneWidget);
    });
  });
}
