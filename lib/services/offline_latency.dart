import 'dart:io';

import 'offline_proxies.dart';

class OfflineLatency {
  const OfflineLatency._();

  /// TCP 握手耗时。内核未启动时用于近似节点延迟，-1 表示超时/不可达。
  static Future<int?> probe(
    OfflineEndpoint endpoint, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final stopwatch = Stopwatch()..start();
    Socket? socket;
    try {
      socket = await Socket.connect(endpoint.host, endpoint.port, timeout: timeout);
      final value = stopwatch.elapsedMilliseconds;
      return value <= 0 ? 1 : value;
    } catch (_) {
      return -1;
    } finally {
      socket?.destroy();
    }
  }
}
