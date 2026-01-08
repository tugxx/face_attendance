// import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/foundation.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
// import 'package:image/image.dart' as img;
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:path_provider/path_provider.dart';

// import '../utils/image_converter.dart';

class RecognitionResult {
  final String name;
  final double distance;
  final bool isUnknown;

  RecognitionResult(this.name, this.distance, this.isUnknown);
}

class FaceRecognitionService {
  // Singleton Pattern (Chỉ tạo 1 instance duy nhất trong app)
  static final FaceRecognitionService _instance =
      FaceRecognitionService._internal();
  factory FaceRecognitionService() => _instance;
  FaceRecognitionService._internal();

  Interpreter? _interpreter;

  // Database giả lập (RAM)
  final Map<String, List<double>> _faceDatabase = {};

  late Box _hiveBox;

  int _outputSize = 192;

  bool get isDatabaseEmpty => _faceDatabase.isEmpty;

  static const double normMean = 127.5;
  static const double normStd = 128.0;

  // Ngưỡng nhận diện (Threshold)
  // MobileFaceNet: < 0.8 là khá chắc chắn, > 1.0 là người lạ
  static const double threshold = 0.50;

  Future<void> initialize() async {
    try {
      // --- PHẦN MỚI: KHỞI TẠO DATABASE ---
      await Hive.initFlutter();
      _hiveBox = await Hive.openBox('face_db'); // Mở cái hộp tên là 'face_db'

      // // --- ĐOẠN CODE QUAN TRỌNG CẦN THÊM ---
      // if (_hiveBox.isEmpty) {
      //   debugPrint(
      //     "📂 Database trống. Đang nạp dữ liệu gốc từ face_db.json...",
      //   );
      //   await _seedDataFromJson(); // Hàm nạp dữ liệu (xem bên dưới)
      // } else {
      //   debugPrint("⚡ Database đã có dữ liệu. Load từ ổ cứng lên RAM...");
      //   _loadDatabaseToMemory();
      // }

      // 1. Luôn luôn nạp dữ liệu từ JSON để update cái mới nhất (nếu có)
      //    Điều này đảm bảo file face_db.json luôn là "Source of Truth"
      debugPrint("🔄 Đang đồng bộ dữ liệu từ JSON...");
      await _seedDataFromJson(); 

      // 2. Sau đó load tất cả từ Hive lên RAM
      _loadDatabaseToMemory();

      // Load model (cần đảm bảo file .tflite nằm trong assets)
      _interpreter = await Interpreter.fromAsset(
        'assets/models/mobilefacenet.tflite',
      );

      // TỰ ĐỘNG LẤY KÍCH THƯỚC OUTPUT CỦA MODEL
      var inputTensor = _interpreter!.getInputTensor(0);
      var outputTensor = _interpreter!.getOutputTensor(0);
      _outputSize = outputTensor.shape[1]; // Lấy số 128 hoặc 192 từ model
      debugPrint("🧠 Model Input Shape: ${inputTensor.shape}");
      debugPrint(
        "🧠 Model Output: $_outputSize - DB Size: ${_faceDatabase.length}",
      );

      // // Warmup: Chạy thử 1 lần với data rỗng để load model vào RAM
      // var input = Float32List(2 * 112 * 112 * 3).reshape([2, 112, 112, 3]);
      // var output = Float32List(2 * _outputSize).reshape([2, _outputSize]);
      // _interpreter?.run(input, output);

      debugPrint("🧠 AI Model loaded successfully");
    } catch (e) {
      debugPrint("❌ Error loading AI Model: $e");
    }
  }

  // --- HÀM MỚI: Đọc JSON và lưu vào Hive ---
  Future<void> _seedDataFromJson() async {
    try {
      final String jsonString = await rootBundle.loadString(
        'assets/face_db.json',
      );
      final Map<String, dynamic> jsonData = json.decode(jsonString);

      int count = 0;
      jsonData.forEach((key, value) {
        // Convert List<dynamic> sang List<double>
        List<double> embedding = List<double>.from(value);

        _faceDatabase[key] = embedding; // Lưu RAM
        _hiveBox.put(key, embedding); // Lưu Ổ cứng
        count++;
      });

      debugPrint("✅ Đã nạp thành công $count nhân viên từ JSON.");
    } catch (e) {
      debugPrint("⚠️ Không tìm thấy face_db.json hoặc lỗi định dạng: $e");
    }
  }

  // --- HÀM MỚI: Load dữ liệu cũ ---
  void _loadDatabaseToMemory() {
    if (_hiveBox.isEmpty) {
      debugPrint("📂 Database trống, chưa có dữ liệu cũ.");
      return;
    }

    for (var key in _hiveBox.keys) {
      // Hive lưu List dưới dạng dynamic, cần ép kiểu về List<double>
      var vector = List<double>.from(_hiveBox.get(key));
      _faceDatabase[key.toString()] = vector;
    }
    debugPrint("📂 Đã load ${_faceDatabase.length} khuôn mặt từ bộ nhớ máy.");
  }

  /// --- 1. HÀM CORE: CHUYỂN ẢNH THÀNH VECTOR (EMBEDDING) ---
  /// Hàm này dùng chung cho cả việc tạo DB và nhận diện Camera
  /// Input: cv.Mat (112x112)
  Future<List<double>> _getEmbedding(cv.Mat faceCropMat) async {
    if (_interpreter == null) return [];

    // A. Xử lý màu sắc (Color Space)
    // OpenCV mặc định là BGR. Model MobileFaceNet thường cần RGB.
    // 👉 THỬ NGHIỆM: Nếu vẫn sai, hãy thử comment dòng này để dùng BGR.
    cv.Mat inputMat = cv.cvtColor(faceCropMat, cv.COLOR_BGR2RGB);

    try {
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        // Kiểm tra null
        // Lưu ảnh RGB ra để kiểm tra
        // (Lưu ý: Khi mở ảnh này trên máy tính, màu sẽ bị ÁM XANH DƯƠNG
        // vì file ảnh lưu dạng BGR, nhưng ta đang ép nó lưu data RGB.
        // Nếu thấy ám xanh -> Code đúng. Nếu thấy màu da bình thường -> Code sai).
        cv.imwrite("${dir.path}/debug_color_check.jpg", inputMat);
        debugPrint(
          "📸 Đã lưu ảnh debug màu tại: ${dir.path}/debug_color_check.jpg",
        );
      }
    } catch (e) {
      debugPrint("❌ Lỗi khi lưu ảnh debug: $e");
    }

    // B. Chuẩn hóa (Normalization) [-1, 1]
    cv.Mat floatMat = inputMat.convertTo(
      cv.MatType.CV_32FC3,
      alpha: 1.0 / normStd, // 1/128
      beta: -normMean / normStd, // -127.5/128
    );

    // C. Input Tensor
    // Copy data an toàn. Dùng buffer view có thể nhanh nhưng dễ lỗi pointer.
    // Với 1 ảnh 112x112, việc copy này mất chưa đến 1ms.
    final floatList = Float32List.fromList(
      Float32List.view(floatMat.data.buffer),
    );

    // Reshape [1, 112, 112, 3]
    var inputBuffer = floatList.reshape([1, 112, 112, 3]);
    var outputBuffer = List.filled(_outputSize, 0.0).reshape([1, _outputSize]);

    // D. Inference
    _interpreter!.run(inputBuffer, outputBuffer);

    // E. L2 Normalize Output (Bắt buộc)
    List<double> rawEmbedding = List<double>.from(outputBuffer[0]);

    // Dọn dẹp
    inputMat.dispose();
    floatMat.dispose();

    return _l2Normalize(rawEmbedding);
  }

  /// Hàm chính: Nhận ảnh Camera + Tọa độ mặt -> Trả về Tên người (nếu có)
  Future<RecognitionResult> predict(cv.Mat faceCropMat) async {
    if (_interpreter == null || _faceDatabase.isEmpty) {
      return RecognitionResult("SystemNotReady", 0.0, true);
    }

    try {
      // // Gọi hàm Core để lấy vector
      // List<double> currentEmbedding = await _getEmbedding(faceCropMat);

      // // 5. So sánh với Database
      // return _findClosestMatch(currentEmbedding);

      // 1. Lấy embedding ảnh gốc
      List<double> emb1 = await _getEmbedding(faceCropMat);

      // 2. Lấy embedding ảnh lật ngang (Mirror)
      cv.Mat flippedMat = cv.flip(faceCropMat, 1);
      List<double> emb2 = await _getEmbedding(flippedMat);
      flippedMat.dispose();

      // 3. Cộng gộp và chia đôi (Lấy trung bình)
      List<double> finalEmb = List.filled(192, 0.0);
      for (int i = 0; i < 192; i++) {
        finalEmb[i] = (emb1[i] + emb2[i]) / 2;
      }
      // Chuẩn hóa lại lần nữa cho chắc
      finalEmb = _l2Normalize(finalEmb);

      return _findClosestMatch(finalEmb);
    } catch (e) {
      debugPrint("❌ Lỗi khi predict: $e");
      return RecognitionResult("Error", 0.0, true);
    }
  }

  // /// Logic chạy TFLite
  // List<double> _generateEmbedding(img.Image image) {
  //   // 1. Tạo Input Buffer cho 2 ảnh: [2, 112, 112, 3]
  //   // Tổng số float = 2 * 112 * 112 * 3
  //   var input = Float32List(2 * 112 * 112 * 3);
  //   var buffer = Float32List.view(input.buffer);
  //   int pixelIndex = 0;

  //   double imageMean = 127.5;
  //   double imageStd = 128.0;

  //   for (var i = 0; i < 112; i++) {
  //     for (var j = 0; j < 112; j++) {
  //       var pixel = image.getPixel(j, i);

  //       double r = pixel.r.toDouble();
  //       double g = pixel.g.toDouble();
  //       double b = pixel.b.toDouble();

  //       // Normalize (pixel - 128) / 128
  //       buffer[pixelIndex++] = (r - imageMean) / imageStd;
  //       buffer[pixelIndex++] = (g - imageMean) / imageStd;
  //       buffer[pixelIndex++] = (b - imageMean) / imageStd;
  //     }
  //   }

  //   // --- ẢNH 2 (Dữ liệu rác/lấp chỗ trống) ---
  //   // Không cần copy dữ liệu thật, để mặc định là 0.0 cũng được
  //   // Vì ta không dùng kết quả của ảnh này.
  //   // (Buffer đã tự khởi tạo bằng 0 rồi nên không cần vòng lặp nữa)

  //   // 2. Định nghĩa Output: [2, 192]
  //   var output = List.filled(2 * _outputSize, 0.0).reshape([2, _outputSize]);

  //   _interpreter!.run(input.reshape([2, 112, 112, 3]), output);

  //   // Lấy vector thô
  //   List<double> rawEmbedding = List<double>.from(output[0]);

  //   // 2. --- QUAN TRỌNG: L2 NORMALIZE (Giống hàm MyUtil.l2Normalize) ---
  //   return _l2Normalize(rawEmbedding);
  // }

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

  // Future<List<double>> generateEmbeddingPublic(img.Image image) async {
  //   // Đảm bảo model đã load
  //   if (_interpreter == null) await initialize();
  //   return _generateEmbedding(image); // Gọi hàm nội bộ cũ
  // }

  // RecognitionResult _findClosestMatch(List<double> embedding) {
  //   String bestName = "Unknown";
  //   double minDistance = 999.0; // Khoảng cách nhỏ nhất tìm thấy

  //   for (var entry in _faceDatabase.entries) {
  //     double dist = _euclideanDistance(embedding, entry.value);
  //     if (dist < minDistance) {
  //       minDistance = dist;
  //       bestName = entry.key;
  //     }
  //   }

  //   debugPrint("🔍 Best: $bestName - Dist: ${minDistance.toStringAsFixed(3)}");

  //   if (minDistance < threshold) {
  //     return RecognitionResult(bestName, minDistance, false);
  //   } else {
  //     return RecognitionResult("Unknown", minDistance, true);
  //   }
  // }

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

  // // Hàm tính khoảng cách Euclidean
  // double _euclideanDistance(List<double> v1, List<double> v2) {
  //   if (v1.length != v2.length) return 999.0;
  //   double sum = 0;
  //   for (int i = 0; i < v1.length; i++) {
  //     double diff = v1[i] - v2[i];
  //     sum += diff * diff;
  //   }
  //   return sqrt(sum);
  // }

  // void registerFace(img.Image fullImage, Face face, String name) {
  //   img.Image faceCrop = ImageConverter.cropFace(
  //     fullImage,
  //     face.boundingBox.left,
  //     face.boundingBox.top,
  //     face.boundingBox.width,
  //     face.boundingBox.height,
  //   );
  //   img.Image inputImage = img.copyResize(faceCrop, width: 112, height: 112);
  //   List<double> embedding = _generateEmbedding(inputImage);

  //   // Gọi hàm lưu mới
  //   registerUser(name, embedding);
  // }

  // Hàm để giả lập đăng ký (Gọi hàm này khi bấm nút Đăng Ký)
  void registerUser(String name, List<double> embedding) {
    _faceDatabase[name] = embedding;

    // 2. Lưu vào ổ cứng (để tắt app không mất)
    _hiveBox.put(name, embedding);

    debugPrint("✅ Database Size: ${_faceDatabase.length} | Added: $name");
  }

  void deleteUser(String name) {
    _faceDatabase.remove(name);
    _hiveBox.delete(name);
  }
}
