import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class MLKitFaceService extends GetxService {
  late final FaceDetector _detector;

  @override
  void onInit() {
    super.onInit();
    // 1. Cấu hình nằm gọn ở đây, UI không cần biết
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.fast,
        enableContours: false,
        enableLandmarks: true,
        enableClassification: false,
        enableTracking: true,
        minFaceSize: 0.15,
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

  @override
  void onClose() {
    _detector.close();
    super.onClose();
  }
}
