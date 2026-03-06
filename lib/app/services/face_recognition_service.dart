import 'dart:math';
import 'dart:convert';
// import 'dart:io';

import 'package:get/get.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';

import '../services/log_service.dart';

class RecognitionResult {
  final String name;
  final double distance;
  final bool isUnknown;

  RecognitionResult(this.name, this.distance, this.isUnknown);
}

class FaceRecognitionService extends GetxService {
  // --- SINGLETON PATTERN --- (Chỉ tạo 1 instance duy nhất trong app)
  static final FaceRecognitionService _instance =
      FaceRecognitionService._internal();
  factory FaceRecognitionService() => _instance;
  FaceRecognitionService._internal();

  // --- CẤU HÌNH ---
  static const String _modelPath = 'assets/models/mobilefacenet.tflite';
  static const String _dbPath = 'assets/db_mobilefacenet_tflite.json';
  static const double _threshold = 0.60;

  // Thông số Normalize chuẩn của MobileFaceNet
  static const double normMean = 127.5;
  static const double normStd = 128.0;

  // --- STATE ---
  Interpreter? _interpreter;
  late Box _hiveBox;
  final Map<String, List<double>> _faceDatabase = {};

  int _inputWidth = 112;
  int _inputHeight = 112;
  int _channels = 3;
  int _outputSize = 192;

  bool get isDatabaseEmpty => _faceDatabase.isEmpty;
  double get threshold => _threshold;

  /// Khởi tạo Service
  Future<void> initialize() async {
    try {
      // AppLog.info("🚀 Bắt đầu khởi tạo FaceRecognitionService...");

      // Khởi tạo Database (Hive)
      await Hive.initFlutter();
      _hiveBox = await Hive.openBox('face_db');

      // 2. Load Model trước để lấy tham số Output Size
      await _loadModel();

      // 3. Sync Database (Truyền size vào để kiểm tra tính hợp lệ)
      await _syncDatabase();

      AppLog.info(
        "✅ FaceRecognitionService sẵn sàng! (Model: $_outputSize dim)",
      );
    } catch (e) {
      AppLog.error("❌ Lỗi Fatal Initialize: $e");
    }
  }

  /// Load TFLite Model & Config Output Size
  Future<void> _loadModel() async {
    try {
      final options = InterpreterOptions();

      // // 🚀 QUAN TRỌNG: BẬT GPU
      // if (Platform.isAndroid) {
      //   options.addDelegate(GpuDelegateV2()); // Android dùng GPU/NNAPI
      // } else if (Platform.isIOS) {
      //   options.addDelegate(GpuDelegate()); // iOS dùng Metal
      // }

      _interpreter = await Interpreter.fromAsset(_modelPath, options: options);

      var inputTensor = _interpreter!.getInputTensor(0);
      var inputShape = inputTensor.shape;

      _inputHeight = inputShape[1];
      _inputWidth = inputShape[2];
      _channels = inputShape[3];

      _interpreter!.resizeInputTensor(0, [1, _inputHeight, _inputWidth, 3]);
      _interpreter!.allocateTensors();

      // Auto-detect Output Shape (Để tránh hardcode)
      var outputTensor = _interpreter!.getOutputTensor(0);
      var outputShape = outputTensor.shape; // Shape thường là [1, 192]

      _outputSize = outputShape.reduce((a, b) => a * b);

      // AppLog.info("🧠 Model Loaded: $_modelPath");
      // AppLog.info("   -> Input: ${_inputWidth}x$_inputHeight");
      // AppLog.info("   -> Output Vector: $_outputSize");
    } catch (e) {
      AppLog.error("❌ Không load được Model tại $_modelPath: $e");
      throw Exception("Model load failed");
    }
  }

  /// Đồng bộ dữ liệu: Hive (Disk) + JSON (Assets) -> RAM
  Future<void> _syncDatabase() async {
    _faceDatabase.clear();

    // // TRƯỜNG HỢP 1: Đã có dữ liệu trong Hive (Từ lần chạy thứ 2 trở đi)
    // if (_hiveBox.isNotEmpty) {
    //   AppLog.info("📂 Đang sử dụng dữ liệu từ Hive (Disk)...");
    //   int conflictCount = 0;

    //   for (var key in _hiveBox.keys) {
    //     // Ép kiểu dynamic về List<double> an toàn
    //     final rawList = _hiveBox.get(key);
    //     if (rawList is List) {
    //       List<double> vector = List<double>.from(rawList);

    //       if (vector.length == _outputSize) {
    //         _faceDatabase[key.toString()] = vector;
    //       } else {
    //         conflictCount++;
    //       }
    //     }
    //   }
    //   AppLog.info("📂 Đã load ${_faceDatabase.length} khuôn mặt từ Hive.");
    //   if (conflictCount > 0) {
    //     AppLog.warning(
    //       "⚠️ CẢNH BÁO: Bỏ qua $conflictCount khuôn mặt do sai kích thước vector (Cần xóa DB cũ hoặc dùng đúng model).",
    //     );
    //   }
    //   return;
    // }

    // TRƯỜNG HỢP 2: Hive chưa có gì (Lần chạy đầu tiên) -> Đọc JSON"
    AppLog.info(
      "✨ Lần chạy đầu tiên (Hive rỗng). Bắt đầu khởi tạo dữ liệu từ JSON...",
    );
    try {
      final String jsonString = await rootBundle.loadString(_dbPath);
      if (jsonString.isEmpty) {
        AppLog.warning("⚠️ File JSON rỗng, không có dữ liệu mẫu.");
        return;
      }

      final Map<String, dynamic> jsonData = json.decode(jsonString);

      jsonData.forEach((key, value) {
        // Chỉ update nếu Hive chưa có hoặc muốn ghi đè (ở đây mình chọn ghi đè để JSON là nhất)
        final embedding = List<double>.from(value);

        if (embedding.length == _outputSize) {
          _faceDatabase[key] = embedding;
          _hiveBox.put(key, embedding);
        }
      });

      AppLog.info("🔄 Đã nạp ${_faceDatabase.length} khuôn mặt.");
    } catch (e) {
      AppLog.error("⚠️ Lỗi load JSON: $e");
    }
  }

  Future<List<double>> _getEmbedding(List<double> inputTensor) async {
    if (_interpreter == null) {
      Exception("Interpreter chưa khởi tạo!");
      return [];
    }

    double expectedSize = _inputHeight * _inputWidth * _channels.toDouble();
    if (inputTensor.length != expectedSize) {
      AppLog.warning(
        "🛑 LỖI INPUT MODEL: Kích thước sai lệch! "
        "Nhận được ${inputTensor.length}, nhưng Model cần $expectedSize.\n"
        "-> Có thể lỗi tại bước FaceAligner.",
      );
      // Trả về rỗng để Controller biết và bỏ qua frame này
      return [];
    }

    try {
      // 1. Reshape dữ liệu cho khớp với input của Model
      // MobileFaceNet yêu cầu shape [1, 112, 112, 3]
      // inputTensor từ FaceAligner đưa sang đang là mảng phẳng (flat list)
      var inputBuffer = inputTensor.reshape([
        1,
        _inputHeight,
        _inputWidth,
        _channels,
      ]);

      // 2. Chuẩn bị Output Buffer để hứng kết quả
      var outputTensor = _interpreter!.getOutputTensor(0);
      Object outputBufferRaw;

      // Luôn tạo buffer đúng kiểu dữ liệu của output model
      if (outputTensor.type == TensorType.float32) {
        outputBufferRaw = Float32List(_outputSize).reshape(outputTensor.shape);
      } else {
        outputBufferRaw = List.filled(
          _outputSize,
          0.0,
        ).reshape(outputTensor.shape);
      }

      // 3. Run Inference (Chạy AI)
      _interpreter!.run(inputBuffer, outputBufferRaw);

      // 4. Parse Output (Lấy kết quả ra)
      List<double> resultVector = [];

      // Flatten dữ liệu (Làm phẳng mảng nhiều chiều thành 1 chiều)
      if (outputBufferRaw is List) {
        var batchResult = outputBufferRaw;
        // Lấy batch đầu tiên (Batch 0)
        var firstResult = (batchResult.isNotEmpty && batchResult[0] is List)
            ? batchResult[0]
            : batchResult;

        if (outputTensor.type == TensorType.float32) {
          // Cách tối ưu: Cast trực tiếp nếu là Float32
          // Lưu ý: Tùy version tflite_flutter mà trả về List<double> hay Float32List
          resultVector = List<double>.from(
            firstResult.map((e) => (e as num).toDouble()),
          );
        } else {
          // Nếu là Int8 -> Cần Dequantize (Optional, thường MobileFaceNet là Float output)
          resultVector = firstResult.map((e) => (e as num).toDouble()).toList();
        }
      }

      // 5. L2 Normalize (Bắt buộc để tính độ chính xác cao)
      return _l2Normalize(resultVector);
    } catch (e, stack) {
      AppLog.error("❌ Error in _getEmbedding: $e");

      AppLog.error("Stack trace: $stack");
      // Trả về vector 0 nếu lỗi để không crash app
      return [];
    }
  }

  Future<RecognitionResult> predict(List<double> inputTensor) async {
    // 1. Guard Clause
    if (_interpreter == null || _faceDatabase.isEmpty) {
      return RecognitionResult("SystemNotReady", 0.0, true);
    }

    try {
      // 2. Lấy embedding (Vector đặc trưng) từ Model
      // Hàm _getEmbedding bây giờ nhận List<double> nên truyền thẳng vào
      List<double> embedding = await _getEmbedding(inputTensor);

      // 3. TÌM NGƯỜI TRONG DATABASE
      return _findClosestMatch(embedding);
    } catch (e) {
      AppLog.error("❌ Lỗi khi predict: $e");
      return RecognitionResult("Error", 0.0, true);
    }
  }

  // Hàm L2 Normalize chuyển từ Java sang Dart
  List<double> _l2Normalize(List<double> embedding) {
    double squareSum = 0;
    for (var x in embedding) {
      squareSum += x * x;
    }

    // epsilon = 1e-10 để tránh chia cho 0
    double xInvNorm = sqrt(max(squareSum, 1e-10));

    return embedding.map((x) => x / xInvNorm).toList();
  }

  RecognitionResult _findClosestMatch(List<double> embedding) {
    String name = "Unknown";
    double maxScore = -1.0; // Cosine càng cao càng tốt (-1 đến 1)

    _faceDatabase.forEach((key, dbEmbedding) {
      double score = _cosineSimilarity(embedding, dbEmbedding);
      // AppLog.info("   Checking $key: $score"); // Uncomment để debug chi tiết
      if (score > maxScore) {
        maxScore = score;
        name = key;
      }
    });

    // Logic Threshold
    if (maxScore < threshold) {
      return RecognitionResult("Unknown", maxScore, true);
    } else {
      return RecognitionResult(name, maxScore, false);
    }
  }

  // Cosine Similarity: DotProduct(A, B) / (NormA * NormB)
  // Vì ta đã L2 Normalize (Norm = 1), nên chỉ cần tính DotProduct
  double _cosineSimilarity(List<double> v1, List<double> v2) {
    double dot = 0.0;
    for (int i = 0; i < v1.length; i++) {
      dot += v1[i] * v2[i];
    }
    return dot;
  }

  Future<bool> register(String name, List<double> inputTensor) async {
    if (_interpreter == null) {
      AppLog.warning("⚠️ Lỗi: Model chưa khởi tạo.");
      return false;
    }

    if (inputTensor.isEmpty) {
      AppLog.warning("⚠️ Lỗi: Dữ liệu đầu vào rỗng, không thể đăng ký.");
      return false;
    }

    try {
      // 1. Chạy Model để lấy vector đặc trưng
      List<double> embedding = await _getEmbedding(inputTensor);

      if (embedding.isEmpty || embedding.length != _outputSize) {
        AppLog.warning("⚠️ Lỗi: AI không tạo được vector hợp lệ. Hủy đăng ký.");
        return false;
      }

      // 2. Lưu vào RAM
      _faceDatabase[name] = embedding;

      // 3. Lưu vào Hive (Disk)
      await _hiveBox.put(name, embedding);

      AppLog.info(
        "✅ Đã đăng ký thành công: $name (Vector size: ${embedding.length})",
      );
      return true;
    } catch (e) {
      AppLog.error("❌ Lỗi đăng ký: $e");
      return false;
    }
  }

  Future<bool> update(String name, List<double> inputTensor) async {
    if (_interpreter == null) return false;
    if (inputTensor.isEmpty) return false;

    try {
      // 1. Lấy Embedding MỚI từ ảnh input
      List<double> newEmbedding = await _getEmbedding(inputTensor);

      if (newEmbedding.isEmpty || newEmbedding.length != _outputSize) {
        AppLog.warning(
          "⚠️ Lỗi update: AI trả về vector rỗng hoặc sai kích thước.",
        );
        return false;
      }

      // 2. Lấy Embedding CŨ từ Database
      List<double>? oldEmbedding = _faceDatabase[name];

      if (oldEmbedding == null) {
        AppLog.info(
          "ℹ️ Chưa có dữ liệu cũ của $name -> Chuyển sang đăng ký mới.",
        );
        return register(name, inputTensor);
      }

      if (oldEmbedding.length != newEmbedding.length) {
        // AppLog.warning(
        //   "⚠️ Lỗi phiên bản Model: Data cũ (${oldEmbedding.length}) khác Data mới (${newEmbedding.length}).\n"
        //   "👉 Ghi đè lại bằng dữ liệu mới!",
        // );
        // Trong trường hợp này, ta nên GHI ĐÈ (Overwrite) thay vì cộng gộp lỗi
        return register(name, inputTensor);
      }

      // 3. THUẬT TOÁN MERGE (Trung bình cộng)
      // Công thức: V_avg = (V_old + V_new) / 2 (Sau đó normalize lại)
      // Ở đây ta cộng trực tiếp rồi Normalize cũng tương đương về hướng vector.
      List<double> mergedEmbedding = List.generate(oldEmbedding.length, (
        index,
      ) {
        return oldEmbedding[index] + newEmbedding[index];
      });

      // 4. Chuẩn hóa lại (QUAN TRỌNG: Tổng của 2 vector đơn vị không phải là vector đơn vị)
      mergedEmbedding = _l2Normalize(mergedEmbedding);

      // 5. Lưu lại
      _faceDatabase[name] = mergedEmbedding;
      await _hiveBox.put(name, mergedEmbedding);

      AppLog.info("♻️ Đã cập nhật vector cho: $name");
      return true;
    } catch (e) {
      AppLog.error("❌ Lỗi update: $e");
      return false;
    }
  }
}
