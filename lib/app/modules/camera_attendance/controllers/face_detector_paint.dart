// widgets/face_detector_painter.dart
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorPainter extends CustomPainter {
  final List<Face> faces;
  final Size absoluteImageSize; // Kích thước gốc của ảnh từ camera
  final InputImageRotation rotation; // Góc xoay

  FaceDetectorPainter(this.faces, this.absoluteImageSize, this.rotation);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.greenAccent; // Màu khung xanh lá

    for (final Face face in faces) {
      // Cần tính toán tỉ lệ scale để vẽ đúng vị trí trên màn hình điện thoại
      // vì ảnh camera (ví dụ 1280x720) khác kích thước màn hình (ví dụ 400x800)

      // Ở đây mình demo vẽ đơn giản, thực tế cần hàm translate coordinate phức tạp hơn
      // tùy thuộc vào BoxFit.cover hay contain
      canvas.drawRect(face.boundingBox, paint);
    }
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) {
    return oldDelegate.faces != faces;
  }
}
