import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../core/errors.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/provider_info.dart';
import '../shell/navigation.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';
import '../widgets/quota_bar.dart';

class ProvidersPage extends StatefulWidget {
  const ProvidersPage({super.key});

  @override
  State<ProvidersPage> createState() => _ProvidersPageState();
}

class _ProvidersPageState extends State<ProvidersPage> {
  AppController? _controller;
  List<ProviderInfo> _providers = const [];
  bool _loading = false;
  bool _loaded = false;
  bool _updatingAll = false;
  AppError? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = context.read<AppController>();
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_onControllerChanged);
      _controller = controller..addListener(_onControllerChanged);
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_controller!.isRunning && !_loaded && !_loading && _error == null) {
      _load();
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final controller = context.read<AppController>();
    if (!controller.isRunning || _loading) return;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final providers = await controller.api.providers();
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

  Future<void> _update(ProviderInfo provider) async {
    if (_busy.contains(provider.name)) return;
    final controller = context.read<AppController>();
    final l10n = context.l10n;
    setState(() => _busy.add(provider.name));
    try {
      await controller.api.updateProvider(provider.name);
      _notice(l10n.get('providers.updateSuccess', [provider.name]));
      await _load(silent: true);
    } catch (error) {
      _notice(errorFrom(error).localized(l10n), error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(provider.name));
    }
  }

  Future<void> _healthcheck(ProviderInfo provider) async {
    if (_busy.contains(provider.name)) return;
    final controller = context.read<AppController>();
    final l10n = context.l10n;
    setState(() => _busy.add(provider.name));
    try {
      await controller.api.healthCheckProvider(provider.name);
      _notice(l10n.get('providers.healthcheckSuccess'));
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
    for (final provider in List<ProviderInfo>.from(_providers)) {
      try {
        await controller.api.updateProvider(provider.name);
      } catch (_) {
        failed = true;
      }
    }
    if (!mounted) return;
    setState(() => _updatingAll = false);
    _notice(failed ? l10n.get('providers.failed') : l10n.get('providers.allUpdated'), error: failed);
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
        title: l10n.get('nav.providers'),
        subtitle: l10n.get('providers.subtitle'),
        actions: [
          AppBadge(
            text: l10n.get('providers.count', [_providers.length]),
            icon: 'cloud-line',
            dense: true,
          ),
          if (running && _providers.isNotEmpty)
            OutlinedButton.icon(
              onPressed: _updatingAll ? null : _updateAll,
              icon: _updatingAll
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const AppIcon('refresh-2-line', size: 16),
              label: Text(l10n.get('providers.updateAll')),
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
                TextButton(onPressed: () => _load(), child: Text(l10n.get('common.retry'))),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: !running
                ? EmptyState(
                    icon: 'cloud-line',
                    title: l10n.get('providers.notRunning'),
                    message: l10n.get('providers.subtitle'),
                  )
                : _loading && _providers.isEmpty
                    ? const LoadingBlock(height: 200)
                    : _providers.isEmpty
                        ? EmptyState(
                            icon: 'cloud-line',
                            title: l10n.get('providers.empty'),
                            message: l10n.get('providers.emptyHint'),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 4),
                            itemCount: _providers.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final provider = _providers[index];
                              return _ProviderCard(
                                provider: provider,
                                busy: _busy.contains(provider.name),
                                onUpdate: () => _update(provider),
                                onHealthcheck: () => _healthcheck(provider),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.busy,
    required this.onUpdate,
    required this.onHealthcheck,
  });

  final ProviderInfo provider;
  final bool busy;
  final VoidCallback onUpdate;
  final VoidCallback onHealthcheck;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    final ratio = provider.usageRatio;
    final quotaColor = ratio >= 0.9 ? palette.danger : ratio >= 0.7 ? palette.warning : accent;
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
                decoration: BoxDecoration(color: palette.accentSoft, borderRadius: BorderRadius.circular(12)),
                child: Center(child: AppIcon('cloud-line', size: 19, color: accent)),
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
                      style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        AppBadge(text: provider.type.isEmpty ? l10n.get('common.unknown') : provider.type, dense: true),
                        if (provider.vehicleType.isNotEmpty)
                          AppBadge(text: provider.vehicleType, dense: true, color: accent),
                        AppBadge(
                          text: l10n.get('providers.nodes', [provider.proxyCount]),
                          dense: true,
                          icon: 'wifi-line',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
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
                  l10n.get('providers.updated', [l10n.formatRelative(provider.updatedAt)]),
                  style: TextStyle(fontSize: 10.5, color: palette.muted),
                ),
              ],
            ),
          ],
          if (provider.hasQuota) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(l10n.get('providers.traffic'), style: TextStyle(fontSize: 11, color: palette.muted)),
                const Spacer(),
                Text(
                  '${formatBytes(provider.used)} / ${formatBytes(provider.total)}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: palette.strongMuted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            QuotaBar(ratio: ratio, color: quotaColor),
            if (provider.expire > 0) ...[
              const SizedBox(height: 6),
              Text(
                '${l10n.get('subscriptions.expire')} ${formatExpire(provider.expire, zh: l10n.isZh)}',
                style: TextStyle(fontSize: 10.5, color: palette.muted),
              ),
            ],
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onUpdate,
                  icon: const AppIcon('refresh-2-line', size: 15),
                  label: Text(l10n.get('providers.update')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : onHealthcheck,
                  icon: const AppIcon('speed-line', size: 15),
                  label: Text(l10n.get('providers.healthcheck')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
