import 'dart:io';

import 'package:clash_go/core/app_info.dart';
import 'package:clash_go/services/tun_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

/// 探测认的是"这张网卡是不是我们这个实例起的"，所以两条判据（内核自己那句宣告、
/// 配置里钉死的网卡名）各自都能单独放行；网卡地址不是判据（真机实测它由
/// dns.fake-ip-range 推出来，而且是 Clash Verge 也会占着的那个 198.18.0.1/30）。
/// 注入的网卡名负责枚举那一半；能被造出来的那一半（判据本身、失败快停、超时措辞）
/// 才值得钉住。
void main() {
  // 探测要等的名字由 AppInfo.tunDeviceName 推出来，测试也跟着它走：写死字面量的话，
  // 常量一改测试就红，而那个红什么也说明不了。
  const device = AppInfo.tunDeviceName;

  Future<List<String>> noLogs() async => const [];
  Future<Set<String>> none() async => const <String>{};

  test('an adapter carrying the pinned device name counts as ready', () async {
    final probe = TunReadiness(listAdapterNames: () async => {'以太网', device});
    final problem = await probe.wait(timeout: const Duration(seconds: 2), pollLogs: noLogs);
    expect(problem, isNull);
  });

  test("the kernel's own success sentence is enough even when the adapter is invisible", () async {
    // 枚举网卡名不是保证能看到的：驱动刚装完时系统列表有延迟，而提权进程建的卡
    // 未必立刻被这边读到。内核说 "Tun adapter listening at" 的那一刻隧道就是起来了，
    // 探测不能因为列表里还没有它就把一次成功的接管报成失败。
    final probe = TunReadiness(listAdapterNames: none);
    final problem = await probe.wait(
      timeout: const Duration(seconds: 2),
      pollLogs: () async => [
        'time="2026-10-31T12:00:00+08:00" level=info msg="[TUN] Tun adapter listening at: '
            '$device([198.18.0.1/30],[])"',
      ],
    );
    expect(problem, isNull);
  });

  test("another client's adapter is not readiness", () async {
    // 用户机器上跑着 Clash Verge 时，那张卡同样叫 Meta、同样拿着 198.18.0.1/30。
    // 认名字而不是认地址/默认名，才不会把别人的隧道当成自己接管成功。
    final probe = TunReadiness(listAdapterNames: () async => {'Meta', '以太网'});
    final problem = await probe.wait(timeout: const Duration(milliseconds: 400), pollLogs: noLogs);
    expect(problem, isNotNull);
  });

  test('the kernel saying tun failed ends the wait immediately with its own words', () async {
    final probe = TunReadiness(listAdapterNames: none, interval: const Duration(milliseconds: 50));
    final started = DateTime.now();
    final problem = await probe.wait(
      timeout: const Duration(seconds: 30),
      pollLogs: () async => [
        'time="2026-10-31T12:00:00" level=warning msg="Start TUN listening error: '
            'configure tun interface: Access is denied."',
      ],
    );
    final elapsed = DateTime.now().difference(started);

    expect(problem, contains('Start TUN listening error'));
    expect(elapsed, lessThan(const Duration(seconds: 5)), reason: '内核已经说出原因了，不该再等满超时');
  });

  test('no adapter at all is reported as a timeout naming the adapter we waited for', () async {
    var checks = 0;
    final probe = TunReadiness(
      listAdapterNames: () async {
        checks++;
        return {'以太网', 'WLAN'};
      },
      interval: const Duration(milliseconds: 50),
    );
    final problem = await probe.wait(timeout: const Duration(milliseconds: 400), pollLogs: noLogs);

    // 用户要能在提示里看到在等哪张网卡：只有"超时"两个字的话，他不知道该去
    // 网络连接面板找什么、也不知道该关哪个占着这个名字的客户端。
    expect(problem, contains(device));
    expect(checks, greaterThan(1), reason: '超时之前必须真的反复查过');
  });

  test('an adapter that shows up late is still caught', () async {
    var checks = 0;
    final probe = TunReadiness(
      listAdapterNames: () async {
        checks++;
        // 模拟驱动首次安装：前两轮还没有网卡，第三轮才出现。
        return checks < 3 ? <String>{} : {device};
      },
      interval: const Duration(milliseconds: 50),
    );
    final problem = await probe.wait(timeout: const Duration(seconds: 2), pollLogs: noLogs);
    expect(problem, isNull);
    expect(checks, greaterThanOrEqualTo(3));
  });

  test('enumerating adapters is not confused with the adapter being absent', () async {
    final probe = TunReadiness(
      listAdapterNames: () async => throw const SocketException('transient'),
      interval: const Duration(milliseconds: 50),
    );
    final problem = await probe.wait(timeout: const Duration(milliseconds: 300), pollLogs: noLogs);

    // 这一条是实话问题：问不到系统就被说成"TUN 建不起来"，用户会去查一个不存在的原因。
    expect(problem, contains('enumeration failed'));
  });

  test('a healthy tun log line is not mistaken for a failure', () async {
    // "看到 tun 就判失败"是最省事的写法，也是最坏的：内核成功时同样在说 tun。
    // 网卡这里给成已就绪，所以用例唯一的出口只能是"这句日志没被判成失败"。
    final probe = TunReadiness(
      listAdapterNames: () async => {device},
      interval: const Duration(milliseconds: 50),
    );
    final problem = await probe.wait(
      timeout: const Duration(seconds: 2),
      pollLogs: () async => ['time="2026-10-31" level=info msg="tun interface configured"'],
    );
    expect(problem, isNull);
  });

  test('a line carrying both the success marker and a failure word counts as success', () async {
    // 同一条日志里两个词都有时（内核的措辞并不总是干净），按成功算才是它的本意。
    final probe = TunReadiness(listAdapterNames: none, interval: const Duration(milliseconds: 50));
    final problem = await probe.wait(
      timeout: const Duration(milliseconds: 400),
      pollLogs: () async => [
        'level=warning msg="Tun adapter listening at: $device([198.18.0.1/30],[]) '
            'but route setup failed"',
      ],
    );
    expect(problem, isNull);
  });

  test('the adapter name the probe waits for is the one the config pins', () async {
    // 就绪探测等的那个名字必须和写进 tun.device 的是同一个常量：两处各留一份迟早
    // 对不上，对不上之后探测会永远等不到，把一次成功的接管报成失败。
    expect(TunReadiness.wantedAdapterName, device);
  });

  test('the real enumerator returns adapter names', () async {
    // 注入替身覆盖了判据，但真那条路（NetworkInterface.list → 名字集合）也得至少跑
    // 一次，否则字段名拼错这类问题要等用户开隧道才暴露。这台机器上没开隧道，
    // 所以只验形状。
    final names = await TunReadiness.systemAdapterNames();
    expect(names, isA<Set<String>>());
    expect(names, isNotEmpty, reason: '任何机器都至少有一张网卡');
    for (final name in names) {
      expect(name.trim(), name, reason: '网卡名不带首尾空格：$name —— 探测按等值比较');
    }
  });
}
