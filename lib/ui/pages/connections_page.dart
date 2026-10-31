import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/connection_info.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../shell/navigation.dart';

class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({super.key, this.showBack = false});

  final bool showBack;

  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ConnectionInfo> _filtered(ConnectionsSnapshot snapshot) {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return snapshot.connections;
    return snapshot.connections.where((item) {
      return item.host.toLowerCase().contains(query) ||
          item.process.toLowerCase().contains(query) ||
          item.ruleLabel.toLowerCase().contains(query) ||
          (item.node ?? '').toLowerCase().contains(query);
    }).toList(growable: false);
  }

  Future<void> _closeAll(AppController controller) async {
    final confirmed = await showConfirmDialog(
      context,
      title: context.t('connections.closeAllTitle'),
      message: context.t('connections.closeAllMessage', [controller.connectionCount]),
      confirmText: context.t('connections.closeAll'),
      danger: true,
      icon: 'close-circle-line',
    );
    if (!confirmed || !mounted) return;
    await controller.closeAllConnections();
  }

  Future<void> _showDetails(AppController controller, ConnectionInfo connection) async {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    await showAppDialog<void>(
      context,
      maxWidth: 540,
      builder: (dialogContext) => AppDialog(
        title: l10n.get('connections.details'),
        subtitle: connection.host,
        icon: 'transfer-line',
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            KeyValueText(label: l10n.get('connections.host'), value: connection.host),
            const SizedBox(height: 10),
            KeyValueText(label: l10n.get('connections.node'), value: connection.node ?? '—'),
            const SizedBox(height: 10),
            KeyValueText(label: l10n.get('connections.rule'), value: connection.ruleLabel),
            const SizedBox(height: 10),
            KeyValueText(label: l10n.get('connections.process'), value: connection.process.isEmpty ? '—' : connection.process),
            const SizedBox(height: 10),
            KeyValueText(label: l10n.get('connections.source'), value: connection.source),
            const SizedBox(height: 10),
            KeyValueText(label: l10n.get('connections.destination'), value: connection.destination),
            const SizedBox(height: 10),
            KeyValueText(label: l10n.get('connections.network'), value: [connection.network, connection.type].where((value) => value.isNotEmpty).join(' · ')),
            const SizedBox(height: 10),
            KeyValueText(
              label: l10n.get('connections.traffic'),
              value: '↑ ${formatBytes(connection.upload)}  ↓ ${formatBytes(connection.download)}',
            ),
            const SizedBox(height: 10),
            KeyValueText(label: l10n.get('connections.duration'), value: formatDurationShort(connection.age)),
            const SizedBox(height: 10),
            KeyValueText(label: l10n.get('connections.start'), value: l10n.formatDateTime(connection.start)),
            if (connection.processPath.isNotEmpty) ...[
              const SizedBox(height: 10),
              KeyValueText(label: 'Path', value: connection.processPath, monospace: true),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    connection.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: palette.muted, fontFamily: 'Consolas'),
                  ),
                ),
                AppIconButton(
                  icon: 'copy-line',
                  tooltip: l10n.get('common.copy'),
                  size: 15,
                  onTap: () => copyToClipboard(dialogContext, connection.id),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(dialogContext.t('common.close')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.danger, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              controller.closeConnection(connection.id);
            },
            child: Text(dialogContext.t('connections.close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    final snapshot = controller.connectionsSnapshot;
    final filtered = _filtered(snapshot);
    final running = controller.isRunning;

    return PageFrame(
      header: PageHeader(
        leading: widget.showBack ? const ToolBackButton() : null,
        title: l10n.get('nav.connections'),
        subtitle: l10n.get('connections.subtitle'),
        actions: [
          if (running)
            OutlinedButton.icon(
              onPressed: snapshot.connections.isEmpty ? null : () => _closeAll(controller),
              icon: const AppIcon('close-circle-line', size: 16),
              label: Text(l10n.get('connections.closeAll')),
            ),
          AppIconButton(
            icon: 'refresh-2-line',
            tooltip: l10n.get('common.refresh'),
            onTap: running ? () => controller.refreshConnections() : null,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            radius: AppTheme.radiusMd,
            child: Row(
              children: [
                _SummaryMetric(
                  icon: 'transfer-line',
                  label: l10n.get('connections.active', [snapshot.connections.length]),
                  value: '${snapshot.count}',
                  color: Theme.of(context).colorScheme.primary,
                ),
                _SummaryDivider(color: palette.border),
                _SummaryMetric(
                  icon: 'upload-line',
                  label: l10n.get('connections.totalUpload'),
                  value: formatBytes(snapshot.uploadTotal),
                  color: palette.upload,
                ),
                _SummaryDivider(color: palette.border),
                _SummaryMetric(
                  icon: 'download-2-line',
                  label: l10n.get('connections.totalDownload'),
                  value: formatBytes(snapshot.downloadTotal),
                  color: palette.download,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppSearchField(
            controller: _search,
            hint: l10n.get('connections.search'),
            onChanged: (_) => setState(() {}),
          ),
          if (controller.connectionsError != null) ...[
            const SizedBox(height: 10),
            InfoBanner(
              message: controller.connectionsError!.localized(l10n),
              color: palette.danger,
              icon: 'close-circle-line',
              dense: true,
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: !running
                ? EmptyState(
                    icon: 'transfer-line',
                    title: l10n.get('connections.notRunning'),
                    message: l10n.get('connections.notRunningHint'),
                  )
                : filtered.isEmpty
                    ? EmptyState(
                        icon: snapshot.connections.isEmpty ? 'transfer-line' : 'search-line',
                        title: snapshot.connections.isEmpty
                            ? l10n.get('connections.empty')
                            : l10n.get('proxy.filterNoResult'),
                        message: snapshot.connections.isEmpty ? l10n.get('connections.emptyHint') : null,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 6),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final connection = filtered[index];
                          return _ConnectionTile(
                            connection: connection,
                            onTap: () => _showDetails(controller, connection),
                            onClose: () => controller.closeConnection(connection.id),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final String icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Center(child: AppIcon(icon, size: 16, color: color)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: palette.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  const _SummaryDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 30, color: color, margin: const EdgeInsets.symmetric(horizontal: 12));
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({required this.connection, required this.onTap, required this.onClose});

  final ConnectionInfo connection;
  final VoidCallback onTap;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final node = connection.node;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      radius: AppTheme.radiusMd,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: palette.accentSoft,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: AppIcon(
                connection.network.toLowerCase() == 'udp' ? 'transfer-line' : 'globe-line',
                size: 17,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        connection.host,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: palette.text),
                      ),
                    ),
                    if (connection.network.isNotEmpty) ...[
                      const SizedBox(width: 7),
                      AppBadge(text: connection.network.toUpperCase(), dense: true),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (connection.process.isNotEmpty) ...[
                      Flexible(
                        child: Text(
                          connection.process,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: palette.muted),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Text(
                        connection.ruleLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: palette.muted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (node != null) ...[
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: palette.cardAlt,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: palette.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon('wifi-line', size: 10, color: palette.muted),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  node,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 10, color: palette.strongMuted),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    IconTheme(
                      data: IconThemeData(color: palette.upload),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('↑', style: TextStyle(fontSize: 10, color: palette.upload)),
                          const SizedBox(width: 2),
                          Text(
                            formatBytes(connection.upload),
                            style: TextStyle(fontSize: 10, color: palette.upload, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('↓', style: TextStyle(fontSize: 10, color: palette.download)),
                        const SizedBox(width: 2),
                        Text(
                          formatBytes(connection.download),
                          style: TextStyle(fontSize: 10, color: palette.download, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AppIconButton(
                icon: 'close-line',
                size: 14,
                padding: 5,
                tooltip: l10n.get('connections.close'),
                onTap: onClose,
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(right: 5),
                child: Text(
                  formatDurationShort(connection.age),
                  style: TextStyle(fontSize: 10, color: palette.muted, fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
