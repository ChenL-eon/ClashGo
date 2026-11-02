import 'dart:convert';

import 'package:dio/dio.dart';

import '../core/errors.dart';
import '../models/connection_info.dart';
import '../models/dns_query.dart';
import '../models/mihomo_version.dart';
import '../models/provider_info.dart';
import '../models/proxy_info.dart';
import '../models/rule_item.dart';
import '../models/rule_provider_info.dart';

class MihomoApi {
  MihomoApi({int port = 19090, String secret = ''}) {
    configure(port: port, secret: secret);
  }

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 3),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 8),
      responseType: ResponseType.json,
    ),
  );

  int _port = 19090;
  String _secret = '';

  int get port => _port;
  String get secret => _secret;
  String get baseUrl => 'http://127.0.0.1:$_port';

  void configure({required int port, required String secret}) {
    _port = port;
    _secret = secret;
    _dio.options.baseUrl = 'http://127.0.0.1:$port';
    _dio.options.headers['Authorization'] = 'Bearer $secret';
  }

  Uri websocketUri(String path, {Map<String, String>? query}) {
    return Uri(
      scheme: 'ws',
      host: '127.0.0.1',
      port: _port,
      path: path,
      queryParameters: {
        ...?query,
        if (_secret.isNotEmpty) 'token': _secret,
      },
    );
  }

  Future<MihomoVersion> version() => _guard(() async {
        final data = await _get<Map<String, dynamic>>('/version');
        return MihomoVersion(
          version: data?['version'] as String? ?? '—',
          meta: data?['meta'] as bool? ?? false,
        );
      });

  Future<Map<String, dynamic>> configs() => _guard(() async {
        final data = await _get<Map<String, dynamic>>('/configs');
        return data ?? <String, dynamic>{};
      });

  Future<void> patchConfigs(Map<String, dynamic> patch) => _guard(() async {
        await _dio.patch('/configs', data: patch);
      });

  Future<void> reloadConfig(String path) => _guard(() async {
        await _dio.put('/configs', data: {'path': path, 'force': true});
      });

  Future<ProxiesSnapshot> proxies() => _guard(() async {
        final data = await _get<Map<String, dynamic>>('/proxies');
        return ProxiesSnapshot.fromJson(data ?? <String, dynamic>{});
      });

  Future<void> selectProxy(String group, String name) => _guard(() async {
        await _dio.put('/proxies/${Uri.encodeComponent(group)}', data: {'name': name});
      });

  Future<int> proxyDelay(String name, {String? url, int timeout = 5000}) => _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/proxies/${Uri.encodeComponent(name)}/delay',
          queryParameters: {
            if (url != null && url.isNotEmpty) 'url': url,
            'timeout': timeout,
          },
          options: Options(receiveTimeout: Duration(milliseconds: timeout + 3000)),
        );
        final value = response.data?['delay'];
        if (value is! num) throw const AppError('apiUnavailable', detail: 'Invalid delay response');
        return value.toInt();
      });

  Future<Map<String, int>> groupDelay(String group, {String? url, int timeout = 5000}) => _guard(() async {
        final response = await _dio.get<Map<String, dynamic>>(
          '/group/${Uri.encodeComponent(group)}/delay',
          queryParameters: {
            if (url != null && url.isNotEmpty) 'url': url,
            'timeout': timeout,
          },
          options: Options(receiveTimeout: Duration(milliseconds: timeout + 3000)),
        );
        final data = response.data ?? <String, dynamic>{};
        final result = <String, int>{};
        data.forEach((key, value) {
          if (value is num) result[key] = value.toInt();
        });
        if (result.isEmpty) {
          final value = data['delay'];
          if (value is num) result[group] = value.toInt();
        }
        return result;
      });

  Future<List<RuleItem>> rules() => _guard(() async {
        final data = await _get<Map<String, dynamic>>('/rules');
        final raw = data?['rules'];
        if (raw is! List) return <RuleItem>[];
        return raw.whereType<Map>().map((item) => RuleItem.fromJson(Map<String, dynamic>.from(item))).toList();
      });

  Future<ConnectionsSnapshot> connections() => _guard(() async {
        final data = await _get<Map<String, dynamic>>('/connections');
        return ConnectionsSnapshot.fromJson(data ?? <String, dynamic>{});
      });

  Future<void> closeConnection(String id) => _guard(() async {
        await _dio.delete('/connections/${Uri.encodeComponent(id)}');
      });

  Future<void> closeAllConnections() => _guard(() async {
        await _dio.delete('/connections');
      });

  Future<List<ProviderInfo>> providers() => _guard(() async {
        final data = await _get<Map<String, dynamic>>('/providers/proxies');
        final raw = data?['providers'];
        if (raw is! Map) return <ProviderInfo>[];
        return raw.entries
            .where((entry) => entry.value is Map)
            .map((entry) => ProviderInfo.fromJson(entry.key.toString(), Map<String, dynamic>.from(entry.value as Map)))
            .where((provider) => provider.vehicleType != 'Compatible')
            .toList();
      });

  Future<void> updateProvider(String name) => _guard(() async {
        await _dio.put(
          '/providers/proxies/${Uri.encodeComponent(name)}',
          options: Options(receiveTimeout: const Duration(seconds: 60)),
        );
      });

  Future<void> healthCheckProvider(String name) => _guard(() async {
        await _dio.get(
          '/providers/proxies/${Uri.encodeComponent(name)}/healthcheck',
          options: Options(receiveTimeout: const Duration(seconds: 40)),
        );
      });

  Future<List<RuleProviderInfo>> ruleProviders() => _guard(() async {
        final data = await _get<Map<String, dynamic>>('/providers/rules');
        final raw = data?['providers'];
        if (raw is! Map) return <RuleProviderInfo>[];
        return raw.entries
            .where((entry) => entry.value is Map)
            .map((entry) => RuleProviderInfo.fromJson(
                  entry.key.toString(),
                  Map<String, dynamic>.from(entry.value as Map),
                ))
            .toList();
      });

  Future<void> updateRuleProvider(String name) => _guard(() async {
        await _dio.put(
          '/providers/rules/${Uri.encodeComponent(name)}',
          options: Options(receiveTimeout: const Duration(seconds: 60)),
        );
      });

  Future<DnsQueryResult> queryDns(String name, String type) => _guard(() async {
        final data = await _get<Map<String, dynamic>>(
          '/dns/query',
          query: {'name': name, 'type': type},
        );
        return DnsQueryResult.fromJson(data ?? <String, dynamic>{});
      });

  Future<void> flushFakeIp() => _guard(() async {
        await _dio.post('/cache/fakeip/flush');
      });

  Future<void> flushDnsCache() => _guard(() async {
        await _dio.post('/cache/dns/flush');
      });

  Future<T?> _get<T>(String path, {Map<String, dynamic>? query}) async {
    final response = await _dio.get<T>(path, queryParameters: query);
    return response.data;
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AppError {
      rethrow;
    } on DioException catch (error) {
      throw AppError(_codeFor(error), detail: _detail(error), statusCode: error.response?.statusCode);
    } catch (error) {
      throw AppError('generic', detail: error.toString());
    }
  }

  String _codeFor(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'apiUnavailable';
      default:
        return 'generic';
    }
  }

  String? _detail(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final message = data['message'] ?? data['error'];
      if (message != null) return message.toString();
    } else if (data is String && data.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map && decoded['message'] != null) return decoded['message'].toString();
      } catch (_) {
        if (data.length < 300) return data;
      }
    }
    final inner = error.error;
    if (inner != null) return '${error.type.name}: $inner';
    return error.message ?? error.type.name;
  }
}
