import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// 内核更新最后一步用的是同目录 rename。它不是"先删再改名"：目标文件已经存在时
/// 一次目录项替换就完成，旧内核在成功之前始终是完整的。
void main() {
  test('同目录 rename 能替换已存在的内核文件', () async {
    final dir = await Directory.systemTemp.createTemp('clashgo_core_replace_');
    addTearDown(() => dir.delete(recursive: true));
    final core = File(p.join(dir.path, 'mihomo.exe'))
      ..writeAsBytesSync(const [1, 2, 3, 4]);
    final update = File(p.join(dir.path, 'mihomo-update.exe'))
      ..writeAsBytesSync(const [9, 9, 9]);

    await update.rename(core.path);

    expect(core.readAsBytesSync(), const [9, 9, 9]);
    expect(update.existsSync(), isFalse, reason: '临时文件不该留在内核目录里');
  });
}
