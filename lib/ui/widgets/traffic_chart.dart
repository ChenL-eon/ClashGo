import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/traffic_sample.dart';

class TrafficChart extends StatelessWidget {
  const TrafficChart({
    super.key,
    required this.samples,
    required this.revision,
    required this.uploadColor,
    required this.downloadColor,
    required this.gridColor,
    this.height = 110,
  });

  final TrafficRing samples;

  /// 环形缓冲是原地改写的，实例不换引用，只能靠 revision 判断要不要重绘。
  final int revision;
  final Color uploadColor;
  final Color downloadColor;
  final Color gridColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _TrafficPainter(
            samples: samples,
            revision: revision,
            uploadColor: uploadColor,
            downloadColor: downloadColor,
            gridColor: gridColor,
          ),
        ),
      ),
    );
  }
}

class _TrafficPainter extends CustomPainter {
  _TrafficPainter({
    required this.samples,
    required this.revision,
    required this.uploadColor,
    required this.downloadColor,
    required this.gridColor,
  });

  final TrafficRing samples;
  final int revision;
  final Color uploadColor;
  final Color downloadColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor.withValues(alpha: 0.55)
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = size.height * (0.25 + i * 0.25);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (samples.isEmpty) return;

    var maxValue = 1024.0;
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      maxValue = math.max(maxValue, math.max(sample.upload, sample.download).toDouble());
    }
    maxValue *= 1.18;

    final width = size.width;
    final height = size.height - 6;
    double xFor(int index) {
      if (samples.length == 1) return width * 0.5;
      return width * index / (samples.length - 1);
    }

    double yFor(int value) => height - (value / maxValue * height) + 2;

    final uploadPoints = <Offset>[
      for (var i = 0; i < samples.length; i++) Offset(xFor(i), yFor(samples[i].upload)),
    ];
    final downloadPoints = <Offset>[
      for (var i = 0; i < samples.length; i++) Offset(xFor(i), yFor(samples[i].download)),
    ];

    _drawArea(canvas, size, downloadPoints, downloadColor);
    _drawArea(canvas, size, uploadPoints, uploadColor);

    canvas.drawPath(_smoothPath(uploadPoints), _strokePaint(uploadColor));
    canvas.drawPath(_smoothPath(downloadPoints), _strokePaint(downloadColor));

    final last = downloadPoints.last;
    canvas.drawCircle(last, 3.2, Paint()..color = downloadColor);
    canvas.drawCircle(last, 6, Paint()..color = downloadColor.withValues(alpha: 0.18));
  }

  Paint _strokePaint(Color color) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _drawArea(Canvas canvas, Size size, List<Offset> points, Color color) {
    if (points.length < 2) return;
    final area = Path()..addPath(_smoothPath(points), Offset.zero);
    area
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.22), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(area, paint);
  }

  Path _smoothPath(List<Offset> points) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    if (points.length == 1) return path;
    for (var i = 0; i < points.length - 1; i++) {
      final current = points[i];
      final next = points[i + 1];
      final midX = (current.dx + next.dx) / 2;
      path.cubicTo(midX, current.dy, midX, next.dy, next.dx, next.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _TrafficPainter oldDelegate) {
    return oldDelegate.revision != revision ||
        oldDelegate.uploadColor != uploadColor ||
        oldDelegate.downloadColor != downloadColor ||
        oldDelegate.gridColor != gridColor;
  }
}
