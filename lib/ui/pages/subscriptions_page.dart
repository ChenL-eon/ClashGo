import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../core/errors.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/subscription_link.dart';
import '../../core/theme.dart';
import '../../models/subscription.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/qr_scan.dart';
import '../widgets/quota_bar.dart';
import '../widgets/subscription_dialogs.dart';

const _cardMenuContentWidth = 150.0;
// 菜单宽度 = 内容宽 + 浮层左右 8 + 菜单行左右 16（与 appMenuStyle/appMenuItemStyle 一致）。
const _cardMenuWidth = _cardMenuContentWidth + 8 * 2 + 16 * 2;

/// 保留旧入口名：二维码测试与页面都从这里取解析结果。
String? subscriptionUrlFromQr(String raw) => subscriptionUrlFromLink(raw);

Widget _actionMenuRow({
  required String icon,
  required String label,
  required Color color,
}) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppIcon(icon, size: 16, color: color),
      const SizedBox(width: 10),
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color),
        ),
      ),
    ],
  );
}

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  bool _importing = false;

  Future<void> _add() async {
    final controller = context.read<AppController>();
    await showAddSubscriptionDialog(context, controller);
  }

  Future<void> _importFile() async {
    if (_importing) return;
    final controller = context.read<AppController>();
    setState(() => _importing = true);
    try {
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['yaml', 'yml'],
      );
      final path = result?.path;
      if (path == null) return;
      await controller.importLocalFile(File(path));
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, errorFrom(error).localized(context.l10n), error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importQr() async {
    if (_importing) return;
    final controller = context.read<AppController>();
    final l10n = context.l10n;
    setState(() => _importing = true);
    try {
      final String? value;
      if (qrScannerSupported) {
        value = await showQrCodeScanner(context);
      } else {
        final result = await pickQrCodeImage(context);
        if (!result.picked) return;
        if (result.text == null) {
          if (!mounted) return;
          showAppToast(context, l10n.get('subscriptions.qrNotFound'), error: true);
          return;
        }
        value = result.text;
      }
      if (value == null || !mounted) return;
      final url = subscriptionUrlFromQr(value);
      if (url == null) {
        showAppToast(context, l10n.get('subscriptions.qrNotLink'), error: true);
        return;
      }
      await controller.addSubscription(url: url);
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, errorFrom(error).localized(context.l10n), error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importClipboard() async {
    if (_importing) return;
    final controller = context.read<AppController>();
    final l10n = context.l10n;
    setState(() => _importing = true);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final raw = data?.text?.trim() ?? '';
      if (raw.isEmpty) {
        if (!mounted) return;
        showAppToast(context, l10n.get('subscriptions.clipboardEmpty'), error: true);
        return;
      }
      final url = subscriptionUrlFromLink(raw);
      if (url == null) {
        if (!mounted) return;
        showAppToast(context, l10n.get('subscriptions.clipboardNoLink'), error: true);
        return;
      }
      await controller.addSubscription(url: url);
    } catch (error) {
      if (!mounted) return;
      showAppToast(context, errorFrom(error).localized(context.l10n), error: true);
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// 四种导入方式：订阅链接、剪贴板、本地文件、二维码。
  /// 桌面端没有摄像头，最后一项是选择二维码图片识别。
  List<({String icon, String label, VoidCallback onPressed})> _importEntries(BuildContext context) {
    final l10n = context.l10n;
    return [
      (icon: 'link-line', label: l10n.get('subscriptions.addByUrl'), onPressed: _add),
      (
        icon: 'copy-line',
        label: l10n.get('subscriptions.importClipboard'),
        onPressed: _importClipboard,
      ),
      (icon: 'file-line', label: l10n.get('subscriptions.importLocal'), onPressed: _importFile),
      (
        icon: 'qrcode-line',
        label: l10n.get(qrScannerSupported ? 'subscriptions.importQr' : 'subscriptions.importQrImage'),
        onPressed: _importQr,
      ),
    ];
  }

  /// 添加订阅只有一个入口：右上角「+」下拉菜单，三种方式都在里面。
  Widget _addMenuButton(BuildContext context, AppController controller, {required bool desktop}) {
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    final busy = _importing || controller.importingSubscription;
    return MenuAnchor(
      alignmentOffset: const Offset(-(_cardMenuWidth + 8), 6),
      style: appMenuStyle(palette).copyWith(alignment: AlignmentDirectional.bottomEnd),
      menuChildren: [
        for (final entry in _importEntries(context))
          MenuItemButton(
            onPressed: entry.onPressed,
            style: appMenuItemStyle(palette),
            child: SizedBox(
              width: _cardMenuContentWidth,
              child: _actionMenuRow(icon: entry.icon, label: entry.label, color: palette.text),
            ),
          ),
      ],
      builder: (context, menu, child) => AppIconButton(
        icon: 'add-line',
        size: desktop ? 18 : 22,
        padding: desktop ? 9 : 7,
        background: desktop ? palette.cardAlt : null,
        tooltip: l10n.get('subscriptions.add'),
        onTap: busy ? null : () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }

  Future<void> _edit(Subscription subscription) async {
    final controller = context.read<AppController>();
    await showEditSubscriptionDialog(context, controller, subscription);
  }

  Future<void> _delete(Subscription subscription) async {
    final controller = context.read<AppController>();
    final confirmed = await showConfirmDialog(
      context,
      title: context.t('subscriptions.deleteTitle'),
      message: context.t('subscriptions.deleteMessage', [subscription.name]),
      confirmText: context.t('common.delete'),
      danger: true,
      icon: 'delete-2-line',
    );
    if (!confirmed || !mounted) return;
    await controller.deleteSubscription(subscription.id);
  }

  Future<void> _update(Subscription subscription) async {
    try {
      await context.read<AppController>().updateSubscription(subscription.id);
    } catch (_) {}
  }

  Future<void> _reorder() async {
    final controller = context.read<AppController>();
    final ordered = await showAppDialog<List<String>>(
      context,
      maxWidth: 440,
      builder: (_) => _ReorderSubscriptionsDialog(subscriptions: controller.subscriptions),
    );
    if (ordered == null || !mounted) return;
    await controller.reorderSubscriptions(ordered);
  }

  Widget _sortButton(BuildContext context, {required bool desktop}) {
    return AppIconButton(
      icon: 'sort-ascending-line',
      size: desktop ? 18 : 20,
      padding: desktop ? 9 : 7,
      background: desktop ? AppPalette.of(context).cardAlt : null,
      tooltip: context.l10n.get('subscriptions.sort'),
      onTap: _reorder,
    );
  }

  String _intervalLabel(BuildContext context, Subscription subscription) {
    final l10n = context.l10n;
    final minutes = subscription.updateIntervalMinutes;
    if (!subscription.autoUpdate || minutes <= 0) return l10n.get('subscriptions.intervalOff');
    if (minutes >= 1440 && minutes % 1440 == 0) {
      return l10n.get('subscriptions.intervalDays', [minutes ~/ 1440]);
    }
    if (minutes >= 60 && minutes % 60 == 0) {
      return l10n.get('subscriptions.intervalHours', [minutes ~/ 60]);
    }
    return l10n.get('subscriptions.intervalMinutes', [minutes]);
  }

  Widget _buildMobile(BuildContext context, AppController controller) {
    final l10n = context.l10n;
    final subscriptions = controller.subscriptions;
    return PageContainer(
      children: [
        MobilePageHeader(
          title: l10n.get('subscriptions.title'),
          actions: [
            if (subscriptions.length > 1) ...[
              _sortButton(context, desktop: false),
              const SizedBox(width: 8),
            ],
            if (controller.updatingAll)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              AppIconButton(
                icon: 'refresh-2-line',
                size: 20,
                padding: 7,
                tooltip: l10n.get('subscriptions.updateAll'),
                onTap: subscriptions.isEmpty ? null : controller.updateAllSubscriptions,
              ),
            const SizedBox(width: 8),
            _addMenuButton(context, controller, desktop: false),
          ],
        ),
        const SizedBox(height: 20),
        if (subscriptions.isEmpty)
          SurfaceCard(
            child: EmptyState(
              icon: 'card-line',
              title: l10n.get('subscriptions.empty'),
              message: l10n.get('subscriptions.emptyHint'),
            ),
          )
        else
          for (final subscription in subscriptions) ...[
            _MobileSubscriptionCard(
              subscription: subscription,
              active: controller.activeId == subscription.id,
              updating: controller.updatingSubscriptions.contains(subscription.id),
              onUse: () => controller.setActiveSubscription(subscription.id),
              onUpdate: () => _update(subscription),
              onDelete: () => _delete(subscription),
              onEdit: () => _edit(subscription),
            ),
            if (subscription != subscriptions.last) const SizedBox(height: 12),
          ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    final subscriptions = controller.subscriptions;
    if (MediaQuery.sizeOf(context).width < appDesktopBreakpoint) {
      return _buildMobile(context, controller);
    }
    return PageContainer(
      children: [
        PageHeader(
          title: l10n.get('nav.subscriptions'),
          subtitle: l10n.get('subscriptions.subtitle'),
          actions: [
            if (subscriptions.length > 1) ...[
              _sortButton(context, desktop: true),
              const SizedBox(width: 8),
            ],
            if (subscriptions.isNotEmpty) ...[
              if (controller.updatingAll)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 9, vertical: 9),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                AppIconButton(
                  icon: 'refresh-2-line',
                  size: 18,
                  padding: 9,
                  background: palette.cardAlt,
                  tooltip: l10n.get('subscriptions.updateAll'),
                  onTap: controller.updateAllSubscriptions,
                ),
              const SizedBox(width: 8),
            ],
            _addMenuButton(context, controller, desktop: true),
          ],
        ),
        const SizedBox(height: 18),
        if (subscriptions.isEmpty)
          SurfaceCard(
            child: EmptyState(
              icon: 'card-line',
              title: l10n.get('subscriptions.empty'),
              message: l10n.get('subscriptions.emptyHint'),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 14.0;
              final columns = constraints.maxWidth >= 820 ? 2 : 1;
              final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final subscription in subscriptions)
                    SizedBox(
                      width: width,
                      child: _SubscriptionCard(
                        subscription: subscription,
                        active: controller.activeId == subscription.id,
                        updating: controller.updatingSubscriptions.contains(subscription.id),
                        intervalLabel: _intervalLabel(context, subscription),
                        onUse: () => controller.setActiveSubscription(subscription.id),
                        onUpdate: () => _update(subscription),
                        onEdit: () => _edit(subscription),
                        onDelete: () => _delete(subscription),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// 手动排序：本地列表一改一存，取消则原样返回。
class _ReorderSubscriptionsDialog extends StatefulWidget {
  const _ReorderSubscriptionsDialog({required this.subscriptions});

  final List<Subscription> subscriptions;

  @override
  State<_ReorderSubscriptionsDialog> createState() => _ReorderSubscriptionsDialogState();
}

class _ReorderSubscriptionsDialogState extends State<_ReorderSubscriptionsDialog> {
  late final List<Subscription> _order = List<Subscription>.of(widget.subscriptions);

  void _move(int index, int delta) {
    final target = index + delta;
    if (target < 0 || target >= _order.length) return;
    setState(() {
      final item = _order.removeAt(index);
      _order.insert(target, item);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    return AppDialog(
      title: l10n.get('subscriptions.sortTitle'),
      subtitle: l10n.get('subscriptions.sortHint'),
      icon: 'sort-ascending-line',
      maxWidth: 440,
      content: Column(
        children: [
          for (var i = 0; i < _order.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == _order.length - 1 ? 0 : 8),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                decoration: BoxDecoration(
                  color: palette.cardAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: palette.border),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.muted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _order[i].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: palette.text),
                      ),
                    ),
                    AppIconButton(
                      key: ValueKey('reorder-up-${_order[i].id}'),
                      icon: 'up-small-line',
                      size: 16,
                      padding: 7,
                      tooltip: l10n.get('subscriptions.moveUp'),
                      onTap: i == 0 ? null : () => _move(i, -1),
                    ),
                    AppIconButton(
                      key: ValueKey('reorder-down-${_order[i].id}'),
                      icon: 'down-small-line',
                      size: 16,
                      padding: 7,
                      tooltip: l10n.get('subscriptions.moveDown'),
                      onTap: i == _order.length - 1 ? null : () => _move(i, 1),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.get('common.cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_order.map((sub) => sub.id).toList()),
          child: Text(l10n.get('common.save')),
        ),
      ],
    );
  }
}

class _MobileSubscriptionCard extends StatefulWidget {
  const _MobileSubscriptionCard({
    required this.subscription,
    required this.active,
    required this.updating,
    required this.onUse,
    required this.onUpdate,
    required this.onDelete,
    required this.onEdit,
  });

  final Subscription subscription;
  final bool active;
  final bool updating;
  final VoidCallback onUse;
  final VoidCallback onUpdate;
  final VoidCallback onDelete;
  final VoidCallback onEdit;

  @override
  State<_MobileSubscriptionCard> createState() => _MobileSubscriptionCardState();
}

class _MobileSubscriptionCardState extends State<_MobileSubscriptionCard> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final subscription = widget.subscription;
    final active = widget.active;
    final updating = widget.updating;
    final onUse = widget.onUse;
    final onUpdate = widget.onUpdate;
    final onDelete = widget.onDelete;
    final onEdit = widget.onEdit;
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final accent = Theme.of(context).colorScheme.primary;
    final ratio = subscription.usageRatio;
    final quotaColor = ratio >= 0.9 ? palette.danger : ratio >= 0.7 ? palette.warning : accent;
    final card = SurfaceCard(
      padding: const EdgeInsets.fromLTRB(18, 15, 16, 15),
      radius: 20,
      // 切换订阅只点卡片：头部不再放“使用”按钮，整张卡就是入口。
      onTap: active ? null : onUse,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  subscription.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: palette.text),
                ),
              ),
              const SizedBox(width: 8),
              if (active)
                Text(
                  l10n.get('subscriptions.active'),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: palette.success),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 9, bottom: 12),
            child: Container(height: 1, color: palette.border),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${l10n.get('subscriptions.used')} ',
                            style: TextStyle(fontSize: 12.5, color: palette.muted),
                          ),
                          TextSpan(
                            text: subscription.hasQuota
                                ? '${formatBytes(subscription.used)} / ${formatBytes(subscription.total)}'
                                : l10n.get('subscriptions.noQuota'),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: palette.text,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // 没有流量信息、没有到期日期也保留同样的行高，卡片外框才能对齐。
                    if (subscription.hasQuota)
                      QuotaBar(ratio: ratio, color: quotaColor, height: 5)
                    else
                      const SizedBox(height: 5),
                    const SizedBox(height: 6),
                    Text(
                      l10n.get('home.lastUpdated', [l10n.formatDateTime(subscription.lastUpdatedAt)]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: palette.muted),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.get('home.expireAt', [
                        subscription.hasExpiry
                            ? formatExpire(subscription.expire, zh: l10n.isZh)
                            : l10n.get('subscriptions.unknown'),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: subscription.isExpired ? palette.danger : palette.muted,
                      ),
                    ),
                    if (subscription.lastError != null) ...[
                      const SizedBox(height: 8),
                      InfoBanner(
                        message: subscription.lastError!,
                        color: palette.danger,
                        icon: 'close-circle-line',
                        dense: true,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MenuAnchor(
                    controller: _menu,
                    alignmentOffset: const Offset(-(_cardMenuWidth + 8), 6),
                    style: appMenuStyle(palette).copyWith(
                      alignment: AlignmentDirectional.bottomEnd,
                    ),
                    menuChildren: [
                      MenuItemButton(
                        onPressed: onEdit,
                        style: appMenuItemStyle(palette),
                        child: SizedBox(
                          width: _cardMenuContentWidth,
                          child: _actionMenuRow(
                            icon: 'settings-3-line',
                            label: l10n.get('common.edit'),
                            color: palette.text,
                          ),
                        ),
                      ),
                    ],
                    builder: (context, menu, child) => _CircleAction(
                      icon: 'more-1-line',
                      onTap: () => menu.isOpen ? menu.close() : menu.open(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _CircleAction(
                    icon: 'refresh-2-line',
                    busy: updating,
                    onTap: updating ? null : onUpdate,
                  ),
                  const SizedBox(width: 8),
                  _CircleAction(icon: 'delete-2-line', onTap: onDelete),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    // 右键整卡等同点「更多」：菜单仍锚在按钮旁，不额外做浮层定位。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (_) {
        if (!_menu.isOpen) _menu.open();
      },
      child: card,
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon, this.onTap, this.busy = false});

  final String icon;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Material(
      color: palette.cardAlt,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Center(
            child: busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.8, color: palette.muted),
                  )
                : AppIcon(
                    icon,
                    size: 17,
                    color: onTap == null ? palette.muted.withValues(alpha: 0.5) : palette.strongMuted,
                  ),
          ),
        ),
      ),
    );
  }
}

class _SubscriptionCard extends StatefulWidget {
  const _SubscriptionCard({
    required this.subscription,
    required this.active,
    required this.updating,
    required this.intervalLabel,
    required this.onUse,
    required this.onUpdate,
    required this.onEdit,
    required this.onDelete,
  });

  final Subscription subscription;
  final bool active;
  final bool updating;
  final String intervalLabel;
  final VoidCallback onUse;
  final VoidCallback onUpdate;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<_SubscriptionCard> createState() => _SubscriptionCardState();
}

class _SubscriptionCardState extends State<_SubscriptionCard> {
  final _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final subscription = widget.subscription;
    final active = widget.active;
    final updating = widget.updating;
    final intervalLabel = widget.intervalLabel;
    final onUse = widget.onUse;
    final onUpdate = widget.onUpdate;
    final onEdit = widget.onEdit;
    final onDelete = widget.onDelete;
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final accent = Theme.of(context).colorScheme.primary;
    final quotaColor = subscription.usageRatio >= 0.9
        ? palette.danger
        : subscription.usageRatio >= 0.7
            ? palette.warning
            : accent;
    final updated = subscription.lastUpdatedAt;
    final card = SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 13, 10, 12),
      radius: 18,
      border: active ? Border.all(color: accent.withValues(alpha: 0.38)) : null,
      onTap: active ? null : onUse,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: active ? palette.accentSoft : palette.cardAlt,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: active ? accent.withValues(alpha: 0.25) : palette.border),
                ),
                child: Center(
                  child: AppIcon(
                    subscription.isLocal ? 'file-line' : 'card-line',
                    size: 17,
                    color: active ? accent : palette.muted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subscription.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: palette.text,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        AppBadge(
                          text: subscription.isLocal ? l10n.get('subscriptions.local') : l10n.get('subscriptions.remote'),
                          icon: subscription.isLocal ? 'file-line' : 'link-line',
                          dense: true,
                        ),
                        if (active)
                          AppBadge(
                            text: l10n.get('subscriptions.active'),
                            color: palette.success,
                            icon: 'check-line',
                            dense: true,
                          ),
                        AppBadge(
                          text: intervalLabel,
                          color: accent,
                          icon: 'refresh-2-line',
                          dense: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AppIconButton(
                icon: 'refresh-2-line',
                size: 15,
                padding: 7,
                background: palette.cardAlt,
                tooltip: updating
                    ? l10n.get('subscriptions.updating')
                    : l10n.get('subscriptions.update'),
                onTap: updating ? null : onUpdate,
              ),
              const SizedBox(width: 6),
              MenuAnchor(
                controller: _menu,
                reservedPadding: const EdgeInsets.all(16),
                // 与设置页下拉一致：菜单在按钮下方、右缘内收 8。
                alignmentOffset: const Offset(-(_cardMenuWidth + 8), 6),
                style: appMenuStyle(palette).copyWith(
                  alignment: AlignmentDirectional.bottomEnd,
                ),
                menuChildren: [
                  MenuItemButton(
                    onPressed: onEdit,
                    style: appMenuItemStyle(palette),
                    child: SizedBox(
                      width: _cardMenuContentWidth,
                      child: _actionMenuRow(
                        icon: 'settings-3-line',
                        label: l10n.get('common.edit'),
                        color: palette.text,
                      ),
                    ),
                  ),
                  MenuItemButton(
                    onPressed: onDelete,
                    style: appMenuItemStyle(palette),
                    child: SizedBox(
                      width: _cardMenuContentWidth,
                      child: _actionMenuRow(
                        icon: 'delete-2-line',
                        label: l10n.get('common.delete'),
                        color: palette.danger,
                      ),
                    ),
                  ),
                ],
                builder: (context, controller, child) => Tooltip(
                  message: l10n.get('common.more'),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () =>
                        controller.isOpen ? controller.close() : controller.open(),
                    child: SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: updating
                            ? SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.8, color: palette.muted),
                              )
                            : AppIcon('down-small-line', size: 16, color: palette.muted),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (subscription.hasQuota) ...[
            Row(
              children: [
                Text(
                  l10n.get('subscriptions.used'),
                  style: TextStyle(fontSize: 11, color: palette.muted),
                ),
                const SizedBox(width: 6),
                Text(
                  '${(subscription.usageRatio * 100).toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: quotaColor),
                ),
                const Spacer(),
                Text(
                  '${formatBytes(subscription.used)} / ${formatBytes(subscription.total)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            QuotaBar(ratio: subscription.usageRatio, color: quotaColor, height: 4),
          ] else
            Row(
              children: [
                Text(
                  l10n.get('subscriptions.used'),
                  style: TextStyle(fontSize: 11, color: palette.muted),
                ),
                const Spacer(),
                Text(
                  l10n.get('subscriptions.noQuota'),
                  style: TextStyle(fontSize: 11, color: palette.strongMuted),
                ),
              ],
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TimeChip(
                  icon: 'clock-line',
                  tooltip: l10n.get('subscriptions.lastUpdated'),
                  text: updated == null ? '—' : l10n.formatDateTime(updated),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TimeChip(
                  icon: 'clock-line',
                  tooltip: l10n.get('subscriptions.expire'),
                  text: subscription.hasExpiry
                      ? formatExpire(subscription.expire, zh: l10n.isZh)
                      : l10n.get('subscriptions.unknown'),
                  color: subscription.isExpired ? palette.danger : null,
                ),
              ),
            ],
          ),
          if (subscription.lastError != null) ...[
            const SizedBox(height: 9),
            InfoBanner(
              message: subscription.lastError!,
              color: palette.danger,
              icon: 'close-circle-line',
              dense: true,
            ),
          ],
        ],
      ),
    );
    // 右键整卡等同点「更多」：菜单仍锚在按钮旁，不额外做浮层定位。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: (_) {
        if (!_menu.isOpen) _menu.open();
      },
      child: card,
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.icon, required this.text, this.tooltip, this.color});

  final String icon;
  final String text;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: palette.cardAlt,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          AppIcon(icon, size: 12, color: palette.muted),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: color ?? palette.strongMuted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip!, child: chip);
  }
}
