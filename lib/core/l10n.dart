import 'package:flutter/widgets.dart';

class L10n {
  const L10n(this.code);

  final String code;

  bool get isZh => code == 'zh';
  bool get isEn => code == 'en';

  static const supported = ['zh', 'en'];

  bool contains(String key) => _strings[key] != null;

  String get(String key, [List<Object?> args = const []]) {
    var text = _strings[key]?[code] ?? _strings[key]?['zh'] ?? key;
    for (var i = 0; i < args.length; i++) {
      text = text.replaceAll('{$i}', '${args[i]}');
    }
    return text;
  }

  String formatRelative(DateTime? time) {
    if (time == null) return get('time.never');
    final delta = DateTime.now().difference(time.toLocal());
    if (delta.inSeconds < 60) return get('time.justNow');
    if (delta.inMinutes < 60) return get('time.minutesAgo', [delta.inMinutes]);
    if (delta.inHours < 24) return get('time.hoursAgo', [delta.inHours]);
    if (delta.inDays < 7) return get('time.daysAgo', [delta.inDays]);
    return formatDate(time);
  }

  String formatDate(DateTime? time) {
    if (time == null) return '—';
    final local = time.toLocal();
    final y = local.year.toString();
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return isZh ? '$y-$m-$d' : '$y-$m-$d';
  }

  String formatDateTime(DateTime? time) {
    if (time == null) return '—';
    final local = time.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '${formatDate(local)} $h:$min';
  }

  static const Map<String, Map<String, String>> _strings = {
    // ---------------------------------------------------------------- common
    'common.cancel': {'zh': '取消', 'en': 'Cancel'},
    'common.save': {'zh': '保存', 'en': 'Save'},
    'common.delete': {'zh': '删除', 'en': 'Delete'},
    'common.edit': {'zh': '编辑', 'en': 'Edit'},
    'common.add': {'zh': '添加', 'en': 'Add'},
    'common.close': {'zh': '关闭', 'en': 'Close'},
    'common.back': {'zh': '返回', 'en': 'Back'},
    'common.confirm': {'zh': '确认', 'en': 'Confirm'},
    'common.refresh': {'zh': '刷新', 'en': 'Refresh'},
    'common.search': {'zh': '搜索', 'en': 'Search'},
    'common.all': {'zh': '全部', 'en': 'All'},
    'common.copy': {'zh': '复制', 'en': 'Copy'},
    'common.copied': {'zh': '已复制', 'en': 'Copied'},
    'common.retry': {'zh': '重试', 'en': 'Retry'},
    'common.loading': {'zh': '加载中…', 'en': 'Loading…'},
    'common.unknown': {'zh': '未知', 'en': 'Unknown'},
    'common.never': {'zh': '从未', 'en': 'Never'},
    'common.enabled': {'zh': '已开启', 'en': 'On'},
    'common.disabled': {'zh': '已关闭', 'en': 'Off'},
    'common.error': {'zh': '出错了', 'en': 'Something went wrong'},
    'common.details': {'zh': '详情', 'en': 'Details'},
    'common.test': {'zh': '测速', 'en': 'Test'},
    'common.testing': {'zh': '测速中…', 'en': 'Testing…'},
    'common.start': {'zh': '启动', 'en': 'Start'},
    'common.stop': {'zh': '停止', 'en': 'Stop'},
    'common.reload': {'zh': '重载', 'en': 'Reload'},
    'common.timeout': {'zh': '超时', 'en': 'Timeout'},
    'common.none': {'zh': '无', 'en': 'None'},
    'common.auto': {'zh': '自动', 'en': 'Auto'},
    'common.manual': {'zh': '手动', 'en': 'Manual'},
    'common.open': {'zh': '打开', 'en': 'Open'},
    'common.done': {'zh': '完成', 'en': 'Done'},
    'common.apply': {'zh': '应用', 'en': 'Apply'},
    'common.notAvailable': {'zh': '不可用', 'en': 'Unavailable'},
    'common.justNow': {'zh': '刚刚', 'en': 'Just now'},
    'common.off': {'zh': '关闭', 'en': 'Off'},
    'common.on': {'zh': '开启', 'en': 'On'},
    'common.viewAll': {'zh': '查看全部', 'en': 'View all'},
    'common.more': {'zh': '更多', 'en': 'More'},
    'common.seconds': {'zh': '{0} 秒', 'en': '{0}s'},
    'common.enabledOn': {'zh': '已开启', 'en': 'Enabled'},

    // ------------------------------------------------------------------- nav
    'nav.home': {'zh': '首页', 'en': 'Home'},
    'nav.proxy': {'zh': '代理', 'en': 'Proxies'},
    'nav.subscriptions': {'zh': '订阅', 'en': 'Subscriptions'},
    'nav.connections': {'zh': '连接', 'en': 'Connections'},
    'nav.logs': {'zh': '日志', 'en': 'Logs'},
    'nav.settings': {'zh': '设置', 'en': 'Settings'},
    'nav.dns': {'zh': 'DNS 查询', 'en': 'DNS'},
    'nav.rules': {'zh': '规则', 'en': 'Rules'},
    'nav.providers': {'zh': '代理提供者', 'en': 'Providers'},
    'nav.ruleProviders': {'zh': '规则提供者', 'en': 'Rule providers'},
    'nav.tools': {'zh': '工具', 'en': 'Tools'},
    'nav.menu': {'zh': '导航', 'en': 'Navigation'},
    'window.minimize': {'zh': '最小化', 'en': 'Minimize'},
    'window.maximize': {'zh': '最大化', 'en': 'Maximize'},
    'window.restore': {'zh': '还原', 'en': 'Restore'},
    'window.close': {'zh': '关闭', 'en': 'Close'},

    // ---------------------------------------------------------------- status
    'status.stopped': {'zh': '已停止', 'en': 'Stopped'},
    'status.starting': {'zh': '启动中', 'en': 'Starting'},
    'status.running': {'zh': '运行中', 'en': 'Running'},
    'status.stopping': {'zh': '停止中', 'en': 'Stopping'},
    'status.stopUnconfirmed': {'zh': '停止未确认', 'en': 'Stop unconfirmed'},
    'mode.rule': {'zh': '规则', 'en': 'Rule'},
    'mode.global': {'zh': '全局', 'en': 'Global'},
    'mode.direct': {'zh': '直连', 'en': 'Direct'},

    // ------------------------------------------------------------------ home
    'home.welcome': {'zh': '欢迎回来', 'en': 'Welcome back'},
    'home.activeNode': {'zh': '当前节点', 'en': 'Active node'},
    'home.uptime': {'zh': '运行时长', 'en': 'Uptime'},
    'home.coreVersion': {'zh': '内核版本', 'en': 'Core version'},
    'home.statusHint.running': {'zh': '内核运行中，流量已就绪', 'en': 'Core is running'},
    'home.statusHint.starting': {'zh': '正在启动内核…', 'en': 'Starting the core…'},
    'home.statusHint.stopping': {'zh': '正在停止内核…', 'en': 'Stopping the core…'},
    'home.statusHint.stopUnconfirmed': {
      'zh': '提权内核可能仍在运行，流量可能仍被接管',
      'en': 'The elevated core may still be running and traffic may still be intercepted',
    },
    'home.speed': {'zh': '实时速率', 'en': 'Realtime speed'},
    'home.upload': {'zh': '上传', 'en': 'Upload'},
    'home.download': {'zh': '下载', 'en': 'Download'},
    'home.connections': {'zh': '连接', 'en': 'Connections'},
    'home.memory': {'zh': '内存', 'en': 'Memory'},
    'home.activeConnections': {'zh': '{0} 条活跃连接', 'en': '{0} active'},
    'home.session': {'zh': '本次会话', 'en': 'This session'},
    'home.latency': {'zh': '网络延迟', 'en': 'Latency'},
    'home.latencyTest': {'zh': '测试延迟', 'en': 'Test latency'},
    'home.latencyHint': {
      'zh': '经由当前规则与节点测试',
      'en': 'Measured through current rules and node',
    },
    'home.latencyNone': {'zh': '尚未测试', 'en': 'Not tested yet'},
    'home.latencyNormal': {'zh': '正常', 'en': 'Healthy'},
    'home.latencyPartial': {'zh': '部分可用', 'en': 'Partial'},
    'home.latencyAbnormal': {'zh': '异常', 'en': 'Unavailable'},
    'home.tools': {'zh': '快捷入口', 'en': 'Quick access'},
    'home.subscription': {'zh': '订阅用量', 'en': 'Subscription'},
    'home.noSubscription': {'zh': '还没有订阅', 'en': 'No subscription yet'},
    'home.manageSubscription': {'zh': '管理订阅', 'en': 'Manage'},
    'home.usedOf': {'zh': '{0} / {1}', 'en': '{0} / {1}'},
    'home.expireAt': {'zh': '到期 {0}', 'en': 'Expires {0}'},
    'home.noExpire': {'zh': '无到期时间', 'en': 'No expiry'},
    'home.lastUpdated': {'zh': '更新于 {0}', 'en': 'Updated {0}'},
    'home.noQuota': {'zh': '未提供流量信息', 'en': 'No quota information'},
    'home.remaining': {'zh': '剩余 {0}', 'en': '{0} left'},
    'home.trafficTotal': {'zh': '会话流量', 'en': 'Session traffic'},
    'home.totalUp': {'zh': '累计上传', 'en': 'Uploaded'},
    'home.totalDown': {'zh': '累计下载', 'en': 'Downloaded'},
    'home.coreSettings': {'zh': '内核设置', 'en': 'Core settings'},
    'home.subscriptionLabel': {'zh': '当前订阅', 'en': 'Active subscription'},
    'home.netSpeed': {'zh': '网速', 'en': 'Network'},
    'home.overview': {'zh': '概览', 'en': 'Overview'},
    'home.metricSubscription': {'zh': '订阅', 'en': 'Subscription'},
    'home.system': {'zh': '系统', 'en': 'System'},
    'home.ip': {'zh': 'IP', 'en': 'IP'},
    'home.address': {'zh': '地址', 'en': 'Address'},
    'home.region': {'zh': '节点区域', 'en': 'Region'},
    'home.used': {'zh': '已用', 'en': 'Used'},
    'home.total': {'zh': '总量', 'en': 'Total'},
    'home.latencyShort': {'zh': '延迟', 'en': 'Latency'},
    'home.noSubscriptionValue': {'zh': '未选择', 'en': 'None'},
    'home.vpn': {'zh': 'VPN', 'en': 'VPN'},
    'home.dashboard': {'zh': '主页', 'en': 'Dashboard'},
    'home.nameLabel': {'zh': '名称', 'en': 'Name'},
    'home.usedTraffic': {'zh': '已用流量', 'en': 'Used traffic'},
    'home.expireLabel': {'zh': '到期', 'en': 'Expires'},
    'home.proxyMode': {'zh': '代理模式', 'en': 'Proxy mode'},
    'home.proxyModeDesc': {
      'zh': '规则按分流规则走、全局全部走代理、直连全部直出；内核运行中即时切换',
      'en': 'Rule follows the rules, Global proxies everything, Direct bypasses. Changes apply instantly while the core runs.',
    },
    'home.coreStatus': {'zh': '内核状态', 'en': 'Core status'},
    'home.takeover': {'zh': '接管方式', 'en': 'Takeover'},
    'home.takeoverProxyHint': {
      'zh': 'Windows 代理已指向 {0} 端口',
      'en': 'Windows proxy points to port {0}',
    },
    'home.takeoverDirectHint': {
      'zh': '系统代理关闭，应用需手动配置代理',
      'en': 'System proxy is off; configure apps manually',
    },
    'home.takeoverPending': {
      'zh': '内核未运行，启动后自动写入系统代理',
      'en': 'Core not running; system proxy applied on start',
    },
    'home.takeoverVpnHint': {
      'zh': 'VPN 接管全部设备流量',
      'en': 'VPN routes all device traffic',
    },
    'home.takeoverTunHint': {
      'zh': '内核以管理员身份接管路由和 DNS',
      'en': 'The core takes over routes and DNS as administrator',
    },
    'home.notRunning': {'zh': '未运行', 'en': 'Not running'},
    'home.startHint': {
      'zh': '点右上角「启动」接管流量',
      'en': 'Use Start at the top right to take over traffic',
    },
    'home.addSubHint': {'zh': '添加订阅后可启动', 'en': 'Add a subscription to start'},
    'home.coreRunningHint': {
      'zh': '已运行 {0} · {1} 条连接',
      'en': 'Running {0} · {1} connections',
    },
    'home.coreMemoryHint': {'zh': '内存占用 {0}', 'en': 'Memory {0}'},
    'home.coreNotRunning': {'zh': '内核未运行', 'en': 'Core is not running'},
    'home.portListening': {'zh': '混合端口监听中', 'en': 'Mixed port is listening'},
    'home.networkTraffic': {'zh': '网络流量', 'en': 'Network traffic'},
    'home.sessionTotal': {'zh': '本次会话 {0}', 'en': 'This session {0}'},
    'home.tun': {'zh': 'TUN', 'en': 'TUN'},
    'home.tunHint': {
      'zh': '接管全部流量，内核需要管理员权限（弹一次 UAC）',
      'en': 'Routes all traffic; the core needs administrator rights (one UAC prompt)',
    },
    'home.tunOn': {'zh': 'TUN 接管已开启', 'en': 'TUN takeover enabled'},
    'home.tunOff': {'zh': 'TUN 接管已关闭', 'en': 'TUN takeover disabled'},

    // ----------------------------------------------------------------- tools
    'tools.connections': {'zh': '连接', 'en': 'Connections'},
    'tools.connectionsSub': {'zh': '查看活跃流量', 'en': 'Active traffic'},
    'tools.logs': {'zh': '日志', 'en': 'Logs'},
    'tools.logsSub': {'zh': '实时内核输出', 'en': 'Live core output'},
    'tools.dns': {'zh': 'DNS 查询', 'en': 'DNS lookup'},
    'tools.dnsSub': {'zh': '测试域名解析', 'en': 'Resolve a domain'},
    'tools.rules': {'zh': '规则', 'en': 'Rules'},
    'tools.rulesSub': {'zh': '查看生效规则', 'en': 'Active rules'},
    'tools.providers': {'zh': '代理提供者', 'en': 'Providers'},
    'tools.providersSub': {'zh': '管理外部资源', 'en': 'Manage remote sets'},
    'tools.ruleProviders': {'zh': '规则提供者', 'en': 'Rule providers'},
    'tools.ruleProvidersSub': {'zh': '管理远程规则集', 'en': 'Manage remote rule sets'},
    'tools.subscriptions': {'zh': '订阅', 'en': 'Subscriptions'},
    'tools.subscriptionsSub': {'zh': '导入与更新', 'en': 'Import & update'},

    // ----------------------------------------------------------------- proxy
    'proxy.groups': {'zh': '{0} 个策略组', 'en': '{0} groups'},
    'proxy.testAll': {'zh': '测速全部', 'en': 'Test all'},
    'proxy.searchNodes': {'zh': '搜索节点', 'en': 'Search nodes'},
    'proxy.nodes': {'zh': '{0} 个节点', 'en': '{0} nodes'},
    'proxy.testGroup': {'zh': '测速本组', 'en': 'Test group'},
    'proxy.noGroups': {'zh': '暂无策略组', 'en': 'No proxy groups'},
    'proxy.noGroupsHint': {
      'zh': '启动内核后，这里会显示订阅中的策略组',
      'en': 'Start the core to load groups from your subscription',
    },
    'proxy.notRunning': {'zh': '内核尚未运行', 'en': 'Core is not running'},
    'proxy.startHint': {'zh': '启动后即可切换节点', 'en': 'Start it to switch nodes'},
    'proxy.selectFailed': {'zh': '切换节点失败', 'en': 'Failed to select node'},
    'proxy.emptyGroup': {'zh': '此策略组暂无节点', 'en': 'No nodes in this group'},
    'proxy.filterNoResult': {'zh': '没有匹配的节点', 'en': 'No matching nodes'},
    'proxy.sort.default': {'zh': '默认', 'en': 'Default'},
    'proxy.sort.delay': {'zh': '延迟', 'en': 'Latency'},
    'proxy.sort.name': {'zh': '名称', 'en': 'Name'},
    'proxy.provider': {'zh': '提供者', 'en': 'Provider'},
    'proxy.groupType.selector': {'zh': '手动选择', 'en': 'Select'},
    'proxy.groupType.urltest': {'zh': '自动测速', 'en': 'URL test'},
    'proxy.groupType.fallback': {'zh': '故障转移', 'en': 'Fallback'},
    'proxy.groupType.loadbalance': {'zh': '负载均衡', 'en': 'Balance'},
    'proxy.groupType.relay': {'zh': '链式代理', 'en': 'Relay'},
    'proxy.noSelection': {'zh': '未选择', 'en': 'None'},
    'proxy.testFailed': {'zh': '测速失败', 'en': 'Test failed'},
    'proxy.bulkTesting': {'zh': '正在测速…', 'en': 'Testing all…'},
    'proxy.current': {'zh': '当前', 'en': 'Current'},
    'proxy.displayGroups': {'zh': '策略组', 'en': 'Groups'},
    'proxy.selectedNode': {'zh': '已选择', 'en': 'Selected'},
    'proxy.title': {'zh': '代理组', 'en': 'Proxy groups'},
    'proxy.offlineHint': {
      'zh': '代理未启动，当前显示所选订阅的节点',
      'en':
          'Proxy is not running — showing nodes from the selected subscription',
    },
    'proxy.offlineTcpHint': {
      'zh': '代理未启动：可选择订阅中的节点，启动内核后生效；测速结果为 TCP 连接延迟',
      'en': 'Proxy is not running: you can pick nodes now, applied when the core starts; delays are TCP connection latency',
    },
    'proxy.offlineSelected': {
      'zh': '已选择，启动内核后生效',
      'en': 'Selected — takes effect when the core starts',
    },
    'proxy.offlineEmpty': {
      'zh': '订阅里没有可预览的节点',
      'en': 'No nodes to preview in this subscription',
    },
    'proxy.offlineNoSubscription': {
      'zh': '选择一个订阅后可在此预览节点',
      'en': 'Select a subscription to preview its nodes',
    },
    'proxy.offlineLoadFailed': {
      'zh': '读取订阅节点失败',
      'en': 'Could not read nodes from the subscription',
    },
    'proxy.offlineNoProfile': {
      'zh': '这个订阅还没有本地缓存，更新一次即可离线查看节点、测速和切换',
      'en': 'This subscription is not cached yet — update it once to browse, test and switch nodes offline',
    },
    'proxy.offlineUpdate': {'zh': '更新订阅', 'en': 'Update subscription'},
    'proxy.refreshNodes': {'zh': '刷新节点', 'en': 'Refresh nodes'},
    'proxy.menu': {'zh': '显示选项', 'en': 'Display options'},
    'proxy.menu.scrollToSelected': {'zh': '滚动到已选', 'en': 'Scroll to selected'},
    'proxy.menu.style': {'zh': '风格', 'en': 'Style'},
    'proxy.menu.sort': {'zh': '排序', 'en': 'Sort'},
    'proxy.menu.layout': {'zh': '布局', 'en': 'Layout'},
    'proxy.menu.size': {'zh': '尺寸', 'en': 'Size'},
    'proxy.menu.hideTimeout': {'zh': '隐藏超时代理', 'en': 'Hide timed-out nodes'},
    'proxy.style.tabs': {'zh': '标签页', 'en': 'Tabs'},
    'proxy.style.list': {'zh': '列表', 'en': 'List'},
    'proxy.size.loose': {'zh': '宽松', 'en': 'Loose'},
    'proxy.size.standard': {'zh': '标准', 'en': 'Standard'},
    'proxy.size.compact': {'zh': '紧凑', 'en': 'Compact'},
    'proxy.noSelectedNode': {'zh': '当前没有已选节点', 'en': 'No node is selected yet'},
    'proxy.timeoutHidden': {
      'zh': '已隐藏 {0} 个超时节点',
      'en': 'Hiding {0} timed-out nodes',
    },
    'proxy.testedCount': {
      'zh': '已测延迟 {0} / 共 {1} 个节点',
      'en': '{0} of {1} nodes tested',
    },

    // ----------------------------------------------------------- subscriptions
    'subscriptions.subtitle': {
      'zh': '导入、更新并管理你的节点配置',
      'en': 'Import, update and manage profiles',
    },
    'subscriptions.title': {'zh': '订阅管理', 'en': 'Subscriptions'},
    'subscriptions.add': {'zh': '添加订阅', 'en': 'Add subscription'},
    'subscriptions.addByUrl': {'zh': '订阅链接', 'en': 'Subscription URL'},
    'subscriptions.importLocal': {'zh': '本地文件', 'en': 'Local file'},
    'subscriptions.importQr': {'zh': '扫描二维码', 'en': 'Scan QR code'},
    'subscriptions.importQrImage': {'zh': '二维码图片', 'en': 'QR code image'},
    'subscriptions.importFromQrImage': {'zh': '从图片识别', 'en': 'From image'},
    'subscriptions.qrTitle': {'zh': '扫描二维码', 'en': 'Scan QR code'},
    'subscriptions.qrHint': {
      'zh': '将订阅二维码放入框内即可自动识别',
      'en': 'Point the camera at a subscription QR code',
    },
    'subscriptions.qrNotFound': {
      'zh': '图片中没有识别到二维码',
      'en': 'No QR code found in that image',
    },
    'subscriptions.qrNotLink': {
      'zh': '二维码内容不是订阅链接',
      'en': 'That QR code is not a subscription URL',
    },
    'subscriptions.qrCameraError': {
      'zh': '无法使用摄像头，请检查权限后重试',
      'en': 'Camera unavailable — check the permission and retry',
    },
    'subscriptions.importFile': {'zh': '从文件导入', 'en': 'Import file'},
    'subscriptions.importClipboard': {
      'zh': '从剪贴板导入',
      'en': 'Import from clipboard',
    },
    'subscriptions.clipboardEmpty': {
      'zh': '剪贴板是空的',
      'en': 'The clipboard is empty',
    },
    'subscriptions.clipboardNoLink': {
      'zh': '剪贴板里没有可识别的订阅链接',
      'en': 'No subscription link found in the clipboard',
    },
    'subscriptions.linkInvalid': {
      'zh': '无法识别的订阅链接',
      'en': 'Unrecognized subscription link',
    },
    'subscriptions.active': {'zh': '使用中', 'en': 'Active'},
    'subscriptions.local': {'zh': '本地', 'en': 'Local'},
    'subscriptions.remote': {'zh': '远程', 'en': 'Remote'},
    'subscriptions.unknown': {'zh': '未知', 'en': 'Unknown'},
    'subscriptions.use': {'zh': '使用', 'en': 'Use'},
    'subscriptions.update': {'zh': '更新', 'en': 'Update'},
    'subscriptions.updating': {'zh': '更新中…', 'en': 'Updating…'},
    'subscriptions.empty': {'zh': '还没有订阅', 'en': 'No subscriptions yet'},
    'subscriptions.emptyHint': {
      'zh': '点击右上角 +，添加订阅链接、本地文件或二维码',
      'en': 'Tap + in the top right to add a URL, local file, or QR code',
    },
    'subscriptions.name': {'zh': '名称', 'en': 'Name'},
    'subscriptions.nameHint': {
      'zh': '留空则自动命名',
      'en': 'Leave empty to auto-name',
    },
    'subscriptions.url': {'zh': '订阅链接', 'en': 'Subscription URL'},
    'subscriptions.urlHint': {
      'zh': 'https://example.com/sub?token=…',
      'en': 'https://example.com/sub?token=…',
    },
    'subscriptions.addTitle': {'zh': '添加订阅', 'en': 'Add subscription'},
    'subscriptions.editTitle': {'zh': '编辑订阅', 'en': 'Edit subscription'},
    'subscriptions.deleteTitle': {'zh': '删除订阅', 'en': 'Delete subscription'},
    'subscriptions.deleteMessage': {
      'zh': '确定要删除“{0}”吗？本地配置也会一并移除。',
      'en': 'Delete “{0}” and its local profile?',
    },
    'subscriptions.adding': {'zh': '正在获取订阅…', 'en': 'Fetching subscription…'},
    'subscriptions.addSuccess': {'zh': '订阅已添加', 'en': 'Subscription added'},
    'subscriptions.updateSuccess': {
      'zh': '订阅已更新',
      'en': 'Subscription updated',
    },
    'subscriptions.deleted': {'zh': '订阅已删除', 'en': 'Subscription deleted'},
    'subscriptions.setActive': {
      'zh': '已切换当前订阅',
      'en': 'Switched active subscription',
    },
    'subscriptions.invalidUrl': {
      'zh': '请输入有效的订阅链接',
      'en': 'Enter a valid subscription URL',
    },
    'subscriptions.fetchFailed': {
      'zh': '获取订阅失败',
      'en': 'Failed to fetch subscription',
    },
    'subscriptions.localFile': {'zh': '本地文件', 'en': 'Local file'},
    'subscriptions.traffic': {'zh': '流量', 'en': 'Traffic'},
    'subscriptions.used': {'zh': '已用', 'en': 'Used'},
    'subscriptions.total': {'zh': '总量', 'en': 'Total'},
    'subscriptions.remaining': {'zh': '剩余', 'en': 'Remaining'},
    'subscriptions.expire': {'zh': '到期', 'en': 'Expires'},
    'subscriptions.lastUpdated': {'zh': '最近更新', 'en': 'Last updated'},
    'subscriptions.autoUpdate': {'zh': '自动更新', 'en': 'Auto update'},
    'subscriptions.interval': {'zh': '更新间隔', 'en': 'Interval'},
    'subscriptions.intervalOff': {'zh': '手动', 'en': 'Manual'},
    'subscriptions.intervalMinutes': {'zh': '{0} 分钟', 'en': '{0} minutes'},
    'subscriptions.intervalHours': {'zh': '{0} 小时', 'en': '{0} hours'},
    'subscriptions.intervalDays': {'zh': '{0} 天', 'en': '{0} days'},
    'subscriptions.lastError': {'zh': '上次更新失败', 'en': 'Failed last time'},
    'subscriptions.updateAll': {
      'zh': '更新全部订阅',
      'en': 'Update all subscriptions',
    },
    'subscriptions.updateAllDone': {
      'zh': '所有订阅已更新',
      'en': 'All subscriptions updated',
    },
    'subscriptions.updateAllPartial': {
      'zh': '已更新 {0} 个订阅，{1} 个失败',
      'en': '{0} updated, {1} failed',
    },
    'subscriptions.updateAllFailed': {
      'zh': '订阅更新失败',
      'en': 'Failed to update subscriptions',
    },
    'subscriptions.updatingAll': {'zh': '正在更新所有订阅…', 'en': 'Updating all…'},
    'subscriptions.sort': {'zh': '调整顺序', 'en': 'Reorder'},
    'subscriptions.sortTitle': {'zh': '调整订阅顺序', 'en': 'Reorder subscriptions'},
    'subscriptions.sortHint': {
      'zh': '只调整列表顺序，不影响当前使用的订阅',
      'en': 'Changes list order only; the active subscription stays the same',
    },
    'subscriptions.moveUp': {'zh': '上移', 'en': 'Move up'},
    'subscriptions.moveDown': {'zh': '下移', 'en': 'Move down'},
    'subscriptions.sortSaved': {
      'zh': '订阅顺序已保存',
      'en': 'Subscription order saved',
    },
    'subscriptions.noQuota': {'zh': '未提供流量信息', 'en': 'No quota information'},
    'subscriptions.source': {'zh': '来源', 'en': 'Source'},
    'subscriptions.autoUpdateHint': {
      'zh': '按间隔在后台检查更新',
      'en': 'Check for updates in the background',
    },
    'subscriptions.createdAt': {'zh': '添加于 {0}', 'en': 'Added {0}'},
    'subscriptions.exportHint': {
      'zh': '支持 Clash / mihomo YAML 配置',
      'en': 'Clash / mihomo YAML configs',
    },
    'subscriptions.unnamed': {'zh': '未命名订阅', 'en': 'Untitled subscription'},
    'subscriptions.autoName': {'zh': '订阅 {0}', 'en': 'Subscription {0}'},
    'subscriptions.intervalInvalid': {
      'zh': '更新间隔需在 60–43200 分钟之间',
      'en': 'Interval must be between 60 and 43200 minutes',
    },

    // -------------------------------------------------------------- connections
    'connections.subtitle': {
      'zh': '实时查看经过内核的连接',
      'en': 'Live connections through the core',
    },
    'connections.active': {'zh': '{0} 条活跃连接', 'en': '{0} active'},
    'connections.totalUpload': {'zh': '上传总量', 'en': 'Total upload'},
    'connections.totalDownload': {'zh': '下载总量', 'en': 'Total download'},
    'connections.closeAll': {'zh': '关闭全部', 'en': 'Close all'},
    'connections.closeAllTitle': {
      'zh': '关闭所有连接',
      'en': 'Close all connections',
    },
    'connections.closeAllMessage': {
      'zh': '确定要关闭当前全部 {0} 条连接吗？',
      'en': 'Close all {0} connections?',
    },
    'connections.closed': {'zh': '连接已关闭', 'en': 'Connection closed'},
    'connections.close': {'zh': '关闭连接', 'en': 'Close connection'},
    'connections.allClosed': {'zh': '已关闭全部连接', 'en': 'All connections closed'},
    'connections.empty': {'zh': '暂无活跃连接', 'en': 'No active connections'},
    'connections.emptyHint': {
      'zh': '内核正在运行，新的连接会实时出现在这里',
      'en': 'New connections will appear here in real time',
    },
    'connections.search': {
      'zh': '搜索主机、规则或进程',
      'en': 'Search host, rule or process',
    },
    'connections.host': {'zh': '主机', 'en': 'Host'},
    'connections.node': {'zh': '节点', 'en': 'Node'},
    'connections.rule': {'zh': '规则', 'en': 'Rule'},
    'connections.traffic': {'zh': '流量', 'en': 'Traffic'},
    'connections.duration': {'zh': '时长', 'en': 'Duration'},
    'connections.process': {'zh': '进程', 'en': 'Process'},
    'connections.source': {'zh': '来源', 'en': 'Source'},
    'connections.destination': {'zh': '目标', 'en': 'Destination'},
    'connections.network': {'zh': '网络', 'en': 'Network'},
    'connections.start': {'zh': '开始时间', 'en': 'Started'},
    'connections.notRunning': {'zh': '内核尚未运行', 'en': 'Core is not running'},
    'connections.notRunningHint': {
      'zh': '启动内核以查看实时连接',
      'en': 'Start the core to inspect connections',
    },
    'connections.details': {'zh': '连接详情', 'en': 'Connection details'},

    // ------------------------------------------------------------------- logs
    'logs.subtitle': {'zh': '内核实时输出', 'en': 'Live output from the core'},
    'logs.level': {'zh': '级别', 'en': 'Level'},
    'logs.level.all': {'zh': '全部', 'en': 'All'},
    'logs.level.debug': {'zh': '调试', 'en': 'Debug'},
    'logs.level.info': {'zh': '信息', 'en': 'Info'},
    'logs.level.warning': {'zh': '警告', 'en': 'Warning'},
    'logs.level.error': {'zh': '错误', 'en': 'Error'},
    'logs.search': {'zh': '搜索日志', 'en': 'Search logs'},
    'logs.pause': {'zh': '暂停', 'en': 'Pause'},
    'logs.resume': {'zh': '继续', 'en': 'Resume'},
    'logs.clear': {'zh': '清空', 'en': 'Clear'},
    'logs.empty': {'zh': '暂无日志', 'en': 'No logs yet'},
    'logs.emptyHint': {
      'zh': '内核运行后，日志会显示在这里',
      'en': 'Logs will appear once the core is running',
    },
    'logs.notRunning': {'zh': '内核尚未运行', 'en': 'Core is not running'},
    'logs.paused': {'zh': '已暂停', 'en': 'Paused'},
    'logs.count': {'zh': '{0} 条日志', 'en': '{0} entries'},
    'logs.copyLine': {'zh': '复制日志', 'en': 'Copy log'},

    // -------------------------------------------------------------------- dns
    'dns.subtitle': {
      'zh': '通过内核 DNS 模块解析域名',
      'en': 'Resolve domains through the core',
    },
    'dns.placeholder': {
      'zh': '输入域名，如 example.com',
      'en': 'Enter a domain, e.g. example.com',
    },
    'dns.type': {'zh': '类型', 'en': 'Type'},
    'dns.query': {'zh': '查询', 'en': 'Query'},
    'dns.querying': {'zh': '查询中…', 'en': 'Querying…'},
    'dns.result': {'zh': '查询结果', 'en': 'Result'},
    'dns.answer': {'zh': '应答', 'en': 'Answers'},
    'dns.empty': {'zh': '没有解析结果', 'en': 'No records returned'},
    'dns.failed': {'zh': '查询失败', 'en': 'Query failed'},
    'dns.hint': {
      'zh': '内核需处于运行状态，且配置启用了 DNS',
      'en': 'The core must be running with DNS enabled',
    },
    'dns.hintReady': {'zh': '输入域名后点击查询', 'en': 'Enter a domain and tap Query'},
    'dns.status': {'zh': '状态码', 'en': 'Status code'},
    'dns.ttl': {'zh': 'TTL', 'en': 'TTL'},
    'dns.name': {'zh': '域名', 'en': 'Name'},
    'dns.value': {'zh': '记录值', 'en': 'Value'},
    'dns.recent': {'zh': '最近查询', 'en': 'Recent queries'},
    'dns.clearHistory': {'zh': '清除历史', 'en': 'Clear history'},
    'dns.invalid': {'zh': '请输入有效域名', 'en': 'Enter a valid domain'},
    'dns.notRunning': {'zh': '内核尚未运行', 'en': 'Core is not running'},

    // ------------------------------------------------------------------ rules
    'rules.subtitle': {'zh': '当前订阅生效的匹配规则', 'en': 'Matching rules in effect'},
    'rules.count': {'zh': '{0} 条规则', 'en': '{0} rules'},
    'rules.search': {
      'zh': '搜索规则类型、内容或策略',
      'en': 'Filter by type, payload or target',
    },
    'rules.empty': {'zh': '暂无规则', 'en': 'No rules'},
    'rules.emptyHint': {
      'zh': '启动内核后这里会显示生效规则',
      'en': 'Start the core to view active rules',
    },
    'rules.type': {'zh': '类型', 'en': 'Type'},
    'rules.payload': {'zh': '内容', 'en': 'Payload'},
    'rules.target': {'zh': '策略', 'en': 'Target'},
    'rules.notRunning': {'zh': '内核尚未运行', 'en': 'Core is not running'},

    // -------------------------------------------------------------- providers
    'providers.subtitle': {
      'zh': '管理订阅内的外部代理集合',
      'en': 'Remote proxy sets from your subscription',
    },
    'providers.count': {'zh': '{0} 个提供者', 'en': '{0} providers'},
    'providers.updateAll': {'zh': '更新全部', 'en': 'Update all'},
    'providers.update': {'zh': '更新', 'en': 'Update'},
    'providers.healthcheck': {'zh': '健康检查', 'en': 'Health check'},
    'providers.updated': {'zh': '更新于 {0}', 'en': 'Updated {0}'},
    'providers.nodes': {'zh': '{0} 个节点', 'en': '{0} nodes'},
    'providers.traffic': {'zh': '流量', 'en': 'Traffic'},
    'providers.empty': {'zh': '暂无代理提供者', 'en': 'No providers'},
    'providers.emptyHint': {
      'zh': '当前订阅没有使用 proxy-providers',
      'en': 'This subscription has no proxy-providers',
    },
    'providers.updateSuccess': {'zh': '“{0}”已更新', 'en': '“{0}” updated'},
    'providers.healthcheckSuccess': {
      'zh': '健康检查完成',
      'en': 'Health check completed',
    },
    'providers.allUpdated': {'zh': '全部提供者已更新', 'en': 'All providers updated'},
    'providers.notRunning': {'zh': '内核尚未运行', 'en': 'Core is not running'},
    'providers.failed': {'zh': '操作失败', 'en': 'Operation failed'},
    'providers.vehicle': {'zh': '类型', 'en': 'Vehicle'},

    // --------------------------------------------------------- rule providers
    'ruleProviders.subtitle': {
      'zh': '管理订阅内的外部规则集合',
      'en': 'Remote rule sets from your subscription',
    },
    'ruleProviders.count': {'zh': '{0} 个规则提供者', 'en': '{0} rule providers'},
    'ruleProviders.updateAll': {'zh': '更新全部', 'en': 'Update all'},
    'ruleProviders.update': {'zh': '更新', 'en': 'Update'},
    'ruleProviders.updated': {'zh': '更新于 {0}', 'en': 'Updated {0}'},
    'ruleProviders.rules': {'zh': '{0} 条规则', 'en': '{0} rules'},
    'ruleProviders.empty': {'zh': '暂无规则提供者', 'en': 'No rule providers'},
    'ruleProviders.emptyHint': {
      'zh': '当前订阅没有使用 rule-providers',
      'en': 'This subscription has no rule-providers',
    },
    'ruleProviders.updateSuccess': {'zh': '“{0}”已更新', 'en': '“{0}” updated'},
    'ruleProviders.allUpdated': {
      'zh': '全部规则提供者已更新',
      'en': 'All rule providers updated',
    },
    'ruleProviders.notRunning': {'zh': '内核尚未运行', 'en': 'Core is not running'},
    'ruleProviders.failed': {'zh': '操作失败', 'en': 'Operation failed'},

    // --------------------------------------------------------------- settings
    'settings.subtitle': {
      'zh': '调整外观、网络与内核选项',
      'en': 'Appearance, network and core options',
    },
    'settings.search': {'zh': '搜索设置', 'en': 'Search settings'},
    'settings.noResults': {'zh': '没有匹配的设置', 'en': 'No matching settings'},
    'settings.group.personalization': {'zh': '个性化', 'en': 'Personalization'},
    'settings.group.clash': {'zh': 'Clash', 'en': 'Clash'},
    'settings.group.advanced': {'zh': '高级配置', 'en': 'Advanced'},
    'settings.group.app': {'zh': '应用', 'en': 'App'},
    'settings.group.maintenance': {'zh': '维护', 'en': 'Maintenance'},
    'settings.hub.themeHint': {
      'zh': '外观模式、主题色与纯黑背景',
      'en': 'Mode, accent color and pure black',
    },
    'settings.hub.clash': {'zh': 'Clash 特性', 'en': 'Clash features'},
    'settings.hub.clashHint': {
      'zh': '端口、密钥、局域网与系统代理',
      'en': 'Ports, secret, LAN and system proxy',
    },
    'settings.hub.behavior': {'zh': '应用行为', 'en': 'App behavior'},
    'settings.hub.behaviorHint': {
      'zh': '内核自启与订阅自动更新',
      'en': 'Core autostart and subscription updates',
    },
    'settings.hub.data': {'zh': '数据管理', 'en': 'Data management'},
    'settings.hub.dataHint': {
      'zh': '批量更新订阅、清除选择与重置',
      'en': 'Refresh subscriptions, clear selections and reset',
    },
    'settings.splitTunnel': {'zh': '分应用代理', 'en': 'Per-app proxy'},
    'settings.splitTunnelHint': {
      'zh': '选择哪些应用通过 VPN 隧道',
      'en': 'Choose which apps use the VPN tunnel',
    },
    'settings.split.mode': {'zh': '代理范围', 'en': 'Proxy scope'},
    'settings.split.mode.all': {'zh': '全部应用', 'en': 'All apps'},
    'settings.split.mode.allHint': {
      'zh': '所有应用都通过 VPN',
      'en': 'Every app uses the VPN',
    },
    'settings.split.mode.allow': {'zh': '仅代理所选', 'en': 'Selected only'},
    'settings.split.mode.allowHint': {
      'zh': '只有选中的应用通过 VPN',
      'en': 'Only selected apps use the VPN',
    },
    'settings.split.mode.allowLocked': {
      'zh': '请先在下方选择至少一个应用',
      'en': 'Select at least one app below first',
    },
    'settings.split.mode.disallow': {'zh': '排除所选', 'en': 'Exclude selected'},
    'settings.split.mode.disallowHint': {
      'zh': '选中的应用不通过 VPN',
      'en': 'Selected apps bypass the VPN',
    },
    'settings.split.apps': {'zh': '应用列表', 'en': 'Apps'},
    'settings.split.search': {'zh': '搜索应用或包名', 'en': 'Search apps or packages'},
    'settings.split.count': {'zh': '已选 {0} 个', 'en': '{0} selected'},
    'settings.split.selectAll': {'zh': '全选', 'en': 'Select all'},
    'settings.split.clear': {'zh': '清空', 'en': 'Clear'},
    'settings.split.loadFailed': {
      'zh': '读取应用列表失败',
      'en': 'Failed to load apps',
    },
    'settings.split.empty': {'zh': '没有可用的应用', 'en': 'No apps available'},
    'settings.split.emptyHint': {
      'zh': '系统没有返回可启动的应用',
      'en': 'No launchable apps were returned',
    },
    'settings.split.searchEmpty': {'zh': '没有匹配的应用', 'en': 'No matching apps'},
    'settings.split.system': {'zh': '系统', 'en': 'System'},
    'settings.split.selfExcluded': {
      'zh': 'ClashGo 自身始终不经过 VPN，避免代理流量回环。',
      'en': 'ClashGo itself always bypasses the VPN to avoid routing loops.',
    },
    'settings.split.allModeNote': {
      'zh': '当前为全部应用模式，下面的选择已保存，切换范围后生效。',
      'en': 'All apps are proxied. Selections below are saved and apply after changing the scope.',
    },
    'settings.split.allowEmpty': {
      'zh': '选中的应用都不可用，请重新选择，否则内核无法启动。',
      'en': 'None of the selected apps are available. Select again or the core cannot start.',
    },
    'settings.split.allowKeepOne': {
      'zh': '「仅代理所选」模式至少要保留一个应用。',
      'en': 'Keep at least one app while using the selected-only mode.',
    },
    'settings.split.restartNeeded': {
      'zh': '分应用代理已修改，重启内核后生效。',
      'en': 'Per-app proxy changed. Restart the core to apply.',
    },
    'settings.split.restart': {'zh': '重启内核', 'en': 'Restart core'},
    'settings.aboutApp': {'zh': '关于 ClashGo', 'en': 'About ClashGo'},
    'settings.appearance': {'zh': '外观', 'en': 'Appearance'},
    'settings.languageHint': {
      'zh': '选择界面显示语言',
      'en': 'Choose the interface language',
    },
    'settings.accentHint': {
      'zh': '选择应用的强调色',
      'en': 'Pick the app accent color',
    },
    'settings.copySecret': {'zh': '复制密钥', 'en': 'Copy secret'},
    'settings.clearSelectionsHint': {
      'zh': '下次启动时重新选择策略组节点',
      'en': 'Pick group nodes again on the next start',
    },
    'settings.resetHint': {
      'zh': '恢复默认外观、端口与内核设置',
      'en': 'Restore default appearance, ports and core settings',
    },
    'settings.theme': {'zh': '主题', 'en': 'Theme'},
    'settings.theme.system': {'zh': '跟随系统', 'en': 'System'},
    'settings.theme.light': {'zh': '浅色', 'en': 'Light'},
    'settings.theme.dark': {'zh': '深色', 'en': 'Dark'},
    'settings.accent': {'zh': '主题色', 'en': 'Accent color'},
    'settings.language': {'zh': '语言', 'en': 'Language'},
    'settings.pureBlack': {'zh': '纯黑模式', 'en': 'Pure black'},
    'settings.pureBlackHint': {
      'zh': '深色模式下使用纯黑背景',
      'en': 'Use true black in dark mode',
    },
    'settings.network': {'zh': '网络', 'en': 'Network'},
    'settings.mixedPort': {'zh': '混合端口', 'en': 'Mixed port'},
    'settings.mixedPortHint': {
      'zh': '应用通过此端口使用代理',
      'en': 'Apps connect through this port',
    },
    'settings.apiPort': {'zh': '控制端口', 'en': 'API port'},
    'settings.apiPortHint': {
      'zh': 'mihomo 外部控制器的监听端口',
      'en': 'External controller port',
    },
    'settings.secret': {'zh': 'API 密钥', 'en': 'API secret'},
    'settings.secretHint': {'zh': '用于保护内核控制接口', 'en': 'Protects the core API'},
    'settings.allowLan': {'zh': '允许局域网连接', 'en': 'Allow LAN'},
    'settings.allowLanHint': {
      'zh': '同一网络下的设备可以使用本机代理',
      'en': 'Let other devices use this proxy',
    },
    'settings.ipv6': {'zh': 'IPv6', 'en': 'IPv6'},
    'settings.ipv6Hint': {
      'zh': '启用 IPv6 解析与连接',
      'en': 'Enable IPv6 resolution',
    },
    'settings.testUrl': {'zh': '测速 URL', 'en': 'Test URL'},
    'settings.testUrlHint': {
      'zh': '节点测速时访问的目标地址',
      'en': 'Target URL used for node delay tests',
    },
    'settings.testUrlTitle': {'zh': '测速 URL', 'en': 'Test URL'},
    'settings.testUrlInvalid': {
      'zh': '请输入有效的 http 或 https 地址',
      'en': 'Enter a valid http or https address',
    },
    'settings.tunParams': {'zh': 'TUN 参数', 'en': 'TUN parameters'},
    'settings.tunMtu': {'zh': 'MTU', 'en': 'MTU'},
    'settings.tunMtuHint': {
      'zh': 'VPN 网卡与内核协议栈共用的最大传输单元',
      'en': 'Maximum transmission unit shared by the VPN device and the core',
    },
    'settings.tunMtuTitle': {'zh': '编辑 TUN MTU', 'en': 'Edit TUN MTU'},
    'settings.tunMtuInvalid': {
      'zh': 'MTU 需在 1280–9000 之间',
      'en': 'MTU must be between 1280 and 9000',
    },
    'settings.tunStack': {'zh': '协议栈', 'en': 'Stack'},
    'settings.tunStackHint': {
      'zh': 'gvisor 兼容性最好，system 使用系统协议栈',
      'en': 'gvisor is the most compatible; system uses the OS stack',
    },
    'settings.tunRestartHint': {
      'zh': '隧道正在使用，保存后内核会自动重启',
      'en': 'TUN is in use; the core restarts automatically after saving',
    },
    'settings.systemProxy': {'zh': '系统代理', 'en': 'System proxy'},
    'settings.systemProxyHint': {
      'zh': '将 Windows 系统代理指向混合端口',
      'en': 'Point Windows proxy settings to the mixed port',
    },
    'settings.systemProxyUnsupported': {
      'zh': '仅 Windows 支持',
      'en': 'Windows only',
    },
    'settings.systemProxyVpn': {
      'zh': '移动端通过 VPN 接管全部流量',
      'en': 'Mobile routes traffic through the VPN',
    },
    'settings.proxyBypass': {'zh': '系统代理绕过', 'en': 'Proxy bypass'},
    'settings.proxyBypassHint': {
      'zh': '这些地址始终直连，不写入系统代理',
      'en': 'These addresses always connect directly',
    },
    'settings.proxyBypassCount': {'zh': '{0} 条规则', 'en': '{0} rules'},
    'settings.proxyBypassTitle': {'zh': '编辑绕过列表', 'en': 'Edit proxy bypass'},
    'settings.proxyBypassMessage': {
      'zh': '每行一条，也可用分号分隔；支持 * 通配，例如 192.168.*。',
      'en': 'One entry per line or separated by semicolons. Wildcards such as 192.168.* are supported.',
    },
    'settings.proxyBypassEmpty': {
      'zh': '至少保留一条绕过规则',
      'en': 'Keep at least one bypass entry',
    },
    'settings.proxyBypassReset': {'zh': '恢复默认', 'en': 'Restore default'},
    'settings.restartRequired': {
      'zh': '修改端口或密钥后需要重启内核',
      'en': 'Restart the core after changing ports or the secret',
    },
    'settings.secretConfirmMessage': {
      'zh': '生成新密钥后，仍在用旧密钥连接的应用需要重新配置。',
      'en': 'Apps still using the old secret will need to be reconfigured.',
    },
    'settings.updateAllSubsHint': {
      'zh': '逐个刷新所有订阅',
      'en': 'Refresh every subscription',
    },
    'settings.saveNetwork': {'zh': '保存设置', 'en': 'Save settings'},
    'settings.saved': {'zh': '设置已保存', 'en': 'Settings saved'},
    'settings.invalidPort': {
      'zh': '端口需在 1–65535 之间',
      'en': 'Port must be between 1 and 65535',
    },
    'settings.portConflict': {'zh': '两个端口不能相同', 'en': 'Ports must differ'},
    'settings.core': {'zh': '内核', 'en': 'Core'},
    'settings.coreState': {'zh': '运行状态', 'en': 'Status'},
    'settings.coreBinary': {'zh': '内核路径', 'en': 'Binary'},
    'settings.runtimeDir': {'zh': '运行目录', 'en': 'Runtime directory'},
    'settings.openRuntimeDir': {'zh': '打开目录', 'en': 'Open folder'},
    'settings.copyPath': {'zh': '复制路径', 'en': 'Copy path'},
    'settings.coreNotBundled': {
      'zh': '当前平台未内置内核',
      'en': 'The core binary is not bundled on this platform',
    },
    'settings.tools': {'zh': '工具', 'en': 'Tools'},
    'settings.data': {'zh': '数据', 'en': 'Data'},
    'settings.updateAllSubs': {
      'zh': '更新全部订阅',
      'en': 'Update all subscriptions',
    },
    'settings.clearSelections': {'zh': '清除节点选择', 'en': 'Clear node selections'},
    'settings.clearSelectionsDone': {
      'zh': '已清除节点选择',
      'en': 'Node selections cleared',
    },
    'settings.backupExport': {'zh': '导出备份', 'en': 'Export backup'},
    'settings.backupExportHint': {
      'zh': '保存设置、订阅、节点选择与测速结果',
      'en': 'Save settings, subscriptions, selections and delays',
    },
    'settings.backupImport': {'zh': '导入备份', 'en': 'Import backup'},
    'settings.backupImportHint': {
      'zh': '从备份文件整包恢复当前数据',
      'en': 'Replace the current data from a backup file',
    },
    'settings.backupExportTitle': {'zh': '导出备份', 'en': 'Export backup'},
    'settings.backupExportMessage': {
      'zh': '备份包含订阅链接、订阅原文和 API 密钥，等同于一份明文凭据。请妥善保管，不要分享给他人。',
      'en': 'The backup contains subscription URLs, profiles and the API secret — treat it as plain-text credentials and keep it private.',
    },
    'settings.backupExportDone': {'zh': '备份已导出', 'en': 'Backup exported'},
    'settings.backupExportFailed': {
      'zh': '导出备份失败',
      'en': 'Could not export the backup',
    },
    'settings.backupImportTitle': {'zh': '导入备份', 'en': 'Import backup'},
    'settings.backupImportMessage': {
      'zh': '将用备份替换当前的设置、订阅和节点选择（{0} 个订阅、{1} 个配置文件）。此操作不可撤销，内核会停止运行。',
      'en': 'This replaces the current settings, subscriptions and selections with the backup ({0} subscriptions, {1} profiles). It cannot be undone and the core will stop.',
    },
    'settings.backupImportInvalid': {
      'zh': '备份文件无效',
      'en': 'This backup file is not valid',
    },
    'settings.backupImported': {
      'zh': '备份已恢复：{0} 个订阅、{1} 个配置文件',
      'en': 'Backup restored: {0} subscriptions, {1} profiles',
    },
    'settings.backupImportedRestart': {
      'zh': '备份已恢复：{0} 个订阅、{1} 个配置文件；内核已停止，请重新启动',
      'en': 'Backup restored: {0} subscriptions, {1} profiles. The core is stopped — start it again.',
    },
    'settings.checkCoreUpdate': {
      'zh': '检查内核更新',
      'en': 'Check core update',
    },
    'settings.checkCoreUpdateHint': {
      'zh': '从 mihomo 官方 release 下载并校验新内核',
      'en': 'Download and verify the latest core from mihomo releases',
    },
    'settings.coreCheckFailed': {
      'zh': '检查内核更新失败',
      'en': 'Could not check for a core update',
    },
    'settings.coreUpdateLatest': {
      'zh': '已是最新内核',
      'en': 'The core is up to date',
    },
    'settings.coreUpdateAvailable': {
      'zh': '发现新内核 {0}',
      'en': 'Core {0} is available',
    },
    'settings.coreUpdateDialogTitle': {'zh': '更新内核', 'en': 'Update core'},
    'settings.coreUpdateDialogMessage': {
      'zh': '当前 {0}，最新 {1}。下载后会先运行新内核校验版本，再停止内核替换文件；期间代理会短暂中断。',
      'en': 'You have {0}; the latest is {1}. The new core is verified before replacing the current one, and the proxy briefly stops during the swap.',
    },
    'settings.coreUpdateAction': {
      'zh': '下载并更新',
      'en': 'Download and update',
    },
    'settings.coreUpdateProgress': {
      'zh': '正在下载并校验新内核…',
      'en': 'Downloading and verifying the new core…',
    },
    'settings.coreUpdateInstalled': {
      'zh': '内核已更新到 {0}',
      'en': 'Core updated to {0}',
    },
    'settings.coreUpdateTunHint': {
      'zh': '内核已更新到 {0}；TUN 需要重新授权，请在首页手动启动',
      'en': 'Core updated to {0}. TUN needs fresh approval — start it from the home page.',
    },
    'settings.coreRestore': {
      'zh': '恢复内置内核',
      'en': 'Restore bundled core',
    },
    'settings.coreRestoreHint': {
      'zh': '删除已更新的内核，回到安装包内置版本',
      'en': 'Remove the updated core and use the bundled one',
    },
    'settings.coreRestoreTitle': {'zh': '恢复内置内核', 'en': 'Restore bundled core'},
    'settings.coreRestoreMessage': {
      'zh': '将删除已下载的内核并改用安装包内置版本，当前内核会停止运行。',
      'en': 'The downloaded core will be removed and the bundled one used instead. The running core will stop.',
    },
    'settings.coreRestoreDone': {
      'zh': '已恢复内置内核',
      'en': 'Bundled core restored',
    },
    'settings.coreSource': {'zh': '内核来源', 'en': 'Core source'},
    'settings.coreSourceBundled': {
      'zh': '安装包内置',
      'en': 'Bundled with the app',
    },
    'settings.coreSourceUpdated': {
      'zh': '已更新（支持目录）',
      'en': 'Updated (app data)',
    },
    'settings.reset': {'zh': '重置设置', 'en': 'Reset settings'},
    'settings.resetTitle': {'zh': '重置所有设置', 'en': 'Reset all settings'},
    'settings.resetMessage': {
      'zh': '将恢复默认外观、网络与内核选项，订阅与节点选择会保留。',
      'en': 'Restore default appearance, network and core settings. Subscriptions are kept.',
    },
    'settings.resetDone': {'zh': '设置已重置', 'en': 'Settings reset'},
    'settings.about': {'zh': '关于', 'en': 'About'},
    'settings.more': {'zh': '更多', 'en': 'More'},
    'settings.aboutHint': {
      'zh': '开源、轻量的 mihomo 客户端',
      'en': 'An open-source, lightweight mihomo client',
    },
    'settings.version': {'zh': '版本', 'en': 'Version'},
    'settings.coreVersion': {'zh': '内核版本', 'en': 'Core version'},
    'settings.github': {'zh': '项目主页', 'en': 'GitHub'},
    'settings.license': {'zh': '许可证', 'en': 'License'},
    'settings.credits': {'zh': '开源致谢', 'en': 'Credits'},
    'settings.diagnostics': {'zh': '诊断', 'en': 'Diagnostics'},
    'settings.copyDiagnostics': {'zh': '复制诊断信息', 'en': 'Copy diagnostics'},
    'settings.diagnosticsCopied': {'zh': '诊断信息已复制', 'en': 'Diagnostics copied'},
    'settings.danger': {'zh': '危险操作', 'en': 'Danger zone'},
    'settings.autoStart': {'zh': '启动时自动运行', 'en': 'Start core on launch'},
    'settings.autoStartHint': {
      'zh': '打开应用后自动启动内核',
      'en': 'Start the core when the app opens',
    },
    'settings.launchAtStartup': {'zh': '开机自启', 'en': 'Launch at login'},
    'settings.launchAtStartupHint': {
      'zh': '登录系统后在托盘中静默启动',
      'en': 'Start hidden in the tray after signing in',
    },
    'settings.closeToTray': {'zh': '关闭窗口时最小化到托盘', 'en': 'Close to tray'},
    'settings.closeToTrayHint': {
      'zh': '托盘菜单可重新打开或退出应用',
      'en': 'Reopen or quit from the tray menu',
    },
    'settings.subscriptionOptions': {'zh': '订阅', 'en': 'Subscriptions'},
    'settings.secretRegenerate': {'zh': '重新生成', 'en': 'Regenerate'},
    'settings.secretRegenerated': {
      'zh': '已生成新的密钥',
      'en': 'New secret generated',
    },
    'settings.openFailed': {'zh': '无法打开目录', 'en': 'Could not open folder'},
    'settings.systemProxySaved': {
      'zh': '系统代理已更新',
      'en': 'System proxy updated',
    },
    'settings.systemProxyDisabled': {
      'zh': '系统代理已恢复',
      'en': 'System proxy restored',
    },
    'settings.autoUpdateSubs': {
      'zh': '自动更新订阅',
      'en': 'Auto update subscriptions',
    },
    'settings.autoUpdateSubsHint': {
      'zh': '按每个订阅设定的间隔检查更新',
      'en': 'Check each subscription at its own interval',
    },
    'settings.systemSection': {'zh': '系统', 'en': 'System'},
    'settings.updateSection': {'zh': '应用更新', 'en': 'App updates'},
    'settings.checkUpdates': {'zh': '检查更新', 'en': 'Check for updates'},
    'settings.checkUpdatesHint': {
      'zh': '检查是否有新版本',
      'en': 'Look for a newer release',
    },
    'settings.updateChannel': {'zh': '更新渠道', 'en': 'Update channel'},
    'settings.channel.stable': {'zh': '稳定版', 'en': 'Stable'},
    'settings.channel.preview': {'zh': '预览版', 'en': 'Preview'},
    'settings.checkUpdatesOnStartup': {
      'zh': '启动时检查更新',
      'en': 'Check for updates on launch',
    },
    'settings.checkUpdatesOnStartupHint': {
      'zh': '发现新版本时提醒',
      'en': 'Notify when a new version is available',
    },
    'settings.upToDate': {'zh': '已是最新版本', 'en': "You're up to date"},
    'settings.updateAvailable': {
      'zh': '发现新版本 {0}',
      'en': 'Version {0} is available',
    },
    'settings.updateDialogTitle': {'zh': '发现新版本', 'en': 'Update available'},
    'settings.updateDialogMessage': {
      'zh': '当前版本 {0}，最新版本 {1}。',
      'en': "You're on {0}; the latest is {1}.",
    },
    'settings.viewRelease': {'zh': '查看更新', 'en': 'View release'},
    'settings.updateFailed': {
      'zh': '检查更新失败',
      'en': 'Could not check for updates',
    },
    'settings.updateStartupNotice': {
      'zh': '发现新版本 {0}，可在“设置 → 关于”中查看',
      'en': 'Version {0} is available — open Settings → About to view it',
    },

    // ------------------------------------------------------------- DNS config
    'settings.dns': {'zh': 'DNS 配置', 'en': 'DNS configuration'},
    'settings.dnsHint': {
      'zh': '覆盖订阅里的 DNS 设置',
      'en': 'Override the subscription DNS',
    },
    'settings.dnsEnable': {'zh': '启用自定义 DNS', 'en': 'Use custom DNS'},
    'settings.dnsEnableHint': {
      'zh': '关闭时沿用订阅中的 dns 段',
      'en': 'When off, the dns section from your subscription is kept',
    },
    'settings.dnsEnhanced': {'zh': '解析模式', 'en': 'Enhanced mode'},
    'settings.dnsEnhancedHint': {
      'zh': 'fake-ip 兼容性最好，redir-host 返回真实 IP',
      'en': 'fake-ip is the most compatible; redir-host returns real IPs',
    },
    'settings.dnsMode.fakeIp': {'zh': 'fake-ip', 'en': 'fake-ip'},
    'settings.dnsMode.redirHost': {'zh': 'redir-host', 'en': 'redir-host'},
    'settings.dnsFakeIpRange': {'zh': 'fake-ip 网段', 'en': 'fake-ip range'},
    'settings.dnsFakeIpRangeHint': {
      'zh': '虚拟地址池，需为 IPv4 CIDR',
      'en': 'Virtual address pool in IPv4 CIDR form',
    },
    'settings.dnsNameserver': {'zh': '主 DNS', 'en': 'Nameservers'},
    'settings.dnsNameserverHint': {
      'zh': '用于解析代理节点域名',
      'en': 'Used to resolve proxy node hostnames',
    },
    'settings.dnsFallback': {'zh': '备用 DNS', 'en': 'Fallback DNS'},
    'settings.dnsFallbackHint': {
      'zh': '主 DNS 无法解析时使用，可留空',
      'en': 'Used when the primary DNS fails — optional',
    },
    'settings.dnsDefaultNameserver': {
      'zh': '引导 DNS',
      'en': 'Default nameservers',
    },
    'settings.dnsDefaultNameserverHint': {
      'zh': '解析 DNS 服务器自身域名，需为 IP',
      'en': 'Resolves the DNS servers themselves; use IPs',
    },
    'settings.dnsRestartHint': {
      'zh': '修改后会重启内核以写入 config.yaml；TUN 模式下会重新接管 DNS。',
      'en': 'Changes restart the core to rewrite config.yaml; TUN mode re-takes over DNS.',
    },
    'settings.dnsDisabledHint': {
      'zh': '自定义 DNS 已关闭，订阅里的 dns 段保持不变。',
      'en': 'Custom DNS is off; the dns section from your subscription is unchanged.',
    },
    'settings.dnsServersEmpty': {
      'zh': '至少填写一个 DNS 服务器',
      'en': 'Add at least one DNS server',
    },
    'settings.dnsServersHint': {'zh': '每行一个，例如 223.5.5.5', 'en': 'One per line, e.g. 223.5.5.5'},
    'settings.dnsServersFormat': {
      'zh': '支持 udp://、tcp://、tls://、https:// 前缀；留空行会被忽略，重复项自动去除。',
      'en': 'Supports udp://, tcp://, tls:// and https:// prefixes. Blank lines are ignored and duplicates removed.',
    },
    'settings.dnsInvalidRange': {
      'zh': '请输入合法的 IPv4 CIDR，例如 198.18.0.1/16',
      'en': 'Enter a valid IPv4 CIDR, e.g. 198.18.0.1/16',
    },

    // --------------------------------------------------------- YAML override
    'settings.override': {'zh': '配置覆写', 'en': 'Config override'},
    'settings.overrideHint': {
      'zh': '把自定义 YAML 深度合并进生成的配置',
      'en': 'Deep-merge custom YAML into the generated config',
    },
    'settings.overrideEditorHint': {
      'zh': 'YAML 顶层必须是映射，会深度合并进生成的 config.yaml；列表和标量直接替换。端口、密钥、TUN、代理模式等由 ClashGo 管理的字段不允许覆写。',
      'en': 'The YAML root must be a mapping and is deep-merged into the generated config.yaml; lists and scalars replace. Fields managed by ClashGo — ports, secret, TUN, proxy mode and similar — cannot be overridden.',
    },
    'settings.overridePlaceholder': {
      'zh': '# 示例\nrouting-mark: 6666\nsniffer:\n  enable: true',
      'en': '# Example\nrouting-mark: 6666\nsniffer:\n  enable: true',
    },
    'settings.overrideApply': {'zh': '保存并应用', 'en': 'Save & apply'},
    'settings.overrideApplying': {'zh': '应用中…', 'en': 'Applying…'},
    'settings.overrideSaved': {'zh': '配置覆写已应用', 'en': 'Override applied'},
    'settings.overrideClear': {'zh': '清空', 'en': 'Clear'},
    'settings.overrideClearTitle': {'zh': '清空配置覆写', 'en': 'Clear override'},
    'settings.overrideClearMessage': {
      'zh': '将删除全部覆写内容并恢复订阅生成的配置。',
      'en': 'All override content will be removed and the generated config restored.',
    },
    'settings.overrideCleared': {'zh': '配置覆写已清空', 'en': 'Override cleared'},
    'tray.showWindow': {'zh': '显示主界面', 'en': 'Show window'},
    'tray.quit': {'zh': '退出 ClashGo', 'en': 'Quit ClashGo'},

    // ---------------------------------------------------------------- errors
    'err.noSubscription': {'zh': '请先添加订阅', 'en': 'Add a subscription first'},
    'err.noActiveSubscription': {
      'zh': '请先选择当前订阅',
      'en': 'Select an active subscription first',
    },
    'err.noProfile': {
      'zh': '找不到当前订阅的配置文件',
      'en': 'Active subscription profile is missing',
    },
    'err.coreMissing': {
      'zh': '未找到 mihomo 内核文件',
      'en': 'mihomo core binary is missing',
    },
    'err.portInUse': {'zh': '端口 {0} 已被占用', 'en': 'Port {0} is already in use'},
    'err.startFailed': {'zh': '内核启动失败', 'en': 'Failed to start the core'},
    'err.startTimeout': {
      'zh': '内核启动超时，请检查日志',
      'en': 'Core start timed out; check the logs',
    },
    'err.apiUnavailable': {
      'zh': '无法连接内核控制接口',
      'en': 'Cannot reach the core API',
    },
    'err.profileInvalid': {
      'zh': '配置文件不是有效的 YAML',
      'en': 'The config is not valid YAML',
    },
    'err.subscriptionFetch': {
      'zh': '获取订阅失败',
      'en': 'Failed to fetch subscription',
    },
    'err.subscriptionEmpty': {
      'zh': '订阅内容为空',
      'en': 'The subscription response is empty',
    },
    'err.invalidUrl': {'zh': '链接格式不正确', 'en': 'Invalid URL'},
    'err.unsupportedPlatform': {
      'zh': '当前平台暂不支持内核管理',
      'en': 'Core management is not supported on this platform',
    },
    'err.vpnPermissionDenied': {
      'zh': '未授予 VPN 权限，无法启动内核',
      'en': 'VPN permission was denied; the core cannot start',
    },
    'err.tunUacDenied': {
      'zh': '未通过管理员授权，TUN 接管无法启动',
      'en': 'Administrator approval was denied; TUN takeover cannot start',
    },
    'err.tunElevateFailed': {
      'zh': '提权内核启动失败',
      'en': 'Failed to start the elevated core',
    },
    'err.tunNotReady': {
      'zh': 'TUN 网卡没有建立，流量没有被接管',
      'en': 'The TUN adapter never came up; no traffic is being taken over',
    },
    'err.tunStopUnconfirmed': {
      'zh': '停止没有被确认：提权内核可能仍在运行，系统流量可能仍被接管。请在管理员权限的任务管理器里结束 mihomo，或重启电脑。',
      'en': 'The stop was not confirmed: the elevated core may still be running and system traffic may still be intercepted. End mihomo from an elevated Task Manager or restart the computer.',
    },
    'err.unsupportedFile': {
      'zh': '仅支持 YAML 配置文件',
      'en': 'Only YAML config files are supported',
    },
    'err.coreExited': {
      'zh': '内核进程已退出（代码 {0}）',
      'en': 'The core exited (code {0})',
    },
    'err.generic': {'zh': '发生未知错误', 'en': 'An unexpected error occurred'},
    'err.overrideInvalid': {
      'zh': '配置覆写无效',
      'en': 'Invalid config override',
    },
    'err.saveConfig': {'zh': '写入配置失败', 'en': 'Failed to write config'},
    'err.filePick': {'zh': '文件选择失败', 'en': 'Failed to pick a file'},
    'err.invalidConfig': {
      'zh': '内核拒绝了该配置',
      'en': 'The core rejected this config',
    },
    'err.noNodes': {
      'zh': '配置中没有可用节点',
      'en': 'The config has no usable proxies',
    },
    'err.systemProxy': {
      'zh': '系统代理设置失败',
      'en': 'Failed to update the system proxy',
    },
    'err.backupInvalid': {
      'zh': '备份文件无效',
      'en': 'The backup file is not valid',
    },
    'err.coreUpdate': {
      'zh': '内核更新失败',
      'en': 'Core update failed',
    },
    'err.coreUpdateVerify': {
      'zh': '新内核校验失败，未替换原内核',
      'en': 'The new core failed verification; the current core was kept',
    },

    // ---------------------------------------------------------------- toasts
    'toast.modeChanged': {'zh': '已切换为{0}模式', 'en': 'Switched to {0} mode'},
    'toast.selectionApplied': {'zh': '已切换节点', 'en': 'Node selected'},
    'toast.coreStarted': {'zh': '内核已启动', 'en': 'Core started'},
    'toast.coreStopped': {'zh': '内核已停止', 'en': 'Core stopped'},

    // --------------------------------------------------------- notifications
    'notification.vpnTitle': {
      'zh': 'ClashGo 正在运行',
      'en': 'ClashGo is connected',
    },
    'notification.vpnText': {'zh': '点击返回应用管理连接', 'en': 'Tap to open the app'},
    'notification.stop': {'zh': '停止', 'en': 'Stop'},
    'toast.subscriptionAutoUpdated': {
      'zh': '已自动更新 {0} 个订阅',
      'en': 'Updated {0} subscriptions',
    },
    'toast.latencyTested': {'zh': '延迟测试完成', 'en': 'Latency test finished'},

    // --------------------------------------------------------------- relative
    'time.justNow': {'zh': '刚刚', 'en': 'Just now'},
    'time.minutesAgo': {'zh': '{0} 分钟前', 'en': '{0} min ago'},
    'time.hoursAgo': {'zh': '{0} 小时前', 'en': '{0} h ago'},
    'time.daysAgo': {'zh': '{0} 天前', 'en': '{0} d ago'},
    'time.never': {'zh': '从未', 'en': 'Never'},

    // ----------------------------------------------------------------- about
    'about.tagline': {
      'zh': '基于 mihomo 的多平台代理客户端，简单易用，开源无广告。',
      'en': 'A simple, open-source multi-platform mihomo client with no ads.',
    },
    'about.coreStopped': {'zh': '内核未运行', 'en': 'Core is not running'},
    'about.gpl': {'zh': '本项目以 GPL-3.0 许可证开源', 'en': 'Licensed under GPL-3.0'},
    'about.mihomo': {'zh': '内核：mihomo', 'en': 'Core: mihomo'},
    'about.brand': {
      'zh': '灵感与品牌来自 ClashGo 与 Mishka',
      'en': 'Inspired by and branded from ClashGo and Mishka',
    },
  };
}

class L10nScope extends InheritedWidget {
  const L10nScope({super.key, required this.l10n, required super.child});

  final L10n l10n;

  static L10n of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<L10nScope>();
    return scope?.l10n ?? const L10n('zh');
  }

  @override
  bool updateShouldNotify(L10nScope oldWidget) =>
      oldWidget.l10n.code != l10n.code;
}

extension L10nContext on BuildContext {
  L10n get l10n => L10nScope.of(this);

  String t(String key, [List<Object?> args = const []]) => l10n.get(key, args);
}
