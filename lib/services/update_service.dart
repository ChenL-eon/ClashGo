import 'package:dio/dio.dart';

import '../core/app_info.dart';
import '../models/app_settings.dart';
import 'network.dart';

class UpdateRelease {
  const UpdateRelease({required this.version, required this.url});

  /// 去掉 tag 前缀 v 的版本号，例如 1.2.0 / 1.3.0-beta.1。
  final String version;
  final String url;
}

class UpdateService {
  const UpdateService();

  static const _latestUrl = '${AppInfo.repository}/releases/latest';
  static const _atomUrl = '${AppInfo.repository}/releases.atom';

  /// 稳定版用 GitHub 的 latest 重定向——它天然排除 draft/prerelease；
  /// 预览版取 releases.atom 的第一条（含 prerelease）。两条路都不吃 API 限流：
  /// 未登录的 api.github.com 与机场出口共享配额，很快就 403。
  Future<UpdateRelease?> latest({
    required String channel,
    int? proxyPort,
  }) async {
    final dio = createDio(proxyPort: proxyPort)
      ..options.connectTimeout = const Duration(seconds: 8)
      ..options.receiveTimeout = const Duration(seconds: 15);
    try {
      if (channel == AppSettings.channelPreview) {
        final response = await dio.get<String>(
          _atomUrl,
          options: Options(
            responseType: ResponseType.plain,
            headers: const {'Accept': 'application/atom+xml'},
          ),
        );
        return parseAtom(response.data ?? '');
      }
      final response = await dio.get<String>(
        _latestUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: const {'Accept': 'text/html'},
        ),
      );
      return releaseFromUri(response.realUri);
    } finally {
      dio.close(force: true);
    }
  }

  static UpdateRelease? releaseFromUri(Uri uri) {
    final tag = tagFromUri(uri);
    if (tag == null) return null;
    return UpdateRelease(version: normalizeVersion(tag), url: uri.toString());
  }

  static UpdateRelease? parseAtom(String xml) {
    final entry = RegExp(r'<entry>([\s\S]*?)</entry>').firstMatch(xml);
    if (entry == null) return null;
    final body = entry.group(1)!;
    final href = RegExp(r'<link[^>]*href="([^"]+)"').firstMatch(body)?.group(1);
    if (href == null) return null;
    final uri = Uri.tryParse(href);
    if (uri == null) return null;
    final tag = tagFromUri(uri);
    if (tag == null) return null;
    return UpdateRelease(version: normalizeVersion(tag), url: href);
  }

  static String? tagFromUri(Uri uri) {
    final segments = uri.pathSegments;
    final index = segments.indexOf('tag');
    if (index < 0 || index + 1 >= segments.length) return null;
    final tag = Uri.decodeComponent(segments[index + 1]).trim();
    return tag.isEmpty ? null : tag;
  }

  static String normalizeVersion(String tag) =>
      tag.trim().replaceFirst(RegExp(r'^[vV]'), '');

  static bool isNewer(String candidate, String current) =>
      compareVersions(candidate, current) > 0;

  /// SemVer 风格比较：先比三段数字，再比预发布标识。
  /// 1.0.0 > 1.0.0-beta.2，1.0.0-beta.2 > 1.0.0-beta.1。
  static int compareVersions(String a, String b) {
    String stripBuild(String value) {
      final plus = value.indexOf('+');
      return plus < 0 ? value : value.substring(0, plus);
    }

    (List<int>, List<String>) split(String value) {
      final text = stripBuild(normalizeVersion(value));
      final dash = text.indexOf('-');
      final core = dash < 0 ? text : text.substring(0, dash);
      final pre = dash < 0 ? '' : text.substring(dash + 1);
      final numbers = core.split('.').map((part) {
        final match = RegExp(r'^\d+').firstMatch(part.trim());
        return match == null ? 0 : int.tryParse(match.group(0)!) ?? 0;
      }).toList();
      while (numbers.length < 3) {
        numbers.add(0);
      }
      return (numbers, pre.isEmpty ? const <String>[] : pre.split('.'));
    }

    final (an, apre) = split(a);
    final (bn, bpre) = split(b);
    for (var i = 0; i < 3; i++) {
      if (an[i] != bn[i]) return an[i].compareTo(bn[i]);
    }
    if (apre.isEmpty != bpre.isEmpty) return apre.isEmpty ? 1 : -1;
    for (var i = 0; i < apre.length && i < bpre.length; i++) {
      final left = apre[i];
      final right = bpre[i];
      final leftNumber = int.tryParse(left);
      final rightNumber = int.tryParse(right);
      if (leftNumber != null && rightNumber != null) {
        if (leftNumber != rightNumber) return leftNumber.compareTo(rightNumber);
      } else if (leftNumber != null) {
        return -1;
      } else if (rightNumber != null) {
        return 1;
      } else {
        final result = left.compareTo(right);
        if (result != 0) return result;
      }
    }
    return apre.length.compareTo(bpre.length);
  }
}
