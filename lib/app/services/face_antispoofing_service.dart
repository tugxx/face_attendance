import 'dart:io';
import 'dart:math';

import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart' as path_provider;

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
  static const double _threshold = 0.75;

  // --- STATE ---
  Interpreter? _interpreter;

  // Model MiniFASNetV2: Input 80x80
  int _inputWidth = 0;
  int _inputHeight = 0;
  bool _isDeepPix = false;

  int get inputWidth => _inputWidth;

  bool get isReady => _interpreter != null;

  // /// Khởi tạo Service
  // Future<void> initialize() async {
  //   try {
  //     debugPrint("🛡️ Khởi tạo FaceAntiSpoofingService...");

  //     final options = InterpreterOptions();
  //     options.threads = 4;

  //     // // 🚀 BẬT GPU (Quan trọng cho tốc độ)
  //     // if (Platform.isAndroid) {
  //     //   options.addDelegate(GpuDelegateV2());
  //     // } else if (Platform.isIOS) {
  //     //   options.addDelegate(GpuDelegate());
  //     // }

  //     _interpreter = await Interpreter.fromAsset(_modelPath, options: options);

  //     // Validate Input Shape
  //     var inputShape = _interpreter!.getInputTensor(0).shape;
  //     var outputShape = _interpreter!.getOutputTensor(0).shape;

  //     _inputHeight = inputShape[1];
  //     _inputWidth = inputShape[2];

  //     _isDeepPix =
  //         (outputShape.contains(14) ||
  //         _interpreter!.getOutputTensors().length > 1);

  //     // _interpreter!.allocateTensors();

  //     debugPrint(
  //       "🚀 Model Loaded Successfully!\n"
  //       "   - Path: $_modelPath\n"
  //       "   - Input: ${_inputWidth}x$_inputHeight\n"
  //       "   - Output Shape: $outputShape\n" // Xem log cái này in ra gì
  //       "   - isDeepPix: $_isDeepPix",
  //     );
  //   } catch (e) {
  //     debugPrint("❌ Lỗi load AntiSpoof Model: $e");
  //   }
  // }

  Future<void> initialize() async {
    try {
      debugPrint("🛡️ Khởi tạo FaceAntiSpoofingService...");

      debugPrint("👉 Bước 1: Cấu hình InterpreterOptions (Dùng CPU)...");
      final options = InterpreterOptions();
      options.threads = 4;

      debugPrint("👉 Bước 2: Đọc file model từ Asset: $_modelPath ...");
      _interpreter = await Interpreter.fromAsset(_modelPath, options: options);

      debugPrint("👉 Bước 3: Load file thành công! Đang lấy Input Tensor...");
      var inputTensor = _interpreter!.getInputTensor(0);
      var inputShape = inputTensor.shape;
      debugPrint("   -> Input Shape: $inputShape");

      debugPrint("👉 Bước 4: Đang lấy Output Tensor...");
      var outputTensor = _interpreter!.getOutputTensor(0);
      var outputShape = outputTensor.shape;
      debugPrint("   -> Output Shape: $outputShape");

      _inputHeight = inputShape[1];
      _inputWidth = inputShape[2];

      debugPrint("👉 Bước 5: Cấu hình tham số phụ...");
      _isDeepPix =
          (outputShape.contains(14) ||
          _interpreter!.getOutputTensors().length > 1);

      final outputs = _interpreter!.getOutputTensors();

      debugPrint("Output tensor count: ${outputs.length}");

      for (int i = 0; i < outputs.length; i++) {
        debugPrint("Output $i shape: ${outputs[i].shape}");
      }

      debugPrint("🚀 HOÀN THÀNH KHỞI TẠO ANTI-SPOOFING MODEL!");
    } catch (e, stackTrace) {
      debugPrint("❌ LỖI TẠI KHÂU KHỞI TẠO ANTI-SPOOFING MODEL!");
      debugPrint("Chi tiết lỗi: $e");
      debugPrint("Dấu vết (StackTrace):\n$stackTrace");
    }
  }

  void _debugSaveImage(List<double> pixels) async {
    try {
      // // Tạo ảnh 224x224
      final image = img.Image(width: _inputWidth, height: _inputHeight);
      final int area = _inputWidth * _inputHeight;

      const mean = [0.485, 0.456, 0.406];
      const std = [0.229, 0.224, 0.225];

      // Loop gán pixel (Giả sử pixels đang là Raw 0-255 chưa chuẩn hóa)
      // Nếu đã chuẩn hóa -1..1 thì phải convert ngược lại: (val + 1) * 127.5
      for (int y = 0; y < _inputHeight; y++) {
        for (int x = 0; x < _inputWidth; x++) {
          // Tính toán lại index dựa trên cấu trúc NCHW
          int rIndex = y * _inputWidth + x;
          int gIndex = area + rIndex;
          int bIndex = 2 * area + rIndex;

          // Giải mã ngược logic Normalize
          int r = ((pixels[rIndex] * std[0] + mean[0]) * 255).toInt().clamp(
            0,
            255,
          );
          int g = ((pixels[gIndex] * std[1] + mean[1]) * 255).toInt().clamp(
            0,
            255,
          );
          int b = ((pixels[bIndex] * std[2] + mean[2]) * 255).toInt().clamp(
            0,
            255,
          );

          // int index = (y * 224 + x) * 3;

          // // Nghịch đảo Normalize ImageNet
          // int r = ((pixels[index] * 0.229 + 0.485) * 255).toInt().clamp(0, 255);
          // int g = ((pixels[index + 1] * 0.224 + 0.456) * 255).toInt().clamp(
          //   0,
          //   255,
          // );
          // int b = ((pixels[index + 2] * 0.225 + 0.406) * 255).toInt().clamp(
          //   0,
          //   255,
          // );

          image.setPixelRgb(x, y, r, g, b);
        }
      }

      // Lưu ra thư mục tạm
      final Directory? dir = await path_provider.getExternalStorageDirectory();
      final path = '${dir!.path}/debug_spoof.png';
      File(path).writeAsBytesSync(img.encodePng(image));

      debugPrint("📸 ĐÃ LƯU ẢNH DEBUG TẠI: $path");
      // Bạn có thể mở Device File Explorer trong Android Studio để tải ảnh này về xem
    } catch (e) {
      debugPrint("Lỗi save ảnh debug: $e");
    }
  }

  // /// Hàm dự đoán: Input là List double đã được C++ crop
  // /// Output: True (Real), False (Fake)
  // Future<bool> predict(List<double> inputPixels) async {
  //   if (_interpreter == null) return false;

  //   // _debugSaveImage(inputPixels);

  //   // for (var i = 0; i < _interpreter!.getOutputTensors().length; i++) {
  //   //   var tensor = _interpreter!.getOutputTensors()[i];
  //   //   debugPrint("Output Index $i: Name: ${tensor.name}, Shape: ${tensor.shape}");
  //   // }

  //   try {
  //     final outputTensors = _interpreter!.getOutputTensors();
  //     final inputBuffer = Float32List.fromList(
  //       inputPixels,
  //     ).reshape([1, _inputHeight, _inputWidth, 3]);

  //     debugPrint("heloooooooooooooooo");

  //     // 1. Khởi tạo các buffer chứa kết quả dựa trên kiến trúc Model
  //     // Dùng Map để lưu kết quả theo đúng index của Interpreter
  //     Map<int, Object> outputs = {};
  //     int scoreIndex = -1;

  //     debugPrint("Checkkkkkkkkkkkkkkkkkkkkkkkkkkkkk");

  //     // for (int i = 0; i < outputTensors.length; i++) {
  //     //   var shape = outputTensors[i].shape;

  //     //   if (shape.length == 2 && shape[0] == 1 && shape[1] == 1) {
  //     //     // Đây là Score dạng [1, 1]
  //     //     outputs[i] = List.filled(1, 0.0).reshape([1, 1]);
  //     //     scoreIndex = i;
  //     //   } else if (shape.length == 1 && shape[0] == 1) {
  //     //     // Đây là Score dạng [1]
  //     //     outputs[i] = List.filled(1, 0.0).reshape([1]);
  //     //     scoreIndex = i;
  //     //   } else if (shape.contains(14)) {
  //     //     // Đây là Map 14x14
  //     //     outputs[i] = List.filled(14 * 14, 0.0).reshape([1, 14, 14, 1]);
  //     //   } else if (shape.contains(3)) {
  //     //     // Trường hợp MiniFASNet [1, 3]
  //     //     outputs[i] = List.filled(3, 0.0).reshape([1, 3]);
  //     //     scoreIndex = i;
  //     //   }
  //     // }

  //     // // 2. Chạy Inference
  //     // _interpreter!.runForMultipleInputs([inputBuffer], outputs);

  //     // // 3. Xử lý kết quả trả về
  //     // if (scoreIndex == -1) return false;

  //     // double score = 0.0;
  //     // var rawScore = outputs[scoreIndex];

  //     // // Trích xuất score dựa trên shape thực tế của buffer
  //     // if (rawScore is List<List<double>>) {
  //     //   // Dạng [1, 1] hoặc [1, 3]
  //     //   if (rawScore[0].length == 3) {
  //     //     score = _calculateSoftmaxScore(rawScore[0]); // MiniFAS
  //     //   } else {
  //     //     score = rawScore[0][0]; // DeepPix [1, 1]
  //     //   }
  //     // } else if (rawScore is List<double>) {
  //     //   score = rawScore[0]; // Dạng [1]
  //     // }

  //     // debugPrint("🛡️ DeepPix Score: ${score.toStringAsFixed(4)}");
  //     // return score > _threshold; // Ngưỡng đồng bộ với bản Python bạn vừa sửa
  //     return true;
  //   } catch (e) {
  //     debugPrint("❌ AntiSpoof Error: $e");
  //     return false;
  //   }
  // }

  // Future<bool> predict(List<double> inputPixels) async {
  //   if (_interpreter == null) return false;
  //   debugPrint("🛡️ Bắt đầu dự đoán với FaceAntiSpoofing Custom Model...");

  //   try {
  //     // ==========================================================
  //     // BƯỚC 0: DEBUG TENSOR SHAPE (CỰC KỲ QUAN TRỌNG CHO LẦN ĐẦU)
  //     // Bỏ comment 3 dòng này ra trong lần chạy đầu tiên để xem
  //     // onnx2tf nó định dạng shape của bác như thế nào nhé!
  //     // ==========================================================
  //     debugPrint("Input Shape: ${_interpreter!.getInputTensor(0).shape}");
  //     debugPrint("Output 0 Shape: ${_interpreter!.getOutputTensor(0).shape}");
  //     debugPrint("Output 1 Shape: ${_interpreter!.getOutputTensor(1).shape}");

  //     // 1. Đổi kích thước Input (Giả định onnx2tf đã tự động convert về NHWC chuẩn TFLite)
  //     // LƯU Ý: Mảng inputPixels của bác PHẢI được chuẩn hóa (x - mean) / std
  //     // giống y hệt file Python trước khi truyền vào đây nhé!
  //     final input = Float32List.fromList(inputPixels).reshape([1, 128, 128, 3]);
  //     // (Nếu log báo input shape là [1, 3, 128, 128] thì bác sửa lại mảng [1, 3, 128, 128])

  //     // 2. Khởi tạo mảng Output (Hứng đủ cả 2 nhánh của model)
  //     // Nhánh 1: Logits [1, 2]
  //     var outputLogits = List.filled(1 * 2, 0.0).reshape([1, 2]);

  //     // Nhánh 2: Depth Map [1, 2, 32, 32] (hoặc [1, 32, 32, 2] tùy TFLite)
  //     // Ở đây ta tạo buffer phẳng rồi reshape cho an toàn
  //     var outputDepth = List.filled(
  //       1 * 32 * 32 * 2,
  //       0.0,
  //     ).reshape([1, 32, 32, 2]);

  //     // Ghép vào Map. Giả định Index 0 là class_logits, Index 1 là depth_map
  //     // NẾU BỊ CRASH DO LỖI "Shape Mismatch", BÁC ĐẢO NGƯỢC LẠI LÀ XONG:
  //     // {0: outputDepth, 1: outputLogits}
  //     final Map<int, Object> outputs = {1: outputLogits, 0: outputDepth};

  //     // 3. Chạy Inference
  //     _interpreter!.runForMultipleInputs([input], outputs);

  //     // 4. Trích xuất Raw Logits
  //     // Dựa theo file train Python: Index 0 là Fake, Index 1 là Live(Real)
  //     final List<dynamic> rawOutput = outputLogits[0];
  //     final double logitFake = rawOutput[0]; // Vị trí 0: Đồ giả
  //     final double logitReal = rawOutput[1]; // Vị trí 1: Đồ thật

  //     // 5. Tính Softmax thủ công
  //     final double maxLogit = max(logitReal, logitFake);
  //     final double expFake = exp(logitFake - maxLogit);
  //     final double expReal = exp(logitReal - maxLogit);
  //     final double sumExp = expFake + expReal;

  //     // Xác suất % cuối cùng
  //     final double realScore = expReal / sumExp;
  //     final double fakeScore = expFake / sumExp;

  //     debugPrint(
  //       "🛡️ Custom TFLite - Thật: ${(realScore * 100).toStringAsFixed(2)}% | Giả: ${(fakeScore * 100).toStringAsFixed(2)}%",
  //     );

  //     // 6. Trả về kết quả với ngưỡng 0.5
  //     return realScore > 0.5;
  //   } catch (e) {
  //     debugPrint("❌ Lỗi AntiSpoof Model: $e");
  //     return false;
  //   }
  // }

  Future<bool> predict(List<double> inputPixels) async {
    if (_interpreter == null) return false;

    try {
      // 1. Reshape Input: Dùng 80x80 theo model Python
      // Lưu ý: Nếu inputPixels là danh sách phẳng, đảm bảo nó là [80*80*3]
      final input = Float32List.fromList(inputPixels).reshape([1, 80, 80, 3]);

      // 2. Định nghĩa Output: Chỉ cần 1 tensor cho Logits [1, 3]
      // Vì model Python của bạn có num_classes=3
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

      // 6. Logic giống Python: Class 1 là Real
      final double scoreReal = probabilities[1];

      debugPrint("🛡️ Real Score: ${(scoreReal * 100).toStringAsFixed(2)}%");

      // 7. Ngưỡng (Threshold)
      return scoreReal > 0.90;
    } catch (e) {
      debugPrint("❌ Lỗi AntiSpoof Model: $e");
      return false;
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
