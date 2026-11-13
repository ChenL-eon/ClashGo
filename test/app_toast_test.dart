import 'package:clash_go/ui/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 通知卡片要跟内容走：短文案收缩成小卡片并水平居中，长文案最多 400 宽、
/// 自动换行；卡片以外的区域不能挡住页面点击（SnackBar 的透明 Material 会
/// 整条吸收点击，所以实现改走 Overlay），到时间自动消失。
void main() {
  const short = '订阅已更新';
  const long = '订阅更新失败：无法连接到订阅服务器，请检查网络连接后重试，如果问题仍然存在请更新订阅链接';

  var message = short;
  var backgroundTaps = 0;

  final card = find.byKey(const Key('appToastCard'));

  Future<void> pumpHost(WidgetTester tester) async {
    backgroundTaps = 0;
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => backgroundTaps++,
                  child: const SizedBox.expand(),
                ),
              ),
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Builder(
                    builder: (context) => ElevatedButton(
                      onPressed: () => showAppToast(context, message),
                      child: const Text('show'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(card, findsOneWidget);
  }

  Future<void> flushToast(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(card, findsNothing);
  }

  testWidgets('短文案：卡片按内容收缩、水平居中', (tester) async {
    message = short;
    await pumpHost(tester);
    final rect = tester.getRect(card);
    expect(rect.width, lessThan(300), reason: '短文案不能撑成 400 宽的长条');
    expect(rect.width, greaterThan(100));
    expect(rect.height, closeTo(56, 1.5), reason: '高度=30 图标+上下 13 内边距');
    expect((rect.center.dx - 640).abs(), lessThan(1), reason: '卡片要水平居中');
    await flushToast(tester);
  });

  testWidgets('长文案：封顶 400 宽并换行', (tester) async {
    message = long;
    await pumpHost(tester);
    final rect = tester.getRect(card);
    expect(rect.width, closeTo(400, 0.5), reason: '长文案封顶 400');
    expect(rect.height, greaterThan(60), reason: '超过一行应换行而不是继续拉宽');
    await flushToast(tester);
  });

  testWidgets('卡片外的区域不挡点击', (tester) async {
    message = short;
    await pumpHost(tester);
    final rect = tester.getRect(card);
    await tester.tapAt(Offset(rect.left - 40, rect.center.dy));
    expect(backgroundTaps, 1, reason: '通知卡片外的区域应把点击放给页面');
    expect(card, findsOneWidget, reason: '穿透的点击不能关掉通知');
    await flushToast(tester);
  });

  testWidgets('到时自动消失', (tester) async {
    message = short;
    await pumpHost(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(card, findsNothing, reason: '默认 2 秒后通知应消失');
  });
}
