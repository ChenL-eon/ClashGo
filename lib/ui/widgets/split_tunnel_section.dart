import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../controllers/app_controller.dart';
import '../../core/errors.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/app_settings.dart';
import '../../services/android_apps.dart';
import 'app_icon.dart';
import 'common.dart';

/// 安卓分应用代理编辑区：模式选择 + 可搜索的应用复选列表。
/// 设置本身立即落盘，但正在运行的内核仍用旧分流规则，因此单独提示重启。
class SplitTunnelSection extends StatefulWidget {
  const SplitTunnelSection({
    super.key,
    required this.controller,
    required this.loadApps,
    this.loadIcons,
  });

  final AppController controller;
  final Future<List<AndroidAppInfo>> Function() loadApps;

  /// 图标单独注入：应用列表先出来，头像随后补上；为空时只显示占位图。
  final Future<Map<String, Uint8List>> Function(List<String> packageNames)?
  loadIcons;

  @override
  State<SplitTunnelSection> createState() => _SplitTunnelSectionState();
}

class _SplitTunnelSectionState extends State<SplitTunnelSection> {
  final TextEditingController _search = TextEditingController();
  String _query = '';
  List<AndroidAppInfo>? _apps;
  Map<String, Uint8List> _icons = const {};
  int _iconGeneration = 0;
  Object? _loadError;
  bool _loading = true;
  bool _restarting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadApps());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    final generation = ++_iconGeneration;
    setState(() {
      _loading = true;
      _loadError = null;
      _icons = const {};
    });
    try {
      final apps = [...await widget.loadApps()];
      apps.sort(
        (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
      );
      if (!mounted || generation != _iconGeneration) return;
      setState(() {
        _apps = apps;
        _loading = false;
      });
      unawaited(_loadIcons(apps, generation));
    } catch (error) {
      if (!mounted || generation != _iconGeneration) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _loadIcons(List<AndroidAppInfo> apps, int generation) async {
    final loader = widget.loadIcons;
    if (loader == null || apps.isEmpty) return;
    try {
      final icons = await loader([
        for (final app in apps) app.packageName,
      ]);
      if (!mounted || generation != _iconGeneration) return;
      setState(() => _icons = icons);
    } catch (_) {
      // 图标只影响观感：拿不到就继续用占位图，不影响选择和保存。
    }
  }

  Future<void> _applyQueue = Future<void>.value();

  /// 所有分应用改动排队串行写盘。连点应用或全选时，若并发保存，两个请求会
  /// 各自基于旧快照算出结果，后落盘的反而覆盖前一次点击；排队后每次都能
  /// 看到上一次保存后的设置。change 返回同一个实例表示无需写盘。
  void _queueChange(AppSettings Function(AppSettings current) change) {
    final controller = widget.controller;
    _applyQueue = _applyQueue.then((_) async {
      final current = controller.settings;
      final next = change(current);
      if (identical(next, current)) return;
      try {
        await controller.applySettings(next);
      } catch (error) {
        if (!mounted) return;
        showAppToast(
          context,
          errorFrom(error).localized(context.l10n),
          error: true,
        );
      }
    });
  }

  void _warnAllowKeepOne() {
    if (!mounted) return;
    showAppToast(
      context,
      context.l10n.get('settings.split.allowKeepOne'),
      error: true,
    );
  }

  void _selectMode(String mode) {
    _queueChange((current) {
      if (mode == current.splitTunnelMode) return current;
      if (mode == AppSettings.splitTunnelAllow &&
          current.splitTunnelPackages.isEmpty) {
        return current;
      }
      return current.copyWith(splitTunnelMode: mode);
    });
  }

  void _toggleApp(AndroidAppInfo app) {
    _queueChange((current) {
      final next = [...current.splitTunnelPackages];
      final removed = next.remove(app.packageName);
      if (!removed) {
        next.add(app.packageName);
      } else if (next.isEmpty &&
          current.splitTunnelMode == AppSettings.splitTunnelAllow) {
        _warnAllowKeepOne();
        return current;
      }
      return current.copyWith(splitTunnelPackages: next);
    });
  }

  void _selectVisible(List<AndroidAppInfo> visible) {
    _queueChange((current) {
      final merged = <String>{
        ...current.splitTunnelPackages,
        for (final app in visible) app.packageName,
      };
      if (merged.length == current.splitTunnelPackages.length) return current;
      return current.copyWith(splitTunnelPackages: merged.toList());
    });
  }

  void _clearSelection() {
    _queueChange((current) {
      if (current.splitTunnelPackages.isEmpty) return current;
      if (current.splitTunnelMode == AppSettings.splitTunnelAllow) {
        _warnAllowKeepOne();
        return current;
      }
      return current.copyWith(splitTunnelPackages: const []);
    });
  }

  Future<void> _restartCore() async {
    setState(() => _restarting = true);
    try {
      await widget.controller.restartCore();
    } catch (error) {
      if (!mounted) return;
      showAppToast(
        context,
        errorFrom(error).localized(context.l10n),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final l10n = context.l10n;
        final palette = AppPalette.of(context);
        final mobile = MediaQuery.sizeOf(context).width < appDesktopBreakpoint;
        final settings = widget.controller.settings;
        final selected = settings.splitTunnelPackages.toSet();
        final apps = _apps ?? const <AndroidAppInfo>[];
        final query = _query.trim().toLowerCase();
        final visible = apps
            .where(
              (app) =>
                  query.isEmpty ||
                  app.label.toLowerCase().contains(query) ||
                  app.packageName.toLowerCase().contains(query),
            )
            .toList();
        final allowLocked =
            settings.splitTunnelMode != AppSettings.splitTunnelAllow &&
            selected.isEmpty;
        final missingSelection =
            settings.splitTunnelMode == AppSettings.splitTunnelAllow &&
            !_loading &&
            (selected.isEmpty ||
                (apps.isNotEmpty &&
                    !apps.any((app) => selected.contains(app.packageName))));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.controller.splitTunnelNeedsRestart) ...[
              InfoBanner(
                message: l10n.get('settings.split.restartNeeded'),
                icon: 'refresh-2-line',
                actions: [
                  TextButton(
                    onPressed: _restarting ? null : _restartCore,
                    child: _restarting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.get('settings.split.restart')),
                  ),
                ],
              ),
              const SizedBox(height: 22),
            ],
            _section(
              context,
              mobile: mobile,
              title: l10n.get('settings.split.mode'),
              children: [
                _ModeRow(
                  title: l10n.get('settings.split.mode.all'),
                  subtitle: l10n.get('settings.split.mode.allHint'),
                  selected:
                      settings.splitTunnelMode == AppSettings.splitTunnelAll,
                  onTap: () => _selectMode(AppSettings.splitTunnelAll),
                ),
                RowDivider(indent: 16),
                _ModeRow(
                  title: l10n.get('settings.split.mode.allow'),
                  subtitle: allowLocked
                      ? '${l10n.get('settings.split.mode.allowHint')} · ${l10n.get('settings.split.mode.allowLocked')}'
                      : l10n.get('settings.split.mode.allowHint'),
                  selected:
                      settings.splitTunnelMode == AppSettings.splitTunnelAllow,
                  onTap: allowLocked
                      ? null
                      : () => _selectMode(AppSettings.splitTunnelAllow),
                  locked: allowLocked,
                ),
                RowDivider(indent: 16),
                _ModeRow(
                  title: l10n.get('settings.split.mode.disallow'),
                  subtitle: l10n.get('settings.split.mode.disallowHint'),
                  selected:
                      settings.splitTunnelMode ==
                      AppSettings.splitTunnelDisallow,
                  onTap: () => _selectMode(AppSettings.splitTunnelDisallow),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _section(
              context,
              mobile: mobile,
              title: l10n.get('settings.split.apps'),
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    mobile ? 14 : 16,
                    14,
                    mobile ? 14 : 16,
                    4,
                  ),
                  child: AppSearchField(
                    controller: _search,
                    hint: l10n.get('settings.split.search'),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 10, 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.get('settings.split.count', [selected.length]),
                          style: TextStyle(fontSize: 12, color: palette.muted),
                        ),
                      ),
                      TextButton(
                        onPressed: visible.isEmpty
                            ? null
                            : () => _selectVisible(visible),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: Text(l10n.get('settings.split.selectAll')),
                      ),
                      TextButton(
                        onPressed: selected.isEmpty ? null : _clearSelection,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                        ),
                        child: Text(l10n.get('settings.split.clear')),
                      ),
                    ],
                  ),
                ),
                if (settings.splitTunnelMode == AppSettings.splitTunnelAll &&
                    selected.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                    child: InfoBanner(
                      message: l10n.get('settings.split.allModeNote'),
                      color: palette.muted,
                      dense: true,
                    ),
                  ),
                if (missingSelection)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                    child: InfoBanner(
                      message: l10n.get('settings.split.allowEmpty'),
                      color: palette.danger,
                      dense: true,
                    ),
                  ),
                if (_loading)
                  const LoadingBlock(height: 96)
                else if (_loadError != null)
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: InfoBanner(
                      message: l10n.get('settings.split.loadFailed'),
                      color: palette.danger,
                      actions: [
                        TextButton(
                          onPressed: _loadApps,
                          child: Text(l10n.get('common.retry')),
                        ),
                      ],
                    ),
                  )
                else if (apps.isEmpty)
                  EmptyState(
                    compact: true,
                    icon: 'grid-line',
                    title: l10n.get('settings.split.empty'),
                    message: l10n.get('settings.split.emptyHint'),
                  )
                else if (visible.isEmpty)
                  EmptyState(
                    compact: true,
                    icon: 'search-line',
                    title: l10n.get('settings.split.searchEmpty'),
                  )
                else
                  for (var i = 0; i < visible.length; i++) ...[
                    if (i > 0) RowDivider(indent: mobile ? 66 : 68),
                    _AppRow(
                      app: visible[i],
                      icon: _icons[visible[i].packageName],
                      selected: selected.contains(visible[i].packageName),
                      onTap: () => _toggleApp(visible[i]),
                    ),
                  ],
              ],
            ),
            const SizedBox(height: 14),
            InfoBanner(
              message: l10n.get('settings.split.selfExcluded'),
              color: palette.muted,
              dense: true,
            ),
          ],
        );
      },
    );
  }

  Widget _section(
    BuildContext context, {
    required bool mobile,
    required String title,
    List<Widget> children = const [],
    Widget? trailing,
  }) {
    final palette = AppPalette.of(context);
    if (!mobile) {
      return SettingSection(
        title: title,
        trailing: trailing,
        children: children,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileSectionLabel(
          title,
          trailing: trailing,
          color: palette.sectionLabel,
        ),
        SurfaceCard(
          padding: EdgeInsets.zero,
          radius: 18,
          elevated: false,
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.locked = false,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SettingRow(
      title: title,
      subtitle: subtitle,
      titleColor: locked ? palette.muted : null,
      onTap: onTap,
      trailing: Container(
        width: 21,
        height: 21,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? Theme.of(context).colorScheme.primary
              : Colors.transparent,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : (locked ? palette.border : palette.muted),
            width: 1.4,
          ),
        ),
        child: selected
            ? Center(
                child: AppIcon('check-line', size: 12, color: palette.onAccent),
              )
            : null,
      ),
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final AndroidAppInfo app;
  final Uint8List? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final mobile = MediaQuery.sizeOf(context).width < appDesktopBreakpoint;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: palette.hover,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: mobile ? 16 : 18,
            vertical: 10,
          ),
          child: Row(
            children: [
              _AppAvatar(icon: icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            app.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: mobile ? 14.5 : 13.5,
                              fontWeight: FontWeight.w600,
                              color: palette.text,
                            ),
                          ),
                        ),
                        if (app.system) ...[
                          const SizedBox(width: 6),
                          const _SystemTag(),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      app.packageName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: palette.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(7),
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : palette.border,
                    width: 1.4,
                  ),
                ),
                child: selected
                    ? Center(
                        child: AppIcon(
                          'check-line',
                          size: 13,
                          color: palette.onAccent,
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AppAvatar extends StatelessWidget {
  const _AppAvatar({required this.icon});

  final Uint8List? icon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final bytes = icon;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: palette.cardAlt,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(
              bytes,
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            )
          : Center(child: AppIcon('grid-line', size: 17, color: palette.muted)),
    );
  }
}

class _SystemTag extends StatelessWidget {
  const _SystemTag();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: palette.cardAlt,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        context.l10n.get('settings.split.system'),
        style: TextStyle(fontSize: 10, height: 1.3, color: palette.muted),
      ),
    );
  }
}
