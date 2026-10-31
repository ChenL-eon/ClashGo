import 'package:clash_go/core/app_info.dart';
import 'package:clash_go/core/formatters.dart';
import 'package:clash_go/core/l10n.dart';
import 'package:clash_go/models/app_settings.dart';
import 'package:clash_go/models/subscription.dart';
import 'package:clash_go/services/android_core.dart';
import 'package:clash_go/services/config_generator.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('formatters', () {
    test('formats byte sizes', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(1023), '1023 B');
      expect(formatBytes(1024), '1 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1 MB');
      expect(formatSpeed(2048), '2 KB/s');
    });

    test('formats uptime', () {
      expect(formatUptime(null), '00:00:00');
      expect(formatUptime(const Duration(seconds: 65)), '00:01:05');
      expect(formatUptime(const Duration(hours: 2, minutes: 3, seconds: 4)), '02:03:04');
    });

    test('derives region flags from node names', () {
      expect(regionEmojiForNode('香港 01'), '🇭🇰');
      expect(regionEmojiForNode('Tokyo JP'), '');
      expect(regionEmojiForNode('🇺🇸 US West'), '🇺🇸');
    });

    test('masks secrets', () {
      expect(maskSecret(''), '—');
      expect(maskSecret('short'), '••••••••');
      expect(maskSecret('abcdefghijklmnop'), 'abcd••••mnop');
    });
  });

  group('subscription', () {
    Subscription build({int total = 0, int upload = 0, int download = 0, int expire = 0}) {
      return Subscription(
        id: 'a',
        name: 'Demo',
        url: 'https://example.com/sub',
        isLocal: false,
        createdAt: DateTime(2026),
        total: total,
        upload: upload,
        download: download,
        expire: expire,
        updateIntervalMinutes: 60,
        lastUpdatedAt: DateTime(2026, 1, 1),
      );
    }

    test('computes quota and next update', () {
      final sub = build(total: 1000, upload: 100, download: 150);
      expect(sub.used, 250);
      expect(sub.remaining, 750);
      expect(sub.usageRatio, closeTo(0.25, 1e-9));
      expect(sub.nextUpdateAt, DateTime(2026, 1, 1, 1));
      expect(sub.hasExpiry, isFalse);
    });

    test('clamps ratio and reads host', () {
      final sub = build(total: 100, upload: 90, download: 90);
      expect(sub.usageRatio, 1.0);
      expect(sub.remaining, 0);
      expect(sub.host, 'example.com');
    });
  });

  group('settings', () {
    test('round-trips through json', () {
      final settings = AppSettings.defaults(zh: false)
        ..mixedPort = 12345
        ..themeMode = 'dark'
        ..pureBlack = true
        ..systemProxy = false;
      final restored = AppSettings.fromJson(settings.toJson());
      expect(restored.language, 'en');
      expect(restored.mixedPort, 12345);
      expect(restored.themeMode, 'dark');
      expect(restored.pureBlack, isTrue);
      expect(restored.systemProxy, isFalse);
    });
  });

  group('l10n', () {
    test('falls back to Chinese and interpolates', () {
      const l10n = L10n('en');
      expect(l10n.get('nav.home'), 'Home');
      expect(l10n.get('connections.active', [3]), '3 active');
      expect(l10n.get('err.portInUse', [7890]), 'Port 7890 is already in use');
      expect(l10n.contains('does.not.exist'), isFalse);
      expect(const L10n('zh').get('nav.home'), '首页');
    });
  });

  group('core log level', () {
    const profile = '''
proxies:
  - {name: "HK 1", type: socks, server: 127.0.0.1, port: 7891}
''';

    test('config.yaml 的 log-level 出自 AppInfo.coreLogLevel', () {
      // 同一档位还被 /logs 订阅用着（见 app_shell_visibility_test 的 D2）。
      // 这里钉住生成器这一侧：改回来写成字面量，两处就会各自漂移。
      final config = const ConfigGenerator().generate(
        profile: profile,
        settings: AppSettings.defaults(zh: false),
        mode: 'rule',
      );
      expect(config, contains('log-level: ${AppInfo.coreLogLevel}'));
    });
  });

  group('tun mtu', () {
    const profile = '''
proxies:
  - {name: "HK 1", type: socks, server: 127.0.0.1, port: 7891}
''';

    test('value is pinned to the path MTU, not jumbo', () {
      // 9000 在蜂窝/普通 Wi-Fi 的 1500 路径上会被分片或触发 PMTUD 黑洞重传，
      // 射频驻留时间跟着变长；改这个数要连同下面的注释一起想清楚。
      expect(AppInfo.tunMtu, 1500);
    });

    test('config 的 tun.mtu 和 VpnService 收到的 mtu 出自同一个常量', () async {
      final config = const ConfigGenerator().generate(
        profile: profile,
        settings: AppSettings.defaults(zh: false),
        mode: 'rule',
        androidTun: true,
      );
      expect(config, contains('mtu: ${AppInfo.tunMtu}'));

      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.clashgo.clash_go/core'),
        (call) async {
          calls.add(call);
          return true;
        },
      );
      await AndroidCore.start(
        configPath: 'c',
        runtimeDir: 'r',
        binaryPath: 'b',
        logPath: 'l',
        apiPort: AppInfo.defaultApiPort,
        subscriptionId: null,
        ipv6: false,
        notificationTitle: 't',
        notificationText: 'x',
        notificationStop: 's',
      );

      final start = calls.singleWhere((call) => call.method == 'startVpn');
      expect((start.arguments as Map)['mtu'], AppInfo.tunMtu);
    });
  });

  group('windows tun config', () {
    const profile = '''
proxies:
  - {name: "HK 1", type: socks, server: 127.0.0.1, port: 7891}
''';

    String render({bool androidTun = false, bool windowsTun = false, bool ipv6 = false}) =>
        const ConfigGenerator().generate(
          profile: profile,
          settings: AppSettings.defaults(zh: false, systemProxy: false).copyWith(ipv6: ipv6),
          mode: 'rule',
          androidTun: androidTun,
          windowsTun: windowsTun,
        );

    test('默认不开 TUN：否则第一次启动内核就会弹 UAC', () {
      expect(AppSettings.defaults().tun, false);
      expect(render(), isNot(contains('tun:')));
    });

    test('windowsTun 建设备而不是接 fd：auto-route 必须为真', () {
      final config = render(windowsTun: true);
      expect(config, contains('tun:'));
      expect(config, contains('stack: gvisor'));
      // Windows 没有 auto-route 就没有任何流量会进隧道，等于开关白开。
      expect(config, contains('auto-route: true'));
      expect(config, contains('auto-detect-interface: true'));
      // strict-route 会把局域网一起吞掉，同机打印和 allow-lan 都会断。
      expect(config, contains('strict-route: false'));
      expect(config, contains('dns-hijack:'));
      expect(config, contains('any:53'));
      expect(config, contains('mtu: ${AppInfo.tunMtu}'));
      // 网卡名必须是那个常量：就绪探测去系统网卡列表里认的就是它，两处一旦写成
      // 不同的值，探测就永远等不到，把一次成功的接管报成失败。
      expect(config, contains('device: ${AppInfo.tunDeviceName}'));
      // 地址不写：这个内核（v1.19.33）不解析 tun.inet4-address——config.go:285 那行
      // yaml tag 是注释掉的，网卡地址一律由 dns.fake-ip-range 的首地址加 /30 推出来
      // （真机实测 198.18.0.1/30）。写进配置只留下一个不起作用的键，还会诱使后来的
      // 维护者拿它当就绪判据，而那条判据会把用户另一个客户端（Clash Verge 同样占着
      // 198.18.0.1/30）的网卡认成自己的接管成功。
      expect(config, isNot(contains('inet4-address')));
      expect(
        config.split('\n').where((line) => line.trim() == 'address:'),
        isEmpty,
        reason: 'address 不是这个内核认的 tun 字段，写了等于没写',
      );
    });

    test('windowsTun 不带 file-descriptor（那是安卓 VpnService 的 fd 通路）', () {
      expect(render(windowsTun: true), isNot(contains('file-descriptor')));
      expect(render(androidTun: true), contains('file-descriptor: __TUN_FD__'));
    });

    test('安卓档保持原样：auto-route 关掉，交给 VpnService', () {
      final config = render(androidTun: true);
      expect(config, contains('auto-route: false'));
      expect(config, contains('auto-detect-interface: false'));
      expect(config, contains('0.0.0.0:53'));
      // 安卓的网卡和地址都由 VpnService 分配，内核这边既不该再写地址，也不该写
      // device——fd 上来的那张卡没有名字可钉。
      expect(config, isNot(contains('inet4-address')));
      expect(config, isNot(contains('device:')));
    });

    test('隧道模式补齐解析器并去掉 53 端口监听', () {
      for (final config in [render(androidTun: true), render(windowsTun: true)]) {
        expect(config, contains('dns:'));
        expect(config, contains('doh.pub'));
        expect(config, isNot(contains('listen:')));
      }
    });

    test('ipv6 打开才分配隧道 v6 地址', () {
      expect(render(windowsTun: true), isNot(contains('inet6-address')));
      expect(render(windowsTun: true, ipv6: true), contains('inet6-address:'));
    });

    test('tun 开关能持久化回来', () {
      final settings = AppSettings.defaults(zh: false).copyWith(tun: true);
      final restored = AppSettings.fromJson(Map<String, dynamic>.from(settings.toJson()));
      expect(restored.tun, true);
      expect(restored.copyWith(tun: false).tun, false);
    });
  });

  test('latency targets are defined', () {
    expect(AppInfo.latencyTargets, isNotEmpty);
    expect(AppInfo.defaultMixedPort, 17890);
    expect(AppInfo.defaultApiPort, 19090);
  });
}
