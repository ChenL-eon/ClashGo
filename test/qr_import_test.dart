import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:clash_go/services/qr_decoder.dart';
import 'package:clash_go/ui/pages/subscriptions_page.dart' show subscriptionUrlFromQr;
import 'package:flutter_test/flutter_test.dart';
import 'package:qr/qr.dart';

/// 把二维码模块渲染成 ARGB 像素，模拟摄像头/图片解码器拿到的画面。
Int32List _render(QrImage image, {int scale = 6, int quiet = 4, bool invert = false}) {
  final modules = image.moduleCount;
  final size = (modules + quiet * 2) * scale;
  final dark = invert ? 0xffffffff : 0xff000000;
  final light = invert ? 0xff000000 : 0xffffffff;
  final pixels = Int32List(size * size)..fillRange(0, size * size, light);
  for (var row = 0; row < modules; row++) {
    for (var col = 0; col < modules; col++) {
      if (!image.isDark(row, col)) continue;
      final top = (row + quiet) * scale;
      final left = (col + quiet) * scale;
      for (var dy = 0; dy < scale; dy++) {
        final offset = (top + dy) * size + left;
        for (var dx = 0; dx < scale; dx++) {
          pixels[offset + dx] = dark;
        }
      }
    }
  }
  return pixels;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  /// 用 dart:ui 把二维码画成 PNG，覆盖 decodeImage 的解码+缩放链路。
  Future<Uint8List> pngOf(String text, {int scale = 6}) async {
    late Uint8List bytes;
    await binding.runAsync(() async {
      final image = QrImage(QrCode(payload: QrPayload.fromString(text)));
      final modules = image.moduleCount + 8;
      final size = modules * scale;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)..drawRect(
          ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
          ui.Paint()..color = const ui.Color(0xffffffff));
      for (var row = 0; row < image.moduleCount; row++) {
        for (var col = 0; col < image.moduleCount; col++) {
          if (!image.isDark(row, col)) continue;
          canvas.drawRect(
            ui.Rect.fromLTWH(
              ((col + 4) * scale).toDouble(),
              ((row + 4) * scale).toDouble(),
              scale.toDouble(),
              scale.toDouble(),
            ),
            ui.Paint()..color = const ui.Color(0xff000000),
          );
        }
      }
      final picture = recorder.endRecording();
      final raster = await picture.toImage(size, size);
      final data = await raster.toByteData(format: ui.ImageByteFormat.png);
      bytes = data!.buffer.asUint8List();
      raster.dispose();
    });
    return bytes;
  }

  group('qr import', () {
    const url = 'https://example.com/sub?token=abc123#demo';

    test('decodes QR from PNG bytes', () async {
      expect(await QrDecoder.decodeImage(await pngOf(url)), url);
    });

    test('decodes a rendered QR image', () {
      final code = QrCode(payload: QrPayload.fromString(url));
      final image = QrImage(code);
      final pixels = _render(image);
      final size = image.moduleCount + 8;
      expect(QrDecoder.decodePixels(pixels, size * 6, size * 6), url);
    });

    test('decodes an inverted QR image', () {
      final code = QrCode(payload: QrPayload.fromString(url));
      final image = QrImage(code);
      final pixels = _render(image, invert: true);
      final size = image.moduleCount + 8;
      expect(QrDecoder.decodePixels(pixels, size * 6, size * 6), url);
    });

    test('reads plain subscription links and wrapped ones', () {
      expect(subscriptionUrlFromQr(url), url);
      expect(subscriptionUrlFromQr('  $url  '), url);
      expect(
        subscriptionUrlFromQr('clash://install-config?url=${Uri.encodeComponent(url)}'),
        url,
      );
      expect(subscriptionUrlFromQr('clashverge://install-config?url=${Uri.encodeComponent(url)}'), url);
      expect(subscriptionUrlFromQr('not a link at all'), isNull);
      expect(subscriptionUrlFromQr('ftp://example.com/sub'), isNull);
    });
  });
}
