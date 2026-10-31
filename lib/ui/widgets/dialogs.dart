import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import 'app_icon.dart';
import 'common.dart';

Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double maxWidth = 520,
  bool dismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: dismissible,
    barrierColor: Colors.black.withValues(alpha: 0.48),
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: builder(context),
      ),
    ),
  );
}

class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.content,
    this.actions = const [],
    this.maxWidth = 520,
  });

  final String title;
  final String? subtitle;
  final String? icon;
  final Widget? content;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = Theme.of(context).textTheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.84;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: palette.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 18, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (icon != null) ...[
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: palette.accentSoft,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Center(
                          child: AppIcon(icon!, size: 20, color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                      const SizedBox(width: 13),
                    ],
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(top: icon != null ? 2 : 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                            if (subtitle != null) ...[
                              const SizedBox(height: 4),
                              Text(subtitle!, style: text.bodySmall?.copyWith(color: palette.muted)),
                            ],
                          ],
                        ),
                      ),
                    ),
                    AppIconButton(
                      icon: 'close-line',
                      tooltip: context.t('common.close'),
                      size: 17,
                      onTap: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
              if (content != null)
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
                    child: content!,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: actions,
                      ),
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

Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmText,
  String? cancelText,
  bool danger = false,
  String icon = 'information-line',
}) async {
  final result = await showAppDialog<bool>(
    context,
    builder: (dialogContext) => AppDialog(
      title: title,
      icon: icon,
      content: Text(
        message,
        style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
              color: AppPalette.of(dialogContext).strongMuted,
              height: 1.6,
            ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelText ?? dialogContext.t('common.cancel')),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(
                  backgroundColor: AppPalette.of(dialogContext).danger,
                  foregroundColor: Colors.white,
                )
              : null,
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmText ?? dialogContext.t('common.confirm')),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> showMessageDialog(
  BuildContext context, {
  required String title,
  required String message,
  String icon = 'information-line',
  String? actionLabel,
}) {
  return showAppDialog<void>(
    context,
    maxWidth: 560,
    builder: (dialogContext) => AppDialog(
      title: title,
      icon: icon,
      content: SelectableText(
        message,
        style: TextStyle(
          fontSize: 12,
          height: 1.6,
          fontFamily: 'Consolas',
          color: AppPalette.of(dialogContext).strongMuted,
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(actionLabel ?? dialogContext.t('common.done')),
        ),
      ],
    ),
  );
}
