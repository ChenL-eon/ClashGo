import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../core/errors.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/dns_query.dart';
import '../shell/navigation.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';

class DnsPage extends StatefulWidget {
  const DnsPage({super.key});

  @override
  State<DnsPage> createState() => _DnsPageState();
}

class _DnsPageState extends State<DnsPage> {
  static const _types = ['A', 'AAAA', 'CNAME', 'TXT', 'MX', 'NS', 'SRV'];

  final TextEditingController _domain = TextEditingController();
  final List<({String domain, String type})> _history = [];

  String _type = 'A';
  bool _loading = false;
  DnsQueryResult? _result;
  AppError? _error;

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  Future<void> _query([String? overrideDomain, String? overrideType]) async {
    final controller = context.read<AppController>();
    final domain = (overrideDomain ?? _domain.text).trim();
    final type = overrideType ?? _type;
    if (domain.isEmpty || !RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(domain)) {
      _showMessage(context.t('dns.invalid'), error: true);
      return;
    }
    if (!controller.isRunning) {
      _showMessage(context.t('dns.notRunning'), error: true);
      return;
    }
    if (overrideDomain != null) _domain.text = overrideDomain;
    if (overrideType != null) setState(() => _type = overrideType);
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await controller.api.queryDns(domain, type);
      if (!mounted) return;
      setState(() => _result = result);
      setState(() {
        _history.removeWhere((item) => item.domain == domain && item.type == type);
        _history.insert(0, (domain: domain, type: type));
        if (_history.length > 8) _history.removeLast();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = errorFrom(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message, {bool error = false}) {
    showAppToast(context, message, error: error);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    final text = Theme.of(context).textTheme;
    final running = controller.isRunning;
    final result = _result;

    return PageFrame(
      floatingNav: false,
      header: PageHeader(
        leading: const ToolBackButton(),
        title: l10n.get('nav.dns'),
        subtitle: l10n.get('dns.subtitle'),
      ),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 10),
        children: [
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 620;
                    final field = TextField(
                      controller: _domain,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _query(),
                      style: TextStyle(fontSize: 13.5, color: palette.text),
                      decoration: InputDecoration(
                        hintText: l10n.get('dns.placeholder'),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 12, right: 8),
                          child: AppIcon('globe-line', size: 17, color: palette.muted),
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                      ),
                    );
                    final button = FilledButton.icon(
                      onPressed: !running || _loading ? null : () => _query(),
                      icon: _loading
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const AppIcon('search-line', size: 16, color: Colors.white),
                      label: Text(l10n.get(_loading ? 'dns.querying' : 'dns.query')),
                    );
                    if (!wide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          field,
                          const SizedBox(height: 10),
                          button,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: field),
                        const SizedBox(width: 10),
                        SizedBox(height: 48, child: button),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(
                      l10n.get('dns.type'),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: palette.muted),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final type in _types) ...[
                              _TypeChip(
                                label: type,
                                selected: _type == type,
                                onTap: () => setState(() => _type = type),
                              ),
                              if (type != _types.last) const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (!running) ...[
                  const SizedBox(height: 12),
                  InfoBanner(
                    message: l10n.get('dns.notRunning'),
                    color: palette.muted,
                    dense: true,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: palette.accentSoft,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Center(
                        child: AppIcon('list-check-line', size: 15, color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(l10n.get('dns.result'), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    if (result != null)
                      AppBadge(
                        text: result.success
                            ? l10n.get('dns.answer')
                            : '${l10n.get('dns.status')} ${result.status}',
                        color: result.success ? palette.success : palette.danger,
                        dense: true,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (_loading)
                  const LoadingBlock()
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: InfoBanner(
                      message: _error!.localized(l10n),
                      color: palette.danger,
                      icon: 'close-circle-line',
                    ),
                  )
                else if (result == null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 26),
                    child: Column(
                      children: [
                        AppIcon('globe-line', size: 26, color: palette.muted),
                        const SizedBox(height: 8),
                        Text(l10n.get(running ? 'dns.hintReady' : 'dns.hint'),
                            style: TextStyle(fontSize: 11.5, color: palette.muted)),
                      ],
                    ),
                  )
                else if (result.answers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    child: Column(
                      children: [
                        Text(l10n.get('dns.empty'), style: TextStyle(fontSize: 12.5, color: palette.strongMuted)),
                        const SizedBox(height: 4),
                        Text(
                          '${l10n.get('dns.status')}: ${result.status}',
                          style: TextStyle(fontSize: 10.5, color: palette.muted),
                        ),
                      ],
                    ),
                  )
                else ...[
                  const SizedBox(height: 8),
                  for (final answer in result.answers) ...[
                    _AnswerTile(answer: answer),
                    const SizedBox(height: 8),
                  ],
                ],
              ],
            ),
          ),
          if (_history.isNotEmpty) ...[
            const SizedBox(height: 20),
            SectionLabel(
              l10n.get('dns.recent'),
              icon: 'clock-line',
              trailing: TextButton(
                onPressed: () => setState(_history.clear),
                child: Text(l10n.get('dns.clearHistory')),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final item in _history)
                  ActionChip(
                    avatar: AppIcon('globe-line', size: 13, color: palette.muted),
                    label: Text('${item.domain} · ${item.type}'),
                    labelStyle: TextStyle(fontSize: 11.5, color: palette.strongMuted),
                    backgroundColor: palette.card,
                    side: BorderSide(color: palette.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    onPressed: () => _query(item.domain, item.type),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.12) : palette.cardAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: selected ? accent.withValues(alpha: 0.45) : palette.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? accent : palette.muted,
              fontFamily: 'Consolas',
            ),
          ),
        ),
      ),
    );
  }
}

class _AnswerTile extends StatelessWidget {
  const _AnswerTile({required this.answer});

  final DnsAnswer answer;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: palette.cardAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppBadge(
            text: answer.typeName,
            color: Theme.of(context).colorScheme.primary,
            dense: true,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  answer.data,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: palette.text, fontFamily: 'Consolas'),
                ),
                const SizedBox(height: 3),
                Text(
                  '${answer.name} · TTL ${answer.ttl}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: palette.muted),
                ),
              ],
            ),
          ),
          AppIconButton(
            icon: 'copy-line',
            size: 14,
            padding: 6,
            tooltip: context.t('common.copy'),
            onTap: () => copyToClipboard(context, answer.data),
          ),
        ],
      ),
    );
  }
}
