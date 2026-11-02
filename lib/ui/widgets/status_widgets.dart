import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../../core/app_info.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import 'app_icon.dart';
import 'common.dart';

class DelayChip extends StatelessWidget {
  const DelayChip({
    super.key,
    required this.delay,
    this.testing = false,
    this.onTap,
    this.dense = false,
    this.placeholder = '—',
  });

  final int? delay;
  final bool testing;
  final VoidCallback? onTap;
  final bool dense;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final color = palette.delayColor(delay);
    final label = delay == null
        ? placeholder
        : delay! < 0
            ? l10n.get('common.timeout')
            : '${delay!} ms';
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: testing
          ? SizedBox(
              width: dense ? 10 : 12,
              height: dense ? 10 : 12,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (delay != null && delay! > 0) ...[
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  SizedBox(width: dense ? 4 : 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: dense ? 10 : 11,
                    fontWeight: FontWeight.w600,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
    );
    if (onTap == null) return child;
    return Tooltip(
      message: context.t('common.test'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: child,
        ),
      ),
    );
  }
}

class CoreStatusBadge extends StatelessWidget {
  const CoreStatusBadge({super.key, required this.controller, this.dense = false});

  final AppController controller;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final (color, label) = controller.stopUnconfirmed
        ? (palette.danger, l10n.get('status.stopUnconfirmed'))
        : switch (controller.phase) {
            CorePhase.running => (palette.success, l10n.get('status.running')),
            CorePhase.preview => (palette.strongMuted, l10n.get('status.ready')),
            CorePhase.starting => (palette.warning, l10n.get('status.starting')),
            CorePhase.stopping => (palette.warning, l10n.get('status.stopping')),
            CorePhase.stopped => (palette.muted, l10n.get('status.stopped')),
          };
    return AppBadge(
      text: label,
      color: color,
      background: color.withValues(alpha: 0.10),
      icon: 'shield-shape-line',
      dense: dense,
    );
  }
}

class CorePowerButton extends StatelessWidget {
  const CorePowerButton({super.key, required this.controller, this.size = 62});

  final AppController controller;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final busy = controller.isBusy;
    final running = controller.isRunning;
    final background = running ? palette.accentSoft : accent;
    final foreground = running ? accent : palette.onAccent;
    return Tooltip(
      message: context.t(running ? 'common.stop' : 'common.start'),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: busy ? null : controller.toggleCore,
          customBorder: const CircleBorder(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: Border.all(color: running ? accent.withValues(alpha: 0.35) : Colors.transparent, width: 1.5),
              boxShadow: running
                  ? null
                  : [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.32),
                        blurRadius: 22,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: Center(
              child: busy
                  ? SizedBox(
                      width: size * 0.36,
                      height: size * 0.36,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: foreground),
                    )
                  : AppIcon('power-line', size: size * 0.42, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}

class ModeSelector extends StatelessWidget {
  const ModeSelector({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppSegmented<String>(
      selected: controller.settings.mode,
      onChanged: controller.setMode,
      dense: true,
      options: [
        SegmentOption('rule', l10n.get('mode.rule'), icon: 'shield-shape-line'),
        SegmentOption('global', l10n.get('mode.global'), icon: 'globe-line'),
        SegmentOption('direct', l10n.get('mode.direct'), icon: 'link-line'),
      ],
    );
  }
}

class LatencyBar extends StatelessWidget {
  const LatencyBar({super.key, required this.controller, this.targets = AppInfo.latencyTargets});

  final AppController controller;
  final List<LatencyTarget> targets;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    return Row(
      children: [
        for (var i = 0; i < targets.length; i++) ...[
          if (i > 0) Container(width: 1, height: 28, color: palette.border),
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 三列布局每格在 360 宽只有 ~98px，安卓还会按系统字号缩放，
                    // 标签必须可压缩，否则整行溢出、状态点被挤出屏幕。
                    Flexible(
                      child: Text(
                        targets[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: palette.muted, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: controller.testingLatency
                            ? palette.muted
                            : palette.delayColor(controller.latency[targets[i].label]),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  controller.testingLatency
                      ? '…'
                      : controller.latency[targets[i].label] == null
                          ? '—'
                          : controller.latency[targets[i].label]! < 0
                              ? l10n.get('common.timeout')
                              : formatDelay(controller.latency[targets[i].label]!, zh: l10n.isZh),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: controller.latency[targets[i].label] == null
                        ? palette.muted
                        : palette.delayColor(controller.latency[targets[i].label]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
