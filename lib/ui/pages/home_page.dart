import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../core/app_info.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../shell/navigation.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/status_widgets.dart';
import '../widgets/traffic_chart.dart';

/// /traffic、/memory 每秒各推一帧，这些读数只属于下面这几张卡片。让它们单独订阅
/// controller.live，首页整树（三处 IntrinsicHeight，每个都要把子树量两遍）就不必
/// 跟着一秒重排两次；离开首页时实时通道本来就会断，读数和以前一样停在最后一次。
Widget _liveScope(AppController controller, WidgetBuilder build) => AnimatedBuilder(
      animation: controller.live,
      builder: (context, _) => build(context),
    );

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    if (MediaQuery.sizeOf(context).width < appDesktopBreakpoint) {
      return _MobileHome(controller: controller);
    }
    return PageContainer(
      children: [
        PageHeader(
          title: l10n.get('home.dashboard'),
          actions: [_HomeHeaderActions(controller: controller)],
        ),
        if (controller.lastError != null) ...[
          const SizedBox(height: 14),
          InfoBanner(
            message: controller.lastError!.localized(l10n),
            color: palette.danger,
            icon: 'close-circle-line',
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: palette.danger,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => showMessageDialog(
                  context,
                  title: l10n.get('common.details'),
                  message: controller.diagnostics(),
                ),
                child: Text(l10n.get('common.details')),
              ),
              AppIconButton(
                icon: 'close-line',
                size: 14,
                padding: 6,
                color: palette.muted,
                onTap: controller.clearLastError,
              ),
            ],
          ),
        ],
        const SizedBox(height: 18),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _CurrentSubscriptionCard(controller: controller)),
              const SizedBox(width: 16),
              Expanded(child: _ModeCard(controller: controller)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _CoreStatusCard(controller: controller)),
              const SizedBox(width: 12),
              Expanded(child: _TakeoverCard(controller: controller)),
              const SizedBox(width: 12),
              Expanded(child: _CoreVersionCard(controller: controller)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _SpeedStatCard(controller: controller, upload: true)),
              const SizedBox(width: 12),
              Expanded(child: _SpeedStatCard(controller: controller, upload: false)),
              const SizedBox(width: 12),
              Expanded(child: _PortCard(controller: controller)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _NetworkTrafficCard(controller: controller),
        const SizedBox(height: 16),
        _LatencyCard(controller: controller),
        const SizedBox(height: 22),
        SectionLabel(l10n.get('home.tools'), icon: 'grid-line'),
        _ToolsGrid(),
      ],
    );
  }
}

class _MobileHome extends StatelessWidget {
  const _MobileHome({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    return PageContainer(
      children: [
        const MobilePageHeader(title: AppInfo.name),
        if (controller.lastError != null) ...[
          const SizedBox(height: 14),
          InfoBanner(
            message: controller.lastError!.localized(l10n),
            color: palette.danger,
            icon: 'close-circle-line',
            dense: true,
            actions: [
              AppIconButton(
                icon: 'close-line',
                size: 14,
                padding: 6,
                color: palette.muted,
                onTap: controller.clearLastError,
              ),
            ],
          ),
        ],
        const SizedBox(height: 22),
        _MobileHeroCard(controller: controller),
        const SizedBox(height: 24),
        MobileSectionLabel(l10n.get('home.overview'), icon: 'information-line'),
        _MobileOverviewGrid(controller: controller),
        const SizedBox(height: 24),
        MobileSectionLabel(
          l10n.get('home.latencyShort'),
          icon: 'lightning-line',
          trailing: controller.testingLatency
              ? const Padding(
                  padding: EdgeInsets.all(5),
                  child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : AppIconButton(
                  icon: 'refresh-2-line',
                  size: 15,
                  padding: 5,
                  tooltip: l10n.get('home.latencyTest'),
                  onTap: controller.isRunning ? controller.testLatency : null,
                ),
        ),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
          radius: 18,
          child: LatencyBar(controller: controller),
        ),
        const SizedBox(height: 24),
        MobileSectionLabel(l10n.get('home.tools'), icon: 'grid-line'),
        _ToolsGrid(),
      ],
    );
  }
}

class _MobileHeroCard extends StatelessWidget {
  const _MobileHeroCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => _liveScope(controller, _content);

  Widget _content(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final accent = Theme.of(context).colorScheme.primary;
    final subscription = controller.activeSubscription;
    final node = controller.activeNode;
    final running = controller.isRunning;
    final busy = controller.isBusy;
    final uptime = running && controller.startedAt != null
        ? formatUptime(DateTime.now().difference(controller.startedAt!))
        : '00:00:00';
    final (dotColor, statusLabel) = switch (controller.phase) {
      CorePhase.running => (palette.success, l10n.get('status.running')),
      CorePhase.starting => (palette.warning, l10n.get('status.starting')),
      CorePhase.stopping => (palette.warning, l10n.get('status.stopping')),
      CorePhase.stopped => (palette.danger, l10n.get('status.stopped')),
    };
    final endpoint = Platform.isAndroid ? l10n.get('home.vpn') : 'PROXY';
    // 运行中即为「停止」：用告警红浅底与红字，和启动态的实心主题色区分，
    // 同时避免整块纯红在大按钮上过于刺眼。
    final buttonBackground = running
        ? Color.alphaBlend(palette.danger.withValues(alpha: 0.12), palette.card)
        : accent;
    final buttonForeground = running ? palette.danger : palette.onAccent;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text(
                statusLabel,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: palette.text),
              ),
              const Spacer(),
              Text(
                endpoint,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.9,
                  color: palette.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _MobileHeroMetric(label: l10n.get('home.uptime'), value: uptime),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _MobileHeroMetric(
                  label: l10n.get('home.subscriptionLabel'),
                  value: subscription?.name ?? l10n.get('home.noSubscriptionValue'),
                ),
              ),
            ],
          ),
          if (running && node != null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                AppIcon('wifi-line', size: 14, color: palette.muted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    node,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: palette.strongMuted),
                  ),
                ),
                DelayChip(
                  delay: controller.displayDelay(node),
                  testing: controller.testingNodes.contains(node),
                  dense: true,
                  onTap: () => controller.testNode(node),
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: busy ? null : controller.toggleCore,
              style: FilledButton.styleFrom(
                backgroundColor: buttonBackground,
                foregroundColor: buttonForeground,
                disabledBackgroundColor: buttonBackground.withValues(alpha: 0.55),
                disabledForegroundColor: buttonForeground,
                elevation: running ? 0 : 6,
                shadowColor: accent.withValues(alpha: 0.34),
                shape: const StadiumBorder(),
              ),
              child: busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2, color: buttonForeground),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon(running ? 'stop-line' : 'play-circle-line', size: 20, color: buttonForeground),
                        const SizedBox(width: 8),
                        Text(
                          l10n.get(running ? 'common.stop' : 'common.start'),
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 14),
          ModeSelector(controller: controller),
          const SizedBox(height: 12),
          Center(
            child: Text(
              controller.coreVersion == null ? 'Mihomo' : 'Mihomo ${controller.coreVersion}',
              style: TextStyle(fontSize: 11, color: palette.muted, letterSpacing: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileHeroMetric extends StatelessWidget {
  const _MobileHeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: palette.muted)),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            height: 1.2,
            color: palette.text,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _MobileOverviewGrid extends StatelessWidget {
  const _MobileOverviewGrid({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final subscription = controller.activeSubscription;
    final running = controller.isRunning;
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final width = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            _liveScope(
              controller,
              (context) => SizedBox(
                width: width,
                child: _MobileMetricCard(
                  icon: 'wifi-line',
                  title: l10n.get('home.netSpeed'),
                  tag: 'NET',
                  rows: [
                    (l10n.get('home.upload'), formatSpeed(controller.uploadSpeed)),
                    (l10n.get('home.download'), formatSpeed(controller.downloadSpeed)),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: _MobileMetricCard(
                icon: 'cloud-line',
                title: l10n.get('home.metricSubscription'),
                tag: 'SUB',
                rows: [
                  (l10n.get('home.used'), subscription == null ? '0 B' : formatBytes(subscription.used)),
                  (
                    l10n.get('home.total'),
                    subscription != null && subscription.hasQuota ? formatBytes(subscription.total) : '--',
                  ),
                ],
              ),
            ),
            SizedBox(width: width, child: _IpMetricCard(controller: controller)),
            _liveScope(
              controller,
              (context) => SizedBox(
                width: width,
                child: _MobileMetricCard(
                  icon: 'chip-line',
                  title: l10n.get('home.system'),
                  tag: 'SYS',
                  rows: [
                    (l10n.get('home.memory'), running ? formatBytes(controller.memoryInUse) : '--'),
                    (
                      l10n.get('home.uptime'),
                      running && controller.startedAt != null
                          ? formatUptime(DateTime.now().difference(controller.startedAt!))
                          : '--',
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MobileMetricCard extends StatelessWidget {
  const _MobileMetricCard({
    required this.icon,
    required this.title,
    required this.tag,
    required this.rows,
  });

  final String icon;
  final String title;
  final String tag;
  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppIcon(icon, size: 15, color: palette.strongMuted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: palette.text),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                tag,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: palette.muted),
              ),
            ],
          ),
          const SizedBox(height: 11),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 7),
            Row(
              children: [
                Text(rows[i].$1, style: TextStyle(fontSize: 11.5, color: palette.muted)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    rows[i].$2,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: palette.text,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _IpMetricCard extends StatefulWidget {
  const _IpMetricCard({required this.controller});

  final AppController controller;

  @override
  State<_IpMetricCard> createState() => _IpMetricCardState();
}

class _IpMetricCardState extends State<_IpMetricCard> with WidgetsBindingObserver {
  Timer? _timer;
  String? _address;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _load();
      _startTimer();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        // 安卓下拉通知栏、弹权限框也只会给 inactive，这时候没必要继续枚举网卡。
        state == AppLifecycleState.inactive) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    // 本机 IPv4 只在切网时变，30s 足够；这条轮询在亮屏期间是纯浪费。
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  Future<void> _load() async {
    String? address;
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final item in interface.addresses) {
          if (item.address.startsWith('169.254.')) continue;
          address = item.address;
          break;
        }
        if (address != null) break;
      }
    } catch (_) {}
    if (!mounted) return;
    if (address != _address) setState(() => _address = address);
  }

  String? get _nodeName {
    final direct = widget.controller.activeNode;
    if (direct != null) return direct;
    final id = widget.controller.activeId;
    final saved = id == null ? null : widget.controller.selections[id];
    if (saved == null) return null;
    for (final name in saved.values) {
      if (name.isNotEmpty) return name;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final node = _nodeName;
    final region = node == null ? null : regionLabelForNode(node, zh: l10n.isZh);
    return _MobileMetricCard(
      icon: 'globe-line',
      title: l10n.get('home.ip'),
      tag: '--',
      rows: [
        (l10n.get('home.address'), _address ?? '0.0.0.0'),
        (l10n.get('home.region'), region ?? '--'),
      ],
    );
  }
}

class _HomeHeaderActions extends StatelessWidget {
  const _HomeHeaderActions({required this.controller});

  final AppController controller;

  Future<void> _setSystemProxy(bool enabled) async {
    try {
      await controller.setSystemProxy(enabled);
    } catch (_) {}
  }

  // 失败原因（UAC 被拒、TUN 网卡没起来）由控制器直接提示出来，这里只负责不让它
  // 变成未捕获异常——chip 的 onTap 没有 ScaffoldMessenger 可以 throw 给。
  Future<void> _setTun(bool enabled) async {
    try {
      await controller.setTun(enabled);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final windows = Platform.isWindows;
    final proxyOn = controller.settings.systemProxy;
    final tunOn = controller.settings.tun;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (windows) ...[
          _TakeoverChip(
            label: l10n.get('settings.systemProxy'),
            selected: proxyOn,
            onTap: () => _setSystemProxy(!proxyOn),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: l10n.get('home.tunHint'),
            child: _TakeoverChip(
              label: l10n.get('home.tun'),
              selected: tunOn,
              onTap: () => _setTun(!tunOn),
            ),
          ),
        ] else
          _TakeoverChip(
            label: l10n.get('home.tun'),
            selected: controller.isRunning,
            onTap: null,
          ),
        const SizedBox(width: 12),
        _StartButton(controller: controller),
      ],
    );
  }
}

class _TakeoverChip extends StatelessWidget {
  const _TakeoverChip({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? accent : palette.cardAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? accent : palette.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: selected ? palette.onAccent : palette.strongMuted,
        ),
      ),
    );
    if (onTap == null) return Opacity(opacity: 0.55, child: content);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        // 悬停不整块填色，避免与选中态叠成两处高亮。
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: accent.withValues(alpha: 0.10),
        child: content,
      ),
    );
  }
}

class _StartButton extends StatelessWidget {
  const _StartButton({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final accent = Theme.of(context).colorScheme.primary;
    final running = controller.isRunning;
    final busy = controller.isBusy;
    final background = running
        ? Color.alphaBlend(palette.danger.withValues(alpha: 0.12), palette.card)
        : accent;
    final foreground = running ? palette.danger : palette.onAccent;
    return FilledButton(
      onPressed: busy ? null : controller.toggleCore,
      style: FilledButton.styleFrom(
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: background.withValues(alpha: 0.6),
        disabledForegroundColor: foreground,
        elevation: 0,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: busy
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(running ? 'stop-line' : 'play-circle-line', size: 16, color: foreground),
                const SizedBox(width: 7),
                Text(
                  l10n.get(running ? 'common.stop' : 'common.start'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
    );
  }
}

class _CurrentSubscriptionCard extends StatelessWidget {
  const _CurrentSubscriptionCard({required this.controller});

  final AppController controller;

  Future<void> _update() async {
    final subscription = controller.activeSubscription;
    if (subscription == null) return;
    try {
      await controller.updateSubscription(subscription.id);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final subscription = controller.activeSubscription;
    final busy = subscription != null && controller.updatingSubscriptions.contains(subscription.id);
    final usedText = subscription == null
        ? '—'
        : subscription.hasQuota
            ? l10n.get('home.usedOf', [formatBytes(subscription.used), formatBytes(subscription.total)])
            : formatBytes(subscription.used);
    final expireText = subscription == null
        ? '—'
        : subscription.hasExpiry
            ? formatExpire(subscription.expire, zh: l10n.isZh)
            : l10n.get('home.noExpire');
    final action = TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: () => AppNavigation.goTab(context, 2),
      child: Text(l10n.get(subscription == null ? 'subscriptions.add' : 'home.manageSubscription')),
    );
    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.get('home.subscriptionLabel'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 6),
              if (subscription != null)
                AppIconButton(
                  icon: 'refresh-2-line',
                  size: 16,
                  padding: 5,
                  tooltip: l10n.get('subscriptions.update'),
                  color: busy ? palette.muted : null,
                  onTap: busy ? null : _update,
                ),
              action,
            ],
          ),
          const SizedBox(height: 6),
          _SubDetail(label: l10n.get('home.nameLabel'), value: subscription?.name ?? '—'),
          const SizedBox(height: 12),
          _SubDetail(label: l10n.get('home.usedTraffic'), value: usedText),
          const SizedBox(height: 12),
          _SubDetail(
            label: l10n.get('home.expireLabel'),
            value: expireText,
            danger: subscription?.isExpired ?? false,
          ),
        ],
      ),
    );
  }
}

class _SubDetail extends StatelessWidget {
  const _SubDetail({required this.label, required this.value, this.danger = false});

  final String label;
  final String value;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(label, style: TextStyle(fontSize: 12.5, color: palette.muted)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: danger ? palette.danger : palette.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.get('home.proxyMode'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.get('home.proxyModeDesc'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, height: 1.55, color: palette.muted),
          ),
          const SizedBox(height: 16),
          ModeSelector(controller: controller),
        ],
      ),
    );
  }
}

class _MetricPanel extends StatelessWidget {
  const _MetricPanel({
    required this.icon,
    required this.title,
    required this.value,
    this.hint,
    this.color,
  });

  final String icon;
  final String title;
  final String value;
  final String? hint;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tone = color ?? Theme.of(context).colorScheme.primary;
    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: AppIcon(icon, size: 16, color: tone)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              height: 1.2,
              color: palette.text,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 7),
            Text(
              hint!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, height: 1.4, color: palette.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _CoreStatusCard extends StatelessWidget {
  const _CoreStatusCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => _liveScope(controller, _content);

  Widget _content(BuildContext context) {
    final l10n = context.l10n;
    final subscription = controller.activeSubscription;
    final running = controller.isRunning;
    final uptime = running && controller.startedAt != null
        ? formatUptime(DateTime.now().difference(controller.startedAt!))
        : '';
    final value = switch (controller.phase) {
      CorePhase.running => l10n.get('status.running'),
      CorePhase.starting => l10n.get('status.starting'),
      CorePhase.stopping => l10n.get('status.stopping'),
      CorePhase.stopped => l10n.get('home.notRunning'),
    };
    final hint = switch (controller.phase) {
      CorePhase.running =>
        l10n.get('home.coreRunningHint', [uptime, '${controller.connectionCount}']),
      CorePhase.starting => l10n.get('home.statusHint.starting'),
      CorePhase.stopping => l10n.get('home.statusHint.stopping'),
      CorePhase.stopped =>
        subscription == null ? l10n.get('home.addSubHint') : l10n.get('home.startHint'),
    };
    return _MetricPanel(
      icon: 'power-line',
      title: l10n.get('home.coreStatus'),
      value: value,
      hint: hint,
    );
  }
}

class _TakeoverCard extends StatelessWidget {
  const _TakeoverCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final windows = Platform.isWindows;
    final proxyOn = controller.settings.systemProxy;
    final tunOn = controller.settings.tun;
    final String value;
    final String hint;
    if (!windows) {
      value = l10n.get('home.tun');
      hint = l10n.get('home.takeoverVpnHint');
    } else if (tunOn) {
      value = l10n.get('home.tun');
      hint = l10n.get('home.takeoverTunHint');
    } else if (proxyOn) {
      value = l10n.get('settings.systemProxy');
      hint = controller.isRunning
          ? l10n.get('home.takeoverProxyHint', ['${controller.settings.mixedPort}'])
          : l10n.get('home.takeoverPending');
    } else {
      value = l10n.get('mode.direct');
      hint = l10n.get('home.takeoverDirectHint');
    }
    return _MetricPanel(
      icon: 'transfer-line',
      title: l10n.get('home.takeover'),
      value: value,
      hint: hint,
    );
  }
}

class _CoreVersionCard extends StatelessWidget {
  const _CoreVersionCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) => _liveScope(controller, _content);

  Widget _content(BuildContext context) {
    final l10n = context.l10n;
    final version = controller.coreVersion;
    return _MetricPanel(
      icon: 'information-line',
      title: l10n.get('home.coreVersion'),
      value: version ?? '--',
      hint: version == null
          ? l10n.get('home.coreNotRunning')
          : l10n.get('home.coreMemoryHint', [formatBytes(controller.memoryInUse)]),
    );
  }
}

class _SpeedStatCard extends StatelessWidget {
  const _SpeedStatCard({required this.controller, required this.upload});

  final AppController controller;
  final bool upload;

  @override
  Widget build(BuildContext context) => _liveScope(controller, _content);

  Widget _content(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final running = controller.isRunning;
    final speed = running
        ? formatSpeed(upload ? controller.uploadSpeed : controller.downloadSpeed)
        : '-- B/s';
    final total = formatBytes(upload ? controller.sessionUpload : controller.sessionDownload);
    return _MetricPanel(
      icon: upload ? 'upload-line' : 'download-2-line',
      title: l10n.get(upload ? 'home.upload' : 'home.download'),
      value: speed,
      hint: l10n.get('home.sessionTotal', [total]),
      color: upload ? palette.upload : palette.download,
    );
  }
}

class _PortCard extends StatelessWidget {
  const _PortCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final running = controller.isRunning;
    return _MetricPanel(
      icon: 'link-line',
      title: l10n.get('settings.mixedPort'),
      value: running ? '${controller.settings.mixedPort}' : '--',
      hint: running ? l10n.get('home.portListening') : l10n.get('home.coreNotRunning'),
      color: palette.warning,
    );
  }
}

class _NetworkTrafficCard extends StatelessWidget {
  const _NetworkTrafficCard({required this.controller});

  final AppController controller;

  String _speed(int value) => controller.isRunning ? formatSpeed(value) : '-- B/s';

  @override
  Widget build(BuildContext context) => _liveScope(controller, _content);

  Widget _content(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                l10n.get('home.networkTraffic'),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 16),
              _LegendDot(color: palette.upload, label: l10n.get('home.upload')),
              const SizedBox(width: 12),
              _LegendDot(color: palette.download, label: l10n.get('home.download')),
              const Spacer(),
              _TrafficNow(
                icon: 'upload-line',
                color: palette.upload,
                value: _speed(controller.uploadSpeed),
                label: l10n.get('home.upload'),
              ),
              const SizedBox(width: 18),
              _TrafficNow(
                icon: 'download-2-line',
                color: palette.download,
                value: _speed(controller.downloadSpeed),
                label: l10n.get('home.download'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TrafficChart(
            samples: controller.trafficHistory,
            revision: controller.trafficHistory.revision,
            uploadColor: palette.upload,
            downloadColor: palette.download,
            gridColor: palette.border,
            height: 142,
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11.5, color: palette.muted)),
      ],
    );
  }
}

class _TrafficNow extends StatelessWidget {
  const _TrafficNow({required this.icon, required this.color, required this.value, required this.label});

  final String icon;
  final Color color;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: palette.text,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10.5, color: palette.muted)),
      ],
    );
  }
}

class _LatencyCard extends StatelessWidget {
  const _LatencyCard({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final values = controller.latency.values.toList();
    final tested = values.whereType<int>().toList();
    final healthy = tested.where((value) => value > 0).length;
    final (statusLabel, statusColor) = tested.isEmpty
        ? (l10n.get('home.latencyNone'), palette.muted)
        : healthy == AppInfo.latencyTargets.length
            ? (l10n.get('home.latencyNormal'), palette.success)
            : healthy > 0
                ? (l10n.get('home.latencyPartial'), palette.warning)
                : (l10n.get('home.latencyAbnormal'), palette.danger);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _IconBox(icon: 'wifi-line'),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.get('home.latency'), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      l10n.get('home.latencyHint'),
                      style: TextStyle(fontSize: 11.5, color: palette.muted),
                    ),
                  ],
                ),
              ),
              AppBadge(text: statusLabel, color: statusColor, dense: true),
              const SizedBox(width: 8),
              if (controller.testingLatency)
                const Padding(
                  padding: EdgeInsets.all(9),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                AppIconButton(
                  icon: 'refresh-2-line',
                  tooltip: l10n.get('home.latencyTest'),
                  onTap: controller.isRunning ? controller.testLatency : null,
                ),
            ],
          ),
          const SizedBox(height: 16),
          LatencyBar(controller: controller),
        ],
      ),
    );
  }
}

class _ToolsGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mobile = MediaQuery.sizeOf(context).width < appDesktopBreakpoint;
    final tools = <(String, String, String, VoidCallback)>[
      (
        'transfer-line',
        l10n.get('tools.connections'),
        l10n.get('tools.connectionsSub'),
        () => mobile ? AppNavigation.tool(context, AppTool.connections) : AppNavigation.goTab(context, 3),
      ),
      (
        'terminal-line',
        l10n.get('tools.logs'),
        l10n.get('tools.logsSub'),
        () => mobile ? AppNavigation.tool(context, AppTool.logs) : AppNavigation.goTab(context, 4),
      ),
      ('globe-line', l10n.get('tools.dns'), l10n.get('tools.dnsSub'), () => AppNavigation.tool(context, AppTool.dns)),
      ('list-check-line', l10n.get('tools.rules'), l10n.get('tools.rulesSub'), () => AppNavigation.tool(context, AppTool.rules)),
      ('cloud-line', l10n.get('tools.providers'), l10n.get('tools.providersSub'), () => AppNavigation.tool(context, AppTool.providers)),
      ('card-line', l10n.get('tools.subscriptions'), l10n.get('tools.subscriptionsSub'), () => AppNavigation.goTab(context, 2)),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 12.0;
        final columns = constraints.maxWidth >= 840 ? 3 : (constraints.maxWidth >= 430 ? 2 : 1);
        final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tool in tools)
              SizedBox(
                width: width,
                child: SurfaceCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  radius: AppTheme.radiusMd,
                  onTap: tool.$4,
                  child: Row(
                    children: [
                      _IconBox(icon: tool.$1, size: 36, iconSize: 17),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(tool.$2, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(
                              tool.$3,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 10.5, color: AppPalette.of(context).muted),
                            ),
                          ],
                        ),
                      ),
                      AppIcon('right-small-line', size: 14, color: AppPalette.of(context).muted),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, this.size = 38, this.iconSize = 18});

  final String icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: palette.accentSoft,
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Center(
        child: AppIcon(icon, size: iconSize, color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}
