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

  /// 风格：true=标签页，false=列表（移动端为下划线标签，桌面端为左侧分组栏）。
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

  /// 「标签页」风格下正在展开节点快切面板的分组名，null 表示收起。
  String? _expandedGroup;
  bool _showSearch = false;
  String? _offlineKey;
  ProxiesSnapshot? _offlineSnapshot;
  Map<String, OfflineEndpoint> _offlineEndpoints = const {};
  final Map<String, int> _offlineDelays = {};
  final Set<String> _offlineTimeout = {};
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
        _offlineDelays.clear();
        _offlineTimeout.clear();
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
    _offlineDelays.clear();
    _offlineTimeout.clear();
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

  int? _offlineDelay(String name) => _offlineDelays[name];

  Future<void> _probeOfflineNode(String name) async {
    final endpoint = _offlineEndpoints[name];
    if (endpoint == null || _offlineTesting.contains(name)) return;
    setState(() {
      _offlineTesting.add(name);
      _offlineDelays.remove(name);
      _offlineTimeout.remove(name);
    });
    final delay = await OfflineLatency.probe(endpoint);
    if (!mounted) return;
    setState(() {
      _offlineTesting.remove(name);
      if (delay != null) _offlineDelays[name] = delay;
      // 离线握手失败给出 -1，完全没有回执时是 null，两者都算超时。
      if (delay == null || delay < 0) _offlineTimeout.add(name);
    });
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
      _offlineDelays.clear();
      _offlineTimeout.clear();
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
    if (offline) return _offlineTimeout.contains(name);
    final info = snapshot.proxies[name];
    if (info != null && !info.alive) return true;
    final delay = controller.displayDelay(name);
    // 内核把超时节点的 delay 报成 0，ProxyInfo 统一记为 -1。
    return delay != null && delay < 0;
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
      int? delayOf(String name) => offline ? _offlineDelay(name) : controller.displayDelay(name);
      int weight(int? value) => value == null || value < 0 ? 1 << 30 : value;
      nodes.sort((a, b) => sort == NodeSort.name
          ? a.toLowerCase().compareTo(b.toLowerCase())
          : weight(delayOf(a)).compareTo(weight(delayOf(b))));
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

  void _scrollToSelected(ProxyInfo? group) {
    final name = group?.now;
    if (name == null || name.isEmpty) {
      _toast(context.l10n.get('proxy.noSelectedNode'));
      return;
    }
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
      onScrollToSelected: () => _scrollToSelected(group),
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    final mobile = MediaQuery.sizeOf(context).width < appDesktopBreakpoint;
    final offline = !controller.isRunning;
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

    return PageContainer(
      children: [
        PageHeader(
          title: l10n.get('nav.proxy'),
          subtitle: l10n.get('proxy.groups', [groups.length]),
          actions: [
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
        LayoutBuilder(
          builder: (context, constraints) {
            final view = _nodeView(controller, group, snapshot, offline: offline, desktop: true);
            final panel = _buildGroupPanel(
              context,
              controller,
              group,
              snapshot,
              offline: offline,
              view: view,
            );
            // 「风格 = 列表」用左侧分组栏；窗口过窄或选择标签页时退回顶部胶囊行。
            if (constraints.maxWidth < 860 || view.tabs) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  view.tabs
                      ? _groupTabBar(controller, group, snapshot, offline: offline)
                      : SizedBox(height: 54, child: _groupChipRow(groups, group)),
                  const SizedBox(height: 12),
                  panel,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 286,
                  child: SurfaceCard(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        for (final item in groups)
                          _GroupTile(
                            group: item,
                            selected: item.name == group.name,
                            onTap: () => setState(() => _selectedGroup = item.name),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: panel),
              ],
            );
          },
        ),
      ],
    );
  }

  /// 「标签页」风格的分组条：图标胶囊 + 选中高亮环，点胶囊上的箭头在该组下方展开节点快切面板。
  Widget _groupTabBar(
    AppController controller,
    ProxyInfo selected,
    ProxiesSnapshot snapshot, {
    required bool offline,
  }) {
    return _GroupTabBar(
      groups: snapshot.groups,
      selected: selected.name,
      expanded: _expandedGroup,
      onSelect: (name) => setState(() => _selectedGroup = name),
      onToggle: (name) => setState(() {
        _selectedGroup = name;
        _expandedGroup = _expandedGroup == name ? null : name;
      }),
      expandedPanel: (group) => _groupQuickPanel(controller, group, snapshot, offline: offline),
    );
  }

  /// 展开面板里的节点列表，过滤与排序沿用主面板那套，避免两处结果对不上。
  Widget _groupQuickPanel(
    AppController controller,
    ProxyInfo group,
    ProxiesSnapshot snapshot, {
    required bool offline,
  }) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final nodes = _visibleNodes(
      controller: controller,
      group: group,
      snapshot: snapshot,
      offline: offline,
      sort: _sortOf(controller),
    );
    if (nodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          l10n.get('proxy.filterNoResult'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: palette.muted),
        ),
      );
    }
    return Container(
      decoration: appCardDecoration(context, radius: 14, elevated: false),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 288),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final name in nodes)
                _NodeQuickRow(
                  name: name,
                  isNow: group.now == name,
                  delay: offline ? _offlineDelay(name) : controller.displayDelay(name),
                  testing: offline ? _offlineTesting.contains(name) : controller.testingNodes.contains(name),
                  onSelect: () {
                    if (offline) {
                      _selectOffline(group, name);
                    } else {
                      _select(group, name);
                    }
                    setState(() => _expandedGroup = null);
                  },
                  onTest: () => offline ? _probeOfflineNode(name) : controller.testNode(name),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupChipRow(List<ProxyInfo> groups, ProxyInfo group) {
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: groups.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (context, index) {
        final item = groups[index];
        return _GroupChip(
          group: item,
          selected: item.name == group.name,
          onTap: () => setState(() => _selectedGroup = item.name),
        );
      },
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
          actions: [
            AppIconButton(
              icon: 'search-line',
              size: 20,
              padding: 7,
              tooltip: l10n.get('common.search'),
              onTap: groups.isEmpty
                  ? null
                  : () {
                      setState(() {
                        _showSearch = !_showSearch;
                        if (!_showSearch) _search.clear();
                      });
                    },
            ),
            const SizedBox(width: 6),
            _testAllButton(controller, snapshot, offline: offline, desktop: false),
            const SizedBox(width: 6),
            _displayMenuButton(controller, group, desktop: false, size: 20, padding: 7),
          ],
        ),
        const SizedBox(height: 14),
        if (group != null)
          view.tabs
              ? _groupTabBar(controller, group, snapshot, offline: offline)
              : SizedBox(
                  height: 46,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: groups.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final item = groups[index];
                      return _GroupChip(
                        group: item,
                        selected: item.name == group!.name,
                        onTap: () => setState(() => _selectedGroup = item.name),
                      );
                    },
                  ),
                ),
        if (offline && group != null) ...[
          const SizedBox(height: 14),
          Text(
            l10n.get('proxy.offlineTcpHint'),
            style: TextStyle(fontSize: 12, height: 1.4, color: palette.muted),
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
                          delay: offline ? _offlineDelay(name) : controller.displayDelay(name),
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
    final testing = offline
        ? _offlineTesting.contains(group.name)
        : controller.testingGroups.contains(group.name);
    final now = group.now;
    final nowDelay = now.isEmpty ? null : (offline ? _offlineDelay(now) : controller.displayDelay(now));
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
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: testing
                    ? null
                    : () => offline ? _probeOfflineGroup(group) : controller.testGroup(group),
                icon: testing
                    ? const SizedBox(width: 13, height: 13, child: CircularProgressIndicator(strokeWidth: 1.8))
                    : const AppIcon('lightning-line', size: 14),
                label: Text(l10n.get('proxy.testGroup')),
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
                          delay: offline ? _offlineDelay(name) : controller.displayDelay(name),
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

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group, required this.selected, required this.onTap});

  final ProxyInfo group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = context.l10n;
    final accent = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: selected ? palette.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: palette.hover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                AppIcon('shield-shape-line', size: 16, color: selected ? accent : palette.muted),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                          color: selected ? accent : palette.text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        group.now.isEmpty ? l10n.get(group.groupTypeKey) : group.now,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: palette.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${group.all.length}',
                  style: TextStyle(fontSize: 10.5, color: palette.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.group, required this.selected, required this.onTap});

  final ProxyInfo group;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: selected ? palette.accentSoft : palette.card,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: selected ? accent.withValues(alpha: 0.35) : palette.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon('shield-shape-line', size: 14, color: selected ? accent : palette.muted),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      group.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selected ? accent : palette.text,
                      ),
                    ),
                    if (group.now.isNotEmpty)
                      Text(
                        group.now,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 9.5, color: palette.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分组类型对应的图标，让标签条一眼分辨手动选择 / 自动测速 / 故障转移。
String _groupTypeIcon(ProxyInfo group) {
  return switch (group.type.toLowerCase()) {
    'urltest' || 'url-test' => 'speed-line',
    'fallback' => 'transfer-line',
    'loadbalance' || 'load-balance' => 'grid-line',
    'relay' => 'link-line',
    _ => 'list-check-line',
  };
}

/// 「标签页」风格的分组条：图标胶囊横排，选中项带高亮环，
/// 展开时在该组正下方挂一个节点快切面板。
class _GroupTabBar extends StatelessWidget {
  const _GroupTabBar({
    required this.groups,
    required this.selected,
    required this.expanded,
    required this.onSelect,
    required this.onToggle,
    required this.expandedPanel,
  });

  final List<ProxyInfo> groups;
  final String selected;
  final String? expanded;
  final ValueChanged<String> onSelect;
  final ValueChanged<String> onToggle;
  final Widget Function(ProxyInfo group) expandedPanel;

  @override
  Widget build(BuildContext context) {
    final bar = SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final item = groups[index];
          return _GroupTabPill(
            group: item,
            selected: item.name == selected,
            expanded: item.name == expanded,
            onTap: () => onSelect(item.name),
            onToggle: () => onToggle(item.name),
          );
        },
      ),
    );
    ProxyInfo? open;
    for (final item in groups) {
      if (item.name == expanded) {
        open = item;
        break;
      }
    }
    if (open == null) return bar;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        bar,
        const SizedBox(height: 10),
        expandedPanel(open),
      ],
    );
  }
}

class _GroupTabPill extends StatelessWidget {
  const _GroupTabPill({
    required this.group,
    required this.selected,
    required this.expanded,
    required this.onTap,
    required this.onToggle,
  });

  final ProxyInfo group;
  final bool selected;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    final content = selected ? accent : palette.text;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: palette.hover,
        // 底色走 Ink 而不是 Container，否则悬停高亮会被不透明底色盖掉。
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? palette.accentSoft : palette.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent.withValues(alpha: 0.45) : palette.border,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(_groupTypeIcon(group), size: 14, color: content),
                const SizedBox(width: 7),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: content,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onToggle,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: AnimatedRotation(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        turns: expanded ? 0.5 : 0,
                        child: AppIcon('down-small-line', size: 15, color: content),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 展开面板里的一行节点：勾选标记 + 节点名 + 延迟胶囊。
class _NodeQuickRow extends StatelessWidget {
  const _NodeQuickRow({
    required this.name,
    required this.isNow,
    required this.delay,
    required this.testing,
    required this.onSelect,
    required this.onTest,
  });

  final String name;
  final bool isNow;
  final int? delay;
  final bool testing;
  final VoidCallback onSelect;
  final VoidCallback onTest;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Material(
      color: isNow ? palette.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(10),
        hoverColor: palette.hover,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: 15,
                child: isNow ? AppIcon('check-line', size: 14, color: accent) : const SizedBox.shrink(),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isNow ? FontWeight.w600 : FontWeight.w500,
                    color: isNow ? accent : palette.text,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DelayChip(delay: delay, testing: testing, dense: true, onTap: onTest),
            ],
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
    final flag = regionEmojiForNode(name);
    final delayLabel = delay == null ? '--' : formatDelay(delay!, zh: l10n.isZh);
    // 选中态用整圈描边 + 浅色底，与桌面节点磁贴一致；
    // 之前的左侧粗竖条在圆角卡片上会切出直角、像贴了一条色带。
    return SurfaceCard(
      padding: scale.cardPadding,
      radius: scale.radius,
      color: selected ? palette.accentSoft : null,
      border: Border.all(
        color: selected ? accent.withValues(alpha: 0.45) : palette.border,
        width: selected ? 1.2 : 1,
      ),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (flag.isNotEmpty) ...[
                Text(flag, style: TextStyle(fontSize: scale.name + 2)),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: scale.name,
                    fontWeight: FontWeight.w600,
                    color: selected ? accent : palette.text,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              selected
                  ? AppIcon('check-line', size: scale.icon, color: accent)
                  : SizedBox(width: scale.icon),
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
    return Material(
      color: selected ? palette.accentSoft : palette.card,
      borderRadius: BorderRadius.circular(scale.radius),
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(scale.radius),
        hoverColor: palette.hover,
        child: Container(
          padding: scale.cardPadding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(scale.radius),
            border: Border.all(
              color: selected ? accent.withValues(alpha: 0.45) : palette.border,
              width: selected ? 1.2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: scale.name,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? accent : palette.text,
                        height: 1.25,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    AppIcon('check-line', size: scale.icon - 2, color: accent),
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
    return SubmenuButton(
      controller: _subController(id),
      // 悬停默认会立刻展开二级菜单；给一个足够长的延迟，让它只响应点击。
      hoverOpenDelay: const Duration(days: 1),
      onOpen: () => _handleSubmenuOpen(id),
      style: appMenuItemStyle(palette),
      menuStyle: appMenuStyle(palette),
      submenuIcon: WidgetStatePropertyAll(AppIcon('right-small-line', size: 16, color: palette.muted)),
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
      child: SizedBox(
        width: _rowWidth,
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
          ],
        ),
      ),
    );
  }
}
