import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/app_controller.dart';
import '../../core/formatters.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../models/app_settings.dart';
import '../../models/proxy_info.dart';
import '../../services/offline_latency.dart';
import '../../services/offline_proxies.dart';
import '../shell/navigation.dart';
import '../widgets/app_icon.dart';
import '../widgets/common.dart';
import '../widgets/status_widgets.dart';

enum NodeSort { original, delay, name }

String nodeSortKey(NodeSort sort) => switch (sort) {
      NodeSort.original => 'default',
      NodeSort.delay => 'delay',
      NodeSort.name => 'name',
    };

NodeSort nodeSortFromKey(String? key) => switch (key) {
      'delay' => NodeSort.delay,
      'name' => NodeSort.name,
      _ => NodeSort.original,
    };

/// 节点卡片/行的尺寸档位，对应菜单里的「尺寸」。
class _NodeScale {
  const _NodeScale({
    required this.cardPadding,
    required this.name,
    required this.meta,
    required this.gap,
    required this.icon,
    required this.radius,
  });

  final EdgeInsets cardPadding;
  final double name;
  final double meta;
  final double gap;
  final double icon;
  final double radius;

  static _NodeScale of(String? value) {
    return switch (value) {
      AppSettings.sizeLoose => const _NodeScale(
          cardPadding: EdgeInsets.fromLTRB(16, 15, 12, 14),
          name: 14,
          meta: 11.5,
          gap: 12,
          icon: 17,
          radius: 18,
        ),
      AppSettings.sizeCompact => const _NodeScale(
          cardPadding: EdgeInsets.fromLTRB(11, 9, 8, 9),
          name: 12,
          meta: 10,
          gap: 7,
          icon: 13,
          radius: 13,
        ),
      _ => const _NodeScale(
          cardPadding: EdgeInsets.fromLTRB(14, 13, 10, 12),
          name: 13,
          meta: 11,
          gap: 10,
          icon: 15,
          radius: 16,
        ),
    };
  }
}

/// 布局档位决定一屏放几列节点，窄屏时自动收回列数以免卡片过窄。
int _columnsFor(String? layout, double width) {
  final wanted = switch (layout) {
    AppSettings.sizeLoose => 1,
    AppSettings.sizeCompact => 3,
    _ => 2,
  };
  return wanted.clamp(1, max(1, (width / 168).floor()));
}

/// 桌面节点行更宽（延迟胶囊 + 测速按钮），按 250 逻辑像素估算最少列数。
int _desktopColumnsFor(String? layout, double width) {
  final wanted = switch (layout) {
    AppSettings.sizeLoose => 1,
    AppSettings.sizeCompact => 3,
    _ => 2,
  };
  return wanted.clamp(1, max(1, (width / 250).floor()));
}

/// 显示选项解析后的结果，桌面与移动共用。
class _NodeView {
  const _NodeView({
    required this.tabs,
    required this.layout,
    required this.scale,
    required this.hideTimeout,
    required this.nodes,
    required this.hiddenTimeout,
  });

  /// 风格：true=标签页，false=列表（分组卡片，展开后显示该组节点）。
  final bool tabs;
  final String layout;
  final _NodeScale scale;
  final bool hideTimeout;
  final List<String> nodes;
  final int hiddenTimeout;
}

class ProxyPage extends StatefulWidget {
  const ProxyPage({super.key});

  @override
  State<ProxyPage> createState() => _ProxyPageState();
}

class _ProxyPageState extends State<ProxyPage> {
  final TextEditingController _search = TextEditingController();
  String? _selectedGroup;

  /// 「列表」风格下展开了节点区的分组，可同时展开多个。
  final Set<String> _openGroups = {};
  bool _showSearch = false;
  String? _offlineKey;
  ProxiesSnapshot? _offlineSnapshot;
  Map<String, OfflineEndpoint> _offlineEndpoints = const {};
  // 延迟结果不放这里：页面 State 会随窗口跨断点重建，结果统一记在控制器里。
  final Set<String> _offlineTesting = {};
  bool _offlineBulkTesting = false;
  bool _offlineLoading = false;
  bool _offlineError = false;
  bool _offlineNoProfile = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _select(ProxyInfo group, String node) async {
    if (!group.isSelector) {
      await context.read<AppController>().testNode(node);
      return;
    }
    try {
      await context.read<AppController>().selectProxy(group, node);
    } catch (_) {}
  }

  Future<void> _selectOffline(ProxyInfo group, String node) async {
    if (!group.isSelector) {
      await _probeOfflineNode(node);
      return;
    }
    await context.read<AppController>().saveSelectionOffline(group, node);
    if (!mounted) return;
    final snapshot = _offlineSnapshot;
    if (snapshot != null) {
      setState(() {
        _offlineSnapshot = ProxiesSnapshot(
          proxies: snapshot.proxies,
          groups: [
            for (final item in snapshot.groups)
              if (item.name == group.name)
                ProxyInfo(
                  name: item.name,
                  type: item.type,
                  alive: item.alive,
                  now: node,
                  all: item.all,
                  delay: item.delay,
                  udp: item.udp,
                  xudp: item.xudp,
                  tfo: item.tfo,
                  provider: item.provider,
                )
              else
                item,
          ],
        );
      });
    }
    _toast(context.l10n.get('proxy.offlineSelected'));
  }

  void _ensureOffline(AppController controller) {
    final subscription = controller.activeSubscription;
    if (subscription == null) {
      if (_offlineKey != null) {
        _offlineKey = null;
        _offlineSnapshot = null;
        _offlineEndpoints = const {};
        _offlineTesting.clear();
        _offlineLoading = false;
        _offlineError = false;
        _offlineNoProfile = false;
      }
      return;
    }
    final key = '${subscription.id}|${subscription.lastUpdatedAt?.millisecondsSinceEpoch ?? 0}';
    if (key == _offlineKey) return;
    _offlineKey = key;
    _offlineLoading = true;
    _offlineError = false;
    _offlineNoProfile = false;
    _offlineSnapshot = null;
    _offlineEndpoints = const {};
    _offlineTesting.clear();
    final selections = controller.activeSelections;
    controller.store.readProfile(subscription.id).then((content) {
      if (!mounted || _offlineKey != key) return;
      OfflineProxiesResult? parsed;
      if (content != null) {
        parsed = OfflineProxies.parse(
          content,
          fallbackGroupName: 'PROXY',
          selections: selections,
        );
      }
      setState(() {
        _offlineSnapshot = parsed?.snapshot;
        _offlineEndpoints = parsed?.endpoints ?? const {};
        _offlineError = content != null && parsed == null;
        _offlineNoProfile = content == null;
        _offlineLoading = false;
      });
    });
  }

  Future<void> _probeOfflineNode(String name) async {
    final endpoint = _offlineEndpoints[name];
    if (endpoint == null || _offlineTesting.contains(name)) return;
    final controller = context.read<AppController>();
    final subscriptionId = controller.activeId;
    setState(() => _offlineTesting.add(name));
    final delay = await OfflineLatency.probe(endpoint);
    // 探测期间切了订阅，这条结果已经不属于当前页面；丢弃而不是写错订阅。
    if (controller.activeId != subscriptionId) return;
    // probe 只会给出正数或 -1；-1 在卡片上显示为超时。页面 State 可能已经
    // 因为跨断点重建而消失，结果仍要记进控制器，否则又退回未测速。
    controller.recordTestedDelay(name, delay ?? -1);
    if (!mounted) return;
    setState(() => _offlineTesting.remove(name));
  }

  Future<void> _probeOfflineGroup(ProxyInfo group) async {
    if (_offlineTesting.contains(group.name)) return;
    setState(() => _offlineTesting.add(group.name));
    final names = group.all.where(_offlineEndpoints.containsKey).toList();
    for (var i = 0; i < names.length; i += 6) {
      final batch = names.skip(i).take(6);
      await Future.wait(batch.map(_probeOfflineNode));
      if (!mounted) return;
    }
    if (!mounted) return;
    setState(() => _offlineTesting.remove(group.name));
  }

  Future<void> _probeOfflineAll(ProxiesSnapshot snapshot) async {
    if (_offlineBulkTesting) return;
    setState(() => _offlineBulkTesting = true);
    final names = <String>{
      for (final group in snapshot.groups) ...group.all,
    }.where(_offlineEndpoints.containsKey).toList();
    for (var i = 0; i < names.length; i += 8) {
      final batch = names.skip(i).take(8);
      await Future.wait(batch.map(_probeOfflineNode));
      if (!mounted) return;
    }
    if (!mounted) return;
    setState(() => _offlineBulkTesting = false);
  }

  void _reloadOffline() {
    setState(() {
      _offlineKey = null;
      _offlineSnapshot = null;
      _offlineEndpoints = const {};
      _offlineTesting.clear();
      _offlineBulkTesting = false;
      _offlineLoading = false;
      _offlineError = false;
      _offlineNoProfile = false;
    });
  }

  /// 订阅缓存缺失时离线页没有节点可预览，就地更新一次后再读缓存。
  Future<void> _updateOfflineSubscription(AppController controller) async {
    final subscription = controller.activeSubscription;
    if (subscription == null) return;
    final ok = await controller.ensureProfile(subscription);
    if (!mounted) return;
    // 静默更新失败不会弹提示，这里补一条，否则点按钮像没反应。
    if (!ok) _toast(context.l10n.get('subscriptions.fetchFailed'));
    _reloadOffline();
  }

  void _toast(String message) {
    showAppToast(context, message);
  }

  // ------------------------------------------------------------- 显示选项

  static String _nodeKey(String name) => 'proxy-node:$name';

  NodeSort _sortOf(AppController controller) => nodeSortFromKey(controller.settings.proxySort);

  Future<void> _setDisplay(
    AppController controller, {
    String? style,
    String? sort,
    String? layout,
    String? size,
    bool? hideTimeout,
  }) async {
    await controller.applySettings(controller.settings.copyWith(
      proxyStyle: style,
      proxySort: sort,
      proxyLayout: layout,
      proxyNodeSize: size,
      hideTimeoutProxies: hideTimeout,
    ));
  }

  bool _isTimeout(
    AppController controller,
    ProxiesSnapshot snapshot,
    String name, {
    required bool offline,
  }) {
    // 内核把超时节点的 delay 报成 0，ProxyInfo 统一记为 -1；离线 TCP 握手
    // 失败也写 -1，两种模式可以用同一个判断。
    final delay = controller.displayDelay(name);
    if (delay != null && delay < 0) return true;
    if (offline) return false;
    final info = snapshot.proxies[name];
    return info != null && !info.alive;
  }

  /// 搜索 + 隐藏超时 + 排序，桌面与移动共用一套结果。
  List<String> _visibleNodes({
    required AppController controller,
    required ProxyInfo group,
    required ProxiesSnapshot snapshot,
    required bool offline,
    required NodeSort sort,
  }) {
    final hideTimeout = controller.settings.hideTimeoutProxies;
    final query = _search.text.trim().toLowerCase();
    final nodes = group.all.where((node) {
      if (query.isNotEmpty && !node.toLowerCase().contains(query)) return false;
      if (hideTimeout && _isTimeout(controller, snapshot, node, offline: offline)) return false;
      return true;
    }).toList();
    if (sort != NodeSort.original) {
      int weight(int? value) => value == null || value < 0 ? 1 << 30 : value;
      nodes.sort((a, b) => sort == NodeSort.name
          ? a.toLowerCase().compareTo(b.toLowerCase())
          : weight(controller.displayDelay(a)).compareTo(weight(controller.displayDelay(b))));
    }
    return nodes;
  }

  int _hiddenTimeoutCount(
    AppController controller,
    ProxiesSnapshot snapshot,
    ProxyInfo group, {
    required bool offline,
  }) {
    if (!controller.settings.hideTimeoutProxies) return 0;
    return group.all.where((node) => _isTimeout(controller, snapshot, node, offline: offline)).length;
  }

  void _scrollToSelected(ProxyInfo? group, {bool expandCard = false}) {
    final name = group?.now;
    if (name == null || name.isEmpty) {
      _toast(context.l10n.get('proxy.noSelectedNode'));
      return;
    }
    if (expandCard) {
      final cardWasOpen = _openGroups.contains(group!.name);
      setState(() => _openGroups.add(group.name));
      if (cardWasOpen) {
        _scrollToNode(name);
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNode(name));
      }
      return;
    }
    _scrollToNode(name);
  }

  void _scrollToNode(String name) {
    final target = GlobalObjectKey(_nodeKey(name)).currentContext;
    // 被搜索或「隐藏超时代理」过滤掉时不在树上，此时不做跳转。
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      alignment: 0.12,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  _NodeView _nodeView(
    AppController controller,
    ProxyInfo? group,
    ProxiesSnapshot snapshot, {
    required bool offline,
    required bool desktop,
  }) {
    final settings = controller.settings;
    final sort = _sortOf(controller);
    return _NodeView(
      tabs: settings.resolvedProxyStyle(desktop: desktop) == AppSettings.styleTabs,
      layout: settings.resolvedProxyLayout(desktop: desktop),
      scale: _NodeScale.of(settings.resolvedProxyNodeSize()),
      hideTimeout: settings.hideTimeoutProxies,
      nodes: group == null
          ? const []
          : _visibleNodes(
              controller: controller,
              group: group,
              snapshot: snapshot,
              offline: offline,
              sort: sort,
            ),
      hiddenTimeout:
          group == null ? 0 : _hiddenTimeoutCount(controller, snapshot, group, offline: offline),
    );
  }

  /// 「隐藏超时代理」生效时，在列表下方说明被收起来的数量，避免误以为节点丢失。
  Widget? _timeoutHint(L10n l10n, AppPalette palette, _NodeView view) {
    if (!view.hideTimeout || view.hiddenTimeout == 0) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          AppIcon('eye-off-line', size: 14, color: palette.muted),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              l10n.get('proxy.timeoutHidden', [view.hiddenTimeout]),
              style: TextStyle(fontSize: 11.5, color: palette.muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _displayMenu(
    AppController controller,
    ProxyInfo? group, {
    required bool desktop,
    required Widget Function(BuildContext context, VoidCallback toggle) builder,
  }) {
    final settings = controller.settings;
    return DisplayMenu(
      style: settings.resolvedProxyStyle(desktop: desktop),
      sort: _sortOf(controller),
      layout: settings.resolvedProxyLayout(desktop: desktop),
      size: settings.resolvedProxyNodeSize(),
      hideTimeout: settings.hideTimeoutProxies,
      onStyle: (value) => _setDisplay(controller, style: value),
      onSort: (value) => _setDisplay(controller, sort: nodeSortKey(value)),
      onLayout: (value) => _setDisplay(controller, layout: value),
      onSize: (value) => _setDisplay(controller, size: value),
      onHideTimeout: () => _setDisplay(controller, hideTimeout: !settings.hideTimeoutProxies),
      onScrollToSelected: () => _scrollToSelected(
        group,
        expandCard: settings.resolvedProxyStyle(desktop: desktop) == AppSettings.styleList,
      ),
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    final mobile = MediaQuery.sizeOf(context).width < appDesktopBreakpoint;
    // 预览内核在线时节点列表与延迟都来自真实代理；只有内核完全没起才退回离线快照。
    final offline = !controller.coreOnline;
    if (mobile) {
      if (offline) _ensureOffline(controller);
      final snapshot = offline
          ? (_offlineSnapshot ?? const ProxiesSnapshot(proxies: {}, groups: []))
          : controller.proxySnapshot;
      return _buildMobilePage(
        context,
        controller,
        snapshot: snapshot,
        offline: offline,
      );
    }
    if (offline) _ensureOffline(controller);
    final snapshot = offline
        ? (_offlineSnapshot ?? const ProxiesSnapshot(proxies: {}, groups: []))
        : controller.proxySnapshot;
    final groups = snapshot.groups;

    if (offline && groups.isEmpty) {
      final starting = controller.phase == CorePhase.starting;
      return PageContainer(
        children: [
          PageHeader(
            title: l10n.get('nav.proxy'),
            subtitle: l10n.get('proxy.notRunning'),
            actions: [
              FilledButton.icon(
                onPressed: controller.isBusy ? null : controller.toggleCore,
                icon: const AppIcon('play-circle-line', size: 15),
                label: Text(l10n.get('common.start')),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SurfaceCard(
            child: _offlineLoading || starting
                ? const LoadingBlock(height: 180)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_offlineNoProfile) ...[
                        InfoBanner(
                          message: l10n.get('proxy.offlineNoProfile'),
                          color: palette.warning,
                          icon: 'information-line',
                        ),
                        const SizedBox(height: 10),
                      ] else if (_offlineError) ...[
                        InfoBanner(
                          message: l10n.get('proxy.offlineLoadFailed'),
                          color: palette.danger,
                          icon: 'close-circle-line',
                        ),
                        const SizedBox(height: 10),
                      ],
                      EmptyState(
                        icon: 'shield-shape-line',
                        title: l10n.get('proxy.offlineEmpty'),
                        message: controller.activeSubscription == null
                            ? l10n.get('proxy.offlineNoSubscription')
                            : l10n.get('proxy.offlineHint'),
                        actions: [
                          if (controller.activeSubscription == null)
                            FilledButton(
                              onPressed: () => AppNavigation.goTab(context, 2),
                              child: Text(l10n.get('home.manageSubscription')),
                            )
                          else if (_offlineNoProfile)
                            FilledButton(
                              onPressed: controller.updatingSubscriptions.contains(controller.activeId)
                                  ? null
                                  : () => _updateOfflineSubscription(controller),
                              child: Text(l10n.get('proxy.offlineUpdate')),
                            )
                          else
                            OutlinedButton(
                              onPressed: _reloadOffline,
                              child: Text(l10n.get('common.refresh')),
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      );
    }

    if (groups.isEmpty) {
      return PageContainer(
        children: [
          PageHeader(
            title: l10n.get('nav.proxy'),
            subtitle: l10n.get('proxy.noGroups'),
          ),
          const SizedBox(height: 18),
          SurfaceCard(
            child: controller.loadingProxies
                ? const LoadingBlock(height: 180)
                : EmptyState(
                    icon: 'shield-shape-line',
                    title: l10n.get('proxy.noGroups'),
                    message: l10n.get('proxy.noGroupsHint'),
                  ),
          ),
        ],
      );
    }

    final group = groups.firstWhere(
      (item) => item.name == _selectedGroup,
      orElse: () => snapshot.primaryGroup() ?? groups.first,
    );

    final tabs = controller.settings.resolvedProxyStyle(desktop: true) == AppSettings.styleTabs;
    return PageContainer(
      children: [
        PageHeader(
          title: l10n.get('nav.proxy'),
          subtitle: l10n.get('proxy.groups', [groups.length]),
          actions: [
            if (!tabs)
              AppIconButton(
                icon: 'search-line',
                size: 18,
                padding: 9,
                background: palette.cardAlt,
                tooltip: l10n.get('common.search'),
                onTap: _toggleSearch,
              ),
            _testAllButton(controller, snapshot, offline: offline, desktop: true),
            const SizedBox(width: 8),
            _displayMenuButton(controller, group, desktop: true, size: 18, padding: 9),
          ],
        ),
        if (offline) ...[
          const SizedBox(height: 14),
          InfoBanner(
            message: l10n.get('proxy.offlineTcpHint'),
            color: Theme.of(context).colorScheme.primary,
            actions: [
              TextButton(
                onPressed: controller.isBusy ? null : controller.toggleCore,
                child: Text(l10n.get('common.start')),
              ),
            ],
          ),
        ] else if (controller.isPreviewing) ...[
          const SizedBox(height: 14),
          InfoBanner(
            message: l10n.get('proxy.previewHint'),
            color: palette.success,
            icon: 'information-line',
          ),
        ],
        if (!offline && controller.proxyError != null) ...[
          const SizedBox(height: 14),
          InfoBanner(
            message: controller.proxyError!.localized(l10n),
            color: palette.danger,
            icon: 'close-circle-line',
          ),
        ],
        const SizedBox(height: 18),
        if (!tabs && _showSearch) ...[
          AppSearchField(
            controller: _search,
            autofocus: true,
            hint: l10n.get('proxy.searchNodes'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
        ],
        if (tabs)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _groupTabBar(snapshot, group),
              const SizedBox(height: 12),
              _buildGroupPanel(
                context,
                controller,
                group,
                snapshot,
                offline: offline,
                view: _nodeView(controller, group, snapshot, offline: offline, desktop: true),
              ),
            ],
          )
        else
          _buildGroupCards(controller, snapshot, offline: offline, mobile: false),
      ],
    );
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) _search.clear();
    });
  }

  /// 「标签页」风格的分组条：文字标签 + 下划线指示器，点标签切换下方节点区。
  Widget _groupTabBar(ProxiesSnapshot snapshot, ProxyInfo selected) {
    return _GroupTabBar(
      groups: snapshot.groups,
      selected: selected.name,
      onSelect: (name) => setState(() => _selectedGroup = name),
    );
  }

  Widget _buildMobilePage(
    BuildContext context,
    AppController controller, {
    required ProxiesSnapshot snapshot,
    required bool offline,
  }) {
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    final groups = snapshot.groups;
    final query = _search.text.trim().toLowerCase();
    ProxyInfo? group;
    if (groups.isNotEmpty) {
      group = groups.firstWhere(
        (item) => item.name == _selectedGroup,
        orElse: () => snapshot.primaryGroup() ?? groups.first,
      );
    }
    final view = _nodeView(controller, group, snapshot, offline: offline, desktop: false);
    final nodes = view.nodes;
    return PageContainer(
      children: [
        MobilePageHeader(
          title: l10n.get('proxy.title'),
          subtitle: view.tabs
              ? null
              : offline
                  ? l10n.get('proxy.offlineHint')
                  : l10n.get('proxy.groups', [groups.length]),
          actions: [
            AppIconButton(
              icon: 'search-line',
              size: 20,
              padding: 7,
              tooltip: l10n.get('common.search'),
              onTap: groups.isEmpty ? null : _toggleSearch,
            ),
            const SizedBox(width: 6),
            _testAllButton(controller, snapshot, offline: offline, desktop: false),
            const SizedBox(width: 6),
            _displayMenuButton(controller, group, desktop: false, size: 20, padding: 7),
          ],
        ),
        const SizedBox(height: 14),
        if (controller.isPreviewing) ...[
          InfoBanner(
            message: l10n.get('proxy.previewHint'),
            color: palette.success,
            icon: 'information-line',
          ),
          const SizedBox(height: 12),
        ],
        if (group != null && view.tabs) ...[
          _groupTabBar(snapshot, group),
          if (offline)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                l10n.get('proxy.offlineHint'),
                style: TextStyle(fontSize: 12, height: 1.4, color: palette.muted),
              ),
            ),
        ],
        if (_showSearch && group != null) ...[
          const SizedBox(height: 12),
          AppSearchField(
            controller: _search,
            autofocus: true,
            hint: l10n.get('proxy.searchNodes'),
            onChanged: (_) => setState(() {}),
          ),
        ],
        if (!offline && controller.proxyError != null) ...[
          const SizedBox(height: 14),
          InfoBanner(
            message: controller.proxyError!.localized(l10n),
            color: palette.danger,
            icon: 'close-circle-line',
            dense: true,
          ),
        ],
        const SizedBox(height: 16),
        if (offline && _offlineLoading && groups.isEmpty)
          const SurfaceCard(child: LoadingBlock(height: 150))
        else if (offline && groups.isEmpty)
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_offlineNoProfile) ...[
                  InfoBanner(
                    message: l10n.get('proxy.offlineNoProfile'),
                    color: palette.warning,
                    icon: 'information-line',
                    dense: true,
                  ),
                  const SizedBox(height: 8),
                ] else if (_offlineError) ...[
                  InfoBanner(
                    message: l10n.get('proxy.offlineLoadFailed'),
                    color: palette.danger,
                    icon: 'close-circle-line',
                    dense: true,
                  ),
                  const SizedBox(height: 8),
                ],
                EmptyState(
                  compact: true,
                  icon: 'shield-shape-line',
                  title: l10n.get('proxy.offlineEmpty'),
                  message: controller.activeSubscription == null
                      ? l10n.get('proxy.offlineNoSubscription')
                      : l10n.get('proxy.offlineHint'),
                  actions: [
                    if (controller.activeSubscription == null)
                      FilledButton(
                        onPressed: () => AppNavigation.goTab(context, 2),
                        child: Text(l10n.get('home.manageSubscription')),
                      )
                    else if (_offlineNoProfile)
                      FilledButton(
                        onPressed: controller.updatingSubscriptions.contains(controller.activeId)
                            ? null
                            : () => _updateOfflineSubscription(controller),
                        child: Text(l10n.get('proxy.offlineUpdate')),
                      )
                    else ...[
                      FilledButton(
                        onPressed: controller.isBusy ? null : controller.toggleCore,
                        child: Text(l10n.get('common.start')),
                      ),
                      OutlinedButton(
                        onPressed: _reloadOffline,
                        child: Text(l10n.get('common.refresh')),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          )
        else if (group == null)
          SurfaceCard(
            child: controller.loadingProxies
                ? const LoadingBlock(height: 180)
                : EmptyState(
                    icon: 'shield-shape-line',
                    title: l10n.get('proxy.noGroups'),
                    message: l10n.get('proxy.noGroupsHint'),
                  ),
          )
        else if (!view.tabs)
          _buildGroupCards(controller, snapshot, offline: offline, mobile: true)
        else ...[
          if (nodes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Center(
                child: Text(
                  query.isEmpty ? l10n.get('proxy.emptyGroup') : l10n.get('proxy.filterNoResult'),
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
              ),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 12.0;
                final columns = _columnsFor(view.layout, constraints.maxWidth);
                final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final name in nodes)
                      SizedBox(
                        width: width,
                        child: _MobileNodeCard(
                          key: GlobalObjectKey(_nodeKey(name)),
                          name: name,
                          type: snapshot.proxies[name]?.type ?? '',
                          selected: group!.now == name,
                          delay: controller.displayDelay(name),
                          testing: offline
                              ? _offlineTesting.contains(name)
                              : controller.testingNodes.contains(name),
                          scale: view.scale,
                          onTap: () => offline ? _selectOffline(group!, name) : _select(group!, name),
                          onTest: offline
                              ? () => _probeOfflineNode(name)
                              : () => controller.testNode(name),
                        ),
                      ),
                  ],
                );
              },
            ),
            ?_timeoutHint(l10n, palette, view),
          ],
        ],
      ],
    );
  }

  // ------------------------------------------------------- 列表风格分组卡片

  Widget _buildGroupCards(
    AppController controller,
    ProxiesSnapshot snapshot, {
    required bool offline,
    required bool mobile,
  }) {
    final groups = snapshot.groups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _buildGroupCard(controller, snapshot, groups[i], offline: offline, mobile: mobile),
        ],
      ],
    );
  }

  /// 分组卡片：标题 + 「类型 · 当前节点 · 已测/总数」，右侧延迟与展开按钮。
  /// 展开后在该卡片内显示节点，布局与尺寸沿用显示选项。
  Widget _buildGroupCard(
    AppController controller,
    ProxiesSnapshot snapshot,
    ProxyInfo group, {
    required bool offline,
    required bool mobile,
  }) {
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    final settings = controller.settings;
    final layout = settings.resolvedProxyLayout(desktop: !mobile);
    final scale = _NodeScale.of(settings.resolvedProxyNodeSize());
    final searching = _search.text.trim().isNotEmpty;
    final nodes = _visibleNodes(
      controller: controller,
      group: group,
      snapshot: snapshot,
      offline: offline,
      sort: _sortOf(controller),
    );
    final view = _NodeView(
      tabs: false,
      layout: layout,
      scale: scale,
      hideTimeout: settings.hideTimeoutProxies,
      nodes: nodes,
      hiddenTimeout: _hiddenTimeoutCount(controller, snapshot, group, offline: offline),
    );
    // 搜索时自动展开有命中的分组，避免结果藏在折叠卡片里。
    final expanded = _openGroups.contains(group.name) || (searching && nodes.isNotEmpty);
    final now = group.now;
    ProxyInfo? inlineGroup;
    for (final item in snapshot.groups) {
      if (item.name == now) {
        inlineGroup = item;
        break;
      }
    }
    int? delayOf(String name) => controller.displayDelay(name);
    final tested = group.all.where((name) {
      final delay = delayOf(name);
      return delay != null && delay >= 0;
    }).length;
    final testingGroup = offline
        ? _offlineTesting.contains(group.name)
        : controller.testingGroups.contains(group.name);
    final typeLabel = l10n.get(group.groupTypeKey);
    final metaStyle = TextStyle(fontSize: mobile ? 12.5 : 12, color: palette.muted, height: 1.3);

    void toggle() {
      setState(() {
        if (!_openGroups.remove(group.name)) _openGroups.add(group.name);
      });
    }

    final avatarChar = group.name.isEmpty ? '?' : String.fromCharCode(group.name.runes.first);
    final titleIcon = _groupCardIcon(group);
    final subtitleIcon = inlineGroup == null ? '' : _groupCardIcon(inlineGroup);

    Widget avatar(double size) => Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.cardAlt,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            avatarChar,
            style: TextStyle(
              fontSize: size * 0.42,
              fontWeight: FontWeight.w700,
              color: palette.strongMuted,
            ),
          ),
        );

    Widget chevronButton() => Material(
          color: palette.cardAlt,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: toggle,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: mobile ? 38 : 36,
              height: mobile ? 38 : 36,
              child: Center(
                child: AnimatedRotation(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  turns: expanded ? 0.5 : 0,
                  child: AppIcon('down-small-line', size: 16, color: palette.strongMuted),
                ),
              ),
            ),
          ),
        );

    final titleBlock = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (titleIcon.isNotEmpty) ...[
                AppIcon(titleIcon, size: mobile ? 16 : 15, color: palette.success),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: mobile ? 17 : 16,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: palette.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (subtitleIcon.isNotEmpty) ...[
                AppIcon(subtitleIcon, size: 13, color: palette.success),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  now.isEmpty ? l10n.get('proxy.noSelection') : now,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: metaStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final heading = Padding(
      padding: mobile
          ? const EdgeInsets.fromLTRB(16, 14, 14, 14)
          : const EdgeInsets.fromLTRB(18, 15, 14, 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          avatar(mobile ? 42 : 40),
          const SizedBox(width: 12),
          titleBlock,
          const SizedBox(width: 12),
          if (expanded)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIconButton(
                  icon: 'focus-line',
                  size: 16,
                  padding: mobile ? 10 : 9,
                  background: palette.cardAlt,
                  tooltip: l10n.get('proxy.menu.scrollToSelected'),
                  onTap: () => _scrollToSelected(group, expandCard: true),
                ),
                const SizedBox(width: 8),
                AppIconButton(
                  icon: 'lightning-line',
                  size: 16,
                  padding: mobile ? 10 : 9,
                  background: palette.cardAlt,
                  tooltip: l10n.get('proxy.testGroup'),
                  onTap: testingGroup
                      ? null
                      : () => offline ? _probeOfflineGroup(group) : controller.testGroup(group),
                ),
                const SizedBox(width: 8),
                chevronButton(),
              ],
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: l10n.get('proxy.testedCount', [tested, group.all.length]),
                  child: Text(
                    typeLabel,
                    style: TextStyle(
                      fontSize: mobile ? 13 : 12.5,
                      fontWeight: FontWeight.w600,
                      color: palette.strongMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                chevronButton(),
              ],
            ),
        ],
      ),
    );

    Widget? expandedBody;
    if (expanded) {
      expandedBody = Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (nodes.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  searching ? l10n.get('proxy.filterNoResult') : l10n.get('proxy.emptyGroup'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final spacing = mobile ? 10.0 : 8.0;
                  final columns = mobile
                      ? _columnsFor(layout, constraints.maxWidth)
                      : _desktopColumnsFor(layout, constraints.maxWidth);
                  final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final name in nodes)
                        SizedBox(
                          width: width,
                          child: mobile
                              ? _MobileNodeCard(
                                  key: GlobalObjectKey(_nodeKey(name)),
                                  name: name,
                                  type: snapshot.proxies[name]?.type ?? '',
                                  selected: now == name,
                                  delay: delayOf(name),
                                  testing: offline
                                      ? _offlineTesting.contains(name)
                                      : controller.testingNodes.contains(name),
                                  scale: scale,
                                  onTap: () => offline ? _selectOffline(group, name) : _select(group, name),
                                  onTest: () =>
                                      offline ? _probeOfflineNode(name) : controller.testNode(name),
                                )
                              : _NodeTile(
                                  key: GlobalObjectKey(_nodeKey(name)),
                                  name: name,
                                  type: snapshot.proxies[name]?.type ?? '',
                                  selected: now == name,
                                  delay: delayOf(name),
                                  testing: offline
                                      ? _offlineTesting.contains(name)
                                      : controller.testingNodes.contains(name),
                                  scale: scale,
                                  onSelect: offline ? () => _selectOffline(group, name) : () => _select(group, name),
                                  onTest: () => offline ? _probeOfflineNode(name) : controller.testNode(name),
                                ),
                        ),
                    ],
                  );
                },
              ),
            ?_timeoutHint(l10n, palette, view),
          ],
        ),
      );
    }

    return SurfaceCard(
      padding: EdgeInsets.zero,
      radius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(onTap: toggle, hoverColor: palette.hover, child: heading),
          ),
          ?expandedBody,
        ],
      ),
    );
  }

  /// 页面右上角的显示选项入口，桌面与移动共用同一个浮层。
  Widget _displayMenuButton(
    AppController controller,
    ProxyInfo? group, {
    required bool desktop,
    required double size,
    required double padding,
  }) {
    return _displayMenu(
      controller,
      group,
      desktop: desktop,
      builder: (context, toggle) => AppIconButton(
        icon: 'more-1-line',
        size: size,
        padding: padding,
        background: AppPalette.of(context).cardAlt,
        tooltip: context.t('proxy.menu'),
        onTap: group == null ? null : toggle,
      ),
    );
  }

  /// 「测速全部」在头部只留图标，避免胶囊把标题行撑宽。
  Widget _testAllButton(
    AppController controller,
    ProxiesSnapshot snapshot, {
    required bool offline,
    required bool desktop,
  }) {
    final testing = offline ? _offlineBulkTesting : controller.bulkTesting;
    final size = desktop ? 18.0 : 20.0;
    final padding = desktop ? 9.0 : 7.0;
    if (testing) {
      return SizedBox(
        width: size + padding * 2,
        height: size + padding * 2,
        child: const Center(
          child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    return AppIconButton(
      icon: 'speed-line',
      size: size,
      padding: padding,
      background: desktop ? AppPalette.of(context).cardAlt : null,
      tooltip: context.t('proxy.testAll'),
      onTap: snapshot.groups.isEmpty
          ? null
          : () {
              if (offline) {
                _probeOfflineAll(snapshot);
              } else {
                controller.testAllGroups();
              }
            },
    );
  }

  Widget _buildGroupPanel(
    BuildContext context,
    AppController controller,
    ProxyInfo group,
    ProxiesSnapshot snapshot, {
    required bool offline,
    required _NodeView view,
  }) {
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    final query = _search.text.trim().toLowerCase();
    final nodes = view.nodes;
    final now = group.now;
    final nowDelay = now.isEmpty ? null : controller.displayDelay(now);
    return SurfaceCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: AppIcon('shield-shape-line', size: 18, color: Theme.of(context).colorScheme.primary),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AppBadge(text: l10n.get(group.groupTypeKey), dense: true),
                        AppBadge(text: l10n.get('proxy.nodes', [group.all.length]), dense: true),
                        if (now.isNotEmpty)
                          AppBadge(
                            text: l10n.get('proxy.current'),
                            icon: 'check-line',
                            dense: true,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (now.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: palette.cardAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: palette.border),
              ),
              child: Row(
                children: [
                  AppIcon('pin-line', size: 15, color: palette.muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      now,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                  DelayChip(
                    delay: nowDelay,
                    testing: offline ? _offlineTesting.contains(now) : controller.testingNodes.contains(now),
                    dense: true,
                    onTap: () => offline ? _probeOfflineNode(now) : controller.testNode(now),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              hintText: l10n.get('proxy.searchNodes'),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(left: 12, right: 6),
                child: Icon(Icons.search, size: 17),
              ),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () {
                        _search.clear();
                        setState(() {});
                      },
                    ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            ),
          ),
          const SizedBox(height: 12),
          if (nodes.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 26),
              child: Center(
                child: Text(
                  query.isEmpty ? l10n.get('proxy.emptyGroup') : l10n.get('proxy.filterNoResult'),
                  style: TextStyle(fontSize: 12, color: palette.muted),
                ),
              ),
            )
          else ...[
            LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                final columns = _desktopColumnsFor(view.layout, constraints.maxWidth);
                final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final name in nodes)
                      SizedBox(
                        width: width,
                        child: _NodeTile(
                          key: GlobalObjectKey(_nodeKey(name)),
                          name: name,
                          type: snapshot.proxies[name]?.type ?? '',
                          selected: now == name,
                          delay: controller.displayDelay(name),
                          testing:
                              offline ? _offlineTesting.contains(name) : controller.testingNodes.contains(name),
                          scale: view.scale,
                          onSelect: offline ? () => _selectOffline(group, name) : () => _select(group, name),
                          onTest: offline ? () => _probeOfflineNode(name) : () => controller.testNode(name),
                        ),
                      ),
                  ],
                );
              },
            ),
            ?_timeoutHint(l10n, palette, view),
          ],
        ],
      ),
    );
  }
}

/// 列表卡片标题前的类型图标；手动选择不显示，与参考稿一致。
String _groupCardIcon(ProxyInfo group) => _typeIcon(group.type);

String _typeIcon(String type) {
  return switch (type.toLowerCase()) {
    'urltest' || 'url-test' => 'refresh-2-line',
    'fallback' => 'transfer-line',
    'loadbalance' || 'load-balance' => 'grid-line',
    'relay' => 'link-line',
    _ => '',
  };
}

/// 「标签页」风格的分组条：参考 FlClash 的单行横向滚动胶囊标签，选中项实心
/// 强调色填充、其余用卡片底色；分组多时左右滚动而不是换行堆叠。
class _GroupTabBar extends StatelessWidget {
  const _GroupTabBar({
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  final List<ProxyInfo> groups;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        key: const ValueKey('proxy-group-tab-bar'),
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final group = groups[index];
          return Center(
            child: _GroupTabItem(
              group: group,
              selected: group.name == selected,
              onTap: () => onSelect(group.name),
            ),
          );
        },
      ),
    );
  }
}

class _GroupTabItem extends StatelessWidget {
  const _GroupTabItem({
    required this.group,
    required this.selected,
    required this.onTap,
  });

  final ProxyInfo group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: selected ? accent : palette.cardAlt,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: palette.hover,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              group.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? palette.onAccent : palette.strongMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileNodeCard extends StatelessWidget {
  const _MobileNodeCard({
    super.key,
    required this.name,
    required this.type,
    required this.selected,
    required this.delay,
    required this.testing,
    required this.onTap,
    required this.onTest,
    required this.scale,
  });

  final String name;
  final String type;
  final bool selected;
  final int? delay;
  final bool testing;
  final VoidCallback onTap;
  final VoidCallback onTest;
  final _NodeScale scale;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final accent = Theme.of(context).colorScheme.primary;
    final delayLabel = delay == null ? '—' : formatDelay(delay!, zh: l10n.isZh);
    final typeIcon = _typeIcon(type);
    return SurfaceCard(
      padding: scale.cardPadding,
      radius: scale.radius,
      color: palette.cardAlt,
      elevated: false,
      border: Border.all(color: Colors.transparent),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (typeIcon.isNotEmpty) ...[
                AppIcon(typeIcon, size: scale.icon, color: palette.success),
                const SizedBox(width: 5),
              ],
              Expanded(
                child: Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: scale.name,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: palette.text,
                    height: 1.25,
                  ),
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 6),
                Container(
                  width: scale.icon + 8,
                  height: scale.icon + 8,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: Center(
                    child: AppIcon('check-line', size: scale.icon - 2, color: palette.onAccent),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: scale.gap),
          Row(
            children: [
              Expanded(
                child: Text(
                  type.isEmpty ? '—' : type,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: scale.meta, color: palette.muted),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTest,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                  child: testing
                      ? SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: palette.delayColor(delay)),
                        )
                      : Text(
                          delayLabel,
                          style: TextStyle(
                            fontSize: scale.meta + 0.5,
                            fontWeight: FontWeight.w600,
                            color: palette.delayColor(delay),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NodeTile extends StatelessWidget {
  const _NodeTile({
    super.key,
    required this.name,
    required this.type,
    required this.selected,
    required this.delay,
    required this.testing,
    required this.onSelect,
    required this.onTest,
    required this.scale,
  });

  final String name;
  final String type;
  final bool selected;
  final int? delay;
  final bool testing;
  final VoidCallback onSelect;
  final VoidCallback onTest;
  final _NodeScale scale;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final accent = Theme.of(context).colorScheme.primary;
    final delayLabel = delay == null ? '—' : formatDelay(delay!, zh: l10n.isZh);
    final typeIcon = _typeIcon(type);
    return Material(
      color: palette.cardAlt,
      borderRadius: BorderRadius.circular(scale.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(scale.radius),
        hoverColor: palette.hover,
        child: Padding(
          padding: scale.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  if (typeIcon.isNotEmpty) ...[
                    AppIcon(typeIcon, size: scale.icon, color: palette.success),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: scale.name,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: palette.text,
                        height: 1.25,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    Container(
                      width: scale.icon + 8,
                      height: scale.icon + 8,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                      child: Center(
                        child: AppIcon('check-line', size: scale.icon - 2, color: palette.onAccent),
                      ),
                    ),
                  ],
                ],
              ),
              SizedBox(height: scale.gap),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      type.isEmpty ? '—' : type,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: scale.meta, color: palette.muted),
                    ),
                  ),
                  Tooltip(
                    message: l10n.get('common.test'),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onTest,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                        child: testing
                            ? SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: palette.delayColor(delay),
                                ),
                              )
                            : Text(
                                delayLabel,
                                style: TextStyle(
                                  fontSize: scale.meta + 0.5,
                                  fontWeight: FontWeight.w600,
                                  color: palette.delayColor(delay),
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 代理页右上角的显示选项：滚动到已选 / 风格 / 排序 / 布局 / 尺寸 / 隐藏超时代理。
class DisplayMenu extends StatefulWidget {
  const DisplayMenu({
    super.key,
    required this.style,
    required this.sort,
    required this.layout,
    required this.size,
    required this.hideTimeout,
    required this.onStyle,
    required this.onSort,
    required this.onLayout,
    required this.onSize,
    required this.onHideTimeout,
    required this.onScrollToSelected,
    required this.builder,
  });

  final String style;
  final NodeSort sort;
  final String layout;
  final String size;
  final bool hideTimeout;
  final ValueChanged<String> onStyle;
  final ValueChanged<NodeSort> onSort;
  final ValueChanged<String> onLayout;
  final ValueChanged<String> onSize;
  final VoidCallback onHideTimeout;
  final VoidCallback onScrollToSelected;
  final Widget Function(BuildContext context, VoidCallback toggle) builder;

  @override
  State<DisplayMenu> createState() => DisplayMenuState();
}

class DisplayMenuState extends State<DisplayMenu> {
  final MenuController _menu = MenuController();

  // 每个二级菜单单独持有控制器：只允许点击展开，并保证同时只开一个。
  final Map<String, MenuController> _subControllers = {};

  static const double _rowWidth = 168;
  // 二级选项行现在带前置图标，比纯文字宽出图标 16 + 间距 10。
  static const double _subRowWidth = 138;
  static const double _edgeInset = 16;
  // 二级菜单箭头连同间距会把菜单行撑宽 28，一级行统一预留这段宽度。
  static const double _submenuGap = 28;
  // 菜单宽 = 行内容 + 二级箭头 + 菜单行左右 16 + 浮层左右 8（与 appMenuStyle/appMenuItemStyle 一致）。
  static const double _menuWidth = _rowWidth + _submenuGap + 16 * 2 + 8 * 2;

  MenuController _subController(String key) => _subControllers.putIfAbsent(key, MenuController.new);

  void _handleSubmenuOpen(String key) {
    _subControllers.forEach((name, controller) {
      if (name != key) controller.close();
    });
  }

  /// 分组之间的细线；菜单本身是浮层，用边框色即可。
  Widget _divider(AppPalette palette) => Divider(
        height: 13,
        thickness: 1,
        indent: 6,
        endIndent: 6,
        color: palette.border,
      );

  /// 「宽松/标准/紧凑」在布局和尺寸两个子菜单里含义不同，图标由调用方指定。
  static List<({String value, String label, String icon})> _scaleOptions(
    L10n l10n, {
    required String loose,
    required String standard,
    required String compact,
  }) =>
      [
        (value: AppSettings.sizeLoose, label: l10n.get('proxy.size.loose'), icon: loose),
        (value: AppSettings.sizeStandard, label: l10n.get('proxy.size.standard'), icon: standard),
        (value: AppSettings.sizeCompact, label: l10n.get('proxy.size.compact'), icon: compact),
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    return MenuAnchor(
      controller: _menu,
      reservedPadding: const EdgeInsets.all(_edgeInset),
      // 入口在页面右上角：菜单与按钮右缘对齐、向下展开。
      alignmentOffset: const Offset(-(_menuWidth + 8), 6),
      style: appMenuStyle(palette).copyWith(alignment: AlignmentDirectional.bottomEnd),
      menuChildren: [
        _entry(
          context,
          icon: 'focus-line',
          label: l10n.get('proxy.menu.scrollToSelected'),
          // 需要看到滚动结果，这一项点完收起浮层。
          closeOnActivate: true,
          onPressed: widget.onScrollToSelected,
        ),
        _divider(palette),
        _submenu(
          context,
          id: 'style',
          icon: 'list-check-line',
          label: l10n.get('proxy.menu.style'),
          selected: widget.style,
          options: [
            (
              value: AppSettings.styleTabs,
              label: l10n.get('proxy.style.tabs'),
              icon: 'layout-tabs-line'
            ),
            (
              value: AppSettings.styleList,
              label: l10n.get('proxy.style.list'),
              icon: 'layout-sidebar-line'
            ),
          ],
          onSelected: widget.onStyle,
        ),
        _submenu(
          context,
          id: 'sort',
          icon: 'sort-ascending-line',
          label: l10n.get('proxy.menu.sort'),
          selected: nodeSortKey(widget.sort),
          options: [
            (value: 'default', label: l10n.get('proxy.sort.default'), icon: 'order-default-line'),
            (value: 'delay', label: l10n.get('proxy.sort.delay'), icon: 'lightning-line'),
            (value: 'name', label: l10n.get('proxy.sort.name'), icon: 'sort-alpha-line'),
          ],
          onSelected: (value) => widget.onSort(nodeSortFromKey(value)),
        ),
        _submenu(
          context,
          id: 'layout',
          icon: 'grid-line',
          label: l10n.get('proxy.menu.layout'),
          selected: widget.layout,
          options: _scaleOptions(
            l10n,
            loose: 'columns-1-line',
            standard: 'columns-2-line',
            compact: 'columns-3-line',
          ),
          onSelected: widget.onLayout,
        ),
        _submenu(
          context,
          id: 'size',
          icon: 'translate-line',
          label: l10n.get('proxy.menu.size'),
          selected: widget.size,
          options: _scaleOptions(
            l10n,
            loose: 'line-spacing-loose-line',
            standard: 'line-spacing-standard-line',
            compact: 'line-spacing-compact-line',
          ),
          onSelected: widget.onSize,
        ),
        _divider(palette),
        _entry(
          context,
          icon: 'eye-off-line',
          label: l10n.get('proxy.menu.hideTimeout'),
          onPressed: widget.onHideTimeout,
          checked: widget.hideTimeout,
        ),
      ],
      builder: (context, controller, child) => widget.builder(
        context,
        () => controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }

  Widget _entry(
    BuildContext context, {
    required String icon,
    required String label,
    required VoidCallback? onPressed,
    bool checked = false,
    bool closeOnActivate = false,
  }) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final color = checked ? accent : palette.text;
    return MenuItemButton(
      onPressed: onPressed,
      closeOnActivate: closeOnActivate,
      style: appMenuItemStyle(palette),
      child: SizedBox(
        width: _rowWidth + _submenuGap,
        child: Row(
          children: [
            AppIcon(icon, size: 17, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: color),
              ),
            ),
            if (checked) ...[
              const SizedBox(width: 10),
              AppIcon('check-line', size: 17, color: accent),
            ],
          ],
        ),
      ),
    );
  }

  Widget _submenu(
    BuildContext context, {
    required String id,
    required String icon,
    required String label,
    required String selected,
    required List<({String value, String label, String icon})> options,
    required ValueChanged<String> onSelected,
  }) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final controller = _subController(id);
    // 不用 SubmenuButton：它悬停时必定抢焦点，焦点被相邻菜单行拿走就自动收起。
    // 这里用嵌套 MenuAnchor，只响应点击，悬停到别处不会关闭；打开的兄弟子菜单
    // 会由 MenuAnchor.open 自动收起，点击浮层外则由根菜单统一关闭。
    return MenuAnchor(
      controller: controller,
      onOpen: () => _handleSubmenuOpen(id),
      // 子菜单自身已有 8px 内边距，这里不再预留额外的边缘间距，
      // 窄窗口下能更早地翻到菜单左侧；实在放不下时由 MenuAnchor 兜底保证不出屏。
      reservedPadding: EdgeInsets.zero,
      // 与 SubmenuButton 默认对齐一致：贴着菜单行左缘展开，首项和入口行齐平。
      alignmentOffset: const Offset(0, -8),
      style: appMenuStyle(palette).copyWith(alignment: AlignmentDirectional.topEnd),
      menuChildren: [
        for (final option in options)
          MenuItemButton(
            // 选项点完不收起，勾选标记原地跳动，方便连续预览布局与尺寸。
            closeOnActivate: false,
            onPressed: () => onSelected(option.value),
            style: appMenuItemStyle(palette),
            child: SizedBox(
              width: _subRowWidth,
              child: Row(
                children: [
                  AppIcon(
                    option.icon,
                    size: 16,
                    color: option.value == selected ? accent : palette.text,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: option.value == selected ? FontWeight.w600 : FontWeight.w500,
                        color: option.value == selected ? accent : palette.text,
                      ),
                    ),
                  ),
                  if (option.value == selected) ...[
                    const SizedBox(width: 10),
                    AppIcon('check-line', size: 16, color: accent),
                  ],
                ],
              ),
            ),
          ),
      ],
      builder: (context, menu, child) => MenuItemButton(
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        closeOnActivate: false,
        style: appMenuItemStyle(palette),
        child: SizedBox(
          width: _rowWidth + _submenuGap,
          child: Row(
            children: [
              AppIcon(icon, size: 17, color: palette.text),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 10),
              AppIcon('right-small-line', size: 16, color: palette.muted),
            ],
          ),
        ),
      ),
    );
  }
}
