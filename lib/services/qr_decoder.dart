import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:zxing2/qrcode.dart';

/// 把图片里的二维码识别成文本。
///
/// 桌面端没有摄像头，「二维码导入」在 Windows 上走的是选择图片再解码；
/// 安卓端摄像头帧由 mobile_scanner 处理，图片导入复用同一套解码。
class QrDecoder {
  QrDecoder._();

  // 先按 1024 边长解码（快），失败再按 2048 重试，兼顾大图与低清截图。
  static const List<int> _maxSides = [1024, 2048];

  static Future<String?> decodeImage(Uint8List bytes) async {
    for (final maxSide in _maxSides) {
      final raster = await _rasterize(bytes, maxSide);
      if (raster == null) continue;
      final text = decodePixels(raster.pixels, raster.width, raster.height);
      if (text != null) return text;
    }
    return null;
  }

  static String? decodePixels(Int32List argb, int width, int height) {
    final source = RGBLuminanceSource(width, height, argb);
    final hints = DecodeHints()..put(DecodeHintType.tryHarder);
    final reader = QRCodeReader();
    for (final inverted in const [false, true]) {
      final luminance = inverted ? InvertedLuminanceSource(source) : source;
      for (final binarizer in <Binarizer>[
        HybridBinarizer(luminance),
        GlobalHistogramBinarizer(luminance),
      ]) {
        try {
          final text = reader.decode(BinaryBitmap(binarizer), hints: hints).text.trim();
          if (text.isNotEmpty) return text;
        } catch (_) {
          continue;
        }
      }
    }
    return null;
  }

  static Future<_Raster?> _rasterize(Uint8List bytes, int maxSide) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final longest = max(descriptor.width, descriptor.height);
      final scale = longest > maxSide ? maxSide / longest : 1.0;
      codec = scale < 1.0
          ? await descriptor.instantiateCodec(
              targetWidth: max(1, (descriptor.width * scale).round()),
              targetHeight: max(1, (descriptor.height * scale).round()),
            )
          : await descriptor.instantiateCodec();
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final width = image.width;
      final height = image.height;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data == null) return null;
        final rgba = data.buffer.asUint8List();
        final pixels = Int32List(width * height);
        for (var i = 0, p = 0; i < pixels.length; i++, p += 4) {
          pixels[i] = (0xff << 24) | (rgba[p] << 16) | (rgba[p + 1] << 8) | rgba[p + 2];
        }
        return _Raster(pixels, width, height);
      } finally {
        image.dispose();
      }
    } catch (_) {
      return null;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer?.dispose();
    }
  }
}

class _Raster {
  const _Raster(this.pixels, this.width, this.height);

  final Int32List pixels;
  final int width;
  final int height;
}
