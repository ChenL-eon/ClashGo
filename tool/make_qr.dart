// 开发期工具：把一段文本渲染成二维码 PNG，用于手工验证「二维码导入」。
// 用法：dart run tool/make_qr.dart [文本] [输出路径]
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

void main(List<String> args) {
  final text = args.isNotEmpty ? args[0] : 'http://127.0.0.1:18099/demo.yaml';
  final output = args.length > 1 ? args[1] : 'build/verify_ui12/qr_demo.png';
  final qr = QrImage(QrCode(payload: QrPayload.fromString(text)));
  const scale = 8;
  const quiet = 4;
  final modules = qr.moduleCount;
  final size = (modules + quiet * 2) * scale;
  final canvas = img.Image(width: size, height: size);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      canvas.setPixelRgb(x, y, 255, 255, 255);
    }
  }
  for (var row = 0; row < modules; row++) {
    for (var col = 0; col < modules; col++) {
      if (!qr.isDark(row, col)) continue;
      for (var dy = 0; dy < scale; dy++) {
        for (var dx = 0; dx < scale; dx++) {
          canvas.setPixelRgb((col + quiet) * scale + dx, (row + quiet) * scale + dy, 0, 0, 0);
        }
      }
    }
  }
  final file = File(output)..createSync(recursive: true);
  file.writeAsBytesSync(img.encodePng(canvas));
  stdout.writeln('wrote $output (${size}x$size) for: $text');
}
