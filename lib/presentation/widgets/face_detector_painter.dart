import 'dart:math';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorPainter extends CustomPainter {
  final List<Face> faces;
  final Size absoluteImageSize; // Kích thước gốc của ảnh Camera
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;

  FaceDetectorPainter(
    this.faces,
    this.absoluteImageSize,
    this.rotation,
    this.cameraLensDirection,
  );

  /// Hàm sửa lỗi 'undefined_method': Tính toán tọa độ X
  /// Tự động xử lý lật gương (Mirror) nếu là Camera trước
  double _translateX(
    double x,
    double scaleX,
    Size size,
    CameraLensDirection direction,
  ) {
    // Tọa độ thực trên màn hình
    final double rawX = x * scaleX;

    if (direction == CameraLensDirection.front) {
      // Nếu là cam trước: Lấy chiều rộng màn hình trừ đi tọa độ (Lật trục X)
      return size.width - rawX;
    } else {
      return rawX;
    }
  }

  /// Tính toán tọa độ Y
  double _translateY(double y, double scaleY) {
    return y * scaleY;
  }

  /// Hàm vẽ các điểm trên mặt (Mắt, mũi, miệng...)
  void _paintContour(
    Canvas canvas,
    Paint paint,
    Face face,
    double scaleX,
    double scaleY,
    Size size,
  ) {
    // Danh sách các bộ phận muốn vẽ
    final contoursToCheck = [
      FaceContourType.face,
      FaceContourType.leftEyebrowTop,
      FaceContourType.rightEyebrowTop,
      FaceContourType.leftEye,
      FaceContourType.rightEye,
      FaceContourType.noseBridge,
      FaceContourType.upperLipTop,
      FaceContourType.lowerLipBottom,
    ];

    for (final type in contoursToCheck) {
      final contour = face.contours[type];
      if (contour?.points != null) {
        for (final Point point in contour!.points) {
          canvas.drawCircle(
            Offset(
              _translateX(
                point.x.toDouble(),
                scaleX,
                size,
                cameraLensDirection,
              ),
              _translateY(point.y.toDouble(), scaleY),
            ),
            2, // Bán kính chấm tròn
            paint,
          );
        }
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.greenAccent;

      final Paint landmarkPaint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 2.0
      ..color = Colors.red;

    for (final Face face in faces) {
      // 1. Xác định kích thước ảnh thực tế sau khi xoay
      // Android: Ảnh gốc là Landscape (ngang), nhưng hiển thị Portrait (dọc) -> Cần đảo chiều
      final bool isRotated = rotation == InputImageRotation.rotation90deg || 
                             rotation == InputImageRotation.rotation270deg;

      final double imageWidth = isRotated ? absoluteImageSize.height : absoluteImageSize.width;
      final double imageHeight = isRotated ? absoluteImageSize.width : absoluteImageSize.height;

      // Logic chuyển đổi tọa độ từ ảnh gốc sang màn hình
      // size: Kích thước của Widget hiển thị trên màn hình (VD: 360x640)
      // absoluteImageSize: Kích thước ảnh từ sensor camera (VD: 720x1280 - đã xoay)
      final double scaleX = size.width / imageWidth;
      final double scaleY = size.height / imageHeight;

      // Lấy tỷ lệ lớn hơn để đảm bảo ảnh phủ kín màn hình (Zoom in)
      final double scale = scaleX > scaleY ? scaleX : scaleY;

      // 3. Tính phần thừa bị cắt (Offset)
      // Khi Zoom in, ảnh sẽ bị thừa ra ngoài màn hình. Cần tính xem nó bị lệch bao nhiêu.
      final double offsetX = (size.width - imageWidth * scale) / 2;
      final double offsetY = (size.height - imageHeight * scale) / 2;

      // 4. Hàm chuyển đổi tọa độ
      double translateX(double x) => x * scale + offsetX;
      double translateY(double y) => y * scale + offsetY;

      // 5. Tính tọa độ khung
      double left = translateX(face.boundingBox.left);
      double top = translateY(face.boundingBox.top);
      double right = translateX(face.boundingBox.right);
      double bottom = translateY(face.boundingBox.bottom);

      // 6. Xử lý Lật Gương (Mirror) cho Camera trước
      if (cameraLensDirection == CameraLensDirection.front) {
        // Lật trục X qua tâm màn hình
        final double tempLeft = left;
        left = size.width - right;
        right = size.width - tempLeft;
      }

      canvas.drawRect(
        Rect.fromLTRB(left, top, right, bottom),
        paint,
      );

      // 3. Vẽ Landmark (Optional - Debug)
      // Gọi hàm vẽ Contour để hết lỗi "unused_element"
      _paintContour(canvas, landmarkPaint, face, scaleX, scaleY, size);
    }
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) {
    return oldDelegate.absoluteImageSize != absoluteImageSize ||
        oldDelegate.faces != faces;
  }
}
