import 'dart:convert';
import 'dart:typed_data';

import '../core/app_info.dart';
import '../core/errors.dart';
import '../models/app_settings.dart';
import '../models/subscription.dart';
import 'config_generator.dart';

class BackupSnapshot {
  const BackupSnapshot({
    required this.settings,
    required this.subscriptions,
    required this.activeId,
    required this.selections,
    required this.testedDelays,
    required this.profiles,
    required this.exportedAt,
  });

  final AppSettings settings;
  final List<Subscription> subscriptions;
  final String? activeId;
  final Map<String, Map<String, String>> selections;
  final Map<String, Map<String, int>> testedDelays;
  final Map<String, String> profiles;
  final DateTime exportedAt;

  int get profileCount => profiles.length;
}

/// 备份包含订阅原文、订阅链接、API 密钥和节点选择，导出前必须让用户知道
/// 这份文件等同于一份明文凭据。恢复走整包替换，不做逐项合并。
class BackupService {
  const BackupService._();

  static const format = 'clashgo-backup';
  static const formatVersion = 1;

  /// 订阅 id 会直接拼进 `profiles/<id>.yaml` 的文件名，只接受本应用生成的
  /// 字母数字短串，挡住 `../` 这类写出数据目录的备份内容。
  static final RegExp _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  static const _modes = {'rule', 'global', 'direct'};

  static void _validateSettings(AppSettings settings) {
    if (settings.mixedPort < 1 || settings.mixedPort > 65535) {
      throw AppError(
        'backupInvalid',
        detail: 'Invalid mixed port: ${settings.mixedPort}',
      );
    }
    if (settings.apiPort < 1 || settings.apiPort > 65535) {
      throw AppError(
        'backupInvalid',
        detail: 'Invalid API port: ${settings.apiPort}',
      );
    }
    if (settings.mixedPort == settings.apiPort) {
      throw AppError(
        'backupInvalid',
        detail: 'Mixed port and API port must differ',
      );
    }
    if (!_modes.contains(settings.mode)) {
      throw AppError('backupInvalid', detail: 'Invalid mode: ${settings.mode}');
    }
    if (settings.splitTunnelMode == AppSettings.splitTunnelAllow &&
        settings.splitTunnelPackages.isEmpty) {
      throw const AppError(
        'backupInvalid',
        detail: 'Split tunnel allow list is empty',
      );
    }
    try {
      ConfigGenerator.validateOverride(settings.overrideYaml);
    } catch (error) {
      throw AppError(
        'backupInvalid',
        detail: 'Invalid override YAML: ${error is AppError ? error.detail ?? error.code : error}',
      );
    }
  }

  static Uint8List encode({
    required AppSettings settings,
    required List<Subscription> subscriptions,
    required String? activeId,
    required Map<String, Map<String, String>> selections,
    required Map<String, Map<String, int>> testedDelays,
    required Map<String, String> profiles,
    DateTime? exportedAt,
  }) {
    final payload = <String, dynamic>{
      'format': format,
      'formatVersion': formatVersion,
      'app': AppInfo.name,
      'appVersion': AppInfo.version,
      'exportedAt': (exportedAt ?? DateTime.now()).toIso8601String(),
      'settings': settings.toJson(),
      'subscriptions': subscriptions.map((sub) => sub.toJson()).toList(),
      'activeId': activeId,
      'selections': selections,
      'testedDelays': testedDelays,
      'profiles': profiles,
    };
    return Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
  }

  static BackupSnapshot decode(Uint8List bytes) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } catch (error) {
      throw AppError('backupInvalid', detail: error.toString());
    }
    if (decoded is! Map) throw const AppError('backupInvalid');
    final map = Map<String, dynamic>.from(decoded);
    if (map['format'] != format) throw const AppError('backupInvalid');
    final version = (map['formatVersion'] as num?)?.toInt() ?? 0;
    if (version < 1 || version > formatVersion) {
      throw AppError('backupInvalid', detail: 'Unsupported format version $version');
    }
    final rawSettings = map['settings'];
    if (rawSettings is! Map) throw const AppError('backupInvalid');
    final settings = AppSettings.fromJson(Map<String, dynamic>.from(rawSettings));
    _validateSettings(settings);

    final subscriptions = <Subscription>[];
    final seenIds = <String>{};
    final rawSubscriptions = map['subscriptions'];
    if (rawSubscriptions is List) {
      for (final item in rawSubscriptions) {
        if (item is! Map) continue;
        try {
          final sub = Subscription.fromJson(Map<String, dynamic>.from(item));
          if (!_safeId.hasMatch(sub.id) || !seenIds.add(sub.id)) continue;
          subscriptions.add(sub);
        } catch (_) {
          // 单条坏记录不拖垮整包：其余订阅仍可恢复。
        }
      }
    }

    var activeId = map['activeId'] is String ? map['activeId'] as String : null;
    if (activeId != null && !seenIds.contains(activeId)) activeId = null;
    activeId ??= subscriptions.isEmpty ? null : subscriptions.first.id;

    final selections = <String, Map<String, String>>{};
    final rawSelections = map['selections'];
    if (rawSelections is Map) {
      rawSelections.forEach((key, value) {
        if (!seenIds.contains(key) || value is! Map) return;
        final entries = <String, String>{};
        value.forEach((group, node) {
          if (node is String) entries[group.toString()] = node;
        });
        if (entries.isNotEmpty) selections[key.toString()] = entries;
      });
    }

    final delays = <String, Map<String, int>>{};
    final rawDelays = map['testedDelays'];
    if (rawDelays is Map) {
      rawDelays.forEach((key, value) {
        if (!seenIds.contains(key) || value is! Map) return;
        final entries = <String, int>{};
        value.forEach((node, delay) {
          if (delay is num) entries[node.toString()] = delay.toInt();
        });
        if (entries.isNotEmpty) delays[key.toString()] = entries;
      });
    }

    final profiles = <String, String>{};
    final rawProfiles = map['profiles'];
    if (rawProfiles is Map) {
      rawProfiles.forEach((key, value) {
        if (!seenIds.contains(key) || value is! String || value.trim().isEmpty) {
          return;
        }
        profiles[key.toString()] = value;
      });
    }

    return BackupSnapshot(
      settings: settings,
      subscriptions: subscriptions,
      activeId: activeId,
      selections: selections,
      testedDelays: delays,
      profiles: profiles,
      exportedAt:
          DateTime.tryParse(map['exportedAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
