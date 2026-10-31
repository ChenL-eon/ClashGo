import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../widgets/app_icon.dart';

enum AppTool { dns, rules, providers, connections, logs }

class AppNavigation extends InheritedWidget {
  const AppNavigation({
    super.key,
    required this.go,
    required this.openTool,
    required super.child,
  });

  final ValueChanged<int> go;
  final ValueChanged<AppTool> openTool;

  static AppNavigation? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppNavigation>();
  }

  static void goTab(BuildContext context, int index) => maybeOf(context)?.go(index);

  static void tool(BuildContext context, AppTool tool) => maybeOf(context)?.openTool(tool);

  @override
  bool updateShouldNotify(AppNavigation oldWidget) => false;
}

class ToolBackButton extends StatelessWidget {
  const ToolBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: context.t('common.close'),
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: palette.border),
            ),
            child: Center(child: AppIcon('arrow-left-line', size: 17, color: palette.strongMuted)),
          ),
        ),
      ),
    );
  }
}
