import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:yaml/yaml.dart';

import '../core/errors.dart';
import '../models/subscription.dart';
import 'network.dart';

class FetchedProfile {
  const FetchedProfile({required this.content, required this.headers, required this.sourceUrl});

  final String content;
  final SubscriptionHeaders headers;
  final String? sourceUrl;
}

class SubscriptionFetcher {
  Future<FetchedProfile> fetchUrl(
    String url, {
    String userAgent = 'clash.meta',
    int? proxyPort,
  }) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const AppError('invalidUrl');
    }
    final dio = createDio(proxyPort: proxyPort);
    try {
      final response = await dio.get<List<int>>(
        uri.toString(),
        options: Options(
          responseType: ResponseType.bytes,
          headers: {
            'User-Agent': userAgent.isEmpty ? 'clash.meta' : userAgent,
            'Accept': '*/*',
          },
          validateStatus: (_) => true,
        ),
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw AppError('subscriptionFetch', detail: 'HTTP $status');
      }
      final bytes = response.data ?? const <int>[];
      if (bytes.isEmpty) throw const AppError('subscriptionEmpty');
      final content = _decode(bytes);
      if (content.trim().isEmpty) throw const AppError('subscriptionEmpty');
      final headers = parseHeaders(response.headers);
      return FetchedProfile(content: content, headers: headers, sourceUrl: response.realUri.toString());
    } on AppError {
      rethrow;
    } on DioException catch (error) {
      throw AppError('subscriptionFetch', detail: error.message ?? error.type.name);
    } finally {
      dio.close(force: true);
    }
  }

  Future<FetchedProfile> readFile(File file) async {
    if (!file.path.toLowerCase().endsWith('.yaml') && !file.path.toLowerCase().endsWith('.yml')) {
      throw const AppError('unsupportedFile');
    }
    try {
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw const AppError('subscriptionEmpty');
      final content = _decode(bytes);
      final name = file.uri.pathSegments.isNotEmpty ? file.uri.pathSegments.last : null;
      return FetchedProfile(
        content: content,
        headers: SubscriptionHeaders(name: name?.replaceAll(RegExp(r'\.(ya?ml)$', caseSensitive: false), '')),
        sourceUrl: null,
      );
    } on AppError {
      rethrow;
    } catch (error) {
      throw AppError('filePick', detail: error.toString());
    }
  }

  String _decode(List<int> bytes) {
    var content = utf8.decode(bytes, allowMalformed: true);
    if (content.startsWith('\uFEFF')) content = content.substring(1);
    return content;
  }

  SubscriptionHeaders parseHeaders(Headers headers) {
    final info = headers.map['subscription-userinfo']?.join(';') ?? '';
    var upload = 0;
    var download = 0;
    var total = 0;
    var expire = 0;
    if (info.isNotEmpty) {
      for (final part in info.split(';')) {
        final pieces = part.split('=');
        if (pieces.length != 2) continue;
        final key = pieces[0].trim().toLowerCase();
        final value = int.tryParse(pieces[1].trim()) ?? 0;
        switch (key) {
          case 'upload':
            upload = value;
          case 'download':
            download = value;
          case 'total':
            total = value;
          case 'expire':
            expire = value;
        }
      }
    }
    final intervalHours = int.tryParse((headers.map['profile-update-interval']?.firstOrNull ?? '').trim());
    String? name;
    final disposition = headers.map['content-disposition']?.join(';') ?? '';
    if (disposition.isNotEmpty) {
      final utf8Match = RegExp(r"filename\*\s*=\s*(?:UTF-8|utf-8)''([^;]+)").firstMatch(disposition);
      if (utf8Match != null) {
        try {
          name = Uri.decodeComponent(utf8Match.group(1)!.trim());
        } catch (_) {}
      }
      if (name == null || name.isEmpty) {
        final plain = RegExp(r'filename\s*=\s*"?([^";]+)"?').firstMatch(disposition);
        if (plain != null) name = plain.group(1)?.trim();
      }
    }
    return SubscriptionHeaders(
      upload: upload,
      download: download,
      total: total,
      expire: expire,
      name: name,
      updateIntervalMinutes: intervalHours != null && intervalHours > 0 ? intervalHours * 60 : null,
    );
  }

  String? validateProfile(String content) {
    dynamic doc;
    try {
      doc = loadYaml(content);
    } catch (error) {
      throw AppError('profileInvalid', detail: _shorten(error.toString()));
    }
    if (doc is! Map) throw const AppError('invalidConfig');
    final map = Map<String, dynamic>.from(doc);
    final proxies = map['proxies'];
    final providers = map['proxy-providers'];
    final hasProxies = proxies is List && proxies.whereType<Map>().any((item) => (item['name'] as Object?) != null && (item['type'] as Object?) != null);
    final hasProviders = providers is Map && providers.isNotEmpty;
    if (!hasProxies && !hasProviders) throw const AppError('noNodes');
    return null;
  }

  String? nameFromProfile(String content) {
    try {
      final doc = loadYaml(content);
      if (doc is Map) {
        final name = doc['name'] ?? doc['profile-name'];
        if (name is String && name.trim().isNotEmpty) return name.trim();
      }
    } catch (_) {}
    return null;
  }

  String _shorten(String text) {
    final singleLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return singleLine.length > 220 ? '${singleLine.substring(0, 220)}…' : singleLine;
  }
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
