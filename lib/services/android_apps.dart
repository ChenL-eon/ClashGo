import 'package:flutter/services.dart';

class AndroidAppInfo {
  const AndroidAppInfo({
    required this.packageName,
    required this.label,
    required this.system,
  });

  final String packageName;
  final String label;
  final bool system;

  factory AndroidAppInfo.fromMap(Map<Object?, Object?> map) {
    return AndroidAppInfo(
      packageName: map['package'] as String? ?? '',
      label: map['label'] as String? ?? '',
      system: map['system'] as bool? ?? false,
    );
  }
}

// Lists launchable apps so the settings page can offer per-app split tunneling.
// Icons travel separately in small batches: one reply carrying every app's icon
// can exceed Binder's ~1 MB transaction limit on phones with 150+ apps, which
// would fail the whole list instead of just some avatars.
class AndroidApps {
  static const String channelName = 'com.clashgo.clash_go/apps';
  static const int iconBatchSize = 16;
  static const MethodChannel _channel = MethodChannel(channelName);

  static Future<List<AndroidAppInfo>> list() async {
    final raw = await _channel.invokeListMethod<Object?>('list');
    final apps = <AndroidAppInfo>[];
    for (final item in raw ?? const <Object?>[]) {
      if (item is! Map) continue;
      final app = AndroidAppInfo.fromMap(item.cast<Object?, Object?>());
      if (app.packageName.isEmpty) continue;
      apps.add(app);
    }
    apps.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return apps;
  }

  static Future<Map<String, Uint8List>> icons(List<String> packageNames) async {
    final result = <String, Uint8List>{};
    for (var start = 0; start < packageNames.length; start += iconBatchSize) {
      var end = start + iconBatchSize;
      if (end > packageNames.length) end = packageNames.length;
      try {
        final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
          'icons',
          packageNames.sublist(start, end),
        );
        if (raw == null) continue;
        for (final entry in raw.entries) {
          final name = entry.key;
          final icon = entry.value;
          if (name is! String) continue;
          if (icon is Uint8List) {
            result[name] = icon;
          } else if (icon is List<int>) {
            result[name] = Uint8List.fromList(icon);
          }
        }
      } catch (_) {
        // 图标只是观感：某一批失败就留给占位图，别让整个应用列表跟着失败。
      }
    }
    return result;
  }
}
