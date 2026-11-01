import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Windows 登录自启：写 HKCU 的 Run 项，并同步 StartupApproved，
/// 否则用户在任务管理器里关过一次之后，再打开开关也不会真正生效。
class StartupService {
  static const _runKeyPath = r'Software\Microsoft\Windows\CurrentVersion\Run';
  static const _approvedKeyPath =
      r'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run';
  static const _valueName = 'ClashGo';

  /// main 看到这个参数就不弹主窗口，直接驻留托盘。
  static const autostartFlag = '--autostart';

  static bool get supported => Platform.isWindows;

  String get command => '"${Platform.resolvedExecutable}" $autostartFlag';

  void apply(bool enabled) {
    if (!supported) return;
    if (enabled) {
      _writeCommand();
      _writeApproved();
    } else {
      _deleteAll();
    }
  }

  /// 启动时对账：开着且注册表指向旧路径（便携包被挪过）就重写；
  /// 关着就清掉残留。路径没变时不动 StartupApproved，保留用户在
  /// 任务管理器里手动关闭的选择。
  void reconcile(bool enabled) {
    if (!supported) return;
    if (enabled) {
      if (_readCommand() == command) return;
      _writeCommand();
      _writeApproved();
    } else {
      _deleteAll();
    }
  }

  String? _readCommand() {
    try {
      return _withKey(
        _runKeyPath,
        (arena, key) => _readString(key, arena, _valueName),
        write: false,
        create: false,
      );
    } catch (_) {
      return null;
    }
  }

  void _writeCommand() {
    _withKey(_runKeyPath, (arena, key) {
      _writeString(key, arena, _valueName, command);
    }, write: true, create: true);
  }

  void _writeApproved() {
    _withKey(_approvedKeyPath, (arena, key) {
      final data = arena<Uint8>(12);
      data.asTypedList(12)[0] = 2;
      final status = RegSetValueEx(key, arena.pcwstr(_valueName), REG_BINARY, data, 12);
      if (status.isError) throw WindowsException(status.toHRESULT());
    }, write: true, create: true);
  }

  void _deleteAll() {
    for (final path in const [_runKeyPath, _approvedKeyPath]) {
      try {
        _withKey(path, (arena, key) {
          RegDeleteValue(key, arena.pcwstr(_valueName));
        }, write: true, create: false);
      } catch (_) {
        // 键或值本来就不存在：关闭操作幂等。
      }
    }
  }

  T _withKey<T>(
    String path,
    T Function(Arena arena, HKEY key) action, {
    required bool write,
    required bool create,
  }) {
    return using((arena) {
      final result = arena<Pointer>();
      final access = write ? (KEY_SET_VALUE | KEY_QUERY_VALUE) : KEY_QUERY_VALUE;
      final status = create
          ? RegCreateKeyEx(
              HKEY_CURRENT_USER,
              arena.pcwstr(path),
              null,
              REG_OPTION_NON_VOLATILE,
              access,
              null,
              result,
              null,
            )
          : RegOpenKeyEx(HKEY_CURRENT_USER, arena.pcwstr(path), 0, access, result);
      if (status.isError) throw WindowsException(status.toHRESULT());
      final key = HKEY(result.value);
      try {
        return action(arena, key);
      } finally {
        key.close();
      }
    });
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

  void _writeString(HKEY key, Arena arena, String name, String value) {
    final units = value.codeUnits;
    final data = arena<Uint8>((units.length + 1) * 2);
    final text = data.cast<Uint16>().asTypedList(units.length + 1);
    text.setAll(0, units);
    text[units.length] = 0;
    final status = RegSetValueEx(key, arena.pcwstr(name), REG_SZ, data, text.lengthInBytes);
    if (status.isError) throw WindowsException(status.toHRESULT());
  }
}
