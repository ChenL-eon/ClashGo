import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../core/errors.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/rule_item.dart';
import '../shell/navigation.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';

class RulesPage extends StatefulWidget {
  const RulesPage({super.key});

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  final TextEditingController _search = TextEditingController();

  AppController? _controller;
  List<RuleItem> _rules = const [];
  bool _loading = false;
  bool _loaded = false;
  AppError? _error;

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
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final controller = context.read<AppController>();
    if (!controller.isRunning || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rules = await controller.api.rules();
      if (!mounted) return;
      setState(() {
        _rules = rules;
        _loaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = errorFrom(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<RuleItem> get _filtered {
    final query = _search.text.trim();
    if (query.isEmpty) return _rules;
    return _rules.where((rule) => rule.matches(query)).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    final running = controller.isRunning;
    final filtered = _filtered;

    return PageFrame(
      floatingNav: false,
      header: PageHeader(
        leading: const ToolBackButton(),
        title: l10n.get('nav.rules'),
        subtitle: l10n.get('rules.subtitle'),
        actions: [
          AppBadge(
            text: l10n.get('rules.count', [filtered.length]),
            icon: 'list-check-line',
            dense: true,
          ),
          AppIconButton(
            icon: 'refresh-2-line',
            tooltip: l10n.get('common.refresh'),
            onTap: running && !_loading ? _load : null,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSearchField(
            controller: _search,
            hint: l10n.get('rules.search'),
            onChanged: (_) => setState(() {}),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            InfoBanner(
              message: _error!.localized(l10n),
              color: palette.danger,
              icon: 'close-circle-line',
              dense: true,
              actions: [
                TextButton(
                  onPressed: _load,
                  child: Text(l10n.get('common.retry')),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: !running
                ? EmptyState(
                    icon: 'list-check-line',
                    title: l10n.get('rules.notRunning'),
                    message: l10n.get('rules.emptyHint'),
                  )
                : _loading && _rules.isEmpty
                    ? const LoadingBlock(height: 200)
                    : filtered.isEmpty
                        ? EmptyState(
                            icon: _rules.isEmpty ? 'list-check-line' : 'search-line',
                            title: _rules.isEmpty ? l10n.get('rules.empty') : l10n.get('proxy.filterNoResult'),
                            message: _rules.isEmpty ? l10n.get('rules.emptyHint') : null,
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 4),
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 6),
                            itemBuilder: (context, index) => _RuleTile(rule: filtered[index], index: index + 1),
                          ),
          ),
        ],
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({required this.rule, required this.index});

  final RuleItem rule;
  final int index;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '$index',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 10,
                color: palette.muted.withValues(alpha: 0.7),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            constraints: const BoxConstraints(minWidth: 62, maxWidth: 118),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              rule.displayType,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: accent, letterSpacing: 0.2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              rule.payload.isEmpty ? '—' : rule.payload,
              maxLines: 2,
              style: TextStyle(fontSize: 12, color: palette.text, height: 1.4),
            ),
          ),
          const SizedBox(width: 10),
          AppIcon('right-small-line', size: 12, color: palette.muted),
          const SizedBox(width: 6),
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 130),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: palette.cardAlt,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: palette.border),
              ),
              child: Text(
                rule.proxy,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: palette.strongMuted),
              ),
            ),
          ),
          AppIconButton(
            icon: 'copy-line',
            size: 13,
            padding: 6,
            tooltip: context.t('common.copy'),
            onTap: () => copyToClipboard(context, '${rule.displayType},${rule.payload},${rule.proxy}'),
          ),
        ],
      ),
    );
  }
}
