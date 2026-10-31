import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/log_entry.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';
import '../shell/navigation.dart';

class LogsPage extends StatefulWidget {
  const LogsPage({super.key, this.showBack = false});

  final bool showBack;

  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  final TextEditingController _search = TextEditingController();
  String _level = 'all';

  static const _levels = ['all', 'debug', 'info', 'warning', 'error'];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<LogEntry> _filtered(AppController controller) {
    final query = _search.text.trim().toLowerCase();
    return controller.logs.where((entry) => entry.matches(_level, query)).toList(growable: false);
  }

  Color _levelColor(AppPalette palette, String level) {
    switch (level) {
      case 'error':
        return palette.danger;
      case 'warning':
        return palette.warning;
      case 'debug':
        return palette.muted;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _time(DateTime time) {
    final local = time.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    final filtered = _filtered(controller);
    final paused = controller.logsPaused;

    return PageFrame(
      header: PageHeader(
        leading: widget.showBack ? const ToolBackButton() : null,
        title: l10n.get('nav.logs'),
        subtitle: l10n.get('logs.subtitle'),
        actions: [
          OutlinedButton.icon(
            onPressed: controller.isRunning ? controller.toggleLogsPaused : null,
            icon: AppIcon(paused ? 'play-circle-line' : 'stop-line', size: 16),
            label: Text(l10n.get(paused ? 'logs.resume' : 'logs.pause')),
          ),
          AppIconButton(
            icon: 'copy-line',
            tooltip: l10n.get('logs.copyLine'),
            onTap: filtered.isEmpty
                ? null
                : () => copyToClipboard(
                      context,
                      filtered.reversed.map((entry) => '[${_time(entry.time)}] ${entry.level.toUpperCase()} ${entry.message}').join('\n'),
                    ),
          ),
          AppIconButton(
            icon: 'delete-2-line',
            tooltip: l10n.get('logs.clear'),
            onTap: controller.logs.isEmpty ? null : controller.clearLogs,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;
              final levels = SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final level in _levels) ...[
                      _LevelChip(
                        label: l10n.get('logs.level.$level'),
                        color: level == 'all' ? Theme.of(context).colorScheme.primary : _levelColor(palette, level),
                        selected: _level == level,
                        onTap: () => setState(() => _level = level),
                      ),
                      if (level != _levels.last) const SizedBox(width: 6),
                    ],
                  ],
                ),
              );
              final search = SizedBox(
                width: wide ? 300 : null,
                child: AppSearchField(
                  controller: _search,
                  hint: l10n.get('logs.search'),
                  onChanged: (_) => setState(() {}),
                ),
              );
              if (!wide) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    levels,
                    const SizedBox(height: 10),
                    search,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: levels),
                  const SizedBox(width: 12),
                  search,
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          if (!controller.isRunning && controller.logs.isNotEmpty) ...[
            InfoBanner(message: l10n.get('logs.notRunning'), color: palette.muted, dense: true),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: palette.card,
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                border: Border.all(color: palette.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: palette.cardAlt,
                      border: Border(bottom: BorderSide(color: palette.border)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: paused
                                ? palette.warning
                                : controller.isRunning
                                    ? palette.success
                                    : palette.muted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'mihomo · ${l10n.get('logs.count', [filtered.length])}',
                          style: TextStyle(
                            fontSize: 11,
                            color: palette.muted,
                            fontFamily: 'Consolas',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (paused) ...[
                          const SizedBox(width: 10),
                          Text(
                            l10n.get('logs.paused'),
                            style: TextStyle(fontSize: 10, color: palette.warning, fontWeight: FontWeight.w600),
                          ),
                        ],
                        const Spacer(),
                        AppIconButton(
                          icon: paused ? 'play-circle-line' : 'stop-line',
                          size: 14,
                          tooltip: l10n.get(paused ? 'logs.resume' : 'logs.pause'),
                          color: palette.strongMuted,
                          onTap: controller.isRunning ? controller.toggleLogsPaused : null,
                        ),
                        AppIconButton(
                          icon: 'delete-2-line',
                          size: 14,
                          tooltip: l10n.get('logs.clear'),
                          color: palette.strongMuted,
                          onTap: controller.logs.isEmpty ? null : controller.clearLogs,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AppIcon('terminal-line', size: 26, color: palette.muted.withValues(alpha: 0.55)),
                                  const SizedBox(height: 10),
                                  Text(
                                    controller.isRunning ? l10n.get('logs.empty') : l10n.get('logs.notRunning'),
                                    style: TextStyle(fontSize: 12, color: palette.strongMuted),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    controller.isRunning ? l10n.get('logs.emptyHint') : '',
                                    style: TextStyle(fontSize: 10.5, color: palette.muted),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : SelectionArea(
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final entry = filtered[index];
                                return _LogRow(
                                  entry: entry,
                                  time: _time(entry.time),
                                  color: _levelColor(palette, entry.levelKey),
                                  label: l10n.get('logs.level.${entry.levelKey}'),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.14) : AppPalette.of(context).card,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: selected ? color.withValues(alpha: 0.45) : AppPalette.of(context).border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 5, height: 5, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? color : AppPalette.of(context).muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry, required this.time, required this.color, required this.label});

  final LogEntry entry;
  final String time;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              time,
              style: TextStyle(fontSize: 10.5, color: palette.muted, fontFamily: 'Consolas', height: 1.5),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 1),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: palette.isDark ? 0.16 : 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              label,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color, letterSpacing: 0.2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              entry.message,
              style: TextStyle(
                fontSize: 11.5,
                color: palette.text,
                fontFamily: 'Consolas',
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
