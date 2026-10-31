import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

HttpClient createHttpClient({int? proxyPort, Duration timeout = const Duration(seconds: 20)}) {
  final client = HttpClient();
  client.connectionTimeout = timeout;
  client.idleTimeout = const Duration(seconds: 15);
  if (proxyPort != null && proxyPort > 0) {
    client.findProxy = (_) => 'PROXY 127.0.0.1:$proxyPort';
  }
  return client;
}

Dio createDio({int? proxyPort}) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 45),
      sendTimeout: const Duration(seconds: 15),
      followRedirects: true,
      maxRedirects: 8,
    ),
  );
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () => createHttpClient(proxyPort: proxyPort, timeout: const Duration(seconds: 15)),
  );
  return dio;
}
