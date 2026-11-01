import 'dart:math' as math;

import 'package:intl/intl.dart';

String formatBytes(num bytes, {bool perSecond = false}) {
  if (bytes <= 0 || !bytes.isFinite) return perSecond ? '0 B/s' : '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value == value.roundToDouble() && unit <= 1
      ? '${value.toInt()}'
      : _trimZero(value.toStringAsFixed(value >= 100 ? 0 : 1));
  return '$text ${units[unit]}${perSecond ? '/s' : ''}';
}

String _trimZero(String text) =>
    text.contains('.') ? text.replaceFirst(RegExp(r'\.0+$'), '') : text;

String formatSpeed(num bytesPerSecond) =>
    formatBytes(bytesPerSecond, perSecond: true);

String formatUptime(Duration? duration) {
  if (duration == null || duration.isNegative) return '00:00:00';
  final total = duration.inSeconds;
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  final seconds = total % 60;
  String two(int value) => value.toString().padLeft(2, '0');
  if (hours >= 100) {
    return '${hours ~/ 24}d ${two(hours % 24)}:${two(minutes)}';
  }
  return '${two(hours)}:${two(minutes)}:${two(seconds)}';
}

String formatDateTime(DateTime? time, {String? locale}) {
  if (time == null) return '--';
  final local = time.toLocal();
  return DateFormat('yyyy-MM-dd HH:mm', locale).format(local);
}

String formatTime(DateTime time) {
  return DateFormat('HH:mm:ss').format(time.toLocal());
}

String formatRelativeTime(DateTime? time, {bool zh = true}) {
  if (time == null) return zh ? '从未' : 'Never';
  final delta = DateTime.now().difference(time.toLocal());
  if (delta.inSeconds < 60) return zh ? '刚刚' : 'Just now';
  if (delta.inMinutes < 60) {
    return zh ? '${delta.inMinutes} 分钟前' : '${delta.inMinutes} min ago';
  }
  if (delta.inHours < 24) {
    return zh ? '${delta.inHours} 小时前' : '${delta.inHours} h ago';
  }
  if (delta.inDays < 7) {
    return zh ? '${delta.inDays} 天前' : '${delta.inDays} d ago';
  }
  return formatDateTime(time);
}

String formatDurationShort(Duration duration) {
  if (duration.inHours >= 24) {
    return '${duration.inDays}d ${duration.inHours % 24}h';
  }
  if (duration.inHours > 0) {
    return '${duration.inHours}h ${duration.inMinutes % 60}m';
  }
  if (duration.inMinutes > 0) return '${duration.inMinutes}m';
  return '${duration.inSeconds}s';
}

String formatExpire(int unixSeconds, {required bool zh}) {
  if (unixSeconds <= 0) return zh ? '无到期时间' : 'No expiry';
  final date = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
  return DateFormat('yyyy-MM-dd').format(date.toLocal());
}

String flagForRegion(String region) {
  final code = region.trim().toUpperCase();
  if (code.length != 2 || !RegExp(r'^[A-Z]{2}$').hasMatch(code)) return '';
  const base = 0x1F1E6;
  final chars = code.codeUnits.map((c) => base + (c - 65));
  return String.fromCharCodes(chars);
}

const _regionHints = <(String, String, String, String)>[
  ('香港', 'HK', '香港', 'Hong Kong'),
  ('澳门', 'MO', '澳门', 'Macao'),
  ('澳門', 'MO', '澳门', 'Macao'),
  ('台湾', 'TW', '台湾', 'Taiwan'),
  ('臺灣', 'TW', '台湾', 'Taiwan'),
  ('日本', 'JP', '日本', 'Japan'),
  ('新加坡', 'SG', '新加坡', 'Singapore'),
  ('美国', 'US', '美国', 'United States'),
  ('美國', 'US', '美国', 'United States'),
  ('韩国', 'KR', '韩国', 'South Korea'),
  ('韓國', 'KR', '韩国', 'South Korea'),
  ('英国', 'GB', '英国', 'United Kingdom'),
  ('德國', 'DE', '德国', 'Germany'),
  ('德国', 'DE', '德国', 'Germany'),
  ('法国', 'FR', '法国', 'France'),
  ('法國', 'FR', '法国', 'France'),
  ('俄罗斯', 'RU', '俄罗斯', 'Russia'),
  ('加拿大', 'CA', '加拿大', 'Canada'),
  ('澳大利亚', 'AU', '澳大利亚', 'Australia'),
  ('澳洲', 'AU', '澳大利亚', 'Australia'),
  ('印度尼西亚', 'ID', '印度尼西亚', 'Indonesia'),
  ('印尼', 'ID', '印度尼西亚', 'Indonesia'),
  ('印度', 'IN', '印度', 'India'),
  ('土耳其', 'TR', '土耳其', 'Turkey'),
  ('荷兰', 'NL', '荷兰', 'Netherlands'),
  ('荷蘭', 'NL', '荷兰', 'Netherlands'),
  ('阿根廷', 'AR', '阿根廷', 'Argentina'),
  ('巴西', 'BR', '巴西', 'Brazil'),
  ('马来西亚', 'MY', '马来西亚', 'Malaysia'),
  ('馬來西亞', 'MY', '马来西亚', 'Malaysia'),
  ('泰國', 'TH', '泰国', 'Thailand'),
  ('泰国', 'TH', '泰国', 'Thailand'),
  ('越南', 'VN', '越南', 'Vietnam'),
  ('菲律宾', 'PH', '菲律宾', 'Philippines'),
  ('菲律賓', 'PH', '菲律宾', 'Philippines'),
  ('瑞士', 'CH', '瑞士', 'Switzerland'),
  ('瑞典', 'SE', '瑞典', 'Sweden'),
  ('挪威', 'NO', '挪威', 'Norway'),
  ('丹麦', 'DK', '丹麦', 'Denmark'),
  ('芬兰', 'FI', '芬兰', 'Finland'),
  ('波兰', 'PL', '波兰', 'Poland'),
  ('西班牙', 'ES', '西班牙', 'Spain'),
  ('意大利', 'IT', '意大利', 'Italy'),
  ('爱尔兰', 'IE', '爱尔兰', 'Ireland'),
  ('奥地利', 'AT', '奥地利', 'Austria'),
  ('比利时', 'BE', '比利时', 'Belgium'),
  ('捷克', 'CZ', '捷克', 'Czechia'),
  ('乌克兰', 'UA', '乌克兰', 'Ukraine'),
  ('阿联酋', 'AE', '阿联酋', 'United Arab Emirates'),
  ('以色列', 'IL', '以色列', 'Israel'),
  ('南非', 'ZA', '南非', 'South Africa'),
  ('埃及', 'EG', '埃及', 'Egypt'),
];

/// Extracts a likely region / flag emoji from a proxy node name.
String regionEmojiForNode(String name) {
  final match = RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true)
      .firstMatch(name);
  if (match != null) return match.group(0)!;
  for (final hint in _regionHints) {
    if (name.contains(hint.$1)) return flagForRegion(hint.$2);
  }
  return '';
}

/// Resolves the ISO 3166-1 alpha-2 region code of a proxy node, if one is known.
String? regionCodeForNode(String name) {
  if (name.trim().isEmpty) return null;
  for (final hint in _regionHints) {
    if (name.contains(hint.$1)) return hint.$2;
  }
  final match = RegExp(r'[\u{1F1E6}-\u{1F1FF}]{2}', unicode: true)
      .firstMatch(name);
  if (match == null) return null;
  return String.fromCharCodes(
    match.group(0)!.runes.map((unit) => 65 + unit - 0x1F1E6),
  );
}

/// Resolves a readable region label from a proxy node name, if one is known.
String? regionLabelForNode(String name, {required bool zh}) {
  if (name.trim().isEmpty) return null;
  for (final hint in _regionHints) {
    if (name.contains(hint.$1)) return zh ? hint.$3 : hint.$4;
  }
  for (final hint in _regionHints) {
    final flag = flagForRegion(hint.$2);
    if (flag.isNotEmpty && name.contains(flag)) return zh ? hint.$3 : hint.$4;
  }
  return null;
}

String maskSecret(String secret) {
  if (secret.isEmpty) return '—';
  if (secret.length <= 8) return '••••••••';
  return '${secret.substring(0, 4)}••••${secret.substring(secret.length - 4)}';
}

String clampText(String value, int max) {
  if (value.length <= max) return value;
  return '${value.substring(0, math.max(0, max - 1))}…';
}

String formatDelay(int delay, {required bool zh}) {
  if (delay < 0) return zh ? '超时' : 'Timeout';
  return '$delay ms';
}
