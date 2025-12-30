import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:image/image.dart' as img;
import '../utils/image_converter.dart';

class FaceRecognitionService {
  // Singleton Pattern (Chỉ tạo 1 instance duy nhất trong app)
  static final FaceRecognitionService _instance =
      FaceRecognitionService._internal();
  factory FaceRecognitionService() => _instance;
  FaceRecognitionService._internal();

  Interpreter? _interpreter;

  // Database giả lập (RAM)
  final Map<String, List<double>> _faceDatabase = {};

  int _outputSize = 192;

  bool get isDatabaseEmpty => _faceDatabase.isEmpty;

  Future<void> initialize() async {
    try {
      // Load model (cần đảm bảo file .tflite nằm trong assets)
      _interpreter = await Interpreter.fromAsset(
        'assets/models/mobilefacenet.tflite',
      );

      // TỰ ĐỘNG LẤY KÍCH THƯỚC OUTPUT CỦA MODEL
      var outputTensor = _interpreter!.getOutputTensor(0);
      _outputSize = outputTensor.shape[1]; // Lấy số 128 hoặc 192 từ model
      debugPrint("🧠 Model Output: $_outputSize - DB Size: ${_faceDatabase.length}");

      // Warmup: Chạy thử 1 lần với data rỗng để load model vào RAM
      var input = List.filled(1 * 112 * 112 * 3, 0.0).reshape([1, 112, 112, 3]);
      var output = List.filled(1 * _outputSize, 0.0).reshape([1, _outputSize]);
      _interpreter?.run(input, output);

      debugPrint("🧠 AI Model loaded successfully");
    } catch (e) {
      debugPrint("❌ Error loading AI Model: $e");
    }
  }

  // Hàm này dùng cho việc ĐĂNG KÝ (Enrollment) từ ảnh Gallery
  Future<List<double>?> getEmbeddingFromImageFile(File file) async {
    if (_interpreter == null) return null;

    // 1. Đọc ảnh từ file
    final bytes = await file.readAsBytes();
    final img.Image? image = img.decodeImage(bytes);
    if (image == null) return null;

    // 2. Resize & Chuẩn hóa (Giống hệt lúc xử lý Camera)
    img.Image inputImage = img.copyResize(image, width: 112, height: 112);
    
    // 3. Tạo vector
    return _generateEmbedding(inputImage);
  }

  Future<String?> predictFromFile(File file) async {
    // 1. Tận dụng hàm có sẵn để lấy vector
    List<double>? embedding = await getEmbeddingFromImageFile(file);
    
    if (embedding == null) return null;

    // 2. So sánh vector đó với database
    return _findClosestMatch(embedding);
  }

  /// Hàm chính: Nhận ảnh Camera + Tọa độ mặt -> Trả về Tên người (nếu có)
  Future<String?> predict(img.Image fullImage, Face face) async {
    if (_interpreter == null) {
      debugPrint("⚠️ Model chưa load xong!");
      return null;
    }

    if (_faceDatabase.isEmpty) {
      debugPrint("⚠️ Database trống! Chưa có ai đăng ký.");
      return "Unknown (DB Empty)";
    }

    // 1. Chuyển YUV -> RGB (Nặng nhất)
    img.Image faceCrop = ImageConverter.cropFace(
      fullImage,
      face.boundingBox.left,
      face.boundingBox.top,
      face.boundingBox.width,
      face.boundingBox.height,
    );
    
    // 2. Resize về 112x112
    img.Image inputImage = img.copyResize(faceCrop, width: 112, height: 112);

    // // 2. Xoay ảnh (Camera trước thường bị xoay 270 độ trên Android)
    // // Lưu ý: Redmi 5 Plus có thể cần xoay -90 hoặc 270 tùy sensorOrientation
    // img.Image rotatedImage = img.copyRotate(convertedImage, angle: -90);

    // // 3. Cắt khuôn mặt (Crop)
    // final boundingBox = face.boundingBox;
    // img.Image faceCrop = ImageConverter.cropFace(
    //   rotatedImage,
    //   boundingBox.left,
    //   boundingBox.top,
    //   boundingBox.width,
    //   boundingBox.height,
    // );

    // // 4. Resize về 112x112 (Input chuẩn của MobileFaceNet)
    // img.Image inputImage = img.copyResize(faceCrop, width: 112, height: 112);

    // 5. Lấy Vector đặc trưng (Embedding)
    List<double> embedding = _generateEmbedding(inputImage);

    // 6. So sánh với Database
    return _findClosestMatch(embedding);
  }

  /// Logic chạy TFLite
  List<double> _generateEmbedding(img.Image image) {
    // Input: [1, 112, 112, 3] -> Output: [1, 192]
    var input = Float32List(1 * 112 * 112 * 3);
    var buffer = Float32List.view(input.buffer);
    int pixelIndex = 0;

    for (var i = 0; i < 112; i++) {
      for (var j = 0; j < 112; j++) {
        var pixel = image.getPixel(j, i);
        // Normalize (pixel - 128) / 128
        buffer[pixelIndex++] = (pixel.r - 128) / 128;
        buffer[pixelIndex++] = (pixel.g - 128) / 128;
        buffer[pixelIndex++] = (pixel.b - 128) / 128;
      }
    }

    var output = List.filled(1 * _outputSize, 0.0).reshape([1, _outputSize]);
    _interpreter!.run(input.reshape([1, 112, 112, 3]), output);
    return List<double>.from(output[0]);
  }

  /// Logic so sánh Vector
  String? _findClosestMatch(List<double> newEmbedding) {
    double maxScore = 0;
    String? foundName;

    for (var entry in _faceDatabase.entries) {
      double score = _cosineSimilarity(newEmbedding, entry.value);
      if (score > maxScore) {
        maxScore = score;
        foundName = entry.key;
      }
    }

    // Threshold: 0.5 là mức trung bình, bạn cần tinh chỉnh tùy model
    if (maxScore > 0.5) {
      return "$foundName (${(maxScore * 100).toStringAsFixed(1)}%)";
    }
    return "Unknown";
  }

  double _cosineSimilarity(List<double> v1, List<double> v2) {
    double dot = 0, mag1 = 0, mag2 = 0;
    for (int i = 0; i < v1.length; i++) {
      dot += v1[i] * v2[i];
      mag1 += v1[i] * v1[i];
      mag2 += v2[i] * v2[i];
    }
    return dot / (sqrt(mag1) * sqrt(mag2));
  }

  // Hàm để giả lập đăng ký (Gọi hàm này khi bấm nút Đăng Ký)
  void registerFace(img.Image fullImage, Face face, String name) {
     img.Image faceCrop = ImageConverter.cropFace(
      fullImage,
      face.boundingBox.left,
      face.boundingBox.top,
      face.boundingBox.width,
      face.boundingBox.height,
    );
    img.Image inputImage = img.copyResize(faceCrop, width: 112, height: 112);
    List<double> embedding = _generateEmbedding(inputImage);
    
    _faceDatabase[name] = embedding;
    debugPrint("✅ Database Size: ${_faceDatabase.length} | Added: $name");
  }

  void registerUser(String name, List<double> embedding) {
    _faceDatabase[name] = embedding;
    debugPrint("✅ Đã đăng ký thành công user: $name");
  }
}
