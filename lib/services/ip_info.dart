import 'dart:convert';
import 'dart:io';

import '../core/app_info.dart';
import 'network.dart';

class IpLocation {
  const IpLocation({required this.address, required this.region});

  final String address;

  /// ISO 3166-1 alpha-2 国家/地区代码，可能为空。
  final String region;
}

/// 经 mixed-port 查询 Cloudflare trace：拿到的 ip 是这条代理链路的真实出口，
/// loc 是出口所属国家/地区。相比解析订阅里的 server（往往是域名、且不等于出口），
/// 这才是用户想看的「节点 IP」。
class IpInfoService {
  const IpInfoService();

  static const _traceUrl = 'https://cloudflare.com/cdn-cgi/trace';

  Future<IpLocation?> lookup({int? proxyPort}) async {
    final client = createHttpClient(proxyPort: proxyPort, timeout: const Duration(seconds: 6));
    try {
      final request = await client.getUrl(Uri.parse(_traceUrl)).timeout(const Duration(seconds: 8));
      request.headers.set(HttpHeaders.userAgentHeader, 'ClashGo/${AppInfo.version}');
      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final body = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 8));
      var address = '';
      var region = '';
      for (final line in const LineSplitter().convert(body)) {
        if (line.startsWith('ip=')) address = line.substring(3).trim();
        if (line.startsWith('loc=')) region = line.substring(4).trim().toUpperCase();
      }
      if (address.isEmpty) return null;
      return IpLocation(address: address, region: region);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
