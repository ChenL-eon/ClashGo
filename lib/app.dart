import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'controllers/app_controller.dart';
import 'core/app_info.dart';
import 'core/l10n.dart';
import 'core/theme.dart';
import 'ui/shell/app_shell.dart';
import 'ui/widgets/common.dart';

class ClashGoApp extends StatefulWidget {
  const ClashGoApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<ClashGoApp> createState() => _ClashGoAppState();
}

class _ClashGoAppState extends State<ClashGoApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<AppNotice>? _noticeSubscription;

  @override
  void initState() {
    super.initState();
    _noticeSubscription = widget.controller.notices.listen(_showNotice);
  }

  @override
  void dispose() {
    _noticeSubscription?.cancel();
    super.dispose();
  }

  void _showNotice(AppNotice notice) {
    final navigator = _navigatorKey.currentState;
    final context = _navigatorKey.currentContext;
    final overlay = navigator?.overlay;
    if (context == null || overlay == null) return;
    final mobile = MediaQuery.sizeOf(context).width < appDesktopBreakpoint;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    showAppToastOverlay(
      overlay,
      notice.message,
      error: notice.error,
      margin: mobile ? EdgeInsets.fromLTRB(20, 12, 20, 92 + bottomInset) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AppController>.value(
      value: widget.controller,
      child: Selector<AppController, (String, String, int, bool)>(
        selector: (_, controller) => (
          controller.settings.language,
          controller.settings.themeMode,
          controller.settings.accentIndex,
          controller.settings.pureBlack,
        ),
        builder: (context, visual, _) {
          final language = visual.$1;
          final themeMode = switch (visual.$2) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          };
          final accent = accentPresets[visual.$3.clamp(0, accentPresets.length - 1)].color;
          final l10n = L10n(language);
          return L10nScope(
            l10n: l10n,
            child: MaterialApp(
              title: AppInfo.name,
              debugShowCheckedModeBanner: false,
              navigatorKey: _navigatorKey,
              themeMode: themeMode,
              theme: AppTheme.build(brightness: Brightness.light, accent: accent),
              darkTheme: AppTheme.build(brightness: Brightness.dark, accent: accent, pureBlack: visual.$4),
              locale: Locale(language),
              supportedLocales: const [Locale('zh'), Locale('en')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              home: const AppShell(),
            ),
          );
        },
      ),
    );
  }
}
