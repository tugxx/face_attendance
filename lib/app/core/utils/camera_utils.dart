import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class CameraUtils {
  static InputImage? convertCameraImageToInputImage(
      CameraImage image, CameraDescription camera) {
    
    // 1. Nối các bytes từ các planes lại với nhau
    final allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    // 2. Lấy kích thước ảnh
    final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

    // 3. Xử lý góc xoay (Rotation)
    final InputImageRotation? imageRotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (imageRotation == null) return null;

    // 4. Xử lý định dạng (Format)
    final InputImageFormat? inputImageFormat =
        InputImageFormatValue.fromRawValue(image.format.raw);
    if (inputImageFormat == null) return null;

    // 5. [THAY ĐỔI QUAN TRỌNG] Sử dụng InputImageMetadata thay vì InputImageData
    // API mới chỉ cần lấy bytesPerRow của plane đầu tiên
    final inputImageMetadata = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: image.planes[0].bytesPerRow, 
    );

    // 6. [THAY ĐỔI TÊN THAM SỐ] Dùng 'metadata' thay vì 'inputImageData'
    return InputImage.fromBytes(
      bytes: bytes, 
      metadata: inputImageMetadata,
    );
  }
}