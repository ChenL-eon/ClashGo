import 'package:flutter/material.dart';

import '../../core/theme.dart';

class QuotaBar extends StatelessWidget {
  const QuotaBar({
    super.key,
    required this.ratio,
    this.color,
    this.height = 7,
    this.trackColor,
  });

  final double ratio;
  final Color? color;
  final double height;
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final tone = color ?? Theme.of(context).colorScheme.primary;
    final value = ratio.isFinite ? ratio.clamp(0.0, 1.0) : 0.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: trackColor ?? palette.cardAlt),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [tone, tone.withValues(alpha: 0.65)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
