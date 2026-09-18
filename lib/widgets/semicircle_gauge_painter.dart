import 'dart:math';
import 'package:flutter/material.dart';

class SemicircleGaugePainter extends CustomPainter {
  final double percentage;
  final bool isDark;

  SemicircleGaugePainter({required this.percentage, this.isDark = false});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 6;
    const strokeWidth = 8.0;

    final bgPaint = Paint()
      ..color = isDark ? const Color(0xFF1F2633) : const Color(0xFFE4E8F2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, pi, pi, false, bgPaint);

    final fgPaint = Paint()
      ..color = isDark ? const Color(0xFF34D399) : const Color(0xFF10B981)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = (percentage / 100) * pi;
    canvas.drawArc(rect, pi, sweepAngle, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant SemicircleGaugePainter oldDelegate) {
    return oldDelegate.percentage != percentage || oldDelegate.isDark != isDark;
  }
}
