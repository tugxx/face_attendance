import 'dart:io';
import 'dart:math';

import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart';

class FaceAntiSpoofingService {
  // --- SINGLETON PATTERN ---
  static final FaceAntiSpoofingService _instance =
      FaceAntiSpoofingService._internal();
  factory FaceAntiSpoofingService() => _instance;
  FaceAntiSpoofingService._internal();

  // --- CẤU HÌNH ---
  // Nhớ copy file tflite vào assets và khai báo trong pubspec.yaml
  static const String _modelPath = 'assets/models/fasnet_float32.tflite';

  // Ngưỡng tin cậy (0.90 như bên Python)
  static const double _threshold = 0.90;

  // --- STATE ---
  Interpreter? _interpreter;

  // Model MiniFASNetV2: Input 80x80
  int _inputWidth = 80;
  int _inputHeight = 80;
  int _channels = 3;

  // // Output: [1, 3] -> (Fake_1, Real, Fake_2)
  // final int _outputSize = 3;

  bool get isReady => _interpreter != null;

  /// Khởi tạo Service
  Future<void> initialize() async {
    try {
      debugPrint("🛡️ Khởi tạo FaceAntiSpoofingService...");

      final options = InterpreterOptions();

      // 🚀 BẬT GPU (Quan trọng cho tốc độ)
      if (Platform.isAndroid) {
        options.addDelegate(GpuDelegateV2());
      } else if (Platform.isIOS) {
        options.addDelegate(GpuDelegate());
      }

      _interpreter = await Interpreter.fromAsset(_modelPath, options: options);

      // Validate Input Shape
      var inputTensor = _interpreter!.getInputTensor(0);
      var shape =
          inputTensor.shape; // Thường là [1, 80, 80, 3] hoặc [1, 3, 80, 80]

      _inputHeight = shape[1]; // 80
      _inputWidth = shape[2]; // 80
      _channels = shape[3]; // 3

      // Resize input cho chắc ăn (Batch size = 1)
      _interpreter!.resizeInputTensor(0, [
        1,
        _inputHeight,
        _inputWidth,
        _channels,
      ]);
      _interpreter!.allocateTensors();

      debugPrint(
        "✅ AntiSpoof Service sẵn sàng! (Input: ${_inputWidth}x$_inputHeight)",
      );
    } catch (e) {
      debugPrint("❌ Lỗi load AntiSpoof Model: $e");
    }
  }

  /// Hàm dự đoán: Input là List double đã được C++ crop (80x80)
  /// Output: True (Real), False (Fake)
  bool predict(List<double> inputPixels) {
    if (_interpreter == null) return false;

    try {
      // 1. Chuẩn bị Input
      // Input từ C++ là mảng phẳng, cần reshape về [1, 80, 80, 3]
      var inputBuffer = inputPixels.reshape([
        1,
        _inputHeight,
        _inputWidth,
        _channels,
      ]);

      // 2. Chuẩn bị Output
      // Output shape [1, 3]
      var outputBuffer = List.filled(1 * 3, 0.0).reshape([1, 3]);

      // 3. Chạy Model
      _interpreter!.run(inputBuffer, outputBuffer);

      // 4. Xử lý kết quả (Softmax)
      // Output mẫu: [[0.1, 0.85, 0.05]] -> Index 1 là Real
      List<double> probs = List<double>.from(outputBuffer[0]);

      // Tính Softmax
      double realScore = _calculateSoftmaxScore(probs);

      // debugPrint("🛡️ Real Score: ${realScore.toStringAsFixed(3)}");

      // 5. So sánh ngưỡng
      return realScore > _threshold;
    } catch (e) {
      debugPrint("❌ Lỗi AntiSpoof Predict: $e");
      return false; // Mặc định là Fake nếu lỗi để an toàn
    }
  }

  /// Tính xác suất Real (Class index 1) dùng hàm Softmax
  double _calculateSoftmaxScore(List<double> logits) {
    // Model trả về 3 giá trị: [Fake_A, Real, Fake_B]
    // Ta cần tính xác suất của Index 1 (Real)

    double maxLogit = logits.reduce(max); // Để ổn định số học
    double sumExp = 0.0;

    for (var logit in logits) {
      sumExp += exp(logit - maxLogit);
    }

    double expReal = exp(logits[1] - maxLogit);

    return expReal / sumExp;
  }

  void dispose() {
    _interpreter?.close();
  }
}
