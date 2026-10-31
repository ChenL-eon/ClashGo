import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../core/app_info.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/subscription.dart';
import '../pages/connections_page.dart';
import '../pages/dns_page.dart';
import '../pages/home_page.dart';
import '../pages/logs_page.dart';
import '../pages/providers_page.dart';
import '../pages/proxy_page.dart';
import '../pages/rules_page.dart';
import '../pages/settings_page.dart';
import '../pages/subscriptions_page.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';
import '../widgets/status_widgets.dart';
import 'navigation.dart';

class _NavItem {
  const _NavItem(this.pageIndex, this.labelKey, this.icon, {this.activeIcon});

  final int pageIndex;
  final String labelKey;
  final String icon;
  final String? activeIcon;
}

const _desktopNavItems = <_NavItem>[
  _NavItem(0, 'nav.home', 'home-2-line', activeIcon: 'home-2-fill'),
  _NavItem(1, 'nav.proxy', 'globe-line'),
  _NavItem(2, 'nav.subscriptions', 'file-line'),
  _NavItem(3, 'nav.connections', 'link-line'),
  _NavItem(4, 'nav.logs', 'terminal-line'),
  _NavItem(5, 'nav.settings', 'settings-3-line', activeIcon: 'settings-3-fill'),
];

const _mobileNavItems = <_NavItem>[
  _NavItem(0, 'nav.home', 'home-2-line', activeIcon: 'home-2-fill'),
  _NavItem(1, 'nav.proxy', 'globe-line'),
  _NavItem(2, 'nav.subscriptions', 'file-line'),
  _NavItem(5, 'nav.settings', 'settings-3-line', activeIcon: 'settings-3-fill'),
];

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;
  late final AppController _controller = context.read<AppController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    // 控制器活得比 shell 久：切换主题/语言会让根 Widget 重建出一个新的 shell，
    // 而 _index 每次都从 0 开始。不在这里把可见性标志重新对齐，控制器会一直
    // 停在旧 shell 销毁前的那一步，主页流量曲线就此永久冻结。
    // 走 postFrame：initState 里直接 setHomeActive 会在 build 期间通知 provider。
    // 这里不判 mounted——控制器比 shell 活得久，宁可多擦一次，也不能把标志留在
    // "首页不可见"那一态。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.setHomeActive(_index == 0);
      _controller.setProxyActive(_index == 1);
      _controller.setConnectionsActive(_index == 3);
      _controller.setLogsActive(_index == 4);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.setForeground(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        // Windows 最小化只会上报 inactive（不发 hidden/paused）；安卓下拉通知栏、
        // 弹权限框同样只给 inactive。两端都按后台处理，回到前台由 resumed 还原。
        state == AppLifecycleState.inactive) {
      _controller.setForeground(false);
    }
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!HardwareKeyboard.instance.isControlPressed) return false;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _controller.toggleCore();
      return true;
    }
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
    ];
    final index = digits.indexOf(key);
    if (index >= 0) {
      _select(index);
      return true;
    }
    return false;
  }

  void _select(int index) {
    if (!mounted) return;
    if (index == _index) {
      _controller.setLogsActive(index == 4);
      return;
    }
    setState(() => _index = index);
    // IndexedStack 会让六个页全部保持存活，所以"谁在显示"只能由这里告诉控制器。
    _controller.setLogsActive(index == 4);
    _controller.setHomeActive(index == 0);
    _controller.setProxyActive(index == 1);
    _controller.setConnectionsActive(index == 3);
  }

  Future<void> _openTool(AppTool tool) async {
    final page = switch (tool) {
      AppTool.dns => const DnsPage(),
      AppTool.rules => const RulesPage(),
      AppTool.providers => const ProvidersPage(),
      AppTool.connections => const ConnectionsPage(showBack: true),
      AppTool.logs => const LogsPage(showBack: true),
    };
    final logs = tool == AppTool.logs;
    final connections = tool == AppTool.connections;
    // 工具页是压在 IndexedStack 上面的路由，底下的主页此刻看不见，
    // 流量/内存推送要一起停掉，pop 回来再按当前索引恢复。
    if (logs) _controller.setLogsActive(true);
    if (connections) _controller.setConnectionsActive(true);
    _controller.setHomeActive(false);
    // 代理页同样被压在下面了：它不可见时，延迟探测那三次出网没有消费者。
    _controller.setProxyActive(false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => _ToolHost(child: page)),
    );
    // 先擦屁股再走人：控制器是全局的，shell 自己被销毁不代表可见性标志可以留在
    // "工具页打开"那一态，否则底下的主页永远不会再被标成 active。
    _controller.setHomeActive(_index == 0);
    _controller.setProxyActive(_index == 1);
    _controller.setConnectionsActive(_index == 3);
    _controller.setLogsActive(_index == 4);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= appDesktopBreakpoint;
    final content = IndexedStack(
      index: _index,
      children: const [
        HomePage(),
        ProxyPage(),
        SubscriptionsPage(),
        ConnectionsPage(),
        LogsPage(),
        SettingsPage(),
      ],
    );
    return AppNavigation(
      go: _select,
      openTool: _openTool,
      child: Scaffold(
        backgroundColor: palette.background,
        body: Stack(
          children: [
            Positioned.fill(child: _ShellBackground(palette: palette)),
            SafeArea(
              bottom: false,
              child: desktop
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Sidebar(controller: _controller, index: _index, onSelect: _select),
                        Expanded(child: content),
                      ],
                    )
                  : Stack(
                      children: [
                        Positioned.fill(child: content),
                        _MobileNavBar(index: _index, onSelect: _select),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShellBackground extends StatelessWidget {
  const _ShellBackground({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < appDesktopBreakpoint) {
      return ColoredBox(color: palette.background);
    }
    final accent = Theme.of(context).colorScheme.primary;
    final strength = palette.isDark ? 0.22 : 0.16;
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: palette.background)),
        Positioned(
          top: -220,
          right: -160,
          child: _Glow(color: accent.withValues(alpha: strength), size: 520),
        ),
        Positioned(
          bottom: -240,
          left: -180,
          child: _Glow(color: palette.upload.withValues(alpha: strength * 0.55), size: 520),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.controller, required this.index, required this.onSelect});

  final AppController controller;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    return Container(
      width: AppTheme.sidebarWidth,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: palette.border)),
        color: palette.navBackground.withValues(alpha: palette.isDark ? 0.55 : 0.65),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 22, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: [
                    const BrandMark(size: 38, radius: 12),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppInfo.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: palette.text,
                            ),
                          ),
                          Text(
                            'v${AppInfo.version}',
                            style: TextStyle(fontSize: 10, color: palette.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 26),
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Text(
                  l10n.get('nav.menu').toUpperCase(),
                  style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: 1, color: palette.muted.withValues(alpha: 0.7)),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _desktopNavItems.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 3),
                  itemBuilder: (context, i) => _SidebarItem(
                    item: _desktopNavItems[i],
                    selected: _desktopNavItems[i].pageIndex == index,
                    onTap: () => onSelect(_desktopNavItems[i].pageIndex),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _SidebarCoreCard(controller: controller),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({required this.item, required this.selected, required this.onTap});

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final selected = widget.selected;
    final icon = selected ? (widget.item.activeIcon ?? widget.item.icon) : widget.item.icon;
    // 选中/悬停底色都做瞬时切换，不用 InkWell 或隐式动画：
    // 颜色与透明度的补间中间帧在 Windows 引擎上会发灰变暗，
    // 切换时看起来像两行同时亮起。
    return Semantics(
      button: true,
      selected: selected,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Stack(
            children: [
              if (selected)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.accentSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accent.withValues(alpha: 0.18)),
                    ),
                  ),
                )
              else if (_hovered)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.hover.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    AppIcon(icon, size: 18, color: selected ? accent : palette.muted),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        context.t(widget.item.labelKey),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? accent : palette.strongMuted,
                        ),
                      ),
                    ),
                    if (selected)
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarCoreCard extends StatelessWidget {
  const _SidebarCoreCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final l10n = context.l10n;
    final running = context.select<AppController, bool>((c) => c.isRunning);
    final phase = context.select<AppController, CorePhase>((c) => c.phase);
    final busy = context.select<AppController, bool>((c) => c.isBusy);
    final subscription = context.select<AppController, Subscription?>((c) => c.activeSubscription);
    final coreVersion = context.select<AppController, String?>((c) => c.coreVersion);
    final color = running ? palette.success : busy ? palette.warning : palette.muted;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
        boxShadow: palette.isDark ? null : [BoxShadow(color: palette.shadow, blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: running ? [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 7)] : null,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  l10n.get('status.${phase.name}'),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: palette.text),
                ),
              ),
              CorePowerButton(controller: controller, size: 32),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            subscription?.name ?? l10n.get('home.noSubscription'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10.5, color: palette.muted),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              AppIcon('shield-shape-line', size: 11, color: accent),
              const SizedBox(width: 4),
              Text(
                coreVersion == null ? 'mihomo' : 'mihomo $coreVersion',
                style: TextStyle(fontSize: 9.5, color: palette.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileNavBar extends StatelessWidget {
  const _MobileNavBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    const radius = 33.0;
    return Positioned(
      left: 20,
      right: 20,
      bottom: 10 + bottom,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: palette.isDark ? 0.45 : 0.14),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Container(
                  decoration: BoxDecoration(
                    color: palette.isDark ? const Color(0xB312151B) : const Color(0xCCFFFFFF),
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(
                      color: palette.isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  padding: const EdgeInsets.all(6),
                  child: SizedBox(
                    height: 46,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final slot = constraints.maxWidth / _mobileNavItems.length;
                        final selected = _mobileNavItems.indexWhere((item) => item.pageIndex == index);
                        return Stack(
                          children: [
                            // 选中胶囊在相邻项之间滑动切换，而不是原地淡入淡出。
                            AnimatedPositioned(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOutCubic,
                              left: selected < 0 ? 0 : slot * selected + 2,
                              top: 0,
                              width: selected < 0 ? 0 : slot - 4,
                              height: 46,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: palette.isDark
                                      ? Colors.white.withValues(alpha: 0.09)
                                      : Colors.black.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(23),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                for (final item in _mobileNavItems)
                                  Expanded(
                                    child: _MobileNavItem(
                                      item: item,
                                      selected: item.pageIndex == index,
                                      onTap: () => onSelect(item.pageIndex),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileNavItem extends StatelessWidget {
  const _MobileNavItem({required this.item, required this.selected, required this.onTap});

  final _NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final icon = selected ? (item.activeIcon ?? item.icon) : item.icon;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(23),
        // 按压高亮/悬停底色会和滑动的选中胶囊叠成“两个高亮”，只保留点击水波纹。
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        child: SizedBox(
          height: 46,
          width: double.infinity,
          // 图标/文字随选中状态一起做颜色、字重与轻微缩放过渡，
          // 与底栏滑动胶囊同时完成，避免突兀跳变。
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: selected ? 1 : 0),
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) {
              final color = Color.lerp(palette.text, accent, t)!;
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform.scale(
                    scale: 1 + 0.06 * t,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: AppIcon(icon, key: ValueKey(icon), size: 19, color: color),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.t(item.labelKey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.lerp(FontWeight.w500, FontWeight.w600, t),
                      color: color,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ToolHost extends StatelessWidget {
  const _ToolHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          Positioned.fill(child: _ShellBackground(palette: palette)),
          SafeArea(bottom: false, child: child),
        ],
      ),
    );
  }
}
