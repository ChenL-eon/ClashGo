import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../../core/errors.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/subscription.dart';
import 'common.dart';
import 'dialogs.dart';

bool _isValidSubscriptionUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null) return false;
  return (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
}

Future<bool?> showAddSubscriptionDialog(BuildContext context, AppController controller) {
  return showAppDialog<bool>(
    context,
    maxWidth: 500,
    dismissible: !controller.importingSubscription,
    builder: (context) => _AddSubscriptionDialog(controller: controller),
  );
}

class _AddSubscriptionDialog extends StatefulWidget {
  const _AddSubscriptionDialog({required this.controller});

  final AppController controller;

  @override
  State<_AddSubscriptionDialog> createState() => _AddSubscriptionDialogState();
}

class _AddSubscriptionDialogState extends State<_AddSubscriptionDialog> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  final _minutesController = TextEditingController(text: '1440');
  bool _autoUpdate = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _urlController.text.trim();
    if (!_isValidSubscriptionUrl(url)) {
      setState(() => _error = context.t('subscriptions.invalidUrl'));
      return;
    }
    final minutes = int.tryParse(_minutesController.text.trim()) ?? 0;
    if (_autoUpdate && (minutes < 60 || minutes > 43200)) {
      setState(() => _error = context.t('subscriptions.intervalInvalid'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.addSubscription(
        url: url,
        name: _nameController.text.trim(),
        autoUpdate: _autoUpdate,
        updateIntervalMinutes: minutes <= 0 ? 1440 : minutes,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = errorFrom(error).localized(context.l10n));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AppDialog(
      title: context.t('subscriptions.addTitle'),
      icon: 'add-line',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: context.t('subscriptions.nameHint'),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 12, right: 6),
                child: Icon(Icons.badge_outlined, size: 18),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            enabled: !_busy,
            minLines: 1,
            maxLines: 2,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _busy ? null : _submit(),
            decoration: InputDecoration(
              hintText: context.t('subscriptions.urlHint'),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 12, right: 6),
                child: Icon(Icons.link, size: 18),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('subscriptions.autoUpdate'),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.t('subscriptions.autoUpdateHint'),
                      style: TextStyle(fontSize: 11.5, color: palette.muted),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _autoUpdate,
                onChanged: _busy ? null : (value) => setState(() => _autoUpdate = value),
              ),
            ],
          ),
          if (_autoUpdate) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _minutesController,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.t('subscriptions.interval'),
                suffixText: context.t('subscriptions.intervalMinutes', ['']).trim(),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (_error != null) ...[
            InfoBanner(message: _error!, color: palette.danger, icon: 'close-circle-line'),
            const SizedBox(height: 12),
          ],
          InfoBanner(
            message: context.t('subscriptions.exportHint'),
            color: palette.muted,
            dense: true,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(context.t('common.cancel')),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(context.t('subscriptions.add')),
        ),
      ],
    );
  }
}

Future<bool?> showEditSubscriptionDialog(
  BuildContext context,
  AppController controller,
  Subscription subscription,
) {
  return showAppDialog<bool>(
    context,
    maxWidth: 520,
    builder: (context) => _EditSubscriptionDialog(controller: controller, subscription: subscription),
  );
}

class _EditSubscriptionDialog extends StatefulWidget {
  const _EditSubscriptionDialog({required this.controller, required this.subscription});

  final AppController controller;
  final Subscription subscription;

  @override
  State<_EditSubscriptionDialog> createState() => _EditSubscriptionDialogState();
}

class _EditSubscriptionDialogState extends State<_EditSubscriptionDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _urlController;
  late final TextEditingController _minutesController;
  late bool _autoUpdate;
  String? _error;

  @override
  void initState() {
    super.initState();
    final subscription = widget.subscription;
    _nameController = TextEditingController(text: subscription.name);
    _urlController = TextEditingController(text: subscription.url);
    _minutesController = TextEditingController(
      text: (subscription.updateIntervalMinutes <= 0 ? 1440 : subscription.updateIntervalMinutes).toString(),
    );
    _autoUpdate = subscription.autoUpdate && !subscription.isLocal;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _minutesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final minutes = int.tryParse(_minutesController.text.trim()) ?? 0;
    if (!widget.subscription.isLocal && _autoUpdate && (minutes < 60 || minutes > 43200)) {
      setState(() => _error = context.t('subscriptions.intervalInvalid'));
      return;
    }
    if (!widget.subscription.isLocal && !_isValidSubscriptionUrl(_urlController.text)) {
      setState(() => _error = context.t('subscriptions.invalidUrl'));
      return;
    }
    await widget.controller.editSubscription(
      widget.subscription.id,
      name: _nameController.text,
      url: _urlController.text,
      autoUpdate: _autoUpdate,
      updateIntervalMinutes: minutes <= 0 ? 1440 : minutes,
    );
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final confirmed = await showConfirmDialog(
      context,
      title: context.t('subscriptions.deleteTitle'),
      message: context.t('subscriptions.deleteMessage', [widget.subscription.name]),
      confirmText: context.t('common.delete'),
      danger: true,
      icon: 'delete-2-line',
    );
    if (!confirmed) return;
    await widget.controller.deleteSubscription(widget.subscription.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return AppDialog(
      title: context.t('subscriptions.editTitle'),
      subtitle: widget.subscription.name,
      icon: 'settings-3-line',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: context.t('subscriptions.name'),
              hintText: context.t('subscriptions.nameHint'),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            enabled: !widget.subscription.isLocal,
            minLines: 1,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: widget.subscription.isLocal
                  ? context.t('subscriptions.localFile')
                  : context.t('subscriptions.url'),
            ),
          ),
          const SizedBox(height: 18),
          if (!widget.subscription.isLocal) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t('subscriptions.autoUpdate'),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.t('subscriptions.autoUpdateHint'),
                        style: TextStyle(fontSize: 11.5, color: palette.muted),
                      ),
                    ],
                  ),
                ),
                Switch(value: _autoUpdate, onChanged: (value) => setState(() => _autoUpdate = value)),
              ],
            ),
            if (_autoUpdate) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _minutesController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.t('subscriptions.interval'),
                  suffixText: context.t('subscriptions.intervalMinutes', ['']).trim(),
                ),
              ),
            ],
          ],
          if (widget.subscription.isLocal) ...[
            InfoBanner(
              message: context.t('subscriptions.localFile'),
              color: palette.muted,
              dense: true,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            InfoBanner(message: _error!, color: palette.danger, icon: 'close-circle-line'),
          ],
        ],
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: palette.danger),
          onPressed: _delete,
          child: Text(context.t('common.delete')),
        ),
        const SizedBox(width: 4),
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(context.t('common.cancel'))),
        FilledButton(onPressed: _save, child: Text(context.t('common.save'))),
      ],
    );
  }
}
