// import 'dart:io';
import 'dart:math';

import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart';
// import 'package:image/image.dart' as img;
// import 'package:path_provider/path_provider.dart' as path_provider;

import '../services/log_service.dart';

class FaceAntiSpoofingService {
  // --- SINGLETON PATTERN ---
  static final FaceAntiSpoofingService _instance =
      FaceAntiSpoofingService._internal();
  factory FaceAntiSpoofingService() => _instance;
  FaceAntiSpoofingService._internal();

  // --- CẤU HÌNH --- Model MiniFASNetV2: Input 80x80
  static const String _modelPath = 'assets/models/fasnet_float32.tflite';

  // Ngưỡng tin cậy
  static const double _threshold = 0.6;

  // --- STATE ---
  Interpreter? _interpreter;

  int _inputWidth = 0;
  int _inputHeight = 0;

  int get inputWidth => _inputWidth;
  int get inputHeight => _inputHeight;

  bool get isReady => _interpreter != null;

  Future<void> initialize() async {
    try {
      AppLog.info("🛡️ Khởi tạo FaceAntiSpoofingService...");

      AppLog.info("👉 Bước 1: Cấu hình InterpreterOptions (Dùng CPU)...");
      final options = InterpreterOptions();
      options.threads = 4;

      AppLog.info("👉 Bước 2: Đọc file model từ Asset: $_modelPath ...");
      _interpreter = await Interpreter.fromAsset(_modelPath, options: options);

      AppLog.info("👉 Bước 3: Load file thành công! Đang lấy Input Tensor...");
      var inputTensor = _interpreter!.getInputTensor(0);
      var inputShape = inputTensor.shape;
      AppLog.info("   -> Input Shape: $inputShape");

      // AppLog.info("👉 Bước 4: Đang lấy Output Tensor...");
      // var outputTensor = _interpreter!.getOutputTensor(0);
      // var outputShape = outputTensor.shape;
      // AppLog.info("   -> Output Shape: $outputShape");

      _inputHeight = inputShape[1];
      _inputWidth = inputShape[2];

      // AppLog.info("👉 Bước 5: Cấu hình tham số phụ...");
      // final outputs = _interpreter!.getOutputTensors();
      // AppLog.info("Output tensor count: ${outputs.length}");

      // for (int i = 0; i < outputs.length; i++) {
      //   AppLog.info("Output $i shape: ${outputs[i].shape}");
      // }

      AppLog.info("🚀 HOÀN THÀNH KHỞI TẠO ANTI-SPOOFING MODEL!");
    } catch (e, stackTrace) {
      AppLog.error("❌ LỖI TẠI KHÂU KHỞI TẠO ANTI-SPOOFING MODEL!");
      AppLog.error("Chi tiết lỗi: $e");
      AppLog.error("Dấu vết (StackTrace):\n$stackTrace");
    }
  }

  Future<bool> predict(List<double> inputPixels) async {
    if (_interpreter == null) return false;

    try {
      // 1. Reshape Input: Dùng 80x80 theo model Python
      final input = Float32List.fromList(inputPixels).reshape([1, 80, 80, 3]);

      // 2. Định nghĩa Output: Chỉ cần 1 tensor cho Logits [1, 3]
      var outputLogits = List.filled(1 * 3, 0.0).reshape([1, 3]);

      // 3. Inference
      _interpreter!.run(input, outputLogits);

      // 4. Trích xuất Output (Dạng List<List<double>>)
      final List<double> rawOutput = (outputLogits[0] as List).cast<double>();

      // 5. Tính Softmax thủ công (Để đưa về xác suất 0-1)
      final double maxVal = rawOutput.reduce(max);
      final List<double> expValues = rawOutput
          .map((val) => exp(val - maxVal))
          .toList();
      final double sumExp = expValues.reduce((a, b) => a + b);

      final List<double> probabilities = expValues
          .map((val) => val / sumExp)
          .toList();

      // 6. Class 1 là Real
      final double scoreReal = probabilities[1];

      AppLog.info("🛡️ Real Score: ${(scoreReal * 100).toStringAsFixed(2)}%");

      // 7. Ngưỡng (Threshold)
      return scoreReal > _threshold;
    } catch (e) {
      AppLog.error("❌ Lỗi AntiSpoof Model: $e");
      return false;
    }
  }

  void dispose() {
    _interpreter?.close();
  }
}
