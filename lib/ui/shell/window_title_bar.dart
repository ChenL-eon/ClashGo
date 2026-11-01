import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';

const double kWindowTitleBarHeight = 36;

/// Windows 自绘标题栏：runner 里用 WM_NCCALCSIZE 让客户区铺满窗口，
/// 系统标题栏不再显示；这枚窗口按钮条必须和它同生共死，否则窗口既没有
/// 标题也没有拖动区。它本身不画底色和分隔线，由 shell 叠在背景最上层，
/// 让页面渐变一直铺到窗口顶边。
class WindowTitleBar extends StatefulWidget {
  const WindowTitleBar({super.key});

  /// 由 main.dart 在 windowManager 初始化后置位；widget 测试默认关闭，
  /// 保证既有布局用例不受桌面窗口控件影响。
  static bool enabled = false;

  @override
  State<WindowTitleBar> createState() => _WindowTitleBarState();
}

class _WindowTitleBarState extends State<WindowTitleBar> with WindowListener {
  bool _maximized = false;
  Color? _windowBackground;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final background = AppPalette.of(context).background;
    if (_windowBackground == background) return;
    _windowBackground = background;
    // 最小化/还原的过渡帧里 DWM 会短暂露出窗口底色，跟主题同色不跳白。
    unawaited(windowManager.setBackgroundColor(background).catchError((_) {}));
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => _setMaximized(true);

  @override
  void onWindowUnmaximize() => _setMaximized(false);

  void _setMaximized(bool value) {
    if (!mounted || _maximized == value) return;
    setState(() => _maximized = value);
  }

  Future<void> _syncMaximized() async {
    try {
      final maximized = await windowManager.isMaximized();
      _setMaximized(maximized);
    } on Exception {
      // 没有原生窗口的环境（widget 测试）拿不到状态，按未最大化渲染即可。
    }
  }

  void _minimize() {
    unawaited(windowManager.minimize());
  }

  Future<void> _toggleMaximize() async {
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } on Exception {
      // 窗口已经销毁时忽略，下一次事件会把图标状态校正回来。
    }
  }

  void _close() {
    // 走 WM_CLOSE，托盘/退出仍然由 _AppWindowListener 决定。
    unawaited(windowManager.close());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // 透明底色是刻意的：窗口按钮、拖动区直接浮在 shell 背景上，不再切出
    // 一条和页面脱开的标题栏。
    return Container(
      key: const ValueKey('window-title-bar'),
      height: kWindowTitleBarHeight,
      color: Colors.transparent,
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onSecondaryTapUp: (_) =>
                  unawaited(windowManager.popUpWindowMenu()),
              child: DragToMoveArea(child: const SizedBox.expand()),
            ),
          ),
          _WindowButton(
            key: const ValueKey('window-minimize'),
            glyph: _CaptionGlyph.minimize,
            label: l10n.get('window.minimize'),
            onTap: _minimize,
          ),
          _WindowButton(
            key: const ValueKey('window-maximize'),
            glyph: _maximized ? _CaptionGlyph.restore : _CaptionGlyph.maximize,
            label: l10n.get(_maximized ? 'window.restore' : 'window.maximize'),
            onTap: _toggleMaximize,
          ),
          _WindowButton(
            key: const ValueKey('window-close'),
            glyph: _CaptionGlyph.close,
            label: l10n.get('window.close'),
            onTap: _close,
            close: true,
          ),
        ],
      ),
    );
  }
}

/// 把窗口控件叠到页面之上：标题栏透明地压在顶部，四边缩放热区铺在最外层。
/// 只在 [WindowTitleBar.enabled] 时生效，Android / widget 测试原样返回页面。
class WindowChrome extends StatelessWidget {
  const WindowChrome({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!WindowTitleBar.enabled) return child;
    return WindowFrame(
      child: Stack(
        children: [
          Positioned.fill(child: child),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: kWindowTitleBarHeight,
            child: WindowTitleBar(),
          ),
        ],
      ),
    );
  }
}

/// 无边框窗口的缩放热区：客户区铺满窗口后系统不再留可抓的边框，
/// 这层透明条带负责把指针换成缩放光标、按下时交给系统缩放循环。
class WindowFrame extends StatefulWidget {
  const WindowFrame({required this.child, super.key});

  final Widget child;

  /// 边缘热区宽度；四角加大到 [cornerSize] 方便斜向缩放。
  static const double edgeWidth = 4;
  static const double cornerSize = 10;

  @override
  State<WindowFrame> createState() => _WindowFrameState();
}

class _WindowFrameState extends State<WindowFrame> with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _syncMaximized();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => _setMaximized(true);

  @override
  void onWindowUnmaximize() => _setMaximized(false);

  @override
  void onWindowRestore() => _syncMaximized();

  void _setMaximized(bool value) {
    if (!mounted || _maximized == value) return;
    setState(() => _maximized = value);
  }

  Future<void> _syncMaximized() async {
    try {
      _setMaximized(await windowManager.isMaximized());
    } on Exception {
      // 没有原生窗口的环境（widget 测试）拿不到状态，按未最大化渲染即可。
    }
  }

  void _startResize(ResizeEdge edge) {
    unawaited(windowManager.startResizing(edge).catchError((_) {}));
  }

  @override
  Widget build(BuildContext context) {
    const edge = WindowFrame.edgeWidth;
    const corner = WindowFrame.cornerSize;
    return Stack(
      children: [
        Positioned.fill(child: widget.child),
        // 最大化后窗口贴死工作区，任何一边都不该再出现缩放热区。
        if (!_maximized) ...[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: edge,
            child: _handle('top', ResizeEdge.top, SystemMouseCursors.resizeUp),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: edge,
            child: _handle(
              'bottom',
              ResizeEdge.bottom,
              SystemMouseCursors.resizeDown,
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: edge,
            child: _handle(
              'left',
              ResizeEdge.left,
              SystemMouseCursors.resizeLeft,
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: edge,
            child: _handle(
              'right',
              ResizeEdge.right,
              SystemMouseCursors.resizeRight,
            ),
          ),
          // 四角压在边条之上，斜向抓取优先。
          Positioned(
            top: 0,
            left: 0,
            width: corner,
            height: corner,
            child: _handle(
              'topLeft',
              ResizeEdge.topLeft,
              SystemMouseCursors.resizeUpLeft,
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            width: corner,
            height: corner,
            child: _handle(
              'topRight',
              ResizeEdge.topRight,
              SystemMouseCursors.resizeUpRight,
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            width: corner,
            height: corner,
            child: _handle(
              'bottomLeft',
              ResizeEdge.bottomLeft,
              SystemMouseCursors.resizeDownLeft,
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            width: corner,
            height: corner,
            child: _handle(
              'bottomRight',
              ResizeEdge.bottomRight,
              SystemMouseCursors.resizeDownRight,
            ),
          ),
        ],
      ],
    );
  }

  Widget _handle(String name, ResizeEdge edge, MouseCursor cursor) {
    return MouseRegion(
      cursor: cursor,
      child: Listener(
        key: ValueKey('window-resize-$name'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _startResize(edge),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.glyph,
    required this.label,
    required this.onTap,
    this.close = false,
    super.key,
  });

  final _CaptionGlyph glyph;
  final String label;
  final VoidCallback onTap;
  final bool close;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final background = !_hovered
        ? Colors.transparent
        : widget.close
        ? (palette.isDark ? const Color(0xFFC42B1C) : const Color(0xFFE81123))
        : palette.hover;
    final foreground = _hovered && widget.close
        ? Colors.white
        : widget.close
        ? palette.strongMuted
        : palette.text;
    // 悬停色瞬时切换，和其他窗口控件一致，不做颜色补间。
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: kWindowTitleBarHeight,
            color: background,
            alignment: Alignment.center,
            child: CustomPaint(
              size: const Size.square(14),
              painter: _CaptionGlyphPainter(
                glyph: widget.glyph,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _CaptionGlyph { minimize, maximize, restore, close }

class _CaptionGlyphPainter extends CustomPainter {
  const _CaptionGlyphPainter({required this.glyph, required this.color});

  final _CaptionGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final left = (size.width - 10) / 2;
    final top = (size.height - 10) / 2;
    switch (glyph) {
      case _CaptionGlyph.minimize:
        canvas.drawLine(
          Offset(left, top + 5),
          Offset(left + 10, top + 5),
          paint,
        );
      case _CaptionGlyph.maximize:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top, 10, 10),
            const Radius.circular(1.2),
          ),
          paint,
        );
      case _CaptionGlyph.restore:
        // 与 Windows 还原图标同构：前窗完整、后窗只留上边和右边。
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(left, top + 2.5, 7.5, 7.5),
            const Radius.circular(1.2),
          ),
          paint,
        );
        final back = Path()
          ..moveTo(left + 2.5, top + 7.5)
          ..lineTo(left + 2.5, top)
          ..lineTo(left + 10, top)
          ..lineTo(left + 10, top + 7.5);
        canvas.drawPath(back, paint);
      case _CaptionGlyph.close:
        canvas.drawLine(Offset(left, top), Offset(left + 10, top + 10), paint);
        canvas.drawLine(Offset(left + 10, top), Offset(left, top + 10), paint);
    }
  }

  @override
  bool shouldRepaint(_CaptionGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph || oldDelegate.color != color;
}
