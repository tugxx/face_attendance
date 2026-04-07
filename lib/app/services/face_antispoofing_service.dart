// import 'dart:io';
// import 'dart:math';

import 'package:get/get.dart';
// import 'package:tflite_flutter/tflite_flutter.dart';
// import 'package:flutter/foundation.dart';
// import 'package:image/image.dart' as img;
// import 'package:path_provider/path_provider.dart' as path_provider;

import '../services/log_service.dart';
import 'native_ai_service.dart';

class FaceAntiSpoofingService extends GetxService {
  // --- SINGLETON PATTERN ---
  static final FaceAntiSpoofingService _instance =
      FaceAntiSpoofingService._internal();
  factory FaceAntiSpoofingService() => _instance;
  FaceAntiSpoofingService._internal();

  static const String _modelPath = 'assets/models/fasnet_float32.tflite';
  String get modelName => _modelPath.split('/').last.replaceAll('.tflite', '');

  // Ngưỡng tin cậy
  static const double _threshold = 0.6;

  final int _inputWidth = 80;
  final int _inputHeight = 80;

  int get inputWidth => _inputWidth;
  int get inputHeight => _inputHeight;

  double get threshold => _threshold;
  bool _isReady = false;
  bool get isReady => _isReady;

  // bool get isReady => _interpreter != null;

  Future<void> initialize() async {
    try {
      _isReady = await NativeAiService().initSpoofModel(_modelPath);
    } catch (e, stackTrace) {
      AppLog.error("❌ LỖI TẠI KHÂU KHỞI TẠO ANTI-SPOOFING MODEL!");
      AppLog.error("Chi tiết lỗi: $e");
      AppLog.error("Stack Trace: $stackTrace");
    }
  }

  Future<bool> predict(List<double> inputPixels) async {
    if (!isReady) return false;

    try {
      // 1. Khoán cho C++ tính toán Softmax và trả về điểm số Real
      final double scoreReal = NativeAiService().predictSpoof(inputPixels);

      if (scoreReal < 0.0) {
        // C++ trả về -1 nghĩa là có lỗi
        // AppLog.warning("⚠️ C++ Spoofing Predict trả về lỗi");
        return false;
      }

      // AppLog.info("🛡️ Real Score (C++): ${(scoreReal * 100).toStringAsFixed(2)}%");

      // 2. Kiểm tra ngưỡng
      return scoreReal > _threshold;
    } catch (e) {
      // AppLog.error("❌ Lỗi AntiSpoof Model: $e");
      return false;
    }
  }

  void dispose() {
    // C++ chạy dạng Singleton Memory, _interpreter không còn tồn tại trên Dart.
    // Việc dọn dẹp bộ nhớ Model đã được gom chung vào hàm dispose()
    // của NativeAiService (giải phóng _spoofBuffer).
    // Hàm này ở đây ta để trống hoặc ghi log thôi.
    // AppLog.info("🧹 Đóng FaceAntiSpoofingService");
  }
}
