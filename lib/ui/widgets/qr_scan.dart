import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as scanner;

import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../services/qr_decoder.dart';
import 'app_icon.dart';
import 'common.dart';

/// 二维码导入：移动端用摄像头实时识别，桌面端没有摄像头，改为选择二维码图片解码。
bool get qrScannerSupported => Platform.isAndroid || Platform.isIOS;

/// 打开摄像头扫码页，返回识别到的文本；取消时返回 null。
Future<String?> showQrCodeScanner(BuildContext context) {
  return Navigator.of(context).push<String>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _QrCodeScannerPage()),
  );
}

/// 选择一张图片并识别其中的二维码。
/// `picked=false` 表示用户取消，`text=null` 表示图里没有二维码。
Future<({bool picked, String? text})> pickQrCodeImage(BuildContext context) async {
  final picked = await FilePicker.pickFile(type: FileType.image);
  if (picked == null) return (picked: false, text: null);
  final bytes = await _readImageBytes(picked);
  if (bytes == null) return (picked: true, text: null);
  return (picked: true, text: await QrDecoder.decodeImage(bytes));
}

Future<Uint8List?> _readImageBytes(PlatformFile file) async {
  try {
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

class _QrCodeScannerPage extends StatefulWidget {
  const _QrCodeScannerPage();

  @override
  State<_QrCodeScannerPage> createState() => _QrCodeScannerPageState();
}

class _QrCodeScannerPageState extends State<_QrCodeScannerPage> {
  final scanner.MobileScannerController _controller = scanner.MobileScannerController(
    detectionSpeed: scanner.DetectionSpeed.noDuplicates,
    facing: scanner.CameraFacing.back,
    formats: const [scanner.BarcodeFormat.qrCode],
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String? value) {
    if (_handled || value == null || value.trim().isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value.trim());
  }

  void _onDetect(scanner.BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        _submit(value);
        return;
      }
    }
  }

  Future<void> _pickImage() async {
    final result = await pickQrCodeImage(context);
    if (!mounted || !result.picked) return;
    final value = result.text;
    if (value == null) {
      showAppToast(context, context.l10n.get('subscriptions.qrNotFound'), error: true);
      return;
    }
    _submit(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            scanner.MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => _QrCameraError(
                onPickImage: _pickImage,
                onRetry: () => _controller.start(),
              ),
            ),
            const _ScanOverlay(color: Colors.white),
            Positioned(
              left: 8,
              right: 8,
              top: 4,
              child: Row(
                children: [
                  _ScanButton(icon: 'close-line', label: l10n.get('common.close'), onTap: () => Navigator.of(context).pop()),
                  Expanded(
                    child: Text(
                      l10n.get('subscriptions.qrTitle'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                  _ScanButton(
                    icon: 'file-line',
                    label: l10n.get('subscriptions.importFromQrImage'),
                    onTap: _pickImage,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 40,
              child: Text(
                l10n.get('subscriptions.qrHint'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QrCameraError extends StatelessWidget {
  const _QrCameraError({required this.onPickImage, required this.onRetry});

  final VoidCallback onPickImage;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = AppPalette.of(context);
    return ColoredBox(
      color: palette.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon('qrcode-line', size: 40),
              const SizedBox(height: 14),
              Text(
                l10n.get('subscriptions.qrCameraError'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, height: 1.5, color: palette.text),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton(onPressed: onRetry, child: Text(l10n.get('common.retry'))),
                  OutlinedButton(onPressed: onPickImage, child: Text(l10n.get('subscriptions.importFromQrImage'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.icon, required this.label, required this.onTap});

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: AppIcon(icon, size: 22, color: Colors.white),
        ),
      ),
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  const _ScanOverlay({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final side = min(constraints.maxWidth, constraints.maxHeight) * 0.66;
          final frame = Rect.fromCenter(
            center: Offset(constraints.maxWidth / 2, constraints.maxHeight / 2 - 14),
            width: side,
            height: side,
          );
          return CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _ScanOverlayPainter(frame: frame, color: color),
          );
        },
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  const _ScanOverlayPainter({required this.frame, required this.color});

  static const double _radius = 18;

  final Rect frame;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(_radius)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrim, Paint()..color = const Color(0x99000000));

    final arm = max(frame.shortestSide * 0.22, _radius * 2);
    final left = frame.left;
    final top = frame.top;
    final right = frame.right;
    final bottom = frame.bottom;
    final brackets = Path()
      ..moveTo(left, top + arm)
      ..lineTo(left, top + _radius)
      ..quadraticBezierTo(left, top, left + _radius, top)
      ..lineTo(left + arm, top)
      ..moveTo(right - arm, top)
      ..lineTo(right - _radius, top)
      ..quadraticBezierTo(right, top, right, top + _radius)
      ..lineTo(right, top + arm)
      ..moveTo(left, bottom - arm)
      ..lineTo(left, bottom - _radius)
      ..quadraticBezierTo(left, bottom, left + _radius, bottom)
      ..lineTo(left + arm, bottom)
      ..moveTo(right - arm, bottom)
      ..lineTo(right - _radius, bottom)
      ..quadraticBezierTo(right, bottom, right, bottom - _radius)
      ..lineTo(right, bottom - arm);
    canvas.drawPath(
      brackets,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.color != color;
}
