import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../../core/theme.dart';
import 'app_icon.dart';

const appDesktopBreakpoint = 1000.0;
const appCompactBreakpoint = 720.0;

class PageContainer extends StatelessWidget {
  const PageContainer({
    super.key,
    required this.children,
    this.maxWidth = AppTheme.pageMaxWidth,
    this.padding,
    this.floatingNav = true,
  });

  final List<Widget> children;
  final double maxWidth;
  final EdgeInsets? padding;
  final bool floatingNav;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= appDesktopBreakpoint;
    final horizontal = width >= appCompactBreakpoint ? 28.0 : 18.0;
    final bottom = desktop ? 36.0 : (floatingNav ? 96.0 : 28.0) + MediaQuery.viewPaddingOf(context).bottom;
    return SingleChildScrollView(
      padding: padding ?? EdgeInsets.fromLTRB(horizontal, desktop ? 16 : 18, horizontal, bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Full-height page frame for lists and consoles that scroll internally.
class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.header,
    required this.child,
    this.maxWidth = AppTheme.pageMaxWidth,
    this.floatingNav = true,
  });

  final Widget header;
  final Widget child;
  final double maxWidth;
  final bool floatingNav;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= appDesktopBreakpoint;
    final horizontal = width >= appCompactBreakpoint ? 28.0 : 18.0;
    final bottom = (desktop ? 36.0 : (floatingNav ? 96.0 : 28.0)) + MediaQuery.viewPaddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, desktop ? 16 : 18, horizontal, bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              const SizedBox(height: 16),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class PageHeader extends StatelessWidget {  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 640;
        final heading = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: (compact ? text.headlineSmall : text.headlineMedium)?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(subtitle!, style: text.bodySmall?.copyWith(color: palette.muted)),
                  ],
                ],
              ),
            ),
            if (!compact && actions.isNotEmpty) ...[
              const SizedBox(width: 16),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.end, children: actions),
            ],
          ],
        );
        if (compact && actions.isNotEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          );
        }
        return heading;
      },
    );
  }
}

/// Large display header used by the four main pages on phone widths.
class MobilePageHeader extends StatelessWidget {
  const MobilePageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (leading != null || actions.isNotEmpty) ...[
          Row(
            children: [
              ?leading,
              const Spacer(),
              ...actions,
            ],
          ),
          const SizedBox(height: 8),
        ],
        Text(
          title,
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            height: 1.12,
            letterSpacing: -0.9,
            color: palette.text,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(subtitle!, style: TextStyle(fontSize: 13, color: palette.muted, height: 1.4)),
        ],
      ],
    );
  }
}

/// Quiet, reference-style section label for mobile dashboards.
class MobileSectionLabel extends StatelessWidget {
  const MobileSectionLabel(this.title, {super.key, this.icon, this.trailing, this.color});

  final String title;
  final String? icon;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
      child: Row(
        children: [
          if (icon != null) ...[
            AppIcon(icon!, size: 15, color: color ?? palette.muted),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: color ?? palette.muted,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Value + optional chevron used by the mobile settings rows.
class MobileValue extends StatelessWidget {
  const MobileValue(this.value, {super.key, this.color, this.showChevron = false});

  final String value;
  final Color? color;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: color ?? palette.strongMuted,
            ),
          ),
        ),
        if (showChevron) ...[
          const SizedBox(width: 4),
          AppIcon('right-small-line', size: 14, color: palette.muted),
        ],
      ],
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {super.key, this.subtitle, this.icon, this.trailing, this.color});

  final String title;
  final String? subtitle;
  final String? icon;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10, top: 2),
      child: Row(
        children: [
          if (icon != null) ...[
            AppIcon(icon!, size: 16, color: color ?? palette.muted),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
                if (subtitle != null)
                  Text(subtitle!, style: text.bodySmall?.copyWith(color: palette.muted, fontSize: 11.5)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.radius = AppTheme.radiusLg,
    this.color,
    this.gradient,
    this.border,
    this.onTap,
    this.elevated = true,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;
  final Gradient? gradient;
  final BoxBorder? border;
  final VoidCallback? onTap;
  final bool elevated;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final shape = BorderRadius.circular(radius);
    final content = Padding(padding: padding, child: child);
    // 行内悬停/选中色块必须被卡片圆角裁剪，同时描边要盖在色块之上，
    // 否则色块会染到圆角外的直角区域并遮住卡片边框。
    return Container(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: elevated ? palette.cardShadows : null,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: shape,
        border: border ?? Border.all(color: palette.border),
      ),
      clipBehavior: clipBehavior,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: gradient == null ? (color ?? palette.card) : null,
          gradient: gradient,
          borderRadius: shape,
        ),
        child: onTap == null
            ? content
            : Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: shape,
                  // Flutter 默认焦点色是 12% 黑；菜单→弹窗收起后整卡 InkWell 可能只收到
                  // 焦点进入、收不到离开，灰底会永久留在卡上，所以整卡不绘制焦点底色。
                  focusColor: Colors.transparent,
                  child: content,
                ),
              ),
      ),
    );
  }
}

class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.text,
    this.color,
    this.background,
    this.icon,
    this.dense = false,
  });

  final String text;
  final Color? color;
  final Color? background;
  final String? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fg = color ?? palette.strongMuted;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 2.5 : 4),
      decoration: BoxDecoration(
        color: background ?? fg.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            AppIcon(icon!, size: dense ? 11 : 12, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: dense ? 10 : 11,
              height: 1.25,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.size = 18,
    this.color,
    this.background,
    this.padding = 8,
  });

  final String icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final double size;
  final Color? color;
  final Color? background;
  final double padding;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final enabled = widget.onTap != null;
    final tappable = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        onHover: enabled ? (value) => setState(() => _hovered = value) : null,
        borderRadius: BorderRadius.circular(10),
        hoverColor: palette.hover,
        // 底色必须走 Ink 而不是 Container：Container 画在 InkWell 的高亮层之上，
        // 传了 background 的按钮（桌面头部的测速和更多）悬停时看不到任何反馈。
        child: Ink(
          decoration: BoxDecoration(
            color: widget.background ?? Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: EdgeInsets.all(widget.padding),
            child: AppIcon(
              widget.icon,
              size: widget.size,
              color: !enabled
                  ? palette.muted.withValues(alpha: 0.5)
                  : _hovered
                      ? accent
                      : (widget.color ?? palette.strongMuted),
            ),
          ),
        ),
      ),
    );
    final withCursor = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      child: tappable,
    );
    return widget.tooltip == null
        ? withCursor
        : Tooltip(message: widget.tooltip!, child: withCursor);
  }
}

class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    this.hint,
    this.onChanged,
    this.trailing,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final Widget? trailing;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 2),
      child: Row(
        children: [
          AppIcon('search-line', size: 16, color: palette.muted),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              autofocus: autofocus,
              style: TextStyle(fontSize: 13, color: palette.text),
              decoration: InputDecoration(
                hintText: hint,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 11),
                hintStyle: TextStyle(fontSize: 12.5, color: palette.muted),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            AppIconButton(
              icon: 'close-line',
              size: 13,
              padding: 5,
              tooltip: context.t('common.close'),
              onTap: () {
                controller.clear();
                onChanged?.call('');
              },
            ),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actions = const [],
    this.compact = false,
  });

  final String icon;
  final String title;
  final String? message;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 30 : 52, horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 52 : 64,
            height: compact ? 52 : 64,
            decoration: BoxDecoration(
              color: palette.accentSoft,
              borderRadius: BorderRadius.circular(compact ? 18 : 22),
              border: Border.all(color: palette.border),
            ),
            child: Center(
              child: AppIcon(icon, size: compact ? 24 : 28, color: Theme.of(context).colorScheme.primary),
            ),
          ),
          SizedBox(height: compact ? 14 : 18),
          Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.center),
          if (message != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                message!,
                style: text.bodySmall?.copyWith(color: palette.muted),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(spacing: 10, runSpacing: 8, alignment: WrapAlignment.center, children: actions),
          ],
        ],
      ),
    );
  }
}

class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.color,
    this.icon = 'information-line',
    this.actions = const [],
    this.dense = false,
  });

  final String message;
  final Color? color;
  final String icon;
  final List<Widget> actions;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tone = color ?? palette.warning;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 14, vertical: dense ? 9 : 12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: palette.isDark ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: AppIcon(icon, size: dense ? 15 : 17, color: tone),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: dense ? 11.5 : 12.5, height: 1.45, color: palette.strongMuted),
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 8),
            Wrap(spacing: 4, children: actions),
          ],
        ],
      ),
    );
  }
}

class SegmentOption<T> {
  const SegmentOption(this.value, this.label, {this.icon});

  final T value;
  final String label;
  final String? icon;
}

class AppSegmented<T> extends StatelessWidget {
  const AppSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.dense = false,
  });

  final List<SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.cardAlt,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: _SegmentItem(
                label: option.label,
                icon: option.icon,
                selected: option.value == selected,
                accent: accent,
                palette: palette,
                dense: dense,
                onTap: () => onChanged(option.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _SegmentItem extends StatelessWidget {
  const _SegmentItem({
    required this.label,
    required this.selected,
    required this.accent,
    required this.palette,
    required this.onTap,
    required this.dense,
    this.icon,
  });

  final String label;
  final String? icon;
  final bool selected;
  final Color accent;
  final AppPalette palette;
  final bool dense;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        // 悬停/按压不整块填色，避免与选中项叠成两处高亮。
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: accent.withValues(alpha: 0.10),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: dense ? 6 : 8),
          decoration: BoxDecoration(
            color: selected ? palette.card : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected && !palette.isDark
                ? [BoxShadow(color: palette.shadow, blurRadius: 8, offset: const Offset(0, 2))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                AppIcon(icon!, size: dense ? 12 : 14, color: selected ? accent : palette.muted),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: dense ? 11 : 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? accent : palette.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppDropdownOption<T> {
  const AppDropdownOption(this.value, this.label, {this.color});

  final T value;
  final String label;
  final Color? color;
}

const _menuPadding = 8.0;
const _menuItemHPadding = 16.0;

/// 下拉/弹出菜单共用的浮层外观：大圆角、柔和阴影、无描边。
MenuStyle appMenuStyle(AppPalette palette) => MenuStyle(
      backgroundColor: WidgetStatePropertyAll(palette.card),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      shadowColor: WidgetStatePropertyAll(palette.shadow),
      elevation: const WidgetStatePropertyAll(18),
      padding: const WidgetStatePropertyAll(EdgeInsets.all(_menuPadding)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg)),
      ),
      // 深色模式阴影几乎不可见，靠 1px 描边区分浮层与卡片。
      side: palette.isDark
          ? WidgetStatePropertyAll(BorderSide(color: palette.border))
          : null,
    );

/// 菜单行样式：46 高、左右 16 内边距，悬停底色与外层圆角同心的 12 圆角。
ButtonStyle appMenuItemStyle(AppPalette palette) => ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: _menuItemHPadding),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
      overlayColor: WidgetStatePropertyAll(palette.hover),
      backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusLg - _menuPadding)),
      ),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );

/// Row/button wrapper that opens an anchored dropdown menu instead of a dialog.
class AppDropdown<T> extends StatefulWidget {
  const AppDropdown({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.builder,
    this.menuWidth = 190,
  });

  final List<AppDropdownOption<T>> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final Widget Function(BuildContext context, VoidCallback toggle) builder;
  final double menuWidth;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  final MenuController _menu = MenuController();

  // 菜单距窗口与锚点的留白，避免贴边或压住锚点。
  static const double _edgeInset = 16;

  double get _menuWidth => widget.menuWidth + (_menuPadding + _menuItemHPadding) * 2;

  void _toggle() {
    if (_menu.isOpen) {
      _menu.close();
    } else {
      _menu.open();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return MenuAnchor(
      controller: _menu,
      reservedPadding: const EdgeInsets.all(_edgeInset),
      // bottomEnd 会把菜单左边缘放在锚点右缘，再靠右对齐需要整体左移；
      // 额外留出 _edgeInset，菜单便不会紧贴窗口或溢出卡片。
      alignmentOffset: Offset(-(_menuWidth + _edgeInset), 6),
      style: appMenuStyle(palette).copyWith(
        alignment: AlignmentDirectional.bottomEnd,
      ),
      menuChildren: [
        for (final option in widget.options)
          MenuItemButton(
            onPressed: () {
              _menu.close();
              if (option.value != widget.selected) widget.onSelected(option.value);
            },
            style: appMenuItemStyle(palette),
            child: SizedBox(
              width: widget.menuWidth,
              child: Row(
                children: [
                  if (option.color != null) ...[
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: option.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: palette.border),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: option.value == widget.selected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        // 选中态只换蓝字与蓝勾，不加灰色底块。
                        color: option.value == widget.selected ? accent : palette.text,
                      ),
                    ),
                  ),
                  if (option.value == widget.selected) ...[
                    const SizedBox(width: 12),
                    AppIcon('check-line', size: 18, color: accent),
                  ],
                ],
              ),
            ),
          ),
      ],
      builder: (context, controller, child) => widget.builder(context, _toggle),
    );
  }
}

class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.title,
    this.subtitle,
    this.titleColor,
    this.trailing,
    this.onTap,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Color? titleColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final mobile = MediaQuery.sizeOf(context).width < appDesktopBreakpoint;
    final titleSize = dense ? 14.0 : (mobile ? 16.5 : 14.5);
    final subtitleSize = dense ? 12.0 : (mobile ? 13.0 : 12.5);
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 14 : (mobile ? 18 : 20),
        vertical: dense ? 11 : (mobile ? 18 : 15),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: titleSize,
                    fontWeight: FontWeight.w600,
                    height: 1.32,
                    color: titleColor ?? palette.text,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(fontSize: subtitleSize, height: 1.45, color: palette.muted),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ],
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, hoverColor: palette.hover, child: content),
    );
  }
}

class RowDivider extends StatelessWidget {
  const RowDivider({super.key, this.indent = 18});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, thickness: 1, indent: indent, endIndent: indent, color: AppPalette.of(context).border);
  }
}

class SettingSection extends StatelessWidget {
  const SettingSection({
    super.key,
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title, trailing: trailing, color: palette.sectionLabel),
        SurfaceCard(
          padding: EdgeInsets.zero,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class KeyValueText extends StatelessWidget {
  const KeyValueText({super.key, required this.label, required this.value, this.valueColor, this.monospace = false});

  final String label;
  final String value;
  final Color? valueColor;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.bodySmall?.copyWith(color: palette.muted)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: text.bodySmall?.copyWith(
              color: valueColor ?? palette.text,
              fontFamily: monospace ? 'Consolas' : null,
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> copyToClipboard(BuildContext context, String value) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  showAppToast(context, context.t('common.copied'));
}

void showAppToast(BuildContext context, String message, {bool error = false}) {
  final palette = AppPalette.of(context);
  final mobile = MediaQuery.sizeOf(context).width < appDesktopBreakpoint;
  final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
  final foreground = error
      ? (palette.isDark ? const Color(0xFF16181D) : Colors.white)
      : palette.text;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: foreground)),
        backgroundColor: error ? palette.danger : null,
        width: mobile ? null : 420,
        margin: mobile ? EdgeInsets.fromLTRB(18, 0, 18, 84 + bottomInset) : null,
        duration: Duration(seconds: error ? 4 : 2),
      ),
    );
}

class LoadingBlock extends StatelessWidget {
  const LoadingBlock({super.key, this.height = 120});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: const Center(
        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.2)),
      ),
    );
  }
}
