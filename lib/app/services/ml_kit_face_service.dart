import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class MLKitFaceService {
  late final FaceDetector _detector;

  MLKitFaceService({required FaceDetectorOptions options})
    : _detector = FaceDetector(options: options);

  /// Gói Điểm danh: Ưu tiên Tốc độ (Fast) & Tracking ID
  factory MLKitFaceService.forAttendance() {
    return MLKitFaceService(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableContours: false,
        enableLandmarks: true,
        enableClassification: false,
        enableTracking: true, // Cần tracking cho streak
        minFaceSize: 0.15,
      ),
    );
  }

  /// Gói Đăng ký: Ưu tiên Độ chính xác (Accurate)
  factory MLKitFaceService.forRegistration() {
    return MLKitFaceService(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableContours: false,
        enableLandmarks: true, // Bắt buộc có để crop mặt thẳng
        enableClassification: false,
        enableTracking: false, // Đăng ký thì không cần tracking ID
        minFaceSize: 0.20, // Bắt người dùng đưa mặt gần hơn chút
      ),
    );
  }

  // 2. Hàm Warm-up chính thức
  Future<MLKitFaceService> warmUp() async {
    try {
      final dummyBytes = Uint8List(10 * 10 * 4);
      final inputImage = InputImage.fromBytes(
        bytes: dummyBytes,
        metadata: InputImageMetadata(
          size: const Size(10, 10),
          rotation: InputImageRotation.rotation0deg,
          format: Platform.isAndroid
              ? InputImageFormat.nv21
              : InputImageFormat.bgra8888,
          bytesPerRow: 10 * 4,
        ),
      );

      // Ép nạp model vào RAM
      await _detector.processImage(inputImage);
      // AppLog.info("🔥 Đã Warm-up thành công Google ML Kit!");
    } catch (e) {
      // Bỏ qua lỗi vì đây là ảnh giả
    }
    return this; // Trả về chính nó để nối chuỗi (chaining) tiện lợi
  }

  // 3. Hàm này để Camera Controller gọi
  Future<List<Face>> processImage(InputImage image) {
    return _detector.processImage(image);
  }

  void dispose() {
    _detector.close();
  }
}
