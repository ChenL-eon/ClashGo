import 'dart:convert';
import 'dart:io';

import '../core/app_paths.dart';
import '../models/app_settings.dart';
import '../models/subscription.dart';

const _encoder = JsonEncoder.withIndent('  ');
const _settingsVersion = 2;

AppSettings _defaults(bool zh) =>
    AppSettings.defaults(zh: zh, systemProxy: Platform.isWindows);

class LocalStore {
  LocalStore(this.paths);

  final AppPaths paths;

  Future<AppSettings> loadSettings({required bool preferChinese}) async {
    try {
      if (!await paths.settingsFile.exists()) {
        return _defaults(preferChinese);
      }
      final text = await paths.settingsFile.readAsString();
      if (text.trim().isEmpty) return _defaults(preferChinese);
      final json = jsonDecode(text);
      if (json is! Map) return _defaults(preferChinese);
      final map = Map<String, dynamic>.from(json);
      final settings = AppSettings.fromJson(map);
      final version = (map['settingsVersion'] as num?)?.toInt() ?? 1;
      if (version < _settingsVersion) {
        // v2：Windows 系统代理改为默认开启；迁移只执行一次，之后保留用户选择。
        settings.systemProxy = Platform.isWindows;
      }
      return settings;
    } catch (_) {
      return _defaults(preferChinese);
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    final json = settings.toJson();
    json['settingsVersion'] = _settingsVersion;
    await _writeJson(paths.settingsFile, json);
  }

  Future<List<Subscription>> loadSubscriptions() async {
    try {
      if (!await paths.subscriptionsFile.exists()) return [];
      final text = await paths.subscriptionsFile.readAsString();
      if (text.trim().isEmpty) return [];
      final decoded = jsonDecode(text);
      List<dynamic> raw = const [];
      if (decoded is Map && decoded['subscriptions'] is List) {
        raw = decoded['subscriptions'] as List;
      } else if (decoded is List) {
        raw = decoded;
      }
      final result = <Subscription>[];
      for (final item in raw) {
        if (item is Map) {
          try {
            final sub = Subscription.fromJson(Map<String, dynamic>.from(item));
            if (sub.id.isNotEmpty) result.add(sub);
          } catch (_) {}
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSubscriptions(List<Subscription> subscriptions) async {
    await _writeJson(paths.subscriptionsFile, {
      'subscriptions': subscriptions.map((sub) => sub.toJson()).toList(),
    });
  }

  Future<String?> loadActiveId() async {
    try {
      if (!await paths.activeSubscriptionFile.exists()) return null;
      final decoded = jsonDecode(await paths.activeSubscriptionFile.readAsString());
      if (decoded is Map) return decoded['activeId'] as String?;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveActiveId(String? id) async {
    await _writeJson(paths.activeSubscriptionFile, {'activeId': id});
  }

  Future<Map<String, Map<String, String>>> loadSelections() async {
    try {
      if (!await paths.selectionsFile.exists()) return {};
      final decoded = jsonDecode(await paths.selectionsFile.readAsString());
      if (decoded is! Map) return {};
      final result = <String, Map<String, String>>{};
      decoded.forEach((key, value) {
        if (value is Map) {
          final entries = <String, String>{};
          value.forEach((group, node) {
            if (node is String) entries[group.toString()] = node;
          });
          result[key.toString()] = entries;
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveSelections(Map<String, Map<String, String>> selections) async {
    await _writeJson(paths.selectionsFile, selections);
  }

  Future<String?> readProfile(String id) async {
    final file = paths.profileFile(id);
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } catch (_) {
      return null;
    }
  }

  Future<void> writeProfile(String id, String content) async {
    await _writeString(paths.profileFile(id), content);
  }

  Future<void> deleteProfile(String id) async {
    final file = paths.profileFile(id);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<void> ensureCleanProfiles(Set<String> validIds) async {
    try {
      final files = await paths.profilesDir.list().toList();
      for (final entity in files) {
        if (entity is! File || !entity.path.endsWith('.yaml')) continue;
        final name = entity.uri.pathSegments.last.replaceAll('.yaml', '');
        if (!validIds.contains(name)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> _writeJson(File file, Object value) async {
    await _writeString(file, _encoder.convert(value));
  }

  Future<void> _writeString(File file, String content) async {
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(content, flush: true);
    try {
      if (await file.exists()) await file.delete();
      await temp.rename(file.path);
    } catch (_) {
      await file.writeAsString(content, flush: true);
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {}
    }
  }
}
