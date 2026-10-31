import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

class AccentPreset {
  const AccentPreset(this.id, this.labelZh, this.labelEn, this.color);

  final String id;
  final String labelZh;
  final String labelEn;
  final Color color;

  String label(bool zh) => zh ? labelZh : labelEn;
}

const accentPresets = <AccentPreset>[
  AccentPreset('blue', '海蓝', 'Ocean', Color(0xFF3B82F6)),
  AccentPreset('violet', '星紫', 'Violet', Color(0xFF8B5CF6)),
  AccentPreset('green', '松绿', 'Pine', Color(0xFF10B981)),
  AccentPreset('amber', '琥珀', 'Amber', Color(0xFFF59E0B)),
  AccentPreset('pink', '樱粉', 'Sakura', Color(0xFFEC4899)),
  AccentPreset('coral', '珊瑚', 'Coral', Color(0xFFF06A5F)),
];

class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.background,
    required this.card,
    required this.cardAlt,
    required this.border,
    required this.text,
    required this.muted,
    required this.strongMuted,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.danger,
    required this.upload,
    required this.download,
    required this.navBackground,
    required this.hover,
    required this.shadow,
    required this.onAccent,
    required this.isDark,
  });

  final Color background;
  final Color card;
  final Color cardAlt;
  final Color border;
  final Color text;
  final Color muted;
  final Color strongMuted;
  final Color accentSoft;
  final Color success;
  final Color warning;
  final Color danger;
  final Color upload;
  final Color download;
  final Color navBackground;
  final Color hover;
  final Color shadow;
  final Color onAccent;
  final bool isDark;

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>() ?? AppPalette.light(const Color(0xFF3B82F6));

  static AppPalette light(Color accent) => AppPalette(
        background: const Color(0xFFF3F5F9),
        card: Colors.white,
        cardAlt: const Color(0xFFF7F8FB),
        border: const Color(0xFFE7EAF1),
        text: const Color(0xFF171A21),
        muted: const Color(0xFF6B7280),
        strongMuted: const Color(0xFF4B5563),
        accentSoft: Color.alphaBlend(accent.withValues(alpha: 0.10), Colors.white),
        success: const Color(0xFF16A34A),
        warning: const Color(0xFFD97706),
        danger: const Color(0xFFDC2626),
        upload: const Color(0xFF4F8DF7),
        download: const Color(0xFF10B981),
        navBackground: const Color(0xF7FFFFFF),
        hover: const Color(0xFFF0F3F8),
        shadow: const Color(0x140F172A),
        onAccent: Colors.white,
        isDark: false,
      );

  static AppPalette dark(Color accent, {bool pureBlack = false}) => AppPalette(
        background: pureBlack ? const Color(0xFF000000) : const Color(0xFF0B0D12),
        card: pureBlack ? const Color(0xFF0D0D0F) : const Color(0xFF15181F),
        cardAlt: pureBlack ? const Color(0xFF161619) : const Color(0xFF1C2029),
        border: pureBlack ? const Color(0xFF232327) : const Color(0xFF252A34),
        text: const Color(0xFFF2F4F8),
        muted: const Color(0xFF8C94A4),
        strongMuted: const Color(0xFFB4BCC9),
        accentSoft: Color.alphaBlend(accent.withValues(alpha: 0.16), pureBlack ? Colors.black : const Color(0xFF15181F)),
        success: const Color(0xFF4ADE80),
        warning: const Color(0xFFFBBF24),
        danger: const Color(0xFFF87171),
        upload: const Color(0xFF7DA8FF),
        download: const Color(0xFF4ADE80),
        navBackground: pureBlack ? const Color(0xF20A0A0C) : const Color(0xF214171E),
        hover: pureBlack ? const Color(0xFF1B1B1F) : const Color(0xFF202530),
        shadow: const Color(0x66000000),
        onAccent: Colors.white,
        isDark: true,
      );

  @override
  AppPalette copyWith({
    Color? background,
    Color? card,
    Color? cardAlt,
    Color? border,
    Color? text,
    Color? muted,
    Color? strongMuted,
    Color? accentSoft,
    Color? success,
    Color? warning,
    Color? danger,
    Color? upload,
    Color? download,
    Color? navBackground,
    Color? hover,
    Color? shadow,
    Color? onAccent,
    bool? isDark,
  }) {
    return AppPalette(
      background: background ?? this.background,
      card: card ?? this.card,
      cardAlt: cardAlt ?? this.cardAlt,
      border: border ?? this.border,
      text: text ?? this.text,
      muted: muted ?? this.muted,
      strongMuted: strongMuted ?? this.strongMuted,
      accentSoft: accentSoft ?? this.accentSoft,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      upload: upload ?? this.upload,
      download: download ?? this.download,
      navBackground: navBackground ?? this.navBackground,
      hover: hover ?? this.hover,
      shadow: shadow ?? this.shadow,
      onAccent: onAccent ?? this.onAccent,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: c(background, other.background),
      card: c(card, other.card),
      cardAlt: c(cardAlt, other.cardAlt),
      border: c(border, other.border),
      text: c(text, other.text),
      muted: c(muted, other.muted),
      strongMuted: c(strongMuted, other.strongMuted),
      accentSoft: c(accentSoft, other.accentSoft),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      danger: c(danger, other.danger),
      upload: c(upload, other.upload),
      download: c(download, other.download),
      navBackground: c(navBackground, other.navBackground),
      hover: c(hover, other.hover),
      shadow: c(shadow, other.shadow),
      onAccent: c(onAccent, other.onAccent),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }

  Color delayColor(int? delay) {
    if (delay == null) return muted;
    if (delay < 0) return danger;
    if (delay < 200) return success;
    if (delay < 500) return warning;
    return danger;
  }
}

class AppTheme {
  AppTheme._();

  static const radiusLg = 20.0;
  static const radiusMd = 16.0;
  static const radiusSm = 12.0;
  static const pageMaxWidth = 1120.0;
  static const sidebarWidth = 244.0;

  static ThemeData build({
    required Brightness brightness,
    required Color accent,
    bool pureBlack = false,
  }) {
    final isDark = brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark(accent, pureBlack: pureBlack) : AppPalette.light(accent);

    final scheme = ColorScheme(
      brightness: brightness,
      primary: accent,
      onPrimary: palette.onAccent,
      secondary: accent,
      onSecondary: palette.onAccent,
      error: palette.danger,
      onError: Colors.white,
      surface: palette.card,
      onSurface: palette.text,
      surfaceContainerHighest: palette.cardAlt,
      onSurfaceVariant: palette.muted,
      outline: palette.border,
      outlineVariant: palette.border,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: palette.text,
      onInverseSurface: palette.card,
      inversePrimary: accent,
      tertiary: palette.success,
    );

    final baseText = Typography.material2021(platform: defaultTargetPlatform).black;
    var textTheme = baseText.apply(bodyColor: palette.text, displayColor: palette.text).copyWith(
      displayLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.8, color: palette.text),
      displayMedium: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, height: 1.18, letterSpacing: -0.6, color: palette.text),
      headlineMedium: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.4, color: palette.text),
      headlineSmall: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -0.2, color: palette.text),
      titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3, color: palette.text),
      titleMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.35, color: palette.text),
      titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.35, color: palette.text),
      bodyLarge: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, height: 1.5, color: palette.text),
      bodyMedium: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w400, height: 1.5, color: palette.text),
      bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.45, color: palette.muted),
      labelLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.2, color: palette.text),
      labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, height: 1.2, color: palette.muted),
      labelSmall: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, height: 1.2, letterSpacing: 0.4, color: palette.muted),
    );
    if (defaultTargetPlatform == TargetPlatform.windows) {
      // Windows 上 fontFamilyFallback 不会覆盖默认的 Roboto，中文会回落到宋体；
      // 显式把雅黑设为主字体，保证中英文都是无衬线字形。
      textTheme = textTheme.apply(fontFamily: 'Microsoft YaHei UI');
    }

    OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: palette.background,
      canvasColor: palette.card,
      cardColor: palette.card,
      dividerColor: palette.border,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      textTheme: textTheme,
      extensions: [palette],
      fontFamilyFallback: const ['Microsoft YaHei UI', 'Microsoft YaHei', 'PingFang SC', 'Noto Sans CJK SC', 'Segoe UI'],
      iconTheme: IconThemeData(color: palette.strongMuted, size: 20),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        foregroundColor: palette.text,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: palette.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg), side: BorderSide(color: palette.border)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        elevation: 24,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24), side: BorderSide(color: palette.border)),
        titleTextStyle: textTheme.headlineSmall,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: palette.strongMuted),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.cardAlt,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        hintStyle: textTheme.bodyMedium?.copyWith(color: palette.muted),
        labelStyle: textTheme.bodyMedium?.copyWith(color: palette.muted),
        border: border(palette.border),
        enabledBorder: border(palette.border),
        focusedBorder: border(accent, 1.6),
        errorBorder: border(palette.danger),
        focusedErrorBorder: border(palette.danger, 1.6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: palette.onAccent,
          disabledBackgroundColor: accent.withValues(alpha: 0.4),
          disabledForegroundColor: palette.onAccent.withValues(alpha: 0.7),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          // 按钮自建 DefaultTextStyle，必须沿用主题字体，否则中文回落到宋体。
          textStyle: textTheme.labelLarge?.copyWith(fontSize: 13.5),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.text,
          side: BorderSide(color: palette.border),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: palette.strongMuted,
          highlightColor: palette.hover,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.white;
          return isDark ? const Color(0xFF9AA2B1) : const Color(0xFFFFFFFF);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return accent;
          return isDark ? palette.cardAlt : const Color(0xFFE2E6EE);
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return isDark ? palette.border : const Color(0xFFD7DCE5);
        }),
        trackOutlineWidth: const WidgetStatePropertyAll(1),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? palette.cardAlt : palette.card,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: palette.text, fontSize: 13),
        actionTextColor: accent,
        closeIconColor: palette.muted,
        elevation: isDark ? 0 : 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        decoration: BoxDecoration(
          color: isDark ? palette.cardAlt : const Color(0xFF232A36),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: textTheme.bodySmall?.copyWith(color: Colors.white, fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(6),
        radius: const Radius.circular(10),
        thumbColor: WidgetStatePropertyAll(palette.muted.withValues(alpha: 0.35)),
        crossAxisMargin: 2,
      ),
      dividerTheme: DividerThemeData(color: palette.border, thickness: 1, space: 1),
      splashColor: accent.withValues(alpha: 0.06),
      highlightColor: accent.withValues(alpha: 0.03),
      hoverColor: palette.hover,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: AppFadePageTransitionsBuilder(),
          TargetPlatform.linux: AppFadePageTransitionsBuilder(),
          TargetPlatform.macOS: AppFadePageTransitionsBuilder(),
          TargetPlatform.android: AppFadePageTransitionsBuilder(),
        },
      ),
    );
  }
}

BoxDecoration appCardDecoration(
  BuildContext context, {
  double radius = AppTheme.radiusLg,
  Color? color,
  bool elevated = true,
  Border? border,
}) {
  final palette = AppPalette.of(context);
  return BoxDecoration(
    color: color ?? palette.card,
    borderRadius: BorderRadius.circular(radius),
    border: border ?? Border.all(color: palette.border),
    boxShadow: elevated && !palette.isDark
        ? [BoxShadow(color: palette.shadow, blurRadius: 22, offset: const Offset(0, 8))]
        : null,
  );
}

class AppFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const AppFadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.015), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}
