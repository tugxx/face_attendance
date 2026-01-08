import 'dart:math' as math;
import 'dart:ui';
import 'dart:math';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;


class ProcessingData {
  final Uint8List imageBytes;
  final FaceLandmarkData landmarks;
  final Rect faceBoundingBox;

  ProcessingData({
    required this.imageBytes,
    required this.landmarks,
    required this.faceBoundingBox,
  });
}

class FaceLandmarkData {
  final Point<int> leftEye;
  final Point<int> rightEye;

  FaceLandmarkData({required this.leftEye, required this.rightEye});
}

class FaceAligner {
  // --- CẤU HÌNH CHUẨN ARCFACE (112x112) ---
  // Theo chuẩn InsightFace: Mắt nằm ở khoảng dòng 35-40% của ảnh
  static const double targetWidth = 112.0;
  static const double targetHeight = 112.0;

  // Mong muốn: Khoảng cách giữa 2 mắt chiếm bao nhiêu % chiều rộng ảnh?
  // Chuẩn thường là 0.35 đến 0.45 (tức là 2 mắt cách nhau khoảng 40-50px)
  static const double desiredEyeDistScale = 0.32;

  // Mong muốn: Mắt nằm ở bao nhiêu % chiều cao ảnh (tính từ trên xuống)?
  static const double desiredEyeY = 0.46;

  /// Hàm chính: Căn chỉnh khuôn mặt
  static Future<img.Image?> alignFace(File imageFile, Face face) async {
    // 1. Đọc bytes từ file (Nhanh)
    final Uint8List bytes = await imageFile.readAsBytes();

    // 1. Lấy tọa độ mốc quan trọng (Landmarks)
    final leftEye = face.landmarks[FaceLandmarkType.leftEye];
    final rightEye = face.landmarks[FaceLandmarkType.rightEye];

    // Nếu ML Kit không bắt được mắt (hiếm), fallback về crop thường
    if (leftEye == null || rightEye == null) {
      return null;
    }

    final data = ProcessingData(
      imageBytes: bytes,
      faceBoundingBox: face.boundingBox,
      landmarks: FaceLandmarkData(
        leftEye: Point(leftEye.position.x, leftEye.position.y),
        rightEye: Point(rightEye.position.x, rightEye.position.y),
      ),
    );

    return await compute(_heavyProcessingEntry, data);

    // // 2. Tính toán góc nghiêng (Angle)
    // // dy/dx để tính góc giữa 2 mắt so với phương ngang
    // final double dy =
    //     rightEye.position.y.toDouble() - leftEye.position.y.toDouble();
    // final double dx =
    //     rightEye.position.x.toDouble() - leftEye.position.x.toDouble();
    // final double angleRad = math.atan2(dy, dx); // Góc tính bằng Radian
    // final double angleDeg = angleRad * 180 / math.pi; // Đổi sang độ

    // // 3. Xoay ảnh (QUAN TRỌNG: Xoay ngược lại góc nghiêng để cân bằng)
    // // img.copyRotate mặc định mở rộng canvas để không mất góc ảnh
    // img.Image rotatedImg = img.copyRotate(srcImage, angle: -angleDeg);

    // // Lấy tâm giữa 2 mắt trên ảnh GỐC
    // final double eyesCenterX = (leftEye.position.x.toDouble() + rightEye.position.x.toDouble()) / 2;
    // final double eyesCenterY = (leftEye.position.y.toDouble() + rightEye.position.y.toDouble()) / 2;

    // // Xoay điểm này theo công thức toán học quanh tâm cũ (oldCx, oldCy)
    // final math.Point<double> newEyeCenter = _mapPointAfterRotation(
    //   x: eyesCenterX,
    //   y: eyesCenterY,
    //   oldW: srcImage.width.toDouble(),
    //   oldH: srcImage.height.toDouble(),
    //   newW: rotatedImg.width.toDouble(),
    //   newH: rotatedImg.height.toDouble(),
    //   angleRad: -angleRad,
    // );

    // // 5. Tính Scale Factor
    // // Khoảng cách thực tế giữa 2 mắt hiện tại
    // final double currentEyeDist = math.sqrt(dx * dx + dy * dy);
    // // Khoảng cách mong muốn trên ảnh 112x112
    // final double desiredDist = targetWidth * desiredEyeDistScale;

    // // Tỉ lệ scale cần thiết
    // final double scale = desiredDist / currentEyeDist;

    // // 6. Tính vùng Crop
    // // Ta có tâm mắt (finalEyeCenterX, finalEyeCenterY).
    // // Điểm này cần nằm ở vị trí (50% Width, 36% Height) của ảnh kết quả.
    
    // // Kích thước vùng cần cắt trên ảnh rotated (trước khi resize xuống 112)
    // double cropW = targetWidth / scale;
    // double cropH = targetHeight / scale;

    // // Tính toạ độ Top-Left của vùng crop
    // double cropX = newEyeCenter.x - (cropW * 0.5); 
    // double cropY = newEyeCenter.y - (cropH * desiredEyeY);

    // final img.Image cropped = img.copyCrop(
    //   rotatedImg,
    //   x: cropX.round(),
    //   y: cropY.round(),
    //   width: cropW.round(),
    //   height: cropH.round(),
    // );

    // // Resize chính xác về 112x112
    // return img.copyResize(
    //   cropped,
    //   width: targetWidth.toInt(),
    //   height: targetHeight.toInt(),
    //   interpolation: img.Interpolation.average,
    // );
  }
}

  Future<img.Image?> _heavyProcessingEntry(ProcessingData data) async {
  try {
    // 1. Decode ảnh gốc (Tốn RAM và CPU nhất -> Đã ở trong Isolate nên ok)
    img.Image? srcImage = img.decodeImage(data.imageBytes);
    if (srcImage == null) return null;

    // --- LOGIC: CROP-FIRST (TĂNG TỐC ĐỘ) ---
    // Thay vì xoay cả bức ảnh 1280x1280, ta cắt vùng mặt ra trước.
    
    // a. Tính vùng Crop thô (Raw Crop Rect)
    // Mở rộng BoundingBox ra 50% để khi xoay không bị mất góc
    final double padding = math.max(data.faceBoundingBox.width, data.faceBoundingBox.height) * 0.5;
    
    int cropX = (data.faceBoundingBox.left - padding).toInt();
    int cropY = (data.faceBoundingBox.top - padding).toInt();
    int cropW = (data.faceBoundingBox.width + padding * 2).toInt();
    int cropH = (data.faceBoundingBox.height + padding * 2).toInt();

    // Kẹp vào biên ảnh (để không crash)
    cropX = cropX.clamp(0, srcImage.width);
    cropY = cropY.clamp(0, srcImage.height);
    cropW = math.min(cropW, srcImage.width - cropX);
    cropH = math.min(cropH, srcImage.height - cropY);

    // b. Cắt thô (Rất nhanh vì chỉ copy bytes)
    // Ảnh lúc này chỉ còn khoảng 300x300 đến 500x500
    img.Image rawFaceImg = img.copyCrop(srcImage, x: cropX, y: cropY, width: cropW, height: cropH);

    // c. Tính lại toạ độ mắt trên ảnh nhỏ vừa cắt
    // Toạ độ mới = Toạ độ cũ - Toạ độ góc trái trên của vùng cắt
    final double relativeLeftEyeX = data.landmarks.leftEye.x.toDouble() - cropX;
    final double relativeLeftEyeY = data.landmarks.leftEye.y.toDouble() - cropY;
    final double relativeRightEyeX = data.landmarks.rightEye.x.toDouble() - cropX;
    final double relativeRightEyeY = data.landmarks.rightEye.y.toDouble() - cropY;

    // --- LOGIC: ALIGNMENT (Trên ảnh nhỏ) ---
    
    // 2. Tính góc nghiêng
    final double dy = relativeRightEyeY - relativeLeftEyeY;
    final double dx = relativeRightEyeX - relativeLeftEyeX;
    final double angleRad = math.atan2(dy, dx);
    final double angleDeg = angleRad * 180 / math.pi;

    // 3. Xoay ảnh nhỏ (Nhanh hơn xoay ảnh to gấp nhiều lần)
    // Dùng linear khi xoay để nhanh, vì sau đó sẽ resize cubic
    img.Image rotatedImg = img.copyRotate(rawFaceImg, angle: -angleDeg, interpolation: img.Interpolation.linear);

    // 4. Map toạ độ mắt sau khi xoay (Logic cũ của bạn, áp dụng cho ảnh nhỏ)
    final double eyesCenterX = (relativeLeftEyeX + relativeRightEyeX) / 2;
    final double eyesCenterY = (relativeLeftEyeY + relativeRightEyeY) / 2;

    final math.Point<double> newEyeCenter = _mapPointAfterRotation(
      x: eyesCenterX,
      y: eyesCenterY,
      oldW: rawFaceImg.width.toDouble(),
      oldH: rawFaceImg.height.toDouble(),
      newW: rotatedImg.width.toDouble(),
      newH: rotatedImg.height.toDouble(),
      angleRad: -angleRad,
    );

    // 5. Tính Scale và Crop lần cuối về 112x112
    final double currentEyeDist = math.sqrt(dx * dx + dy * dy);
    final double desiredDist = FaceAligner.targetWidth * FaceAligner.desiredEyeDistScale;
    final double scale = desiredDist / currentEyeDist;

    final double cropFinalW = FaceAligner.targetWidth / scale;
    final double cropFinalH = FaceAligner.targetHeight / scale;

    final double cropFinalX = newEyeCenter.x - (cropFinalW * 0.5);
    final double cropFinalY = newEyeCenter.y - (cropFinalH * FaceAligner.desiredEyeY);

    // Crop chính xác
    final img.Image finalCropped = img.copyCrop(
      rotatedImg,
      x: cropFinalX.round(),
      y: cropFinalY.round(),
      width: cropFinalW.round(),
      height: cropFinalH.round(),
    );

    // Resize về 112x112 dùng Cubic (Chất lượng cao nhất)
    return img.copyResize(
      finalCropped,
      width: FaceAligner.targetWidth.toInt(),
      height: FaceAligner.targetHeight.toInt(),
      interpolation: img.Interpolation.cubic, // Hoặc average
    );

  } catch (e) {
    debugPrint("Isolate Error: $e");
    return null;
  }
}

  /// Hàm map tọa độ quan trọng: Chuyển điểm (x,y) từ ảnh gốc sang ảnh đã xoay (và bị resize canvas)
  math.Point<double> _mapPointAfterRotation({
    required double x,
    required double y,
    required double oldW,
    required double oldH,
    required double newW,
    required double newH,
    required double angleRad, // Góc xoay thực tế (đã đảo dấu)
  }) {
    // 1. Chuyển về hệ tọa độ tâm (0,0 ở giữa ảnh cũ)
    final double cx = oldW / 2;
    final double cy = oldH / 2;
    final double dx = x - cx;
    final double dy = y - cy;

    // 2. Xoay điểm
    // Công thức xoay vector 2D
    final double cosA = math.cos(angleRad);
    final double sinA = math.sin(angleRad);
    final double rX = dx * cosA - dy * sinA;
    final double rY = dx * sinA + dy * cosA;

    // 3. Chuyển về hệ tọa độ ảnh mới (0,0 ở góc trái trên ảnh mới)
    final double newCx = newW / 2;
    final double newCy = newH / 2;

    return math.Point<double>(newCx + rX, newCy + rY);
  }

  // // Fallback: Nếu không tìm thấy mắt, dùng cách cũ (mở rộng bbox)
  // static img.Image _fallbackCrop(img.Image srcImage, Face face) {
  //   double scaleFactor = 0.4; // Mở rộng 
  //   double w = face.boundingBox.width;
  //   double h = face.boundingBox.height;
  //   double maxSide = math.max(w, h);
  //   double sideLength = maxSide * (1 + scaleFactor);

  //   double centerX = face.boundingBox.center.dx;
  //   double centerY = face.boundingBox.center.dy;

  //   int x = (centerX - sideLength / 2).toInt();
  //   int y = (centerY - sideLength / 2).toInt();

  //   final cropped = img.copyCrop(
  //     srcImage,
  //     x: x,
  //     y: y,
  //     width: sideLength.toInt(),
  //     height: sideLength.toInt(),
  //   );

  //   return img.copyResize(
  //     cropped,
  //     width: 112,
  //     height: 112,
  //     interpolation: img.Interpolation.linear,
  //   );
  // }

