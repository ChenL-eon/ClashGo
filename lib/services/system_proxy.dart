import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../core/app_paths.dart';
import '../core/errors.dart';

class _ProxyBackup {
  const _ProxyBackup({
    required this.enable,
    this.server,
    this.override,
    required this.applied,
    required this.createdAt,
  });

  factory _ProxyBackup.fromJson(Map<String, dynamic> json) {
    return _ProxyBackup(
      enable: (json['enable'] as num?)?.toInt() ?? 0,
      server: json['server'] as String?,
      override: json['override'] as String?,
      applied: json['applied'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  final int enable;
  final String? server;
  final String? override;
  final String applied;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'enable': enable,
        'server': server,
        'override': override,
        'applied': applied,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Windows system proxy support backed by the Internet Settings registry key.
/// The previous proxy values are backed up to disk so a crash cannot leave the
/// user's settings permanently overwritten.
class SystemProxyService {
  SystemProxyService(this.paths);

  final AppPaths paths;

  static const _keyPath = r'Software\Microsoft\Windows\CurrentVersion\Internet Settings';
  static const _proxyEnable = 'ProxyEnable';
  static const _proxyServer = 'ProxyServer';
  static const _proxyOverride = 'ProxyOverride';

  static bool get supported => Platform.isWindows;

  File get _backupFile => File('${paths.supportDir.path}${Platform.pathSeparator}system_proxy_backup.json');

  static String serverFor(int port) => '127.0.0.1:$port';

  Future<bool> enable(int port) async {
    if (!supported) throw const AppError('unsupportedPlatform');
    if (port <= 0 || port > 65535) throw AppError('systemProxy', detail: 'Invalid port $port');
    final current = _readSettings();
    if (current == null) throw const AppError('systemProxy', detail: 'Cannot open Internet Settings');
    await _writeBackup(current, serverFor(port));
    try {
      _withKey((arena, key) {
        _writeDword(key, arena, _proxyEnable, 1);
        _writeString(key, arena, _proxyServer, serverFor(port));
        _writeString(key, arena, _proxyOverride, 'localhost;127.*;10.*;172.16.*;172.17.*;172.18.*;172.19.*;172.20.*;172.21.*;172.22.*;172.23.*;172.24.*;172.25.*;172.26.*;172.27.*;172.28.*;172.29.*;172.30.*;172.31.*;192.168.*;<local>');
      });
    } catch (_) {
      await _restoreBackup();
      throw const AppError('systemProxy', detail: 'Failed to write Internet Settings');
    }
    _refresh();
    return true;
  }

  Future<void> disable() async {
    if (!supported) return;
    if (await _readBackup() == null) return;
    await _restoreBackup();
  }

  /// Restores the backed-up values if the current proxy still points at the
  /// server this app applied, then clears the stale backup.
  Future<void> recoverIfStale({required int mixedPort}) async {
    if (!supported) return;
    final backup = await _readBackup();
    if (backup == null) return;
    final current = _readSettings();
    final applied = serverFor(mixedPort);
    final ours = current != null &&
        current.enable == 1 &&
        (current.server == applied || current.server == backup.applied);
    if (ours) {
      await _restoreBackup();
    } else {
      await _deleteBackup();
    }
  }

  Future<bool> isEnabledFor(int port) async {
    if (!supported) return false;
    final current = _readSettings();
    return current != null && current.enable == 1 && current.server == serverFor(port);
  }

  _ProxyState? _readSettings() {
    if (!supported) return null;
    try {
      return _withKey((arena, key) => _ProxyState(
            enable: _readDword(key, arena, _proxyEnable) ?? 0,
            server: _readString(key, arena, _proxyServer),
            override: _readString(key, arena, _proxyOverride),
          ));
    } catch (_) {
      return null;
    }
  }

  T _withKey<T>(T Function(Arena arena, HKEY key) action) {
    return using((arena) {
      final result = arena<Pointer>();
      final status = RegOpenKeyEx(
        HKEY_CURRENT_USER,
        arena.pcwstr(_keyPath),
        0,
        KEY_QUERY_VALUE | KEY_SET_VALUE,
        result,
      );
      if (status.isError) throw WindowsException(status.toHRESULT());
      final key = HKEY(result.value);
      try {
        return action(arena, key);
      } finally {
        key.close();
      }
    });
  }

  int? _readDword(HKEY key, Arena arena, String name) {
    final type = arena<Uint32>();
    final size = arena<Uint32>()..value = 4;
    final data = arena<Uint8>(4);
    final status = RegQueryValueEx(key, arena.pcwstr(name), type, data, size);
    if (status.isError || size.value < 4) return null;
    return data.cast<Uint32>().value;
  }

  String? _readString(HKEY key, Arena arena, String name) {
    final type = arena<Uint32>();
    final size = arena<Uint32>();
    var status = RegQueryValueEx(key, arena.pcwstr(name), type, nullptr, size);
    if (status.isError || size.value == 0) return null;
    final data = arena<Uint8>(size.value);
    status = RegQueryValueEx(key, arena.pcwstr(name), type, data, size);
    if (status.isError || size.value < 2) return null;
    if (type.value != REG_SZ && type.value != REG_EXPAND_SZ) return null;
    return data.cast<Utf16>().toDartString();
  }

  void _writeDword(HKEY key, Arena arena, String name, int value) {
    final data = arena<Uint32>()..value = value;
    final status = RegSetValueEx(key, arena.pcwstr(name), REG_DWORD, data.cast<Uint8>(), 4);
    if (status.isError) throw WindowsException(status.toHRESULT());
  }

  void _writeString(HKEY key, Arena arena, String name, String value) {
    final units = value.codeUnits;
    final data = arena<Uint8>((units.length + 1) * 2);
    final text = data.cast<Uint16>().asTypedList(units.length + 1);
    text.setAll(0, units);
    text[units.length] = 0;
    final status = RegSetValueEx(key, arena.pcwstr(name), REG_SZ, data, text.lengthInBytes);
    if (status.isError) throw WindowsException(status.toHRESULT());
  }

  void _deleteValue(HKEY key, Arena arena, String name) {
    RegDeleteValue(key, arena.pcwstr(name));
  }

  void _refresh() {
    try {
      final wininet = DynamicLibrary.open('wininet.dll');
      final setOption = wininet.lookupFunction<
          Int32 Function(IntPtr, Uint32, Pointer<Void>, Uint32),
          int Function(int, int, Pointer<Void>, int)>('InternetSetOptionW');
      setOption(0, 39, nullptr, 0); // INTERNET_OPTION_SETTINGS_CHANGED
      setOption(0, 37, nullptr, 0); // INTERNET_OPTION_REFRESH
    } catch (_) {}
  }

  Future<void> _writeBackup(_ProxyState current, String applied) async {
    if (await _backupFile.exists()) return;
    final backup = _ProxyBackup(
      enable: current.enable,
      server: current.server,
      override: current.override,
      applied: applied,
      createdAt: DateTime.now(),
    );
    await paths.supportDir.create(recursive: true);
    await _backupFile.writeAsString(const JsonEncoder.withIndent('  ').convert(backup.toJson()));
  }

  Future<_ProxyBackup?> _readBackup() async {
    try {
      if (!await _backupFile.exists()) return null;
      final decoded = jsonDecode(await _backupFile.readAsString());
      if (decoded is Map<String, dynamic>) return _ProxyBackup.fromJson(decoded);
      if (decoded is Map) return _ProxyBackup.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {}
    return null;
  }

  Future<void> _restoreBackup() async {
    final backup = await _readBackup();
    if (backup == null) return;
    _withKey((arena, key) {
      _writeDword(key, arena, _proxyEnable, backup.enable);
      if (backup.server == null || backup.server!.isEmpty) {
        _deleteValue(key, arena, _proxyServer);
      } else {
        _writeString(key, arena, _proxyServer, backup.server!);
      }
      if (backup.override == null) {
        _deleteValue(key, arena, _proxyOverride);
      } else {
        _writeString(key, arena, _proxyOverride, backup.override!);
      }
    });
    _refresh();
    await _deleteBackup();
  }

  Future<void> _deleteBackup() async {
    try {
      if (await _backupFile.exists()) await _backupFile.delete();
    } catch (_) {}
  }
}

class _ProxyState {
  const _ProxyState({required this.enable, this.server, this.override});

  final int enable;
  final String? server;
  final String? override;
}
