import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;

import '../core/errors.dart';
import 'network.dart';
import 'update_service.dart';

class CoreRelease {
  const CoreRelease({
    required this.version,
    required this.tag,
    required this.assetName,
    required this.assetUrl,
  });

  final String version;
  final String tag;
  final String assetName;
  final Uri assetUrl;
}

/// Windows 内核更新：直接替换应用支持目录里的 mihomo.exe，下一次启动内核时生效。
/// 安卓内核在 APK 的 nativeLibraryDir 里、随应用升级走，不走这条通路。
class CoreUpdateService {
  const CoreUpdateService();

  static const _latestUrl =
      'https://github.com/MetaCubeX/mihomo/releases/latest';
  static const _downloadRoot =
      'https://github.com/MetaCubeX/mihomo/releases/download';

  Future<CoreRelease?> latest({int? proxyPort}) async {
    if (!Platform.isWindows) throw const AppError('unsupportedPlatform');
    final dio = createDio(proxyPort: proxyPort)
      ..options.connectTimeout = const Duration(seconds: 10)
      ..options.receiveTimeout = const Duration(seconds: 20);
    try {
      final response = await dio.get<String>(
        _latestUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: const {'Accept': 'text/html'},
        ),
      );
      final tag = UpdateService.tagFromUri(response.realUri);
      if (tag == null) return null;
      final release = UpdateService.releaseFromUri(response.realUri);
      if (release == null) return null;
      // GitHub 的 mihomo Windows amd64 资产名固定带 tag：
      // mihomo-windows-amd64-v1.19.33.zip。下载 404 时这条约定会在
      // install 阶段立刻报错，不会把别的平台包装进来。
      final assetName = 'mihomo-windows-amd64-$tag.zip';
      return CoreRelease(
        version: release.version,
        tag: tag,
        assetName: assetName,
        assetUrl: Uri.parse('$_downloadRoot/$tag/$assetName'),
      );
    } finally {
      dio.close(force: true);
    }
  }

  Future<Uint8List> download(
    CoreRelease release, {
    int? proxyPort,
    void Function(int received, int total)? onProgress,
  }) async {
    final dio = createDio(proxyPort: proxyPort)
      ..options.connectTimeout = const Duration(seconds: 15)
      ..options.receiveTimeout = const Duration(minutes: 3);
    try {
      final response = await dio.get<List<int>>(
        release.assetUrl.toString(),
        options: Options(responseType: ResponseType.bytes),
        onReceiveProgress: onProgress,
      );
      final data = response.data;
      if (data == null || data.isEmpty) {
        throw const AppError('coreUpdate', detail: 'The download is empty');
      }
      return Uint8List.fromList(data);
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      throw AppError(
        'coreUpdate',
        detail: status == null ? error.message : 'HTTP $status',
      );
    } finally {
      dio.close(force: true);
    }
  }

  /// 官方 zip 里只有一个 exe，名字叫 mihomo-windows-amd64.exe 而不是 mihomo.exe，
  /// 所以按“优先 mihomo.exe，否则第一个 exe”来取，不依赖具体资产命名。
  static Uint8List extractCore(Uint8List archiveBytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(archiveBytes);
    } catch (error) {
      throw AppError('coreUpdate', detail: 'Invalid zip: $error');
    }
    ArchiveFile? fallback;
    for (final file in archive) {
      if (!file.isFile) continue;
      final name = p.basename(file.name).toLowerCase();
      if (!name.endsWith('.exe')) continue;
      if (name == 'mihomo.exe') {
        fallback = file;
        break;
      }
      fallback ??= file;
    }
    if (fallback == null) {
      throw const AppError(
        'coreUpdate',
        detail: 'The archive contains no executable',
      );
    }
    final bytes = fallback.readBytes();
    if (bytes == null || bytes.isEmpty) {
      throw const AppError(
        'coreUpdate',
        detail: 'The executable in the archive is empty',
      );
    }
    return bytes;
  }

  /// 用新下载的 exe 自己跑一次 `-v`，确认它能启动、报告的版本和 release 一致，
  /// 再让控制器停内核替换。坏包、错平台包都会在替换前被拦下。
  static Future<String?> binaryVersion(
    String path, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    try {
      final result = await Process.run(
        path,
        const ['-v'],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      ).timeout(timeout);
      return '${result.stdout}\n${result.stderr}'.trim();
    } catch (_) {
      return null;
    }
  }

  static String? versionFromOutput(String output) {
    final match = RegExp(
      r'v(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)',
    ).firstMatch(output);
    return match?.group(1);
  }
}
