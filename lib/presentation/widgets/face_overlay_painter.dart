import 'dart:math';

import 'package:flutter/material.dart';

class FaceOverlayPainter extends CustomPainter {
  final Color borderColor;
  final double progress;

  FaceOverlayPainter({required this.borderColor, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Phủ màn đen mờ toàn bộ màn hình
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.7);
    final bgRect = Rect.fromLTWH(0, 0, size.width, size.height);

    // 2. Tính toán vị trí và kích thước hình Oval ở giữa màn hình
    final ovalWidth = size.width * 0.7; // Chiều rộng bằng 70% màn hình
    final ovalHeight = ovalWidth * 1.3; // Chiều cao tỷ lệ 1.3
    final ovalRect = Rect.fromCenter(
      center: Offset(
        size.width / 2,
        size.height / 2.2,
      ), // Hơi xích lên trên 1 tí
      width: ovalWidth,
      height: ovalHeight,
    );

    // 3. Đục lỗ hình Oval (Path.combine lấy phần giao nhau)
    final bgPath = Path()..addRect(bgRect);
    final ovalPath = Path()..addOval(ovalRect);
    final cutoutPath = Path.combine(PathOperation.difference, bgPath, ovalPath);

    canvas.drawPath(cutoutPath, paint);

    // 4. Vẽ cái viền chớp chớp bao quanh
    final baseBorderPaint = Paint()
      ..color = borderColor
          .withValues(alpha: 0.2) // Rất mờ
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawOval(ovalRect, baseBorderPaint);

    if (progress > 0) {
      final progressPaint = Paint()
        ..color =
            borderColor // Tươi rói
        ..style = PaintingStyle.stroke
        ..strokeWidth =
            6.0 // Dày hơn đường ray một chút cho nổi bật
        ..strokeCap = StrokeCap.round; // Đầu thanh progress bo tròn cực đẹp

      // Bắt đầu vẽ từ góc 12 giờ (-pi/2) và quét thuận chiều kim đồng hồ
      final sweepAngle = 2 * pi * progress;
      canvas.drawArc(ovalRect, -pi / 2, sweepAngle, false, progressPaint);
    }
  }

  @override
  bool shouldRepaint(covariant FaceOverlayPainter oldDelegate) {
    return oldDelegate.borderColor != borderColor || oldDelegate.progress != progress;
  }
}
