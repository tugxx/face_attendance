import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:tflite_flutter/tflite_flutter.dart';

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

  static const String modelPath = 'assets/models/w600k_mbf_float32.tflite';

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

      debugPrint("🔍 Model Detected Shape: $rawShape");
      debugPrint("   -> Height: $_inputHeight");
      debugPrint("   -> Width: $_inputWidth");

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

      debugPrint("🧠 AI Model Loaded: $modelPath");
      debugPrint("   - Input: ${_inputHeight}x$_inputWidth");
      debugPrint("   - Input Type: $_inputType");
      debugPrint("   - Quantization: Scale=$_scale, ZeroPoint=$_zeroPoint");
      debugPrint("   - Output Vector: $_outputSize dimensions");

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

      debugPrint("🧠 AI Tool Model loaded. Output: $_outputSize");
    } catch (e) {
      debugPrint("❌ Error loading Model: $e");
    }
  }

  List<double> generateEmbedding(cv.Mat alignedMat) {
    if (_interpreter == null) {
      debugPrint("⚠️ Model chưa init!");
      return [];
    }

    // 1. Convert BGR -> RGB & Resize
    cv.Mat rgbMat = cv.cvtColor(alignedMat, cv.COLOR_BGR2RGB);
    if (rgbMat.rows != _inputHeight || rgbMat.cols != _inputWidth) {
      cv.Mat resizedMat = cv.resize(rgbMat, (_inputWidth, _inputHeight));
      rgbMat.dispose(); // Giải phóng ảnh cũ ngay lập tức
      rgbMat = resizedMat;
    }

    Object inputBuffer;
    cv.Mat? processedMat;

    try {
      // 2. CHUẨN BỊ INPUT DATA DỰA TRÊN TYPE
      if (_inputType == TensorType.float32) {
        // --- TRƯỜNG HỢP FLOAT32 ---
        processedMat = rgbMat.convertTo(
          cv.MatType.CV_32FC3,
          alpha: normAlpha, // 1/128
          beta: normBeta, // -127.5/128
        );

        // Zero-copy: Ánh xạ bộ nhớ trực tiếp
        final byteData = processedMat.data;
        final inputFloatList = Float32List.view(
          byteData.buffer,
          byteData.offsetInBytes,
          byteData.lengthInBytes ~/ 4,
        );

        inputBuffer = Float32List.fromList(
          inputFloatList,
        ).reshape([1, _inputHeight, _inputWidth, _channels]);
      } else {
        // --- TRƯỜNG HỢP INT8 / UINT8 ---
        double qAlpha = 1.0 / (128.0 * _scale);
        double qBeta = _zeroPoint - (127.5 / (128.0 * _scale));

        // Chọn kiểu dữ liệu đích
        var targetType = (_inputType == TensorType.int8)
            ? cv.MatType.CV_8SC3
            : cv.MatType.CV_8UC3;

        processedMat = rgbMat.convertTo(targetType, alpha: qAlpha, beta: qBeta);

        // Lấy raw bytes từ ảnh RGB (đang là uint8: 0-255)
        Uint8List rawBytes = processedMat.data;

        // Reshape & Cast đúng kiểu
        if (_inputType == TensorType.int8) {
          // Int8List view trên bộ nhớ raw
          inputBuffer = Int8List.view(
            rawBytes.buffer,
          ).reshape([1, _inputHeight, _inputWidth, 3]);
        } else {
          // Uint8List
          inputBuffer = rawBytes.reshape([1, _inputHeight, _inputWidth, 3]);
        }
      }

      // 3. CHUẨN BỊ OUTPUT & RUN
      // Lưu ý: Output của model Face Recognition thường luôn là Float32 (Embedding vector)
      // ngay cả khi input là Int8. Nếu model trả về Int8, ta phải Dequantize.

      var outputTensor = _interpreter!.getOutputTensor(0);
      var outputShape = outputTensor.shape;

      Object outputBufferRaw;
      if (outputTensor.type == TensorType.float32) {
        outputBufferRaw = Float32List(_outputSize).reshape(outputShape);
      } else {
        // Int8/Uint8
        outputBufferRaw = List.filled(_outputSize, 0).reshape(outputShape);
      }

      _interpreter!.run(inputBuffer, outputBufferRaw);

      // 6. XỬ LÝ KẾT QUẢ
      List<double> rawEmbedding = [];

      // Lấy data từ buffer ra (dù shape là [1,128] hay [128] thì flatten đều ra list)
      var batchResult = outputBufferRaw as List;

      // Lấy vector của bức ảnh đầu tiên (Batch size = 1 nên lấy index 0)
      var firstVector = batchResult[0] as List;

      if (outputTensor.type == TensorType.float32) {
        // Nếu output model là Float, chỉ cần copy sang List<double>
        // Dùng map để đảm bảo chuyển đổi đúng kiểu số
        rawEmbedding = firstVector.map((e) => (e as num).toDouble()).toList();
      } else {
        // Nếu output model là Int8/Uint8, phải Dequantize
        // Công thức: f = (q - zero_point) * scale
        double outScale = outputTensor.params.scale;
        int outZeroPoint = outputTensor.params.zeroPoint;

        for (var element in firstVector) {
          num val = element as num; // Ép về num cho an toàn
          rawEmbedding.add((val - outZeroPoint) * outScale);
        }
      }

      return _l2Normalize(rawEmbedding);
    } catch (e) {
      debugPrint("❌ Error in generateEmbedding: $e");
      return [];
    } finally {
      // Dọn dẹp bộ nhớ Native C++ (Rất quan trọng để không leak RAM)
      rgbMat.dispose();
      processedMat?.dispose();
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
