import 'dart:math';
import 'package:flutter/material.dart';

class DonutSegment {
  final double value;
  final Color color;
  final String label;

  const DonutSegment({
    required this.value,
    required this.color,
    required this.label,
  });
}

class MultiSegmentDonutPainter extends CustomPainter {
  final List<DonutSegment> segments;
  final bool isDark;
  final double strokeWidth;

  MultiSegmentDonutPainter({
    required this.segments,
    required this.isDark,
    this.strokeWidth = 26.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - (strokeWidth / 2) - 2;

    // Subtle background track ring
    final bgPaint = Paint()
      ..color = isDark ? const Color(0xFF1E2638) : const Color(0xFFF1F5F9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, bgPaint);

    final activeSegments = segments.where((s) => s.value > 0).toList();
    final total = activeSegments.fold<double>(0.0, (sum, s) => sum + s.value);

    if (total <= 0 || activeSegments.isEmpty) {
      return;
    }

    // If only 1 segment, draw a complete solid ring
    if (activeSegments.length == 1) {
      final singlePaint = Paint()
        ..color = activeSegments.first.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..isAntiAlias = true;
      canvas.drawCircle(center, radius, singlePaint);
      return;
    }

    // Angular half-width of a cap at the center line radius:
    final double capAngle = (strokeWidth / 2) / radius;
    
    // Tight, sleek visual gap between the tips of rounded caps (~2 degrees)
    const double visualGapAngle = 0.032;

    // Each segment takes: sweepAngle + 2 * capAngle (from the round caps).
    // Between consecutive segments, we leave visualGapAngle.
    final double reservedAngle = activeSegments.length * (2 * capAngle + visualGapAngle);
    final double availableAngle = (2 * pi) - reservedAngle;

    final bool canUseFullCaps = availableAngle > 0;
    final double effectiveAvailable = canUseFullCaps ? availableAngle : (2 * pi * 0.75);
    final double effectiveCapAngle = canUseFullCaps ? capAngle : 0.0;
    final double effectiveGap = canUseFullCaps ? visualGapAngle : ((2 * pi * 0.25) / activeSegments.length);

    double currentAngle = -pi / 2; // Start from 12 o'clock (top)

    for (var seg in activeSegments) {
      final sweepFraction = seg.value / total;
      final sweepAngle = sweepFraction * effectiveAvailable;
      if (sweepAngle <= 0) continue;

      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = canUseFullCaps ? StrokeCap.round : StrokeCap.butt
        ..isAntiAlias = true;

      final arcStart = currentAngle + (effectiveGap / 2) + effectiveCapAngle;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        arcStart,
        sweepAngle,
        false,
        paint,
      );

      currentAngle += sweepAngle + (2 * effectiveCapAngle) + effectiveGap;
    }
  }

  @override
  bool shouldRepaint(covariant MultiSegmentDonutPainter oldDelegate) {
    return true;
  }
}

class DynamicPercentagePainter extends CustomPainter {
  final double percentage;
  final bool isDark;

  DynamicPercentagePainter({required this.percentage, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;
    const strokeWidth = 14.0;

    final bgPaint = Paint()
      ..color = isDark ? const Color(0xFF1F2633) : const Color(0xFFE5E7EB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, bgPaint);

    final fgPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = (percentage / 100) * 2 * pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2,
      sweepAngle,
      false,
      fgPaint,
    );
  }

  @override
  bool shouldRepaint(covariant DynamicPercentagePainter oldDelegate) {
    return oldDelegate.percentage != percentage || oldDelegate.isDark != isDark;
  }
}
