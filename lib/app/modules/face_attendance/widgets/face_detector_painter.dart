import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorPainter extends CustomPainter {
  final List<Face> faces;
  final Size absoluteImageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;

  FaceDetectorPainter(
    this.faces,
    this.absoluteImageSize,
    this.rotation,
    this.cameraLensDirection,
  );

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.greenAccent;

    for (final Face face in faces) {
      // Logic vẽ khung (Scaling tọa độ từ ảnh gốc sang màn hình)
      // Chỗ này cần tính toán tỷ lệ scaleX và scaleY
      // Để đơn giản, tôi vẽ tạm bounding box gốc, thực tế bạn cần scale lại

      // Ví dụ đơn giản (Cần logic translateX/translateY chuẩn từ Google ML Kit Sample)
      canvas.drawRect(
        Rect.fromLTRB(
          face.boundingBox.left * size.width / absoluteImageSize.width,
          face.boundingBox.top * size.height / absoluteImageSize.height,
          face.boundingBox.right * size.width / absoluteImageSize.width,
          face.boundingBox.bottom * size.height / absoluteImageSize.height,
        ),
        paint,
      );
    }

    // for (final Face face in faces) {
    //   // Logic Scale để vẽ đúng tỉ lệ
    //   final double scaleX = size.width / absoluteImageSize.width;
    //   final double scaleY = size.height / absoluteImageSize.height;

    //   // Lưu ý: Cần xử lý thêm vụ Mirror nếu dùng cam trước (logic lật ngược trục X)
    //   // Ở đây là demo cơ bản
    //   final left = face.boundingBox.left * scaleX;
    //   final top = face.boundingBox.top * scaleY;
    //   final right = face.boundingBox.right * scaleX;
    //   final bottom = face.boundingBox.bottom * scaleY;

    //   canvas.drawRect(Rect.fromLTRB(left, top, right, bottom), paint);
    // }
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) {
    return oldDelegate.absoluteImageSize != absoluteImageSize ||
        oldDelegate.faces != faces;
  }
}
