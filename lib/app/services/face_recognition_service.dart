import 'dart:math';
import 'dart:convert';

import 'package:uuid/uuid.dart';
import 'package:get/get.dart';
import 'package:hive_flutter/hive_flutter.dart';
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
  String get modelName => _modelPath.split('/').last.replaceAll('.tflite', '');

  static const String _dbPath = 'assets/db_mobilefacenet_tflite.json';
  static const double _threshold = 0.60;

  // --- STATE ---;
  late Box _hiveBox;

  final int _outputSize = 192;

  int _inputWidth = 112;
  int _inputHeight = 112;

  int get inputWidth => _inputWidth;
  int get inputHeight => _inputHeight;

  bool get isDatabaseEmpty => _hiveBox.isEmpty;
  double get threshold => _threshold;

  int get recogPixelSize => _inputWidth * _inputHeight * 3;

  /// Khởi tạo Service
  Future<void> initialize() async {
    try {
      AppLog.info("🚀 Bắt đầu khởi tạo FaceRecognitionService...");

      final encodedDims = await NativeAiService().initFaceModel(_modelPath);

      if (encodedDims <= 0) {
        AppLog.error("❌ FATAL: Không thể nạp Face Model vào C++!");
        return;
      }

      _inputWidth = encodedDims >> 16;
      _inputHeight = encodedDims & 0xFFFF;

      AppLog.info(
        "🛡️ Face Model Auto Configured: ${_inputWidth}x$_inputHeight (RAM: $recogPixelSize bytes)",
      );

      _hiveBox = Hive.box('face_db');

      await syncDatabase();

      AppLog.info(
        "✅ FaceRecognitionService sẵn sàng! (Model: $_outputSize dim)",
      );
    } catch (e) {
      AppLog.error("❌ Lỗi Fatal Initialize: $e");
    }
  }

  /// Đồng bộ dữ liệu: Hive (Disk) + JSON (Assets) -> RAM
  Future<void> syncDatabase() async {
    NativeAiService().clearNativeDatabase(); // Xóa sạch dữ liệu cũ trong C++

    // TRƯỜNG HỢP 1: Đã có dữ liệu trong Hive (Từ lần chạy thứ 2 trở đi)
    if (_hiveBox.isNotEmpty) {
      AppLog.info("📂 Đang sử dụng dữ liệu từ Hive (Disk)...");

      int conflictCount = 0;
      int successCount = 0;
      for (var key in _hiveBox.keys) {
        // Ép kiểu dynamic về List<double> an toàn
        final rawData = _hiveBox.get(key);
        if (rawData is Map) {
          final mapData = Map<String, dynamic>.from(rawData);
          final String templateId =
              mapData['template_id']?.toString() ?? "unknown_id";
          final List<dynamic> rawVector = mapData['vector'] ?? [];

          List<double> vector = List<double>.from(rawVector);

          if (vector.length == _outputSize) {
            NativeAiService().addFaceToNative(
              key.toString(),
              vector,
              templateId,
            );
            successCount++;
          } else {
            conflictCount++;
          }
        }
      }
      AppLog.info("📂 Đã load $successCount khuôn mặt từ Hive.");
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
      int count = 0;

      jsonData.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          final String templateId =
              value['template_id']?.toString() ?? "json_id_$key";

          // Chỉ update nếu Hive chưa có hoặc muốn ghi đè (ở đây mình chọn ghi đè để JSON là nhất)
          final embedding = List<double>.from(value['vector'] ?? []);

          if (embedding.length == _outputSize) {
            _hiveBox.put(key, value);
            NativeAiService().addFaceToNative(key, embedding, templateId);
            count++;
          }
        }
      });

      AppLog.info("🔄 Đã nạp $count khuôn mặt.");
    } catch (e) {
      AppLog.error("⚠️ Lỗi load JSON: $e");
    }
  }

  Future<RecognitionResult> predict(List<double> inputTensor) async {
    // 1. Guard Clause (Bảo vệ)
    if (isDatabaseEmpty) {
      return RecognitionResult("Error", 0.0, true, "", "Unknown", 0.0);
    }

    try {
      // 2. Khoán trắng mọi việc cho C++ xử lý và nhận kết quả cuối cùng
      // AppLog.info("🔍 Đang dự đoán khuôn mặt với C++...");
      return NativeAiService().predictFace(inputTensor, threshold);
    } catch (e) {
      AppLog.error("❌ Lỗi khi predict: $e");
      return RecognitionResult("Error", 0.0, true, "", "Unknown", 0.0);
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

      final String newTemplateId = const Uuid().v4();

      // 3. ĐẨY XUỐNG RAM CỦA C++ (Cực kỳ quan trọng để Predict nhận ra người này)
      NativeAiService().addFaceToNative(name, embedding, newTemplateId);

      // 4. Lưu vào ổ cứng (Hive)
      await _hiveBox.put(name, {
        'template_id': newTemplateId,
        'vector': embedding,
      });

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
    if (inputTensor.isEmpty) return false;

    try {
      // 1. Lấy Embedding MỚI từ ảnh input qua C++
      List<double>? newEmbedding = NativeAiService().getEmbeddingFromC(
        inputTensor,
      );

      if (newEmbedding == null || newEmbedding.length != _outputSize) {
        AppLog.warning(
          "⚠️ Lỗi update: AI trả về vector rỗng hoặc sai kích thước.",
        );
        return false;
      }

      // 2. Lấy Embedding CŨ từ Database (RAM Dart)
      List<double>? oldEmbedding;
      String currentTemplateId = const Uuid().v4();

      final rawData = _hiveBox.get(name);

      if (rawData is Map) {
        currentTemplateId =
            rawData['template_id']?.toString() ?? currentTemplateId;
        if (rawData['vector'] != null) {
          oldEmbedding = (rawData['vector'] as List)
              .map((e) => double.parse(e.toString()))
              .toList();
        }
      } else if (rawData is List) {
        // Đề phòng còn dính data cũ
        oldEmbedding = List<double>.from(rawData);
      }

      if (oldEmbedding == null || oldEmbedding.length != newEmbedding.length) {
        return register(name, inputTensor);
      }

      // 3. THUẬT TOÁN MERGE (Trung bình cộng) trên Dart
      List<double> mergedEmbedding = List.generate(oldEmbedding.length, (
        index,
      ) {
        return oldEmbedding![index] + newEmbedding[index];
      });

      // 4. Chuẩn hóa lại L2 (Dùng hàm Dart ở bên dưới)
      mergedEmbedding = _l2Normalize(mergedEmbedding);

      // 5. LƯU LẠI Ở CẢ 3 NƠI
      NativeAiService().addFaceToNative(
        name,
        mergedEmbedding,
        currentTemplateId,
      ); // Update C++

      await _hiveBox.put(name, {
        'template_id': currentTemplateId,
        'vector': mergedEmbedding,
      });

      AppLog.info("♻️ Đã cập nhật vector cho: $name");
      return true;
    } catch (e) {
      AppLog.error("❌ Lỗi update: $e");
      return false;
    }
  }
}
