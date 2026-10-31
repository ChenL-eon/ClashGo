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
        SizedBox(height: mobile ? 18 : 20),
        _section(
          context,
          mobile: mobile,
          title: l10n.get('settings.group.personalization'),
          icon: 'palette-line',
          children: [
            SettingRow(
              icon: 'moon-cloudy-line',
              title: l10n.get('settings.theme'),
              subtitle: l10n.get('settings.hub.themeHint'),
              trailing: chevron(),
              onTap: () => _open(_SettingsView.theme),
            ),
            SettingRow(
              icon: 'translate-line',
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
          icon: 'chip-line',
          children: [
            SettingRow(
              icon: 'settings-3-line',
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
          icon: 'grid-line',
          children: [
            SettingRow(
              icon: 'power-line',
              title: l10n.get('settings.hub.behavior'),
              subtitle: l10n.get('settings.hub.behaviorHint'),
              trailing: chevron(),
              onTap: () => _open(_SettingsView.behavior),
            ),
            SettingRow(
              icon: 'information-line',
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
          icon: 'transfer-line',
          children: [
            SettingRow(
              icon: 'folder-line',
              title: l10n.get('settings.hub.data'),
              subtitle: l10n.get('settings.hub.dataHint'),
              trailing: chevron(),
              onTap: () => _open(_SettingsView.data),
            ),
          ],
        ),
        const SizedBox(height: 30),
        _BrandFooter(compact: mobile),
      ],
    );
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
            icon: 'palette-line',
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
                  icon: 'moon-cloudy-line',
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
                  icon: 'palette-line',
                  title: l10n.get('settings.accent'),
                  subtitle: l10n.get('settings.accentHint'),
                  onTap: toggle,
                  trailing: _AccentValue(index: settings.accentIndex),
                ),
              ),
              _SwitchRow(
                icon: 'moon-cloudy-line',
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
            icon: 'translate-line',
            children: [
              AppDropdown<String>(
                options: const [
                  AppDropdownOption('zh', '简体中文'),
                  AppDropdownOption('en', 'English'),
                ],
                selected: settings.language,
                onSelected: (value) => _apply(context, controller, settings.copyWith(language: value)),
                builder: (context, toggle) => _ValueRow(
                  icon: 'translate-line',
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
            icon: 'globe-line',
            children: [
              _ValueRow(
                icon: 'link-line',
                title: l10n.get('settings.mixedPort'),
                subtitle: l10n.get('settings.mixedPortHint'),
                value: '${settings.mixedPort}',
                onTap: () => _showPortDialog(context, controller, apiPort: false),
              ),
              _ValueRow(
                icon: 'terminal-line',
                title: l10n.get('settings.apiPort'),
                subtitle: l10n.get('settings.apiPortHint'),
                value: '${settings.apiPort}',
                onTap: () => _showPortDialog(context, controller, apiPort: true),
              ),
              if (mobile)
                SettingRow(
                  icon: 'file-line',
                  title: l10n.get('settings.secret'),
                  subtitle: maskSecret(settings.secret),
                  trailing: chevron(),
                  onTap: () => _showSecretSheet(controller),
                )
              else
                SettingRow(
                  icon: 'file-line',
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
                icon: 'wifi-line',
                title: l10n.get('settings.allowLan'),
                subtitle: l10n.get('settings.allowLanHint'),
                value: settings.allowLan,
                onChanged: (value) => _apply(context, controller, settings.copyWith(allowLan: value)),
              ),
              _SwitchRow(
                icon: 'globe-line',
                title: l10n.get('settings.ipv6'),
                subtitle: l10n.get('settings.ipv6Hint'),
                value: settings.ipv6,
                onChanged: (value) => _apply(context, controller, settings.copyWith(ipv6: value)),
              ),
              _SwitchRow(
                icon: 'shield-shape-line',
                title: l10n.get('settings.systemProxy'),
                subtitle: systemProxyHint,
                value: settings.systemProxy,
                enabled: SystemProxyService.supported,
                onChanged: (value) => _toggleSystemProxy(context, controller, value),
              ),
            ],
          ),
          const SizedBox(height: 22),
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.core'),
            icon: 'chip-line',
            trailing: CoreStatusBadge(controller: controller, dense: true),
            children: [
              _ValueRow(
                icon: 'shield-shape-line',
                title: l10n.get('settings.coreVersion'),
                value: controller.coreVersion ?? '—',
                onTap: null,
              ),
              _ValueRow(
                icon: 'file-line',
                title: l10n.get('settings.coreBinary'),
                value: controller.coreBinary,
                onTap: () => copyToClipboard(context, controller.coreBinary),
                trailingIcon: 'copy-line',
                monospace: true,
              ),
              _ValueRow(
                icon: 'folder-line',
                title: l10n.get('settings.runtimeDir'),
                value: controller.core.runtimeDir,
                onTap: !Platform.isWindows
                    ? () => copyToClipboard(context, controller.core.runtimeDir)
                    : () => _openFolder(context, controller.core.runtimeDir, l10n.get('settings.openFailed')),
                trailingIcon: Platform.isWindows ? 'folder-line' : 'copy-line',
                monospace: true,
              ),
              SettingRow(
                icon: 'play-circle-line',
                title: l10n.get('settings.restartCore'),
                subtitle: l10n.get('settings.restartHint'),
                trailing: FilledButton(
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                  onPressed: controller.isRunning ? () => _restartCore(context, controller) : null,
                  child: Text(l10n.get('common.restart')),
                ),
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
            icon: 'settings-3-line',
            children: [
              _SwitchRow(
                icon: 'power-line',
                title: l10n.get('settings.autoStart'),
                subtitle: l10n.get('settings.autoStartHint'),
                value: settings.autoStartCore,
                onChanged: (value) => _apply(context, controller, settings.copyWith(autoStartCore: value)),
              ),
              _SwitchRow(
                icon: 'refresh-2-line',
                title: l10n.get('settings.autoUpdateSubs'),
                subtitle: l10n.get('settings.autoUpdateSubsHint'),
                value: settings.autoUpdateSubscriptions,
                onChanged: (value) => _apply(context, controller, settings.copyWith(autoUpdateSubscriptions: value)),
              ),
            ],
          ),
        ];
      case _SettingsView.about:
        return [
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.about'),
            icon: 'information-line',
            children: [
              SettingRow(
                icon: 'grid-line',
                title: l10n.get('settings.github'),
                subtitle: AppInfo.repository,
                trailing: chevron(),
                onTap: () => _openUrl(context, AppInfo.repository, l10n.get('settings.openFailed')),
              ),
              SettingRow(
                icon: 'shield-shape-line',
                title: l10n.get('about.mihomo'),
                subtitle: AppInfo.mihomoRepository,
                trailing: chevron(),
                onTap: () => _openUrl(context, AppInfo.mihomoRepository, l10n.get('settings.openFailed')),
              ),
              SettingRow(
                icon: 'file-line',
                title: l10n.get('settings.license'),
                subtitle: AppInfo.license,
                trailing: chevron(),
                onTap: () => showMessageDialog(
                  context,
                  title: l10n.get('settings.license'),
                  message:
                      '${AppInfo.name} ${AppInfo.version}\n\n${l10n.get('about.gpl')}\n${l10n.get('about.brand')}\n\n${AppInfo.repository}\n${AppInfo.mihomoRepository}',
                  icon: 'file-line',
                ),
              ),
              SettingRow(
                icon: 'information-line',
                title: l10n.get('settings.diagnostics'),
                subtitle: l10n.get('settings.copyDiagnostics'),
                trailing: AppIcon('copy-line', size: 15, color: palette.muted),
                onTap: () => copyToClipboard(context, controller.diagnostics()),
              ),
            ],
          ),
          const SizedBox(height: 30),
          _BrandFooter(compact: mobile),
        ];
      case _SettingsView.data:
        return [
          _section(
            context,
            mobile: mobile,
            title: l10n.get('settings.data'),
            icon: 'transfer-line',
            children: [
              SettingRow(
                icon: 'refresh-2-line',
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
                icon: 'close-circle-line',
                title: l10n.get('settings.clearSelections'),
                subtitle: l10n.get('settings.clearSelectionsHint'),
                trailing: chevron(),
                onTap: () => _clearSelections(controller),
              ),
              SettingRow(
                icon: 'delete-2-line',
                title: l10n.get('settings.reset'),
                subtitle: l10n.get('settings.resetHint'),
                iconColor: palette.danger,
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
    String? icon,
    List<Widget> children = const [],
    Widget? trailing,
  }) {
    if (!mobile) {
      return SettingSection(title: title, icon: icon, trailing: trailing, children: children);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MobileSectionLabel(title, trailing: trailing),
        SurfaceCard(
          padding: EdgeInsets.zero,
          radius: 18,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const RowDivider(indent: 16),
                children[i],
              ],
            ],
          ),
        ),
      ],
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
                    icon: 'copy-line',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      copyToClipboard(context, controller.settings.secret);
                    },
                  ),
                  RowDivider(indent: 14),
                  SettingRow(
                    dense: true,
                    title: l10n.get('settings.secretRegenerate'),
                    icon: 'refresh-2-line',
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

class _BrandFooter extends StatelessWidget {
  const _BrandFooter({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    return Center(
      child: Column(
        children: [
          BrandMark(size: compact ? 44 : 48, radius: compact ? 14 : 15),
          const SizedBox(height: 12),
          Text(
            AppInfo.name,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            'v${AppInfo.version} · ${l10n.get('about.gpl')}',
            style: TextStyle(fontSize: 10.5, color: palette.muted),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.get('about.brand'),
            style: TextStyle(fontSize: 10, color: palette.muted.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
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
    required this.icon,
    required this.title,
    required this.value,
    this.subtitle,
    this.onTap,
    this.trailingIcon = 'right-small-line',
    this.monospace = false,
  });

  final String icon;
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
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      // 取值为弹性列：窄屏下若用固定宽度，标题列会被挤到一字一行（如图「运/行/目/录」）。
      trailing: Flexible(
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: onTap == null ? palette.strongMuted : Theme.of(context).colorScheme.primary,
                    fontFamily: monospace ? 'Consolas' : null,
                  ),
                ),
              ),
            ),
            if (trailingIcon != null) ...[
              const SizedBox(width: 6),
              AppIcon(trailingIcon!, size: 13, color: palette.muted),
            ],
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final String icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return SettingRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: Switch(
        value: value,
        onChanged: enabled ? onChanged : null,
      ),
    );
  }
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

Future<void> _restartCore(BuildContext context, AppController controller) async {
  final l10n = context.l10n;
  final confirmed = await showConfirmDialog(
    context,
    title: l10n.get('settings.restartConfirm'),
    message: l10n.get('settings.restartConfirmMessage'),
    confirmText: l10n.get('common.restart'),
    icon: 'refresh-2-line',
  );
  if (!confirmed || !context.mounted) return;
  try {
    await controller.restartCore();
  } catch (error) {
    if (!context.mounted) return;
    showAppToast(context, errorFrom(error).localized(l10n), error: true);
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
