import '../services/native_ai_service.dart';
import '../services/log_service.dart';

class FaceQualityAssessor {
  bool isReady = false;
  static final String modelPath = 'assets/models/lightqnet_mobile.tflite';
  String get modelName => modelPath.split('/').last.replaceAll('.tflite', '');

  static const double _threshold = 0.4;
  double get threshold => _threshold;

  int _inputWidth = 96;
  int _inputHeight = 96;

  /// Khởi tạo model từ thư mục assets bằng cách gọi C++
  Future<void> initialize() async {
    try {
      final encodedDims = await NativeAiService().initQualityModel(modelPath);
      if (encodedDims <= 0) {
        AppLog.error("❌ FATAL: C++ nạp Quality Model thất bại!");
        isReady = false; // Nhớ đổi _isReady thành biến tương ứng của bạn
        return;
      }

      // 👉 GIẢI MÃ VÀ LƯU VÀO STATE
      _inputWidth = encodedDims >> 16;
      _inputHeight = encodedDims & 0xFFFF;

      AppLog.info(
        "🛡️ Nạp Quality Model thành công! Auto Config: ${_inputWidth}x$_inputHeight",
      );

      isReady = true;
    } catch (e) {
      AppLog.error('⚠️ Lỗi khi khởi tạo model C++: $e');
    }
  }

  /// Hàm chấm điểm chất lượng khuôn mặt
  /// [normalizedPixels] đã được resize 96x96, chuyển RGB và chia 255.0
  double predict(List<double> normalizedPixels) {
    if (!isReady) {
      AppLog.warning('⚠️ Face Quality Model chưa sẵn sàng!');
      return -1.0;
    }

    try {
      // 1. Khoán cho C++ tính toán và trả về điểm chất lượng
      final double qualityScore = NativeAiService().predictQuality(
        normalizedPixels,
      );

      if (qualityScore < 0.0) {
        // C++ trả về -1 nghĩa là có lỗi (ví dụ: sai shape mảng truyền vào)
        // AppLog.warning("⚠️ C++ Face Quality Predict trả về lỗi");
        return -1.0;
      }

      return qualityScore;
    } catch (e) {
      AppLog.error("❌ Lỗi C++ Face Quality Model: $e");
      return -1.0;
    }
  }
}
