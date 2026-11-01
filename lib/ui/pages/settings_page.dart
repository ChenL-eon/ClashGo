import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../controllers/app_controller.dart';
import '../../core/app_info.dart';
import '../../core/errors.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/app_settings.dart';
import '../../services/system_proxy.dart';
import '../../services/update_service.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';
import '../widgets/dialogs.dart';
import '../widgets/status_widgets.dart';

enum _SettingsView { hub, theme, language, clash, behavior, about, data }

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  _SettingsView _view = _SettingsView.hub;
  final TextEditingController _search = TextEditingController();
  String _query = '';
  bool _checkingUpdate = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(_SettingsView view) => setState(() => _view = view);

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final mobile = MediaQuery.sizeOf(context).width < appDesktopBreakpoint;
    if (_view == _SettingsView.hub) {
      return _buildHub(context, controller, mobile: mobile);
    }
    return _buildDetail(context, controller, mobile: mobile);
  }

  Widget _buildHub(BuildContext context, AppController controller, {required bool mobile}) {
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    Widget chevron() => AppIcon('right-small-line', size: 14, color: palette.muted);
    return PageContainer(
      children: [
        if (mobile)
          MobilePageHeader(title: l10n.get('nav.settings'), subtitle: l10n.get('settings.subtitle'))
        else
          PageHeader(
            title: l10n.get('nav.settings'),
            subtitle: l10n.get('settings.subtitle'),
            actions: [
              AppBadge(text: 'v${AppInfo.version}', icon: 'shield-shape-line', dense: true),
            ],
          ),
        SizedBox(height: mobile ? 16 : 20),
        _searchField(context),
        SizedBox(height: mobile ? 18 : 22),
        if (_query.trim().isNotEmpty)
          ..._searchSections(context, controller, mobile: mobile)
        else ...[
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.group.personalization'),
            children: [
              SettingRow(
                title: l10n.get('settings.theme'),
                subtitle: l10n.get('settings.hub.themeHint'),
                trailing: chevron(),
                onTap: () => _open(_SettingsView.theme),
              ),
              SettingRow(
                title: l10n.get('settings.language'),
                subtitle: l10n.get('settings.languageHint'),
                trailing: chevron(),
                onTap: () => _open(_SettingsView.language),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.group.clash'),
            children: [
              SettingRow(
                title: l10n.get('settings.hub.clash'),
                subtitle: l10n.get('settings.hub.clashHint'),
                trailing: chevron(),
                onTap: () => _open(_SettingsView.clash),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.group.app'),
            children: [
              SettingRow(
                title: l10n.get('settings.hub.behavior'),
                subtitle: l10n.get('settings.hub.behaviorHint'),
                trailing: chevron(),
                onTap: () => _open(_SettingsView.behavior),
              ),
              SettingRow(
                title: l10n.get('settings.about'),
                subtitle: l10n.get('settings.aboutHint'),
                trailing: chevron(),
                onTap: () => _open(_SettingsView.about),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.group.maintenance'),
            children: [
              SettingRow(
                title: l10n.get('settings.hub.data'),
                subtitle: l10n.get('settings.hub.dataHint'),
                trailing: chevron(),
                onTap: () => _open(_SettingsView.data),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _searchField(BuildContext context) {
    return AppSearchField(
      controller: _search,
      hint: context.t('settings.search'),
      onChanged: (value) => setState(() => _query = value),
    );
  }

  List<Widget> _searchSections(BuildContext context, AppController controller, {required bool mobile}) {
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    final query = _query.trim().toLowerCase();
    final matches = _settingsCatalog(controller).where((entry) => entry.matches(query)).toList();
    if (matches.isEmpty) {
      return [
        SurfaceCard(
          padding: EdgeInsets.zero,
          radius: 18,
          elevated: false,
          child: EmptyState(
            compact: true,
            icon: 'search-line',
            title: l10n.get('settings.noResults'),
          ),
        ),
      ];
    }
    final grouped = <String, List<_SettingEntry>>{};
    for (final entry in matches) {
      grouped.putIfAbsent(entry.groupKey, () => []).add(entry);
    }
    final widgets = <Widget>[];
    grouped.forEach((groupKey, entries) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 22));
      widgets.add(
        _section(
          context,
          mobile: mobile,
          title: l10n.get(groupKey),
          children: [
            for (final entry in entries)
              SettingRow(
                title: l10n.get(entry.titleKey),
                subtitle: entry.subtitleKey == null ? null : l10n.get(entry.subtitleKey!),
                titleColor: entry.danger ? palette.danger : null,
                trailing: AppIcon('right-small-line', size: 14, color: palette.muted),
                onTap: () => _openFromSearch(entry.view),
              ),
          ],
        ),
      );
    });
    return widgets;
  }

  void _openFromSearch(_SettingsView view) {
    _search.clear();
    setState(() {
      _query = '';
      _view = view;
    });
  }

  Future<void> _checkUpdates(AppController controller) async {
    final l10n = context.l10n;
    setState(() => _checkingUpdate = true);
    try {
      final release = await const UpdateService().latest(
        channel: controller.settings.updateChannel,
        // 内核在跑时借 mixed-port 出网：GitHub 在很多地区直连不通。
        proxyPort: controller.isRunning ? controller.settings.mixedPort : null,
      );
      if (!mounted) return;
      if (release == null) {
        showAppToast(context, l10n.get('settings.updateFailed'), error: true);
        return;
      }
      if (!UpdateService.isNewer(release.version, AppInfo.version)) {
        showAppToast(context, l10n.get('settings.upToDate'));
        return;
      }
      final open = await showAppDialog<bool>(
        context,
        maxWidth: 440,
        builder: (dialogContext) => AppDialog(
          title: l10n.get('settings.updateDialogTitle'),
          subtitle: l10n.get('settings.updateAvailable', [release.version]),
          icon: 'download-2-line',
          content: Text(
            l10n.get('settings.updateDialogMessage', [AppInfo.version, release.version]),
            style: TextStyle(fontSize: 13, height: 1.5, color: AppPalette.of(dialogContext).strongMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(dialogContext.t('common.cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(dialogContext.t('settings.viewRelease')),
            ),
          ],
        ),
      );
      if (open == true && mounted) {
        await _openUrl(context, release.url, l10n.get('settings.openFailed'));
      }
    } catch (_) {
      if (!mounted) return;
      showAppToast(context, l10n.get('settings.updateFailed'), error: true);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  List<_SettingEntry> _settingsCatalog(AppController controller) {
    final channelKey = controller.settings.updateChannel == AppSettings.channelPreview
        ? 'settings.channel.preview'
        : 'settings.channel.stable';
    return [
      const _SettingEntry(
        view: _SettingsView.theme,
        groupKey: 'settings.group.personalization',
        titleKey: 'settings.theme',
        subtitleKey: 'settings.hub.themeHint',
      ),
      const _SettingEntry(
        view: _SettingsView.theme,
        groupKey: 'settings.group.personalization',
        titleKey: 'settings.accent',
        subtitleKey: 'settings.accentHint',
      ),
      const _SettingEntry(
        view: _SettingsView.theme,
        groupKey: 'settings.group.personalization',
        titleKey: 'settings.pureBlack',
        subtitleKey: 'settings.pureBlackHint',
      ),
      const _SettingEntry(
        view: _SettingsView.language,
        groupKey: 'settings.group.personalization',
        titleKey: 'settings.language',
        subtitleKey: 'settings.languageHint',
      ),
      const _SettingEntry(
        view: _SettingsView.clash,
        groupKey: 'settings.group.clash',
        titleKey: 'settings.hub.clash',
        subtitleKey: 'settings.hub.clashHint',
      ),
      const _SettingEntry(
        view: _SettingsView.clash,
        groupKey: 'settings.group.clash',
        titleKey: 'settings.mixedPort',
        subtitleKey: 'settings.mixedPortHint',
      ),
      const _SettingEntry(
        view: _SettingsView.clash,
        groupKey: 'settings.group.clash',
        titleKey: 'settings.apiPort',
        subtitleKey: 'settings.apiPortHint',
      ),
      const _SettingEntry(
        view: _SettingsView.clash,
        groupKey: 'settings.group.clash',
        titleKey: 'settings.secret',
        subtitleKey: 'settings.secretHint',
      ),
      const _SettingEntry(
        view: _SettingsView.clash,
        groupKey: 'settings.group.clash',
        titleKey: 'settings.allowLan',
        subtitleKey: 'settings.allowLanHint',
      ),
      const _SettingEntry(
        view: _SettingsView.clash,
        groupKey: 'settings.group.clash',
        titleKey: 'settings.ipv6',
        subtitleKey: 'settings.ipv6Hint',
      ),
      const _SettingEntry(
        view: _SettingsView.clash,
        groupKey: 'settings.group.clash',
        titleKey: 'settings.systemProxy',
        subtitleKey: 'settings.systemProxyHint',
      ),
      if (Platform.isWindows)
        const _SettingEntry(
          view: _SettingsView.clash,
          groupKey: 'settings.group.clash',
          titleKey: 'settings.proxyBypass',
          subtitleKey: 'settings.proxyBypassHint',
        ),
      const _SettingEntry(
        view: _SettingsView.clash,
        groupKey: 'settings.group.clash',
        titleKey: 'settings.runtimeDir',
      ),
      const _SettingEntry(
        view: _SettingsView.behavior,
        groupKey: 'settings.group.app',
        titleKey: 'settings.hub.behavior',
        subtitleKey: 'settings.hub.behaviorHint',
      ),
      const _SettingEntry(
        view: _SettingsView.behavior,
        groupKey: 'settings.group.app',
        titleKey: 'settings.autoStart',
        subtitleKey: 'settings.autoStartHint',
      ),
      const _SettingEntry(
        view: _SettingsView.behavior,
        groupKey: 'settings.group.app',
        titleKey: 'settings.autoUpdateSubs',
        subtitleKey: 'settings.autoUpdateSubsHint',
      ),
      if (Platform.isWindows) ...[
        const _SettingEntry(
          view: _SettingsView.behavior,
          groupKey: 'settings.group.app',
          titleKey: 'settings.launchAtStartup',
          subtitleKey: 'settings.launchAtStartupHint',
        ),
        const _SettingEntry(
          view: _SettingsView.behavior,
          groupKey: 'settings.group.app',
          titleKey: 'settings.closeToTray',
          subtitleKey: 'settings.closeToTrayHint',
        ),
      ],
      const _SettingEntry(
        view: _SettingsView.about,
        groupKey: 'settings.group.app',
        titleKey: 'settings.about',
        subtitleKey: 'settings.aboutHint',
      ),
      const _SettingEntry(
        view: _SettingsView.about,
        groupKey: 'settings.group.app',
        titleKey: 'settings.checkUpdates',
        subtitleKey: 'settings.checkUpdatesHint',
      ),
      _SettingEntry(
        view: _SettingsView.about,
        groupKey: 'settings.group.app',
        titleKey: 'settings.updateChannel',
        subtitleKey: channelKey,
        extraKeys: const ['settings.channel.stable', 'settings.channel.preview'],
      ),
      const _SettingEntry(
        view: _SettingsView.about,
        groupKey: 'settings.group.app',
        titleKey: 'settings.checkUpdatesOnStartup',
        subtitleKey: 'settings.checkUpdatesOnStartupHint',
      ),
      const _SettingEntry(
        view: _SettingsView.about,
        groupKey: 'settings.group.app',
        titleKey: 'settings.coreVersion',
      ),
      const _SettingEntry(
        view: _SettingsView.about,
        groupKey: 'settings.group.app',
        titleKey: 'settings.coreBinary',
      ),
      const _SettingEntry(
        view: _SettingsView.about,
        groupKey: 'settings.group.app',
        titleKey: 'settings.github',
      ),
      const _SettingEntry(
        view: _SettingsView.about,
        groupKey: 'settings.group.app',
        titleKey: 'about.mihomo',
      ),
      const _SettingEntry(
        view: _SettingsView.about,
        groupKey: 'settings.group.app',
        titleKey: 'settings.license',
      ),
      const _SettingEntry(
        view: _SettingsView.about,
        groupKey: 'settings.group.app',
        titleKey: 'settings.diagnostics',
        subtitleKey: 'settings.copyDiagnostics',
      ),
      const _SettingEntry(
        view: _SettingsView.data,
        groupKey: 'settings.group.maintenance',
        titleKey: 'settings.hub.data',
        subtitleKey: 'settings.hub.dataHint',
      ),
      const _SettingEntry(
        view: _SettingsView.data,
        groupKey: 'settings.group.maintenance',
        titleKey: 'settings.updateAllSubs',
        subtitleKey: 'settings.updateAllSubsHint',
      ),
      const _SettingEntry(
        view: _SettingsView.data,
        groupKey: 'settings.group.maintenance',
        titleKey: 'settings.clearSelections',
        subtitleKey: 'settings.clearSelectionsHint',
      ),
      const _SettingEntry(
        view: _SettingsView.data,
        groupKey: 'settings.group.maintenance',
        titleKey: 'settings.reset',
        subtitleKey: 'settings.resetHint',
        danger: true,
      ),
    ];
  }

  Widget _buildDetail(BuildContext context, AppController controller, {required bool mobile}) {
    final l10n = context.l10n;
    final title = switch (_view) {
      _SettingsView.theme => l10n.get('settings.theme'),
      _SettingsView.language => l10n.get('settings.language'),
      _SettingsView.clash => l10n.get('settings.hub.clash'),
      _SettingsView.behavior => l10n.get('settings.hub.behavior'),
      _SettingsView.about => l10n.get('settings.aboutApp'),
      _SettingsView.data => l10n.get('settings.hub.data'),
      _SettingsView.hub => l10n.get('nav.settings'),
    };
    final subtitle = switch (_view) {
      _SettingsView.theme => l10n.get('settings.hub.themeHint'),
      _SettingsView.language => l10n.get('settings.languageHint'),
      _SettingsView.clash => l10n.get('settings.hub.clashHint'),
      _SettingsView.behavior => l10n.get('settings.hub.behaviorHint'),
      _SettingsView.about => l10n.get('settings.aboutHint'),
      _SettingsView.data => l10n.get('settings.hub.dataHint'),
      _SettingsView.hub => null,
    };
    final back = _BackChip(onTap: () => setState(() => _view = _SettingsView.hub));
    return PageContainer(
      // 详情页按视图换 key：否则 PageContainer 内的滚动位置会被复用，
      // 从滚到底部的 hub 点进「关于」会直接落在详情页底部。
      key: ValueKey('settings-${_view.name}'),
      children: [
        if (mobile)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              back,
              const SizedBox(width: 12),
              Expanded(child: MobilePageHeader(title: title, subtitle: subtitle)),
            ],
          )
        else
          PageHeader(leading: back, title: title, subtitle: subtitle),
        const SizedBox(height: 20),
        ..._detailSections(context, controller, mobile: mobile),
      ],
    );
  }

  List<Widget> _detailSections(BuildContext context, AppController controller, {required bool mobile}) {
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    final settings = controller.settings;
    Widget chevron() => AppIcon('right-small-line', size: 14, color: palette.muted);
    final systemProxyHint = SystemProxyService.supported
        ? l10n.get('settings.systemProxyHint')
        : Platform.isAndroid
            ? l10n.get('settings.systemProxyVpn')
            : l10n.get('settings.systemProxyUnsupported');
    switch (_view) {
      case _SettingsView.theme:
        return [
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.appearance'),
            children: [
              AppDropdown<String>(
                options: [
                  AppDropdownOption('system', l10n.get('settings.theme.system')),
                  AppDropdownOption('light', l10n.get('settings.theme.light')),
                  AppDropdownOption('dark', l10n.get('settings.theme.dark')),
                ],
                selected: settings.themeMode,
                onSelected: (value) => _apply(context, controller, settings.copyWith(themeMode: value)),
                builder: (context, toggle) => _ValueRow(
                  title: l10n.get('settings.theme'),
                  value: l10n.get('settings.theme.${settings.themeMode}'),
                  onTap: toggle,
                ),
              ),
              AppDropdown<int>(
                options: [
                  for (var i = 0; i < accentPresets.length; i++)
                    AppDropdownOption(i, accentPresets[i].label(l10n.isZh), color: accentPresets[i].color),
                ],
                selected: settings.accentIndex,
                onSelected: (index) => _apply(context, controller, settings.copyWith(accentIndex: index)),
                builder: (context, toggle) => SettingRow(
                  title: l10n.get('settings.accent'),
                  subtitle: l10n.get('settings.accentHint'),
                  onTap: toggle,
                  trailing: _AccentValue(index: settings.accentIndex),
                ),
              ),
              _SwitchRow(
                title: l10n.get('settings.pureBlack'),
                subtitle: l10n.get('settings.pureBlackHint'),
                value: settings.pureBlack,
                enabled: settings.themeMode != 'light',
                onChanged: (value) => _apply(context, controller, settings.copyWith(pureBlack: value)),
              ),
            ],
          ),
        ];
      case _SettingsView.language:
        return [
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.language'),
            children: [
              AppDropdown<String>(
                options: const [
                  AppDropdownOption('zh', '简体中文'),
                  AppDropdownOption('en', 'English'),
                ],
                selected: settings.language,
                onSelected: (value) => _apply(context, controller, settings.copyWith(language: value)),
                builder: (context, toggle) => _ValueRow(
                  title: l10n.get('settings.language'),
                  subtitle: l10n.get('settings.languageHint'),
                  value: settings.isZh ? '简体中文' : 'English',
                  onTap: toggle,
                ),
              ),
            ],
          ),
        ];
      case _SettingsView.clash:
        return [
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.network'),
            children: [
              _ValueRow(
                title: l10n.get('settings.mixedPort'),
                subtitle: l10n.get('settings.mixedPortHint'),
                value: '${settings.mixedPort}',
                onTap: () => _showPortDialog(context, controller, apiPort: false),
              ),
              _ValueRow(
                title: l10n.get('settings.apiPort'),
                subtitle: l10n.get('settings.apiPortHint'),
                value: '${settings.apiPort}',
                onTap: () => _showPortDialog(context, controller, apiPort: true),
              ),
              if (mobile)
                SettingRow(
                  title: l10n.get('settings.secret'),
                  subtitle: maskSecret(settings.secret),
                  trailing: chevron(),
                  onTap: () => _showSecretSheet(controller),
                )
              else
                SettingRow(
                  title: l10n.get('settings.secret'),
                  subtitle: maskSecret(settings.secret),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppIconButton(
                        icon: 'copy-line',
                        size: 15,
                        tooltip: l10n.get('common.copy'),
                        onTap: () => copyToClipboard(context, settings.secret),
                      ),
                      TextButton(
                        onPressed: () => _regenerateSecret(context, controller),
                        child: Text(l10n.get('settings.secretRegenerate')),
                      ),
                    ],
                  ),
                ),
              _SwitchRow(
                title: l10n.get('settings.allowLan'),
                subtitle: l10n.get('settings.allowLanHint'),
                value: settings.allowLan,
                onChanged: (value) => _apply(context, controller, settings.copyWith(allowLan: value)),
              ),
              _SwitchRow(
                title: l10n.get('settings.ipv6'),
                subtitle: l10n.get('settings.ipv6Hint'),
                value: settings.ipv6,
                onChanged: (value) => _apply(context, controller, settings.copyWith(ipv6: value)),
              ),
              _SwitchRow(
                title: l10n.get('settings.systemProxy'),
                subtitle: systemProxyHint,
                value: settings.systemProxy,
                enabled: SystemProxyService.supported,
                onChanged: (value) => _toggleSystemProxy(context, controller, value),
              ),
              if (Platform.isWindows)
                _ValueRow(
                  title: l10n.get('settings.proxyBypass'),
                  subtitle: l10n.get('settings.proxyBypassHint'),
                  value: l10n.get(
                    'settings.proxyBypassCount',
                    [_bypassCount(settings.proxyBypass)],
                  ),
                  onTap: () => _showBypassDialog(context, controller),
                ),
            ],
          ),
          const SizedBox(height: 22),
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.core'),
            trailing: CoreStatusBadge(controller: controller, dense: true),
            children: [
              // 内核版本/路径移到了「关于」页的只读区；启停与重载统一走主页、
              // 代理页和状态胶囊上的开关，这里只留排障要用的运行目录。
              _ValueRow(
                title: l10n.get('settings.runtimeDir'),
                value: controller.core.runtimeDir,
                onTap: !Platform.isWindows
                    ? () => copyToClipboard(context, controller.core.runtimeDir)
                    : () => _openFolder(context, controller.core.runtimeDir, l10n.get('settings.openFailed')),
                trailingIcon: Platform.isWindows ? 'folder-line' : 'copy-line',
                monospace: true,
              ),
            ],
          ),
          if (!controller.core.supported) ...[
            const SizedBox(height: 8),
            InfoBanner(
              message: l10n.get('settings.coreNotBundled'),
              color: palette.muted,
              dense: true,
            ),
          ],
        ];
      case _SettingsView.behavior:
        return [
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.systemSection'),
            children: [
              _SwitchRow(
                title: l10n.get('settings.autoStart'),
                subtitle: l10n.get('settings.autoStartHint'),
                value: settings.autoStartCore,
                onChanged: (value) => _apply(context, controller, settings.copyWith(autoStartCore: value)),
              ),
              _SwitchRow(
                title: l10n.get('settings.autoUpdateSubs'),
                subtitle: l10n.get('settings.autoUpdateSubsHint'),
                value: settings.autoUpdateSubscriptions,
                onChanged: (value) => _apply(context, controller, settings.copyWith(autoUpdateSubscriptions: value)),
              ),
              if (Platform.isWindows) ...[
                _SwitchRow(
                  title: l10n.get('settings.launchAtStartup'),
                  subtitle: l10n.get('settings.launchAtStartupHint'),
                  value: settings.launchAtStartup,
                  onChanged: (value) => _apply(context, controller, settings.copyWith(launchAtStartup: value)),
                ),
                _SwitchRow(
                  title: l10n.get('settings.closeToTray'),
                  subtitle: l10n.get('settings.closeToTrayHint'),
                  value: settings.closeToTray,
                  onChanged: (value) => _apply(context, controller, settings.copyWith(closeToTray: value)),
                ),
              ],
            ],
          ),
        ];
      case _SettingsView.about:
        return [
          _aboutHero(context, controller, mobile: mobile),
          SizedBox(height: mobile ? 24 : 28),
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.updateSection'),
            children: [
              AppDropdown<String>(
                options: [
                  AppDropdownOption(
                    AppSettings.channelStable,
                    l10n.get('settings.channel.stable'),
                  ),
                  AppDropdownOption(
                    AppSettings.channelPreview,
                    l10n.get('settings.channel.preview'),
                  ),
                ],
                selected: settings.updateChannel,
                onSelected: (value) =>
                    _apply(context, controller, settings.copyWith(updateChannel: value)),
                builder: (context, toggle) => SettingRow(
                  title: l10n.get('settings.updateChannel'),
                  subtitle: l10n.get('settings.channel.${settings.updateChannel}'),
                  trailing: chevron(),
                  onTap: toggle,
                ),
              ),
              _SwitchRow(
                title: l10n.get('settings.checkUpdatesOnStartup'),
                subtitle: l10n.get('settings.checkUpdatesOnStartupHint'),
                value: settings.checkUpdatesOnStartup,
                onChanged: (value) =>
                    _apply(context, controller, settings.copyWith(checkUpdatesOnStartup: value)),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.core'),
            trailing: CoreStatusBadge(controller: controller, dense: true),
            children: [
              SettingRow(
                title: l10n.get('settings.coreVersion'),
                subtitle: controller.isRunning && controller.coreVersion != null
                    ? 'Mihomo ${controller.coreVersion}'
                    : l10n.get('about.coreStopped'),
              ),
              _ValueRow(
                title: l10n.get('settings.coreBinary'),
                value: controller.coreBinary,
                onTap: () => copyToClipboard(context, controller.coreBinary),
                trailingIcon: 'copy-line',
                monospace: true,
              ),
            ],
          ),
          const SizedBox(height: 22),
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.more'),
            children: [
              _AboutLinkRow(
                icon: 'link-line',
                title: l10n.get('settings.github'),
                subtitle: AppInfo.repository,
                onTap: () => _openUrl(context, AppInfo.repository, l10n.get('settings.openFailed')),
              ),
              _AboutLinkRow(
                icon: 'chip-line',
                title: l10n.get('settings.core'),
                subtitle: AppInfo.mihomoRepository,
                onTap: () => _openUrl(context, AppInfo.mihomoRepository, l10n.get('settings.openFailed')),
              ),
              _AboutLinkRow(
                icon: 'shield-shape-line',
                title: l10n.get('settings.license'),
                subtitle: AppInfo.license,
                trailingIcon: 'right-small-line',
                onTap: () => showMessageDialog(
                  context,
                  title: l10n.get('settings.license'),
                  message:
                      '${AppInfo.name} ${AppInfo.version}\n\n${l10n.get('about.gpl')}\n${l10n.get('about.brand')}\n\n${AppInfo.repository}\n${AppInfo.mihomoRepository}',
                  icon: 'file-line',
                ),
              ),
              _AboutLinkRow(
                icon: 'file-line',
                title: l10n.get('settings.diagnostics'),
                subtitle: l10n.get('settings.copyDiagnostics'),
                trailingIcon: 'copy-line',
                onTap: () => copyToClipboard(context, controller.diagnostics()),
              ),
            ],
          ),
        ];
      case _SettingsView.data:
        return [
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.data'),
            children: [
              SettingRow(
                title: l10n.get('settings.updateAllSubs'),
                subtitle: l10n.get('settings.updateAllSubsHint'),
                trailing: controller.updatingAll
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : chevron(),
                onTap: controller.updatingAll || controller.subscriptions.isEmpty
                    ? null
                    : () => controller.updateAllSubscriptions(),
              ),
              SettingRow(
                title: l10n.get('settings.clearSelections'),
                subtitle: l10n.get('settings.clearSelectionsHint'),
                trailing: chevron(),
                onTap: () => _clearSelections(controller),
              ),
              SettingRow(
                title: l10n.get('settings.reset'),
                subtitle: l10n.get('settings.resetHint'),
                titleColor: palette.danger,
                trailing: chevron(),
                onTap: () => _resetSettings(context, controller),
              ),
            ],
          ),
        ];
      case _SettingsView.hub:
        return const [];
    }
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
      return SettingSection(title: title, trailing: trailing, children: children);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileSectionLabel(title, trailing: trailing, color: palette.sectionLabel),
        SurfaceCard(
          padding: EdgeInsets.zero,
          radius: 18,
          elevated: false,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _aboutHero(BuildContext context, AppController controller, {required bool mobile}) {
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    return Padding(
      padding: EdgeInsets.only(top: mobile ? 6 : 10, bottom: 2),
      child: Column(
        children: [
          BrandMark(size: mobile ? 76 : 92, radius: mobile ? 20 : 24),
          SizedBox(height: mobile ? 14 : 18),
          Text(
            AppInfo.name,
            style: TextStyle(
              fontSize: mobile ? 22 : 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: palette.text,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _AboutPill(text: 'v${AppInfo.version}', filled: true),
              const SizedBox(width: 8),
              _AboutPill(text: AppInfo.license),
            ],
          ),
          const SizedBox(height: 14),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              l10n.get('about.tagline'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.6, color: palette.strongMuted),
            ),
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _checkingUpdate ? null : () => _checkUpdates(controller),
            icon: _checkingUpdate
                ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2))
                : const AppIcon('refresh-2-line', size: 15),
            label: Text(l10n.get('settings.checkUpdates')),
            style: OutlinedButton.styleFrom(
              foregroundColor: palette.text,
              backgroundColor: palette.card,
              side: BorderSide(color: palette.border),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSecretSheet(AppController controller) async {
    final l10n = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(12),
          child: SurfaceCard(
            padding: EdgeInsets.zero,
            radius: 22,
            elevated: false,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SettingRow(
                    dense: true,
                    title: l10n.get('settings.copySecret'),
                    subtitle: maskSecret(controller.settings.secret),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      copyToClipboard(context, controller.settings.secret);
                    },
                  ),
                  RowDivider(indent: 14),
                  SettingRow(
                    dense: true,
                    title: l10n.get('settings.secretRegenerate'),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _regenerateSecret(context, controller);
                    },
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _clearSelections(AppController controller) async {
    await controller.clearSelections();
    if (!mounted) return;
    showAppToast(context, context.t('settings.clearSelectionsDone'));
  }
}

class _BackChip extends StatelessWidget {
  const _BackChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Tooltip(
      message: context.t('common.back'),
      child: Material(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
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

class _SettingEntry {
  const _SettingEntry({
    required this.view,
    required this.groupKey,
    required this.titleKey,
    this.subtitleKey,
    this.extraKeys = const [],
    this.danger = false,
  });

  final _SettingsView view;
  final String groupKey;
  final String titleKey;
  final String? subtitleKey;
  final List<String> extraKeys;
  final bool danger;

  bool matches(String query) {
    bool hit(String key) {
      for (final code in L10n.supported) {
        if (L10n(code).get(key).toLowerCase().contains(query)) return true;
      }
      return false;
    }

    if (hit(groupKey) || hit(titleKey)) return true;
    final subtitle = subtitleKey;
    if (subtitle != null && hit(subtitle)) return true;
    return extraKeys.any(hit);
  }
}

class _AccentValue extends StatelessWidget {
  const _AccentValue({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final preset = accentPresets[index.clamp(0, accentPresets.length - 1)];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: preset.color,
            shape: BoxShape.circle,
            border: Border.all(color: palette.border),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          preset.label(context.l10n.isZh),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 6),
        AppIcon('right-small-line', size: 13, color: palette.muted),
      ],
    );
  }
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.title,
    required this.value,
    this.subtitle,
    this.onTap,
    this.trailingIcon = 'right-small-line',
    this.monospace = false,
  });

  final String title;
  final String value;
  final String? subtitle;
  final VoidCallback? onTap;
  final String? trailingIcon;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SettingRow(
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      // 取值为弹性列，但要占满自己的槽位并右对齐：只写 MainAxisSize.min 时
      // 内容会停在弹性槽左端，桌面宽卡片上看起来像悬在卡片中间。
      trailing: Flexible(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: palette.muted,
                    fontFamily: monospace ? 'Consolas' : null,
                  ),
                ),
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 6),
              AppIcon(trailingIcon!, size: 14, color: palette.muted),
            ],
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      title: title,
      subtitle: subtitle,
      trailing: Switch(
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
}

int _bypassCount(String value) {
  final normalized = AppSettings.normalizeProxyBypass(value);
  return normalized.isEmpty ? 0 : normalized.split(';').length;
}

Future<void> _showBypassDialog(BuildContext context, AppController controller) async {
  final l10n = context.l10n;
  final field = TextEditingController(
    text: AppSettings.normalizeProxyBypass(controller.settings.proxyBypass).replaceAll(';', '\n'),
  )..selection = const TextSelection.collapsed(offset: 0);
  await showAppDialog<void>(
    context,
    maxWidth: 460,
    builder: (dialogContext) {
      var error = '';
      var saving = false;
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> save() async {
            final normalized = AppSettings.normalizeProxyBypass(field.text);
            if (normalized.isEmpty) {
              setState(() => error = l10n.get('settings.proxyBypassEmpty'));
              return;
            }
            setState(() {
              saving = true;
              error = '';
            });
            try {
              await controller.applySettings(
                controller.settings.copyWith(proxyBypass: normalized),
                announce: true,
              );
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            } catch (applyError) {
              setState(() {
                saving = false;
                error = errorFrom(applyError).localized(l10n);
              });
            }
          }

          return AppDialog(
            title: l10n.get('settings.proxyBypassTitle'),
            subtitle: l10n.get('settings.proxyBypassHint'),
            icon: 'shield-shape-line',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: field,
                  autofocus: true,
                  enabled: !saving,
                  minLines: 6,
                  maxLines: 10,
                  style: const TextStyle(fontSize: 13, fontFamily: 'Consolas', height: 1.5),
                  decoration: const InputDecoration(hintText: 'localhost\n127.*\n192.168.*'),
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  InfoBanner(message: error, color: AppPalette.of(dialogContext).danger, dense: true),
                ],
                const SizedBox(height: 10),
                Text(
                  l10n.get('settings.proxyBypassMessage'),
                  style: TextStyle(fontSize: 11, height: 1.5, color: AppPalette.of(dialogContext).muted),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => setState(() {
                          field.text = AppSettings.defaultProxyBypass.replaceAll(';', '\n');
                          error = '';
                        }),
                child: Text(dialogContext.t('settings.proxyBypassReset')),
              ),
              TextButton(
                onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                child: Text(dialogContext.t('common.cancel')),
              ),
              FilledButton(
                onPressed: saving ? null : save,
                child: saving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(dialogContext.t('common.save')),
              ),
            ],
          );
        },
      );
    },
  );
  field.dispose();
}

Future<void> _showPortDialog(BuildContext context, AppController controller, {required bool apiPort}) async {
  final l10n = context.l10n;
  final settings = controller.settings;
  final field = TextEditingController(text: '${apiPort ? settings.apiPort : settings.mixedPort}');
  await showAppDialog<void>(
    context,
    maxWidth: 420,
    builder: (dialogContext) {
      var error = '';
      var saving = false;
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> save() async {
            final value = int.tryParse(field.text.trim());
            if (value == null || value < 1 || value > 65535) {
              setState(() => error = l10n.get('settings.invalidPort'));
              return;
            }
            final other = apiPort ? controller.settings.mixedPort : controller.settings.apiPort;
            if (value == other) {
              setState(() => error = l10n.get('settings.portConflict'));
              return;
            }
            setState(() {
              saving = true;
              error = '';
            });
            try {
              await controller.applySettings(
                apiPort ? controller.settings.copyWith(apiPort: value) : controller.settings.copyWith(mixedPort: value),
                announce: true,
              );
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            } catch (applyError) {
              setState(() {
                saving = false;
                error = errorFrom(applyError).localized(l10n);
              });
            }
          }

          return AppDialog(
            title: l10n.get(apiPort ? 'settings.apiPort' : 'settings.mixedPort'),
            subtitle: l10n.get(apiPort ? 'settings.apiPortHint' : 'settings.mixedPortHint'),
            icon: apiPort ? 'terminal-line' : 'link-line',
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: field,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  enabled: !saving,
                  onSubmitted: (_) => save(),
                  style: const TextStyle(fontSize: 15),
                  decoration: const InputDecoration(prefixText: '# '),
                ),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  InfoBanner(message: error, color: AppPalette.of(dialogContext).danger, dense: true),
                ],
                const SizedBox(height: 10),
                Text(
                  l10n.get('settings.restartRequired'),
                  style: TextStyle(fontSize: 11, color: AppPalette.of(dialogContext).muted),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                child: Text(dialogContext.t('common.cancel')),
              ),
              FilledButton(
                onPressed: saving ? null : save,
                child: saving
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(dialogContext.t('common.save')),
              ),
            ],
          );
        },
      );
    },
  );
  field.dispose();
}

Future<void> _regenerateSecret(BuildContext context, AppController controller) async {
  final l10n = context.l10n;
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.get('settings.secret'),
    message: l10n.get('settings.secretConfirmMessage'),
    confirmText: l10n.get('settings.secretRegenerate'),
    icon: 'file-line',
  );
  if (!confirmed || !context.mounted) return;
  try {
    await controller.regenerateSecret();
    if (!context.mounted) return;
    showAppToast(context, l10n.get('settings.secretRegenerated'));
  } catch (error) {
    if (!context.mounted) return;
    showAppToast(context, errorFrom(error).localized(l10n), error: true);
  }
}

Future<void> _apply(BuildContext context, AppController controller, AppSettings next) async {
  final l10n = context.l10n;
  try {
    await controller.applySettings(next);
  } catch (error) {
    if (!context.mounted) return;
    showAppToast(context, errorFrom(error).localized(l10n), error: true);
  }
}

Future<void> _toggleSystemProxy(BuildContext context, AppController controller, bool value) async {
  try {
    await controller.setSystemProxy(value);
  } catch (_) {
    // The controller already surfaced the failure through a notice.
  }
}

Future<void> _resetSettings(BuildContext context, AppController controller) async {
  final l10n = context.l10n;
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.get('settings.resetTitle'),
    message: l10n.get('settings.resetMessage'),
    confirmText: l10n.get('settings.reset'),
    danger: true,
    icon: 'delete-2-line',
  );
  if (!confirmed || !context.mounted) return;
  await controller.resetSettings();
}

Future<void> _openFolder(BuildContext context, String path, String failureMessage) async {
  if (!Platform.isWindows) {
    showAppToast(context, failureMessage, error: true);
    return;
  }
  try {
    await Process.run('explorer', [path]);
  } catch (_) {
    if (!context.mounted) return;
    showAppToast(context, failureMessage, error: true);
  }
}

Future<void> _openUrl(BuildContext context, String url, String failureMessage) async {
  try {
    final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!launched) throw Exception('launch failed');
  } catch (_) {
    if (!context.mounted) return;
    showAppToast(context, failureMessage, error: true);
  }
}

class _AboutPill extends StatelessWidget {
  const _AboutPill({required this.text, this.filled = false});

  final String text;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? Theme.of(context).colorScheme.primary : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        border: filled ? null : Border.all(color: palette.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.2,
          color: filled ? palette.onAccent : palette.strongMuted,
        ),
      ),
    );
  }
}

class _AboutLinkRow extends StatelessWidget {
  const _AboutLinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailingIcon = 'link-line',
  });

  final String icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String trailingIcon;

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
          padding: EdgeInsets.symmetric(horizontal: mobile ? 16 : 18, vertical: mobile ? 13 : 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: palette.cardAlt, borderRadius: BorderRadius.circular(11)),
                child: AppIcon(icon, size: 16, color: palette.strongMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: mobile ? 15 : 13.5, fontWeight: FontWeight.w600, color: palette.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: mobile ? 12.5 : 12, color: palette.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AppIcon(trailingIcon, size: 14, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}
