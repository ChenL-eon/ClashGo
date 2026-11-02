import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../core/errors.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/rule_provider_info.dart';
import '../shell/navigation.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';

class RuleProvidersPage extends StatefulWidget {
  const RuleProvidersPage({super.key});

  @override
  State<RuleProvidersPage> createState() => _RuleProvidersPageState();
}

class _RuleProvidersPageState extends State<RuleProvidersPage> {
  AppController? _controller;
  List<RuleProviderInfo> _providers = const [];
  bool _loading = false;
  bool _loaded = false;
  bool _updatingAll = false;
  bool _wasRunning = false;
  AppError? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<AppController>();
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_onControllerChanged);
      _controller = controller..addListener(_onControllerChanged);
      _wasRunning = controller.isRunning;
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final running = _controller!.isRunning;
    if (running != _wasRunning) {
      _wasRunning = running;
      if (!running && (_loaded || _providers.isNotEmpty || _error != null)) {
        // 内核停了以后旧列表已经没有意义；重启后必须重新拉一次。
        setState(() {
          _providers = const [];
          _loaded = false;
          _error = null;
          _updatingAll = false;
        });
      }
    }
    if (running && !_loaded && !_loading && _error == null) {
      _load();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    final controller = context.read<AppController>();
    if (!controller.isRunning || _loading) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final providers = await controller.api.ruleProviders();
      if (!mounted) return;
      setState(() {
        _providers = providers;
        _loaded = true;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = errorFrom(error));
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  void _notice(String message, {bool error = false}) {
    if (!mounted) return;
    showAppToast(context, message, error: error);
  }

  Future<void> _update(RuleProviderInfo provider) async {
    if (_busy.contains(provider.name)) return;
    final controller = context.read<AppController>();
    final l10n = context.l10n;
    setState(() => _busy.add(provider.name));
    try {
      await controller.api.updateRuleProvider(provider.name);
      _notice(l10n.get('ruleProviders.updateSuccess', [provider.name]));
      await _load(silent: true);
    } catch (error) {
      _notice(errorFrom(error).localized(l10n), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(provider.name));
    }
  }

  Future<void> _updateAll() async {
    if (_updatingAll) return;
    final controller = context.read<AppController>();
    final l10n = context.l10n;
    setState(() => _updatingAll = true);
    var failed = false;
    for (final provider in List<RuleProviderInfo>.from(_providers)) {
      try {
        await controller.api.updateRuleProvider(provider.name);
      } catch (_) {
        failed = true;
      }
    }
    if (!mounted) return;
    setState(() => _updatingAll = false);
    _notice(
      failed
          ? l10n.get('ruleProviders.failed')
          : l10n.get('ruleProviders.allUpdated'),
      error: failed,
    );
    await _load(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    final running = controller.isRunning;

    return PageFrame(
      floatingNav: false,
      header: PageHeader(
        leading: const ToolBackButton(),
        title: l10n.get('nav.ruleProviders'),
        subtitle: l10n.get('ruleProviders.subtitle'),
        actions: [
          AppBadge(
            text: l10n.get('ruleProviders.count', [_providers.length]),
            icon: 'file-line',
            dense: true,
          ),
          if (running && _providers.isNotEmpty)
            OutlinedButton.icon(
              onPressed: _updatingAll ? null : _updateAll,
              icon: _updatingAll
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const AppIcon('refresh-2-line', size: 16),
              label: Text(l10n.get('ruleProviders.updateAll')),
            ),
          AppIconButton(
            icon: 'refresh-2-line',
            tooltip: l10n.get('common.refresh'),
            onTap: running && !_loading ? () => _load() : null,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            InfoBanner(
              message: _error!.localized(l10n),
              color: palette.danger,
              icon: 'close-circle-line',
              dense: true,
              actions: [
                TextButton(
                  onPressed: () => _load(),
                  child: Text(l10n.get('common.retry')),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: !running
                ? EmptyState(
                    icon: 'file-line',
                    title: l10n.get('ruleProviders.notRunning'),
                    message: l10n.get('ruleProviders.subtitle'),
                  )
                : _loading && _providers.isEmpty
                ? const LoadingBlock(height: 200)
                : _providers.isEmpty
                ? EmptyState(
                    icon: 'file-line',
                    title: l10n.get('ruleProviders.empty'),
                    message: l10n.get('ruleProviders.emptyHint'),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 4),
                    itemCount: _providers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final provider = _providers[index];
                      return _RuleProviderCard(
                        provider: provider,
                        busy: _busy.contains(provider.name),
                        onUpdate: () => _update(provider),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RuleProviderCard extends StatelessWidget {
  const _RuleProviderCard({
    required this.provider,
    required this.busy,
    required this.onUpdate,
  });

  final RuleProviderInfo provider;
  final bool busy;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: AppIcon('file-line', size: 19, color: accent),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        AppBadge(
                          text: provider.type.isEmpty
                              ? l10n.get('common.unknown')
                              : provider.type,
                          dense: true,
                        ),
                        if (provider.behavior.isNotEmpty)
                          AppBadge(
                            text: provider.behavior,
                            dense: true,
                            color: accent,
                          ),
                        AppBadge(
                          text: l10n.get('ruleProviders.rules', [
                            provider.ruleCount,
                          ]),
                          dense: true,
                          icon: 'list-check-line',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          if (provider.updatedAt != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                AppIcon('clock-line', size: 12, color: palette.muted),
                const SizedBox(width: 5),
                Text(
                  l10n.get('ruleProviders.updated', [
                    l10n.formatRelative(provider.updatedAt),
                  ]),
                  style: TextStyle(fontSize: 10.5, color: palette.muted),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: busy ? null : onUpdate,
            icon: const AppIcon('refresh-2-line', size: 15),
            label: Text(l10n.get('ruleProviders.update')),
          ),
        ],
      ),
    );
  }
}
