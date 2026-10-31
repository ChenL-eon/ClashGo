class AppInfo {
  AppInfo._();

  static const name = 'Clash Go';
  static const version = '1.0.0';
  static const repository = 'https://github.com/ChenL-eon/ClashGo';
  static const mihomoRepository = 'https://github.com/MetaCubeX/mihomo';
  static const license = 'GPL-3.0';

  static const defaultMixedPort = 17890;
  static const defaultApiPort = 19090;
  static const defaultTestUrl = 'http://cp.cloudflare.com/generate_204';
  static const defaultUserAgent = 'clash.meta';

  // tun 的 MTU 只有一个来源：内核设备（安卓 VpnService.setMtu）和用户态协议栈
  // （mihomo tun.mtu，gvisor 按它切片）必须相等，不一致就会分片或踩 PMTUD 黑洞。
  // 这里改一次，config_generator 与 android_core 一起跟着走；安卓侧只认 extras
  // 里传过去的值，不再自己留一份常量。9000 在蜂窝/普通 Wi-Fi 的 1500 路径上会
  // 明显拉长射频驻留时间，所以固定 1500。
  static const tunMtu = 1500;

  // Windows 上给 TUN 网卡钉死的名字：不写 device 时内核用自己的默认名（这台机器
  // 实测是 Meta），默认名跟着内核走，探测就没法稳定认出"刚起的这张卡是不是我们的"。
  // device 在 Windows 上确实会被采用（只有 macOS 才校验名字格式），钉住它同时是
  // 可读性收益：网络连接面板里一眼看得出这张卡属于 ClashGo。
  //
  // 这里没有"网卡地址"常量：这个内核的 tun.inet4-address 不被解析，网卡地址一律由
  // dns.fake-ip-range 的首地址加 /30 推出来（真机实测 198.18.0.1/30）。把它写成
  // 常量再拿去判就绪，等到的是别人的 Clash Verge 那张同地址的网卡——判据见
  // TunReadiness。
  static const tunDeviceName = 'ClashGo';

  // 提权内核起来之后给网卡留多久。首次使用要装虚拟网卡驱动，慢的那一下是安装不是
  // 失败；但等太久，用户对着一个还在转的开关完全不知道该不该取消。
  static const tunReadyTimeout = Duration(seconds: 10);

  // /proxies 是这条控制面上最重的定期请求：整棵节点树（分组 + 每个节点的
  // now/history）一次全量拉回来。真正逐节点消费它的是代理页，其他页面只读主页
  // 那张"当前节点"卡片。所以代理页可见才保持 8 秒，不可见降到 30 秒——
  // 不能整个停掉：fallback / url-test 组会在内核侧自己换节点，停在 30 秒既能把
  // 变化带回来，又把无人看管时的唤醒次数砍到约 1/4。
  static const proxyPollVisibleInterval = Duration(seconds: 8);
  static const proxyPollIdleInterval = Duration(seconds: 30);

  // 内核日志档位只有一个来源：config 生成器写进 config.yaml 的值，和 /logs
  // 订阅的过滤档位，必须是同一个。两处各写一个 'info' 看着一样，改一处就漂移，
  // 而且漂移之后日志页只是静默空白，看不出是哪边的问题。
  // 保持 info 是有意的：日志页的价值在于"这条连接为什么走了这条规则"，降到
  // warning 只剩错误。它平时的唤醒代价由"日志页不可见就整条断开"控制
  // （见 AppController._syncLogFeed），不靠把档位调低来省。
  static const coreLogLevel = 'info';

  // 延迟探测的周期。一轮探测要对三条 target 各开一条经 mixed-port 的连接，
  // 等于三次独立出网 + 三次握手；5 分钟一档意味着挂着不动也会一直叫醒射频，
  // 而探测结果只是首页/代理页上那排状态点，页面不可见时没有消费者。
  // 所以周期放宽到 15 分钟，并且只在那些页面真的可见时才跑
  // （切到可见页面时补测一次，见 AppController.testLatency）。
  static const latencyProbeInterval = Duration(minutes: 15);

  static const latencyTargets = <LatencyTarget>[
    LatencyTarget('Baidu', 'http://www.baidu.com'),
    LatencyTarget('Cloudflare', 'http://cp.cloudflare.com/generate_204'),
    LatencyTarget('Google', 'http://www.google.com/generate_204'),
  ];
}

class LatencyTarget {
  const LatencyTarget(this.label, this.url);

  final String label;
  final String url;
}
