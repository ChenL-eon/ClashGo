import 'dart:async';
import 'dart:io';

import '../core/app_info.dart';

/// Windows 的 TUN 就绪探测。
///
/// 为什么必须有它：内核在非管理员下建不出虚拟网卡，却**不会退出**——实测它照样把
/// mixed-port 和控制端口听起来继续跑，日志里只留一句 `Start TUN listening error`。
/// 于是"进程活着"和"控制接口答话"这两条判据全都通过，界面却是一片虚假的绿色。
///
/// 判据为什么不是网卡地址：这个内核（v1.19.33）里 `tun.inet4-address` 根本不被解析
/// （config.go:285 那行 yaml tag 是注释掉的），网卡地址一律由 `dns.fake-ip-range` 的
/// 首个地址加上 /30 推出来（config.go:1688-1706）。真机实测网卡拿到的是 198.18.0.1/30，
/// 配置里写什么都没用。而且这条判据本身也不安全：用户机器上跑着 Clash Verge 时，
/// 那张网卡同样是 198.18.0.1/30，"地址对上了"会把别人的隧道当成自己的接管成功。
///
/// 所以说话的是两条只属于我们这个实例的东西：内核自己宣告网卡建好的那句
/// `[TUN] Tun adapter listening at`（listener.go:534），和配置里钉死的网卡名——
/// `device` 在 Windows 上确实会被采用（sing_tun/server.go:151-154，只有 macOS 才校验
/// 名字格式），名字不对时内核才会退回默认名（实测是 Meta）。
class TunReadiness {
  TunReadiness({
    Future<Set<String>> Function()? listAdapterNames,
    this.interval = const Duration(milliseconds: 300),
  }) : _listAdapterNames = listAdapterNames ?? systemAdapterNames;

  final Duration interval;
  final Future<Set<String>> Function() _listAdapterNames;

  /// 内核宣告隧道网卡建好时用的那句话（v1.19.33 实测原文）。
  static const _readyMarker = 'tun adapter listening';

  /// 探测在等的网卡名，和写进 config 的 tun.device 是同一个常量：两处各写一份迟早
  /// 对不上，对不上之后探测就会永远等不到，把一次成功的接管报成失败。
  static String get wantedAdapterName => AppInfo.tunDeviceName;

  Future<String?> wait({
    required Duration timeout,
    required Future<List<String>> Function() pollLogs,
  }) async {
    final deadline = DateTime.now().add(timeout);
    Object? lastListFailure;
    while (true) {
      for (final line in await pollLogs()) {
        final text = line.toLowerCase();
        // 先认成功再认失败：一句同时含 "listening" 和某个失败字数的日志，按成功算
        // 才是内核的本意，按失败算就会把一次真的接管报成故障。
        if (text.contains(_readyMarker)) return null;
        if (_isTunFailure(text)) return line;
      }
      Set<String>? names;
      try {
        names = await _listAdapterNames();
        lastListFailure = null;
      } catch (error) {
        // 问不到系统不能当成"网卡不在"：那是探测自己的问题，不是用户隧道的问题。
        // 记下它，超时信息里带上。
        lastListFailure = error;
      }
      if (names != null && names.contains(wantedAdapterName)) return null;
      if (!DateTime.now().isBefore(deadline)) {
        final suffix = lastListFailure == null ? '' : ' (adapter enumeration failed: $lastListFailure)';
        return 'no TUN adapter named $wantedAdapterName appeared '
            'within ${timeout.inSeconds}s$suffix';
      }
      await Future<void>.delayed(interval);
    }
  }

  bool _isTunFailure(String text) {
    if (!text.contains('tun')) return false;
    // 成功那句里也有 tun，所以必须先由调用方判过 readyMarker；这里只认失败的措辞。
    return text.contains('error') || text.contains('denied') || text.contains('fail');
  }

  /// 系统里现在的网卡名。地址不进判据（理由见类注释），所以这里只取名字；
  /// 也不按 IPv4 过滤——判的既然是名字，一张只配了 IPv6 的网卡同样该被认出来。
  static Future<Set<String>> systemAdapterNames() async {
    final interfaces = await NetworkInterface.list(includeLoopback: false);
    return {for (final interface in interfaces) interface.name};
  }
}
