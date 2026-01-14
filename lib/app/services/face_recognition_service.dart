import 'dart:math';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

class RecognitionResult {
  final String name;
  final double distance;
  final bool isUnknown;

  RecognitionResult(this.name, this.distance, this.isUnknown);
}

class FaceRecognitionService {
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
  int _outputSize = 192;

  bool get isDatabaseEmpty => _faceDatabase.isEmpty;
  double get threshold => _threshold;

  /// Khởi tạo Service
  Future<void> initialize() async {
    try {
      debugPrint("🚀 Bắt đầu khởi tạo FaceRecognitionService...");

      // Khởi tạo Database (Hive)
      await Hive.initFlutter();
      _hiveBox = await Hive.openBox('face_db');

      // 2. Load Model trước để lấy tham số Output Size
      await _loadModel();

      // 3. Sync Database (Truyền size vào để kiểm tra tính hợp lệ)
      await _syncDatabase();

      debugPrint(
        "✅ FaceRecognitionService sẵn sàng! (Model: $_outputSize dim)",
      );
    } catch (e) {
      debugPrint("❌ Lỗi Fatal Initialize: $e");
    }
  }

  /// Load TFLite Model & Config Output Size
  Future<void> _loadModel() async {
    try {
      final options = InterpreterOptions();
      _interpreter = await Interpreter.fromAsset(_modelPath, options: options);

      var inputTensor = _interpreter!.getInputTensor(0);
      var inputShape = inputTensor.shape;

      _inputHeight = inputShape[1];
      _inputWidth = inputShape[2];

      _interpreter!.resizeInputTensor(0, [1, _inputHeight, _inputWidth, 3]);
      _interpreter!.allocateTensors();

      // Auto-detect Output Shape (Để tránh hardcode)
      var outputTensor = _interpreter!.getOutputTensor(0);
      var outputShape = outputTensor.shape; // Shape thường là [1, 192]

      _outputSize = outputShape.reduce((a, b) => a * b);

      debugPrint("🧠 Model Loaded: $_modelPath");
      debugPrint("   -> Input: ${_inputWidth}x$_inputHeight");
      debugPrint("   -> Output Vector: $_outputSize");
    } catch (e) {
      debugPrint("❌ Không load được Model tại $_modelPath: $e");
      throw Exception("Model load failed");
    }
  }

  /// Đồng bộ dữ liệu: Hive (Disk) + JSON (Assets) -> RAM
  Future<void> _syncDatabase() async {
    _faceDatabase.clear();

    // // TRƯỜNG HỢP 1: Đã có dữ liệu trong Hive (Từ lần chạy thứ 2 trở đi)
    // if (_hiveBox.isNotEmpty) {
    //   debugPrint("📂 Đang sử dụng dữ liệu từ Hive (Disk)...");
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
    //   debugPrint("📂 Đã load ${_faceDatabase.length} khuôn mặt từ Hive.");
    //   if (conflictCount > 0) {
    //     debugPrint(
    //       "⚠️ CẢNH BÁO: Bỏ qua $conflictCount khuôn mặt do sai kích thước vector (Cần xóa DB cũ hoặc dùng đúng model).",
    //     );
    //   }
    //   return;
    // }

    // TRƯỜNG HỢP 2: Hive chưa có gì (Lần chạy đầu tiên) -> Đọc JSON"
    debugPrint(
      "✨ Lần chạy đầu tiên (Hive rỗng). Bắt đầu khởi tạo dữ liệu từ JSON...",
    );
    try {
      final String jsonString = await rootBundle.loadString(_dbPath);
      if (jsonString.isEmpty) {
        debugPrint("⚠️ File JSON rỗng, không có dữ liệu mẫu.");
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

      debugPrint("🔄 Đã nạp ${_faceDatabase.length} khuôn mặt.");
    } catch (e) {
      debugPrint("⚠️ Lỗi load JSON: $e");
    }
  }

  /// --- CORE FUNCTION: CHUYỂN ẢNH THÀNH VECTOR ---
  /// Input: cv.Mat
  Future<List<double>> _getEmbedding(cv.Mat faceCropMat) async {
    if (_interpreter == null) throw Exception("Interpreter chưa khởi tạo!");

    cv.Mat? rgbMat;
    cv.Mat? floatMat;

    // try {
    //   final dir = await getExternalStorageDirectory();
    //   if (dir != null) {
    //     // Kiểm tra null
    //     // Lưu ảnh RGB ra để kiểm tra
    //     // (Lưu ý: Khi mở ảnh này trên máy tính, màu sẽ bị ÁM XANH DƯƠNG
    //     // vì file ảnh lưu dạng BGR, nhưng ta đang ép nó lưu data RGB.
    //     // Nếu thấy ám xanh -> Code đúng. Nếu thấy màu da bình thường -> Code sai).
    //     cv.imwrite("${dir.path}/debug_color_check.jpg", inputMat);
    //     debugPrint(
    //       "📸 Đã lưu ảnh debug màu tại: ${dir.path}/debug_color_check.jpg",
    //     );
    //   }
    // } catch (e) {
    //   debugPrint("❌ Lỗi khi lưu ảnh debug: $e");
    // }

    try {
      // 1. Chuyển đổi không gian màu (BGR -> RGB)
      // Model MobileFaceNet được train trên ảnh RGB.
      rgbMat = cv.cvtColor(faceCropMat, cv.COLOR_BGR2RGB);

      if (rgbMat.rows != _inputHeight || rgbMat.cols != _inputWidth) {
        var resized = cv.resize(rgbMat, (_inputWidth, _inputHeight));
        rgbMat.dispose(); // Xóa ảnh cũ
        rgbMat = resized; // Gán ảnh mới đã resize
      }

      // 2. Chuẩn hóa (Normalization)
      // Chuyển pixel [0, 255] về khoảng [-1, 1]
      // Công thức: (x - 127.5) / 128
      floatMat = rgbMat.convertTo(
        cv.MatType.CV_32FC3,
        alpha: 1.0 / normStd,
        beta: -normMean / normStd,
      );

      // 3. Chuẩn bị Input Tensor
      // Lấy buffer dữ liệu từ Mat đã chuẩn hóa
      final byteData = floatMat.data;
      final floatList = Float32List.view(
        byteData.buffer,
        byteData.offsetInBytes,
        byteData.lengthInBytes ~/ 4,
      );

      // Reshape khớp input model
      var inputBuffer = floatList.reshape([1, _inputHeight, _inputWidth, 3]);

      // Tạo buffer để hứng kết quả
      var outputTensor = _interpreter!.getOutputTensor(0);
      Object outputBufferRaw;

      // Luôn resize buffer theo đúng shape của tensor
      if (outputTensor.type == TensorType.float32) {
        outputBufferRaw = Float32List(_outputSize).reshape(outputTensor.shape);
      } else {
        outputBufferRaw = List.filled(
          _outputSize,
          0.0,
        ).reshape(outputTensor.shape);
      }

      // Run Inference (Chạy AI)
      _interpreter!.run(inputBuffer, outputBufferRaw);

      // 5. Lấy kết quả thô
      // 6. Parse Output
      List<double> resultVector = [];
      var batchResult = outputBufferRaw as List;
      var firstResult = batchResult[0]; // Batch 0

      if (firstResult is List) {
        // Trường hợp output là mảng [1, 128]
        resultVector = firstResult.map((e) => (e as num).toDouble()).toList();
      } else {
        // Trường hợp Flatten [128]
        resultVector = batchResult.map((e) => (e as num).toDouble()).toList();
      }

      // L2 Normalize
      return _l2Normalize(resultVector);
    } catch (e) {
      debugPrint("❌ Error in _getEmbedding: $e");
      return List.filled(_outputSize, 0.0); // Trả về vector rỗng nếu lỗi
    } finally {
      // QUAN TRỌNG: Giải phóng bộ nhớ OpenCV
      rgbMat?.dispose();
      floatMat?.dispose();
    }
  }

  /// Hàm chính: Nhận ảnh Camera + Tọa độ mặt -> Trả về Tên người (nếu có)
  Future<RecognitionResult> predict(cv.Mat faceCropMat) async {
    // 1. Guard Clause: Kiểm tra hệ thống sẵn sàng chưa
    if (_interpreter == null || _faceDatabase.isEmpty) {
      return RecognitionResult("SystemNotReady", 0.0, true);
    }

    try {
      // 1. Lấy embedding ảnh gốc
      List<double> embeddingNormal = await _getEmbedding(faceCropMat);

      // // 2. Lấy embedding ảnh lật ngang (Mirror)
      // cv.Mat flippedMat = cv.flip(faceCropMat, 1);
      // List<double> embeddingMirrored = await _getEmbedding(flippedMat);
      // flippedMat.dispose();

      // // 3. Cộng gộp và chia đôi (Lấy trung bình)
      // final int vectorDim = embeddingNormal.length;
      // List<double> finalEmbedding = List.generate(vectorDim, (i) {
      //   return (embeddingNormal[i] + embeddingMirrored[i]) / 2;
      // });

      // --- CHUẨN HÓA LẠI (RE-NORMALIZE) ---
      embeddingNormal = _l2Normalize(embeddingNormal);

      // --- TÌM NGƯỜI TRONG DATABASE ---
      return _findClosestMatch(embeddingNormal);
    } catch (e) {
      debugPrint("❌ Lỗi khi predict: $e");
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
      // debugPrint("   Checking $key: $score"); // Uncomment để debug chi tiết
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

  /// Hàm đăng ký nhân viên mới
  /// Input: Tên nhân viên + Ảnh khuôn mặt đã Crop & Align (112x112)
  Future<bool> register(String name, cv.Mat faceCropMat) async {
    if (_interpreter == null) return false;

    try {
      // 1. Lấy vector đặc trưng (Embedding)
      // Lưu ý: Hàm _getEmbedding phải trả về vector đã L2 Normalize
      List<double> embedding = await _getEmbedding(faceCropMat);

      // 2. Lưu vào RAM (để nhận diện được ngay lập tức)
      _faceDatabase[name] = embedding;

      // 3. Lưu vào Ổ cứng (Hive) (để tắt app không mất)
      await _hiveBox.put(name, embedding);

      debugPrint("✅ Đã đăng ký thành công: $name");
      return true;
    } catch (e) {
      debugPrint("❌ Lỗi đăng ký: $e");
      return false;
    }
  }

  /// Cập nhật khuôn mặt đã có (Cộng gộp Vector cũ + mới)
  Future<bool> update(String name, cv.Mat faceCropMat) async {
    if (_interpreter == null) return false;

    try {
      // 1. Lấy Embedding MỚI
      List<double> newEmbedding = await _getEmbedding(faceCropMat);

      // 2. Lấy Embedding CŨ
      List<double>? oldEmbedding = _faceDatabase[name];

      if (oldEmbedding == null) {
        // Nếu không tìm thấy cũ (lỗi lạ), thì coi như đăng ký mới
        return register(name, faceCropMat);
      }

      // 3. THUẬT TOÁN MERGE (Trung bình cộng)
      // Công thức: V_final = Normalize(V_old + V_new)
      List<double> mergedEmbedding = List.generate(192, (index) {
        return oldEmbedding[index] + newEmbedding[index];
      });

      // 4. Chuẩn hóa lại (Bắt buộc để dùng Cosine Similarity)
      mergedEmbedding = _l2Normalize(mergedEmbedding);

      // 5. Lưu lại
      _faceDatabase[name] = mergedEmbedding;
      await _hiveBox.put(name, mergedEmbedding);

      debugPrint("♻️ Đã cập nhật vector cho: $name");
      return true;
    } catch (e) {
      debugPrint("❌ Lỗi update: $e");
      return false;
    }
  }
}
