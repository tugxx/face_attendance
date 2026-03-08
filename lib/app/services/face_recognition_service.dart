import 'dart:math';
import 'dart:convert';
// import 'dart:io';

import 'package:get/get.dart';
// import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
// import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart';

import '../services/log_service.dart';
import '../services/native_ai_service.dart';

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

  // --- STATE ---;
  late Box _hiveBox;
  final Map<String, List<double>> _faceDatabase = {};

  final int _outputSize = 192;

  bool get isDatabaseEmpty => _faceDatabase.isEmpty;
  double get threshold => _threshold;

  /// Khởi tạo Service
  Future<void> initialize() async {
    try {
      AppLog.info("🚀 Bắt đầu khởi tạo FaceRecognitionService...");

      // 1. NẠP MODEL CHO C++ (ĐÂY LÀ DÒNG BẠN THIẾU)
      final isModelLoaded = await NativeAiService().initFaceModel(_modelPath);
      if (!isModelLoaded) {
        // AppLog.error("❌ FATAL: Không thể nạp Face Model vào C++!");
        return; // Dừng luôn nếu không nạp được
      }

      // Khởi tạo Database (Hive)
      await Hive.initFlutter();
      _hiveBox = await Hive.openBox('face_db');

      // 3. Sync Database (Truyền size vào để kiểm tra tính hợp lệ)
      await _syncDatabase();

      AppLog.info(
        "✅ FaceRecognitionService sẵn sàng! (Model: $_outputSize dim)",
      );
    } catch (e) {
      AppLog.error("❌ Lỗi Fatal Initialize: $e");
    }
  }

  /// Đồng bộ dữ liệu: Hive (Disk) + JSON (Assets) -> RAM
  Future<void> _syncDatabase() async {
    _faceDatabase.clear();
    NativeAiService().clearNativeDatabase(); // Xóa sạch dữ liệu cũ trong C++

    // TRƯỜNG HỢP 1: Đã có dữ liệu trong Hive (Từ lần chạy thứ 2 trở đi)
    if (_hiveBox.isNotEmpty) {
      AppLog.info("📂 Đang sử dụng dữ liệu từ Hive (Disk)...");
      int conflictCount = 0;

      for (var key in _hiveBox.keys) {
        // Ép kiểu dynamic về List<double> an toàn
        final rawList = _hiveBox.get(key);
        if (rawList is List) {
          List<double> vector = List<double>.from(rawList);

          if (vector.length == _outputSize) {
            _faceDatabase[key.toString()] = vector;

            NativeAiService().addFaceToNative(key.toString(), vector);
          } else {
            conflictCount++;
          }
        }
      }
      AppLog.info("📂 Đã load ${_faceDatabase.length} khuôn mặt từ Hive.");
      if (conflictCount > 0) {
        AppLog.warning(
          "⚠️ CẢNH BÁO: Bỏ qua $conflictCount khuôn mặt do sai kích thước vector (Cần xóa DB cũ hoặc dùng đúng model).",
        );
      }
      return;
    }

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

        NativeAiService().addFaceToNative(key, embedding);
      });

      AppLog.info("🔄 Đã nạp ${_faceDatabase.length} khuôn mặt.");
    } catch (e) {
      AppLog.error("⚠️ Lỗi load JSON: $e");
    }
  }

  Future<RecognitionResult> predict(List<double> inputTensor) async {
    // 1. Guard Clause (Bảo vệ)
    if (isDatabaseEmpty) {
      return RecognitionResult("SystemNotReady", 0.0, true);
    }

    try {
      // 2. Khoán trắng mọi việc cho C++ xử lý và nhận kết quả cuối cùng
      // AppLog.info("🔍 Đang dự đoán khuôn mặt với C++...");
      return NativeAiService().predictFace(inputTensor, threshold);
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

  Future<bool> register(String name, List<double> inputTensor) async {
    // Xóa đoạn check _interpreter == null vì giờ ta dùng C++

    if (inputTensor.isEmpty) {
      AppLog.warning("⚠️ Lỗi: Dữ liệu đầu vào rỗng, không thể đăng ký.");
      return false;
    }

    try {
      // 1. Gọi thẳng xuống C++ để lấy vector đặc trưng
      List<double>? embedding = NativeAiService().getEmbeddingFromC(
        inputTensor,
      );

      // Vì getEmbeddingFromC trả về List<double>? (nullable), ta check null
      if (embedding == null || embedding.length != _outputSize) {
        // AppLog.warning("⚠️ Lỗi: AI không tạo được vector hợp lệ. Hủy đăng ký.");
        return false;
      }

      // 2. Lưu vào RAM của Dart
      _faceDatabase[name] = embedding;

      // 3. ĐẨY XUỐNG RAM CỦA C++ (Cực kỳ quan trọng để Predict nhận ra người này)
      NativeAiService().addFaceToNative(name, embedding);

      // 4. Lưu vào ổ cứng (Hive)
      await _hiveBox.put(name, embedding);

      // AppLog.info("✅ Đã đăng ký thành công: $name (Vector size: ${embedding.length})");
      return true;
    } catch (e) {
      AppLog.error("❌ Lỗi đăng ký: $e");
      return false;
    }
  }

  Future<bool> update(String name, List<double> inputTensor) async {
    if (inputTensor.isEmpty) return false;

    try {
      // 1. Lấy Embedding MỚI từ ảnh input qua C++
      List<double>? newEmbedding = NativeAiService().getEmbeddingFromC(
        inputTensor,
      );

      if (newEmbedding == null || newEmbedding.length != _outputSize) {
        // AppLog.warning("⚠️ Lỗi update: AI trả về vector rỗng hoặc sai kích thước.");
        return false;
      }

      // 2. Lấy Embedding CŨ từ Database (RAM Dart)
      List<double>? oldEmbedding = _faceDatabase[name];

      if (oldEmbedding == null) {
        // AppLog.info("ℹ️ Chưa có dữ liệu cũ của $name -> Chuyển sang đăng ký mới.");
        return register(name, inputTensor);
      }

      if (oldEmbedding.length != newEmbedding.length) {
        return register(name, inputTensor);
      }

      // 3. THUẬT TOÁN MERGE (Trung bình cộng) trên Dart
      List<double> mergedEmbedding = List.generate(oldEmbedding.length, (
        index,
      ) {
        return oldEmbedding[index] + newEmbedding[index];
      });

      // 4. Chuẩn hóa lại L2 (Dùng hàm Dart ở bên dưới)
      mergedEmbedding = _l2Normalize(mergedEmbedding);

      // 5. LƯU LẠI Ở CẢ 3 NƠI
      _faceDatabase[name] = mergedEmbedding;
      NativeAiService().addFaceToNative(name, mergedEmbedding); // Update C++
      await _hiveBox.put(name, mergedEmbedding); // Update Ổ cứng

      AppLog.info("♻️ Đã cập nhật vector cho: $name");
      return true;
    } catch (e) {
      AppLog.error("❌ Lỗi update: $e");
      return false;
    }
  }
}
