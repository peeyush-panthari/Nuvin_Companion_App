import 'package:flutter/material.dart';
import '../constants/colors.dart';

class NuvinMark extends StatelessWidget {
  final double size;

  const NuvinMark({super.key, this.size = 36.0});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _NuvinMarkPainter(),
    );
  }
}

class _NuvinMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 48.0;
    canvas.save();
    canvas.scale(scale, scale);

    // Background circle
    final bgPaint = Paint()
      ..color = NuvinColors.card
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(24, 24), 23, bgPaint);

    // Cyan arc: M11 27.5c0-8.8 5.8-15.5 13-15.5 4.2 0 7.7 2.1 10 5.6
    final cyanPaint = Paint()
      ..color = NuvinColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    final path1 = Path();
    path1.moveTo(11, 27.5);
    path1.cubicTo(11, 18.7, 16.8, 12.0, 24, 12.0);
    path1.cubicTo(28.2, 12.0, 31.7, 14.1, 34, 17.6);
    canvas.drawPath(path1, cyanPaint);

    // Amber arc: M37 20.5c0 8.8-5.8 15.5-13 15.5-4.2 0-7.7-2.1-10-5.6
    final amberPaint = Paint()
      ..color = NuvinColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round;

    final path2 = Path();
    path2.moveTo(37, 20.5);
    path2.cubicTo(37, 29.3, 31.2, 36.0, 24, 36.0);
    path2.cubicTo(19.8, 36.0, 16.3, 33.9, 14, 30.4);
    canvas.drawPath(path2, amberPaint);

    // Anchor dots
    final dotCyan = Paint()
      ..color = NuvinColors.primary
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(35, 15), 2.2, dotCyan);

    final dotAmber = Paint()
      ..color = NuvinColors.accent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(13, 33), 2.2, dotAmber);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
