import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
// import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:archive/archive.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../app/core/services/face_aligner_cv.dart';

class ToolAIService {
  Interpreter? _interpreter;
  int _inputSize = 112;
  int _outputSize = 192;

  TensorType _inputType = TensorType.float32;

  // Tham số Quantization (Dành cho model int8/uint8)
  double _scale = 1.0;
  int _zeroPoint = 0;

  static const double normAlpha = 1.0 / 128.0;
  static const double normBeta = -127.5 / 128.0;

  int get inputSize => _inputSize;
  int get outputSize => _outputSize;

  static const String modelPath = 'assets/models/mobilefacenet.tflite';

  Future<void> initialize() async {
    try {
      // Load Interpreter với options tối ưu cho Android/iOS
      final options = InterpreterOptions();

      _interpreter = await Interpreter.fromAsset(modelPath, options: options);

      // 1. TỰ ĐỘNG LẤY INPUT SHAPE
      var inputTensor = _interpreter!.getInputTensor(0);
      _inputSize = inputTensor.shape[1];
      _inputType = inputTensor.type;

      // Lấy tham số Quantization (Nếu model là float thì scale=0, zeroPoint=0)
      if (inputTensor.params.scale > 0) {
        _scale = inputTensor.params.scale;
        _zeroPoint = inputTensor.params.zeroPoint;
      }

      var outputTensor = _interpreter!.getOutputTensor(0);
      _outputSize = outputTensor.shape[1];

      debugPrint("🧠 AI Model Loaded: $modelPath");
      debugPrint("   - Input: ${_inputSize}x$_inputSize");
      debugPrint("   - Input Type: $_inputType");
      debugPrint("   - Quantization: Scale=$_scale, ZeroPoint=$_zeroPoint");
      debugPrint("   - Output Vector: $_outputSize dimensions");

      // // --- 3. WARMUP (Tự động theo kiểu dữ liệu) ---
      // // Tạo buffer input giả lập
      // Object inputBuffer;
      // if (_inputType == TensorType.float32) {
      //   inputBuffer = Float32List(
      //     1 * _inputSize * _inputSize * 3,
      //   ).reshape([1, _inputSize, _inputSize, 3]);
      // } else if (_inputType == TensorType.int8) {
      //   inputBuffer = Int8List(
      //     1 * _inputSize * _inputSize * 3,
      //   ).reshape([1, _inputSize, _inputSize, 3]);
      // } else {
      //   // uint8
      //   inputBuffer = Uint8List(
      //     1 * _inputSize * _inputSize * 3,
      //   ).reshape([1, _inputSize, _inputSize, 3]);
      // }

      // var outputBuffer = List.filled(
      //   1 * _outputSize,
      //   0.0,
      // ).reshape([1, _outputSize]);

      var inputBuffer = Float32List(
        1 * _inputSize * _inputSize * 3,
      ).reshape([1, _inputSize, _inputSize, 3]);
      var outputBuffer = List.filled(
        _outputSize,
        0.0,
      ).reshape([1, _outputSize]);

      _interpreter?.run(inputBuffer, outputBuffer);

      debugPrint("🧠 AI Tool Model loaded. Output: $_outputSize");
    } catch (e) {
      debugPrint("❌ Error loading Model: $e");
    }
  }

  // Logic Generate Embedding (GIỐNG HỆT APP)
  List<double> generateEmbedding(cv.Mat alignedMat) {
    if (_interpreter == null) {
      debugPrint("⚠️ Model chưa init!");
      return [];
    }

    // // 1. Chuẩn hóa Input (Pre-processing)
    // // Các model InsightFace thường dùng chuẩn: (pixel - 127.5) / 128.0
    // // Input phải đúng kích thước model yêu cầu (thường là 112x112)
    // if (image.width != _inputSize || image.height != _inputSize) {
    //   image = img.copyResize(image, width: _inputSize, height: _inputSize);
    // }

    // double imageMean = 127.5;
    // double imageStd = 128.0;

    // // Khởi tạo mảng phẳng (flat array) tùy theo kiểu dữ liệu
    // List<num> flatInput;
    // if (_inputType == TensorType.float32) {
    //   flatInput = Float32List(1 * _inputSize * _inputSize * 3);
    // } else if (_inputType == TensorType.int8) {
    //   flatInput = Int8List(1 * _inputSize * _inputSize * 3);
    // } else {
    //   flatInput = Uint8List(1 * _inputSize * _inputSize * 3);
    // }

    // int pixelIndex = 0;
    // for (var i = 0; i < _inputSize; i++) {
    //   for (var j = 0; j < _inputSize; j++) {
    //     var pixel = image.getPixel(j, i);

    //     // Bước A: Tính giá trị Float chuẩn hóa trước
    //     double r = (pixel.r.toDouble() - imageMean) / imageStd;
    //     double g = (pixel.g.toDouble() - imageMean) / imageStd;
    //     double b = (pixel.b.toDouble() - imageMean) / imageStd;

    //     // Bước B: Nếu là model Quantized, chuyển Float -> Int
    //     // Công thức: q = (f / scale) + zero_point
    //     if (_inputType != TensorType.float32) {
    //       flatInput[pixelIndex++] = (r / _scale + _zeroPoint).round().clamp(
    //         -128,
    //         255,
    //       );
    //       flatInput[pixelIndex++] = (g / _scale + _zeroPoint).round().clamp(
    //         -128,
    //         255,
    //       );
    //       flatInput[pixelIndex++] = (b / _scale + _zeroPoint).round().clamp(
    //         -128,
    //         255,
    //       );
    //     } else {
    //       // Model Float thường
    //       flatInput[pixelIndex++] = r;
    //       flatInput[pixelIndex++] = g;
    //       flatInput[pixelIndex++] = b;
    //     }
    //   }
    // }

    // // 3. Reshape để đưa vào model [1, 112, 112, 3]
    // Object inputTensorData;
    // if (flatInput is Float32List) {
    //   inputTensorData = flatInput.reshape([1, _inputSize, _inputSize, 3]);
    // } else if (flatInput is Int8List) {
    //   inputTensorData = flatInput.reshape([1, _inputSize, _inputSize, 3]);
    // } else {
    //   inputTensorData = (flatInput as Uint8List).reshape([
    //     1,
    //     _inputSize,
    //     _inputSize,
    //     3,
    //   ]);
    // }

    // // 4. Chuẩn bị Output
    // // Lưu ý: Ngay cả model Input Int8, thì Output Embedding thường vẫn là Float32
    // // (trừ khi Full Integer Quantization). Ta cứ hứng bằng Float32, nếu model trả về Int8 thì ta Dequantize sau.
    // var outputTensor = _interpreter!.getOutputTensor(0);
    // List<dynamic> outputBuffer; // Dùng dynamic để linh hoạt

    // if (outputTensor.type == TensorType.float32) {
    //   outputBuffer = List.filled(
    //     1 * _outputSize,
    //     0.0,
    //   ).reshape([1, _outputSize]);
    // } else {
    //   // Trường hợp output cũng bị quantized (hiếm gặp với Embedding nhưng có thể)
    //   // Ta hứng tạm bằng int, sau đó sẽ convert ra float
    //   outputBuffer = List.filled(1 * _outputSize, 0).reshape([1, _outputSize]);
    // }

    try {
      // 1. Convert BGR -> RGB (BẮT BUỘC)
      // OpenCV mặc định là BGR, Model AI cần RGB
      cv.Mat rgbMat = cv.cvtColor(alignedMat, cv.COLOR_BGR2RGB);

      // 2. Resize ảnh nếu kích thước ảnh đầu vào khác với kích thước model yêu cầu
      // (Phòng trường hợp ảnh crop ra là 112x112 nhưng model lại cần 128x128)
      if (rgbMat.rows != _inputSize || rgbMat.cols != _inputSize) {
        // debugPrint("⚠️ Resize ảnh từ ${rgbMat.rows} -> $_inputSize");
        cv.Mat resizedMat = cv.resize(rgbMat, (
          _inputSize,
          _inputSize,
        ), interpolation: cv.INTER_LINEAR);
        rgbMat.dispose(); // Giải phóng ảnh cũ
        rgbMat = resizedMat; // Gán ảnh mới
      }

      // 2. Convert sang Float32 & Normalize
      cv.Mat floatMat = rgbMat.convertTo(
        cv.MatType.CV_32FC3,
        alpha: normAlpha, // 1/128
        beta: normBeta, // -127.5/128
      );

      // 3. Lấy dữ liệu RAW HWC (Height-Width-Channel)
      // Tức là: [R1, G1, B1, R2, G2, B2, ...]
      // Đây là định dạng native của ảnh và TFLite thích cái này.
      final byteData = floatMat.data;

      // Sử dụng offsetInBytes để AN TOÀN BỘ NHỚ (Tránh crash SIGSEGV)
      final inputFloatList = Float32List.view(
        byteData.buffer,
        byteData.offsetInBytes,
        byteData.lengthInBytes ~/ 4,
      );

      // 4. Đưa vào Model
      var inputBuffer = Float32List.fromList(inputFloatList).reshape([
        1,
        _inputSize,
        _inputSize,
        3, // Số kênh màu (RGB) thường luôn là 3
      ]);

      var outputBuffer = List.filled(
        _outputSize,
        0.0,
      ).reshape([1, _outputSize]);

      // 5. Run Inference
      _interpreter!.run(inputBuffer, outputBuffer);

      // // 6. Xử lý kết quả (Dequantize Output nếu cần)
      // List<double> rawEmbedding = [];
      // var rawOutput = outputBuffer[0]; // Lấy batch đầu tiên

      // if (outputTensor.type == TensorType.float32) {
      //   rawEmbedding = List<double>.from(rawOutput);
      // } else {
      //   // Nếu Output là Int8, ta cần đổi ngược lại ra Float để tính toán khoảng cách
      //   // Công thức: f = (q - zero_point) * scale
      //   double outScale = outputTensor.params.scale;
      //   int outZeroPoint = outputTensor.params.zeroPoint;
      //   for (var val in rawOutput) {
      //     rawEmbedding.add((val - outZeroPoint) * outScale);
      //   }
      // }

      // Dọn dẹp
      rgbMat.dispose();
      floatMat.dispose();

      // 6. Lấy kết quả & L2 Normalize
      List<double> rawEmbedding = List<double>.from(outputBuffer[0]);
      return _l2Normalize(rawEmbedding);
    } catch (e) {
      debugPrint("❌ Error generating embedding: $e");
      return [];
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

class FaceSeeder extends StatefulWidget {
  const FaceSeeder({super.key});

  @override
  State<FaceSeeder> createState() => _FaceSeederState();
}

class _FaceSeederState extends State<FaceSeeder> {
  String _status = "Sẵn sàng...";
  bool _isProcessing = false;
  final ToolAIService _aiService = ToolAIService();
  late FaceDetector _faceDetector;

  Map<String, List<List<double>>> tempMapEmbeddings = {};
  final Map<String, int> _debugImageCounter = {};

  @override
  void initState() {
    super.initState();
    // Khởi tạo ML Kit
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        performanceMode: FaceDetectorMode.accurate,
        enableLandmarks: true,
        enableContours: false,
      ),
    );
    // Khởi tạo AI Service (Load model TFLite)
    _aiService.initialize();
  }

  // --- HÀM CHÍNH: XỬ LÝ VÀ XUẤT JSON ---
  Future<void> _startSeeding() async {
    setState(() {
      _isProcessing = true;
      _status = "Đang giải nén & Xử lý...";
    });

    _debugImageCounter.clear();
    tempMapEmbeddings.clear();

    // Bắt đầu bấm giờ
    Stopwatch stopwatch = Stopwatch()..start();
    int totalImagesProcessed = 0;

    try {
      final extDir = await getExternalStorageDirectory();
      final debugDir = Directory('${extDir!.path}/debug_seeder');
      if (await debugDir.exists()) {
        await debugDir.delete(recursive: true);
      }
    } catch (_) {}

    try {
      // 1. Đọc file Zip từ Assets
      final byteData = await rootBundle.load('assets/dataset.zip');
      final buffer = byteData.buffer.asUint8List();

      // 2. Giải nén
      final archive = ZipDecoder().decodeBytes(buffer);

      debugPrint("📦 Đã tìm thấy ${archive.length} file trong Zip.");

      // 3. Duyệt từng file trong file Zip
      for (final file in archive) {
        if (file.isFile) {
          final filename = file.name; // Ví dụ: dataset/xuantung/anh1.jpg

          // Lọc chỉ lấy ảnh
          if (!filename.toLowerCase().endsWith('.jpg') &&
              !filename.toLowerCase().endsWith('.png') &&
              !filename.toLowerCase().endsWith('.jpeg')) {
            continue;
          }

          totalImagesProcessed++;

          // Phân tích tên User từ đường dẫn trong Zip
          // dataset/xuantung/anh1.jpg -> parts[-2] là xuantung
          List<String> parts = filename.split('/');
          if (parts.length < 2) continue;

          // Nếu cấu trúc là dataset/xuantung/anh.jpg thì lấy parts[parts.length - 2]
          // Nếu zip trực tiếp xuantung/anh.jpg thì lấy parts[0]
          // Logic an toàn: Lấy tên thư mục chứa file
          String name = parts[parts.length - 2];

          debugPrint("⚡ Đang xử lý: $name - ${filename.split('/').last}");

          // A. Ghi file ra bộ nhớ tạm (Cache) để ML Kit đọc
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/temp_img');
          await tempFile.writeAsBytes(file.content as List<int>);

          // B. Xử lý ảnh
          await _processImageFile(tempFile, name);

          // Xóa file tạm
          if (await tempFile.exists()) await tempFile.delete();

          final files = archive.files;
          final index = files.indexOf(file);

          setState(() {
            _status = "Đang xử lý: $name (${index + 1}/${files.length})";
          });
        }
      }

      Map<String, List<double>> finalJsonData = {};
      tempMapEmbeddings.forEach((user, embeddingsList) {
        if (embeddingsList.isNotEmpty) {
          finalJsonData[user] = _calculateMean(embeddingsList);
        }
      });

      debugPrint("✅ Đã xử lý xong ${finalJsonData.length} người dùng!");

      // --- SAU KHI XỬ LÝ XONG TẤT CẢ ẢNH ---
      stopwatch.stop();

      // 1. Lấy thông số chất lượng (Hàm vừa sửa ở trên)
      var qualityStats = _validateDataQuality();

      // 2. Lấy thông số hiệu năng
      int totalTimeMs = stopwatch.elapsedMilliseconds;
      double avgTimePerImage = totalImagesProcessed > 0
          ? totalTimeMs / totalImagesProcessed
          : 0.0;

      // 3. Lấy thông tin Model (Size, Tên)
      String modelName = ToolAIService.modelPath.split('/').last;
      double modelSizeMB = 0.0;
      try {
        final byteData = await rootBundle.load(ToolAIService.modelPath);
        modelSizeMB = byteData.lengthInBytes / (1024 * 1024);
      } catch (e) {
        debugPrint("Không lấy được size model: $e");
      }

      // 4. TẠO JSON BÁO CÁO (Cái bạn cần đây)
      Map<String, dynamic> reportData = {
        "model_info": {
          "name": modelName,
          "input_size": _aiService.inputSize,
          "output_dim": _aiService.outputSize,
          "file_size_mb": double.parse(modelSizeMB.toStringAsFixed(2)),
          // Nếu dùng code fix trước đó thì lấy _aiService._inputType
          // "data_type": _aiService._inputType.toString(),
        },
        "performance": {
          "total_images": totalImagesProcessed,
          "total_time_ms": totalTimeMs,
          "avg_ms_per_image": double.parse(avgTimePerImage.toStringAsFixed(1)),
        },
        "quality_metrics": {
          // 👉 SỬA Ở ĐÂY: Key mới là 'intra_sim' (Cosine)
          "avg_intra_sim": double.parse(
            (qualityStats['intra_sim'] ?? 0.0).toStringAsFixed(4),
          ),
          // 👉 SỬA Ở ĐÂY: Key mới là 'inter_sim' (Cosine)
          "avg_inter_sim": double.parse(
            (qualityStats['inter_sim'] ?? 0.0).toStringAsFixed(4),
          ),
          // 👉 SỬA Ở ĐÂY: Margin = Intra - Inter
          "quality_margin": double.parse(
            (qualityStats['quality_score'] ?? 0.0).toStringAsFixed(4),
          ),
        },
        // Kèm luôn dữ liệu vector để backup
        // "database": finalJsonData
      };

      String reportJson = jsonEncode(reportData);
      String safeModelName = modelName.replaceAll('.', '_'); // w600k_r50_tflite

      // 5. Gửi File Báo Cáo
      String reportFileName = "report_$safeModelName.json";
      await _sendToServer(reportJson, filename: reportFileName);

      // 6. Gửi File Database (Vector)
      String dbJsonString = json.encode(finalJsonData);
      String dbFileName = "db_$safeModelName.json";
      await _sendToServer(dbJsonString, filename: dbFileName);
    } catch (e) {
      debugPrint("❌ Lỗi: $e");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  // void _log(String msg) {
  //   setState(() {
  //     _status = msg;
  //   });
  //   debugPrint(msg);
  // }

  Future<void> _processImageFile(File tempFile, String name) async {
    String? smallPath;

    try {
      final Uint8List? compressedBytes =
          await FlutterImageCompress.compressWithFile(
            tempFile.path,
            minWidth: 1280,
            minHeight: 1280,
            quality: 95,
            format: CompressFormat.jpeg,
          );

      if (compressedBytes == null) return;

      final tempDir = await getTemporaryDirectory();
      smallPath =
          '${tempDir.path}/temp_small_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final smallFile = File(smallPath);
      await smallFile.writeAsBytes(compressedBytes);

      final inputImageFile = InputImage.fromFile(smallFile);
      final faces = await _faceDetector.processImage(inputImageFile);

      if (faces.isNotEmpty) {
        Face mainFace = faces.reduce((curr, next) {
          final currArea = curr.boundingBox.width * curr.boundingBox.height;
          final nextArea = next.boundingBox.width * next.boundingBox.height;
          return currArea > nextArea ? curr : next;
        });

        // Kiểm tra phụ (Optional): Nếu khuôn mặt lớn nhất vẫn quá nhỏ so với ảnh thì có thể bỏ qua
        // Ví dụ: Chỉ nhận nếu mặt chiếm > 10% diện tích ảnh (tùy chỉnh nếu cần)
        // double imageArea = processingImage.width * processingImage.height * 1.0;
        // double faceArea = mainFace.boundingBox.width * mainFace.boundingBox.height;
        // if (faceArea / imageArea < 0.1) return;

        // final Uint8List? alignedBytes = await FaceAlignerCV.alignFace(
        //   smallFile.path,
        //   mainFace,
        //   targetSize: _aiService.inputSize,
        // );

        cv.Mat? alignedMat = await FaceAlignerCV.alignFace(
          smallFile.path,
          mainFace,
          debugName: name, // Truyền tên để lưu ảnh debug
          saveDebug: true, // 🟢 BẬT CÁI NÀY LÊN
        );

        // -----------------------------------------------------------
        // 2. DEBUG: LƯU ẢNH CROP RA FILE ĐỂ KIỂM TRA
        // -----------------------------------------------------------
        if (alignedMat != null && !alignedMat.isEmpty) {
          // try {
          //   final extDir = await getExternalStorageDirectory();
          //   if (extDir != null) {
          //     // Tạo folder riêng tên là 'debug_seeder' cho gọn
          //     final debugDir = Directory('${extDir.path}/debug_seeder');
          //     if (!await debugDir.exists()) {
          //       await debugDir.create(recursive: true);
          //     }

          //     int count = (_debugImageCounter[name] ?? 0) + 1;
          //     _debugImageCounter[name] = count;

          //     final String debugPath = '${debugDir.path}/${name}_$count.jpg';

          //     File(debugPath).writeAsBytesSync(alignedBytes);

          //     debugPrint(
          //       "📸 [Debug] Đã lưu crop của $name tại: .../debug_seeder/",
          //     );
          //   }
          // } catch (e) {
          //   debugPrint("⚠️ Lỗi lưu debug: $e");
          // }

          // img.Image? imgForAi = img.decodeImage(alignedBytes);

          // if (imgForAi != null) {
          //   // Lấy Vector
          //   List<double> emb = _aiService.generateEmbedding(imgForAi);

          //   // Lưu vào map tạm
          //   if (!tempMapEmbeddings.containsKey(name)) {
          //     tempMapEmbeddings[name] = [];
          //   }
          //   tempMapEmbeddings[name]!.add(emb);
          // }

          // 2. Tạo embedding bằng hàm HWC chuẩn
          List<double> emb = _aiService.generateEmbedding(alignedMat);

          // 3. Lưu
          if (!tempMapEmbeddings.containsKey(name)) {
            tempMapEmbeddings[name] = [];
          }
          tempMapEmbeddings[name]!.add(emb);

          alignedMat.dispose();
        }
      }
    } catch (e) {
      debugPrint("⚠️ Lỗi xử lý ảnh: $e");
    } finally {
      // Dọn dẹp bộ nhớ ngay lập tức
      if (smallPath != null) {
        try {
          await File(smallPath).delete();
        } catch (_) {}
      }
      // Nghỉ 50ms để Garbage Collector kịp dọn RAM trước khi qua ảnh tiếp theo
      // Đây là bí quyết để không bị OOM khi chạy vòng lặp lớn
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }

  Map<String, double> _validateDataQuality() {
    debugPrint("\n--- 🕵️ BẮT ĐẦU KIỂM TRA CHẤT LƯỢNG DỮ LIỆU ---");

    double totalIntraSim = 0;
    int intraCount = 0;

    // 1. KIỂM TRA ĐỘ ỔN ĐỊNH (Cùng 1 người, các ảnh có giống nhau không?)
    tempMapEmbeddings.forEach((name, embeddings) {
      if (embeddings.length < 2) {
        debugPrint("⚠️ $name: Chỉ có 1 ảnh -> Không thể kiểm tra độ ổn định.");
        return;
      }

      double currentPersonSim = 0;
      int count = 0;

      // So sánh từng cặp ảnh của cùng 1 người
      for (int i = 0; i < embeddings.length - 1; i++) {
        for (int j = i + 1; j < embeddings.length; j++) {
          double sim = _cosineSimilarity(embeddings[i], embeddings[j]);
          currentPersonSim += sim;
          count++;
        }
      }

      double avgSim = currentPersonSim / count;
      totalIntraSim += avgSim;
      intraCount++;

      // ĐÁNH GIÁ (Thang điểm Cosine):
      // > 0.8: Tuyệt vời (Rất giống nhau)
      // 0.6 - 0.8: Ổn
      // < 0.6: Cảnh báo (Ảnh cùng 1 người mà nhìn khác nhau quá)
      String quality = avgSim > 0.8
          ? "✅ Tốt"
          : (avgSim > 0.6 ? "⚠️ Tạm" : "❌ KHÔNG ỔN ĐỊNH");
      debugPrint(
        "👤 $name ($count cặp ảnh): Trung bình sai số = ${avgSim.toStringAsFixed(3)} -> $quality",
      );
    });

    double avgIntra = intraCount > 0 ? totalIntraSim / intraCount : 0.0;

    if (intraCount > 0) {
      debugPrint(
        "=> Sai số nội bộ trung bình toàn data: ${avgIntra.toStringAsFixed(3)}",
      );
    }

    // 2. KIỂM TRA ĐỘ PHÂN BIỆT (Người A có khác người B không?)
    debugPrint("\n--- ⚔️ KIỂM TRA PHÂN BIỆT GIỮA CÁC NGƯỜI DÙNG ---");
    List<String> names = tempMapEmbeddings.keys.toList();

    // Tính vector trung bình tạm thời để so sánh
    Map<String, List<double>> means = {};
    tempMapEmbeddings.forEach((k, v) => means[k] = _calculateMean(v));

    double totalInterSim = 0;
    int interCount = 0;

    for (int i = 0; i < names.length - 1; i++) {
      for (int j = i + 1; j < names.length; j++) {
        String u1 = names[i];
        String u2 = names[j];
        double sim = _cosineSimilarity(means[u1]!, means[u2]!);

        totalInterSim += sim;
        interCount++;

        String statusIcon;
        String note = "";

        // ĐÁNH GIÁ (Thang điểm Cosine):
        // > 0.6: NGUY HIỂM (Hai người lạ mà giống nhau > 60%)
        // 0.4 - 0.6: Hơi giống
        // < 0.4: Tốt (Khác biệt rõ ràng)
        if (sim > 0.6) {
          statusIcon = "❌ NGUY HIỂM";
          note = "(Dễ nhận nhầm)";
        } else if (sim > 0.4) {
          statusIcon = "⚠️ Hơi giống";
          note = "(Cẩn thận)";
        } else {
          statusIcon = "✅ Tốt";
        }

        // IN RA TẤT CẢ CÁC CẶP (Theo yêu cầu của bạn)
        debugPrint(
          "$statusIcon $u1 vs $u2: Sim = ${sim.toStringAsFixed(3)} $note",
        );
      }
    }

    double avgInter = interCount > 0 ? totalInterSim / interCount : 0.0;

    // --- PHẦN BỔ SUNG ĐỂ HẾT LỖI VÀ BÁO CÁO TỔNG QUAN ---
    if (interCount > 0) {
      debugPrint("--------------------------------------------------");
      debugPrint(
        "=> Khoảng cách tách biệt trung bình: ${avgInter.toStringAsFixed(3)}",
      );

      // Margin = (Giống nội bộ) - (Giống chéo). Càng lớn càng tốt.
      double margin = avgIntra - avgInter;

      if (margin > 0.4) {
        debugPrint(
          "🌟 TỔNG KẾT: Model phân biệt RẤT TỐT! (Margin: ${margin.toStringAsFixed(2)})",
        );
      } else if (margin > 0.2) {
        debugPrint("✅ TỔNG KẾT: Model hoạt động ỔN.");
      } else {
        debugPrint("⚠️ TỔNG KẾT: Cảnh báo, dữ liệu khó phân biệt.");
      }
    }
    debugPrint("--------------------------------------------------\n");

    return {
      "intra_sim": avgIntra,
      "inter_sim": avgInter,
      "quality_score": avgIntra - avgInter, // Điểm chất lượng
    };
  }

  // --- HÀM TÍNH COSINE SIMILARITY (Thay thế Euclidean) ---
  // Công thức: A . B (Vì vector đã được normalize độ dài = 1)
  double _cosineSimilarity(List<double> v1, List<double> v2) {
    double dot = 0.0;
    for (int i = 0; i < v1.length; i++) {
      dot += v1[i] * v2[i];
    }
    return dot;
  }

  // // Copy lại hàm tính khoảng cách vào đây nếu chưa có
  // double _euclideanDistance(List<double> v1, List<double> v2) {
  //   double sum = 0;
  //   for (int i = 0; i < v1.length; i++) {
  //     sum += math.pow((v1[i] - v2[i]), 2);
  //   }
  //   return math.sqrt(sum);
  // }

  // Hàm gửi JSON về Server Dart trên PC
  Future<void> _sendToServer(
    String jsonString, {
    String filename = "face_db.json",
  }) async {
    debugPrint("📡 Đang gửi dữ liệu về máy tính...");
    try {
      // SỬA IP TẠI ĐÂY (Dùng ipconfig trên PC để xem)
      String serverUrl = "http://192.168.0.186:5000/upload-json";

      var response = await http.post(
        Uri.parse(serverUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "filename": filename, // Gửi tên file lên server
          "content": jsonString,
        }),
      );

      if (response.statusCode == 200) {
        debugPrint(
          "🎉 THÀNH CÔNG! File face_db.json đã nằm trong assets máy tính.",
        );
      } else {
        debugPrint("⚠️ Server lỗi: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("❌ Không kết nối được: $e");
      debugPrint(
        "👉 Kiểm tra lại IP máy tính và đảm bảo Server Dart đang chạy.",
      );
    }
  }

  // Hàm phụ: Tính trung bình
  List<double> _calculateMean(List<List<double>> embeddings) {
    int dim = embeddings[0].length;
    List<double> mean = List.filled(dim, 0.0);
    for (var emb in embeddings) {
      for (int i = 0; i < dim; i++) {
        mean[i] += emb[i];
      }
    }
    for (int i = 0; i < dim; i++) {
      mean[i] /= embeddings.length;
    }
    return mean;
  }

  // // Hàm phụ: Asset -> File
  // Future<File> _assetToFile(String assetPath) async {
  //   final byteData = await rootBundle.load(assetPath);
  //   final tempDir = await getTemporaryDirectory();
  //   final tempFile = File('${tempDir.path}/${assetPath.split('/').last}');
  //   await tempFile.writeAsBytes(byteData.buffer.asUint8List());
  //   return tempFile;
  // }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Công cụ tạo dữ liệu FaceDB")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isProcessing) const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              _status,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _startSeeding,
              icon: const Icon(Icons.engineering),
              label: const Text("Bắt đầu xử lý & Xuất JSON"),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
