import 'dart:typed_data';
import 'dart:math' as math;

import 'package:tflite_flutter/tflite_flutter.dart';

import '../app/services/log_service.dart';

class ToolAIService {
  Interpreter? _interpreter;
  static int _inputHeight = 0;
  static int _inputWidth = 0;
  int _outputSize = 192;
  static int _channels = 0;

  static int get inputHeight => _inputHeight;
  static int get inputWidth => _inputWidth;
  static int get channels => _channels;

  TensorType _inputType = TensorType.float32;

  // Tham số Quantization (Dành cho model int8/uint8)
  double _scale = 1.0;
  int _zeroPoint = 0;

  static const double normAlpha = 1.0 / 128.0;
  static const double normBeta = -127.5 / 128.0;

  int get outputSize => _outputSize;

  static const String modelPath = 'assets/models/mobilefacenet.tflite';

  Future<void> initialize() async {
    try {
      // Load Interpreter với options tối ưu cho Android/iOS
      final options = InterpreterOptions();

      _interpreter = await Interpreter.fromAsset(modelPath, options: options);

      // 1. TỰ ĐỘNG LẤY INPUT SHAPE
      var inputTensor = _interpreter!.getInputTensor(0);
      var rawShape = inputTensor.shape;
      _inputHeight = rawShape[1];
      _inputWidth = rawShape[2];
      _channels = rawShape[3];
      _inputType = inputTensor.type;

      AppLog.info("🔍 Model Detected Shape: $rawShape");
      AppLog.info("   -> Height: $_inputHeight");
      AppLog.info("   -> Width: $_inputWidth");

      _interpreter!.resizeInputTensor(0, [
        1,
        _inputHeight,
        _inputWidth,
        _channels,
      ]);
      _interpreter!.allocateTensors();

      // Lấy tham số Quantization (Nếu model là float thì scale=0, zeroPoint=0)
      if (inputTensor.params.scale > 0) {
        _scale = inputTensor.params.scale;
        _zeroPoint = inputTensor.params.zeroPoint;
      }

      var outputTensor = _interpreter!.getOutputTensor(0);
      var outputShape = outputTensor.shape;

      _outputSize = outputShape.reduce((a, b) => a * b);

      AppLog.info("🧠 AI Model Loaded: $modelPath");
      AppLog.info("   - Input: ${_inputHeight}x$_inputWidth");
      AppLog.info("   - Input Type: $_inputType");
      AppLog.info("   - Quantization: Scale=$_scale, ZeroPoint=$_zeroPoint");
      AppLog.info("   - Output Vector: $_outputSize dimensions");

      int bufferSize = 1 * _inputHeight * _inputWidth * _channels;
      Object inputBuffer;

      switch (_inputType) {
        case TensorType.int8:
          inputBuffer = Int8List(
            bufferSize,
          ).reshape([1, _inputHeight, _inputWidth, _channels]);
          break;
        case TensorType.uint8:
          inputBuffer = Uint8List(
            bufferSize,
          ).reshape([1, _inputHeight, _inputWidth, _channels]);
          break;
        case TensorType.float32:
        default:
          inputBuffer = Float32List(
            bufferSize,
          ).reshape([1, _inputHeight, _inputWidth, _channels]);
          break;
      }

      Object outputBuffer;

      if (outputTensor.type == TensorType.float32) {
        outputBuffer = Float32List(_outputSize).reshape(outputShape);
      } else {
        outputBuffer = List.filled(_outputSize, 0).reshape(outputShape);
      }

      _interpreter?.run(inputBuffer, outputBuffer);

      AppLog.info("🧠 AI Tool Model loaded. Output: $_outputSize");
    } catch (e) {
      AppLog.error("❌ Error loading Model: $e");
    }
  }

  Future<List<double>> generateEmbedding(List<double> inputPixels) async {
    if (_interpreter == null) {
      AppLog.warning("⚠️ Model chưa init!");
      return [];
    }

    // Guard: Kiểm tra kích thước dữ liệu đầu vào có khớp không
    if (inputPixels.length != _inputHeight * _inputWidth * _channels) {
      AppLog.warning(
        "⚠️ Sai kích thước input! Nhận ${inputPixels.length}, cần ${_inputHeight * _inputWidth * _channels}",
      );
      return [];
    }

    try {
      // 1. CHUẨN BỊ INPUT BUFFER
      Object inputBuffer;

      if (_inputType == TensorType.float32) {
        // --- TRƯỜNG HỢP FLOAT32 (Phổ biến nhất) ---
        // inputPixels đã là double [-1, 1], chỉ cần cast sang Float32List và Reshape
        inputBuffer = Float32List.fromList(
          inputPixels,
        ).reshape([1, _inputHeight, _inputWidth, _channels]);
      } else {
        // --- TRƯỜNG HỢP INT8 / UINT8 (Quantized Model) ---
        // Ta cần chuyển đổi từ Float [-1, 1] sang Int/Uint dựa trên Scale & ZeroPoint
        // Công thức: q = x / scale + zeroPoint

        List<int> quantizedData = inputPixels.map((x) {
          double q = (x / _scale) + _zeroPoint;
          if (_inputType == TensorType.uint8) {
            return q.round().clamp(0, 255);
          } else {
            return q.round().clamp(-128, 127);
          }
        }).toList();

        if (_inputType == TensorType.uint8) {
          inputBuffer = Uint8List.fromList(
            quantizedData,
          ).reshape([1, _inputHeight, _inputWidth, _channels]);
        } else {
          inputBuffer = Int8List.fromList(
            quantizedData,
          ).reshape([1, _inputHeight, _inputWidth, _channels]);
        }
      }

      // 2. CHUẨN BỊ OUTPUT BUFFER
      var outputTensor = _interpreter!.getOutputTensor(0);
      Object outputBufferRaw;

      // Luôn hứng output theo đúng kiểu dữ liệu của Model
      if (outputTensor.type == TensorType.float32) {
        outputBufferRaw = Float32List(_outputSize).reshape(outputTensor.shape);
      } else {
        // Nếu output là int8/uint8
        outputBufferRaw = List.filled(
          _outputSize,
          0.0,
        ).reshape(outputTensor.shape); // Dart List dynamic cho an toàn
      }

      // 3. CHẠY MODEL (Inference)
      _interpreter!.run(inputBuffer, outputBufferRaw);

      // 4. XỬ LÝ KẾT QUẢ (Parsing Output)
      List<double> rawEmbedding = [];
      var batchResult = outputBufferRaw as List;
      var firstVector = batchResult[0]; // Batch 0

      // Flatten kết quả ra List<double>
      if (firstVector is List) {
        // Output dạng [1, 192]
        for (var item in firstVector) {
          rawEmbedding.add(_parseOutputValue(item, outputTensor));
        }
      } else {
        // Output dạng [192] (Flatten sẵn)
        for (var item in batchResult) {
          rawEmbedding.add(_parseOutputValue(item, outputTensor));
        }
      }

      // 5. L2 NORMALIZE (Bắt buộc)
      return _l2Normalize(rawEmbedding);
    } catch (e) {
      AppLog.error("❌ Error in generateEmbedding: $e");
      return [];
    }
  }

  double _parseOutputValue(dynamic value, Tensor outputTensor) {
    if (outputTensor.type == TensorType.float32) {
      return (value as num).toDouble();
    } else {
      // Dequantize: f = (q - zeroPoint) * scale
      double scale = outputTensor.params.scale;
      int zeroPoint = outputTensor.params.zeroPoint;
      return ((value as num) - zeroPoint) * scale;
    }
  }

  List<double> _l2Normalize(List<double> embedding) {
    double squareSum = 0;
    for (var x in embedding) {
      squareSum += x * x;
    }
    double xInvNorm = math.sqrt(math.max(squareSum, 1e-10));
    return embedding.map((x) => x / xInvNorm).toList();
  }

  void dispose() {
    _interpreter?.close();
  }
}
