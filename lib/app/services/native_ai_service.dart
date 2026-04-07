import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../app/services/log_service.dart';

class RecognitionResult {
  final String name;
  final double score;
  final bool isUnknown;
  final String matchedTemplateId;
  final String imposterName;
  final double imposterScore;

  RecognitionResult(
    this.name,
    this.score,
    this.isUnknown,
    this.matchedTemplateId,
    this.imposterName,
    this.imposterScore,
  );

  @override
  String toString() {
    return 'Tên: $name, Điểm: ${(score * 100).toStringAsFixed(1)}%, Lạ mặt: $isUnknown\n'
        'Template ID: $matchedTemplateId\n'
        'Imposter (Giống thứ 2): $imposterName, Điểm Imposter: ${(imposterScore * 100).toStringAsFixed(1)}%';
  }
}

// 1. Khởi tạo Model Face
typedef InitFaceModelC = Int32 Function(Pointer<Void> faceData, Int32 faceSize);
typedef InitFaceModelDart = int Function(Pointer<Void> faceData, int faceSize);

// Khởi tạo Model Spoofing
typedef InitSpoofModelC =
    Int32 Function(Pointer<Void> spoofData, Int32 spoofSize);
typedef InitSpoofModelDart =
    int Function(Pointer<Void> spoofData, int spoofSize);

// 2. Trích xuất Đặc trưng (Extract Embedding)
typedef ExtractFeatureC =
    Int32 Function(
      Pointer<Float> input,
      Int32 inputSize,
      Pointer<Float> output,
    );
typedef ExtractFeatureDart =
    int Function(Pointer<Float> input, int inputSize, Pointer<Float> output);

// 3. Quản lý Database trên RAM C++
typedef RegisterFaceC =
    Void Function(
      Pointer<Utf8> name,
      Pointer<Float> embedding,
      Int32 size,
      Pointer<Utf8> templateId,
    );
typedef RegisterFaceDart =
    void Function(
      Pointer<Utf8> name,
      Pointer<Float> embedding,
      int size,
      Pointer<Utf8> templateId,
    );

typedef ClearDatabaseC = Void Function();
typedef ClearDatabaseDart = void Function();

// 4. Dự đoán (Predict)
typedef PredictFaceC =
    Int32 Function(
      Pointer<Float> input,
      Int32 inputSize,
      Float threshold,
      Pointer<Utf8> outName,
      Pointer<Utf8> outTemplateId,
      Pointer<Utf8> outImposterName,
      Pointer<Float> outScore,
      Pointer<Float> outImposterScore,
    );
typedef PredictFaceDart =
    int Function(
      Pointer<Float> input,
      int inputSize,
      double threshold,
      Pointer<Utf8> outName,
      Pointer<Utf8> outTemplateId,
      Pointer<Utf8> outImposterName,
      Pointer<Float> outScore,
      Pointer<Float> outImposterScore,
    );

typedef PredictSpoofC = Float Function(Pointer<Float> input, Int32 inputSize);
typedef PredictSpoofDart = double Function(Pointer<Float> input, int inputSize);

typedef RemoveFaceC = Void Function(Pointer<Utf8> name);
typedef RemoveFaceDart = void Function(Pointer<Utf8> name);

// --- FACE QUALITY ---
typedef InitQualityModelC =
    Int32 Function(Pointer<Void> modelData, Int32 modelSize);
typedef InitQualityModelDart =
    int Function(Pointer<Void> modelData, int modelSize);

typedef PredictQualityC =
    Float Function(Pointer<Float> inputPixels, Int32 pixelsCount);
typedef PredictQualityDart =
    double Function(Pointer<Float> inputPixels, int pixelsCount);

class NativeAiService {
  static final NativeAiService _instance = NativeAiService._internal();
  factory NativeAiService() => _instance;
  NativeAiService._internal();

  late DynamicLibrary _dylib;

  late InitFaceModelDart _initFaceModelNative;
  late ExtractFeatureDart _extractFeatureNative;
  late RegisterFaceDart _registerFaceNative;
  late ClearDatabaseDart _clearDatabaseNative;
  late PredictFaceDart _predictFaceNative;
  late InitSpoofModelDart _initSpoofModelNative;
  late PredictSpoofDart _predictSpoofNative;
  late RemoveFaceDart _removeFaceNative;
  late InitQualityModelDart _initQualityModelNative;
  late PredictQualityDart _predictQualityNative;

  // Biến giữ vùng nhớ C++ không bị Dart gom rác (BẮT BUỘC PHẢI GIỮ)
  Pointer<Uint8>? _faceBuffer;
  Pointer<Uint8>? _spoofBuffer; // Buffer giữ model Spoofing trên RAM

  // 2. Thêm Buffer giữ model Quality trên RAM
  Pointer<Uint8>? _qualityBuffer;

  // Hàm phụ trợ đọc asset
  Future<Uint8List> _loadAssetBytes(String path) async {
    final byteData = await rootBundle.load(path);
    return byteData.buffer.asUint8List();
  }

  /// Mở thư viện và móc nối toàn bộ các hàm C++
  void _openLibrary() {
    // AppLog.info("🔗 Đang móc nối thư viện C++...");
    _dylib = DynamicLibrary.open('libnative_face_align.so');

    _initFaceModelNative = _dylib
        .lookupFunction<InitFaceModelC, InitFaceModelDart>('InitFaceModel');
    _extractFeatureNative = _dylib
        .lookupFunction<ExtractFeatureC, ExtractFeatureDart>(
          'ExtractFaceFeature',
        );
    _registerFaceNative = _dylib
        .lookupFunction<RegisterFaceC, RegisterFaceDart>('RegisterFace');
    _clearDatabaseNative = _dylib
        .lookupFunction<ClearDatabaseC, ClearDatabaseDart>('ClearDatabase');
    _predictFaceNative = _dylib.lookupFunction<PredictFaceC, PredictFaceDart>(
      'PredictFaceNative',
    );
    _initSpoofModelNative = _dylib
        .lookupFunction<InitSpoofModelC, InitSpoofModelDart>('InitSpoofModel');
    _predictSpoofNative = _dylib
        .lookupFunction<PredictSpoofC, PredictSpoofDart>('PredictSpoofNative');
    _removeFaceNative = _dylib.lookupFunction<RemoveFaceC, RemoveFaceDart>(
      'RemoveFace',
    );
    _initQualityModelNative = _dylib
        .lookupFunction<InitQualityModelC, InitQualityModelDart>(
          'InitQualityModelNative',
        );
    _predictQualityNative = _dylib
        .lookupFunction<PredictQualityC, PredictQualityDart>(
          'PredictQualityNative',
        );
  }

  /// Khởi tạo Face Model từ thư mục Assets
  Future<int> initFaceModel(String modelPath) async {
    if (_faceBuffer != null) return 1; // Đã khởi tạo rồi thì bỏ qua

    try {
      _openLibrary();

      // 1. Đọc file .tflite thành byte
      final faceBytes = await _loadAssetBytes(modelPath);

      // 2. Cấp phát bộ nhớ không giải phóng (Để C++ dùng liên tục)
      _faceBuffer = calloc<Uint8>(faceBytes.length);
      _faceBuffer!.asTypedList(faceBytes.length).setAll(0, faceBytes);

      // 3. Gọi C++ khởi tạo Interpreter
      return _initFaceModelNative(_faceBuffer!.cast<Void>(), faceBytes.length);
    } catch (e) {
      AppLog.error("❌ Lỗi FFI Init Face Model: $e");
      return -1;
    }
  }

  /// Khởi tạo Anti-Spoofing Model
  Future<bool> initSpoofModel(String modelPath) async {
    if (_spoofBuffer != null) return true; // Đã khởi tạo rồi thì bỏ qua

    try {
      _openLibrary(); // Nếu dylib mở rồi thì nó không mở lại đâu, đừng lo

      final spoofBytes = await _loadAssetBytes(modelPath);

      _spoofBuffer = calloc<Uint8>(spoofBytes.length);
      _spoofBuffer!.asTypedList(spoofBytes.length).setAll(0, spoofBytes);

      final int encodedDims = _initSpoofModelNative(
        _spoofBuffer!.cast<Void>(),
        spoofBytes.length,
      );

      if (encodedDims > 0) {
        // 👉 GIẢI MÃ: Lấy 16 bit đầu làm Width, 16 bit sau làm Height
        int inputWidth = encodedDims >> 16;
        int inputHeight = encodedDims & 0xFFFF;

        AppLog.info(
          "🛡️ Nạp Anti-Spoof Model thành công! Auto Config: ${inputWidth}x$inputHeight",
        );
        return true;
      } else {
        AppLog.error("❌ C++ nạp Anti-Spoof Model thất bại!");
        return false;
      }
    } catch (e) {
      AppLog.error("❌ Lỗi FFI Init Anti-Spoof Model: $e");
      return false;
    }
  }

  /// Trích xuất Vector đặc trưng (192 chiều) từ mảng Pixel ảnh
  List<double>? getEmbeddingFromC(List<double> inputPixels) {
    // 1. Chép mảng pixel ảnh sang C++
    final inputPointer = calloc<Float>(inputPixels.length);
    inputPointer.asTypedList(inputPixels.length).setAll(0, inputPixels);

    // Cấp phát buffer 192 chiều để hứng kết quả
    final outputPointer = calloc<Float>(192);

    // 3. Chạy hàm C++
    final result = _extractFeatureNative(
      inputPointer,
      inputPixels.length,
      outputPointer,
    );

    List<double>? embedding;
    if (result == 1) {
      // Đọc dữ liệu C++ đã điền vào
      embedding = outputPointer.asTypedList(192).toList();
    }

    // Dọn rác
    calloc.free(inputPointer);
    calloc.free(outputPointer);

    return embedding;
  }

  /// Bơm 1 khuôn mặt vào RAM của C++
  void addFaceToNative(String name, List<double> embedding, String templateId) {
    // Chuyển String Dart thành char* C++
    final nativeName = name.toNativeUtf8();
    final nativeTemplateId = templateId.toNativeUtf8();

    // Cấp phát bộ nhớ C++ và copy List<double> sang Float*
    final pointer = calloc<Float>(embedding.length);
    pointer.asTypedList(embedding.length).setAll(0, embedding);

    // Gửi xuống C++
    _registerFaceNative(
      nativeName,
      pointer,
      embedding.length,
      nativeTemplateId,
    );

    // BẮT BUỘC DỌN RÁC (Tránh rò rỉ RAM)
    calloc.free(nativeName);
    calloc.free(nativeTemplateId);
    calloc.free(pointer);
  }

  RecognitionResult predictFace(List<double> inputPixels, double threshold) {
    // 1. Chuẩn bị ảnh đầu vào
    final inputPtr = calloc<Float>(inputPixels.length);
    inputPtr.asTypedList(inputPixels.length).setAll(0, inputPixels);

    // 2. Chuẩn bị 2 THÙNG RỖNG để hứng Tên và Điểm
    final outNamePtr = calloc<Uint8>(256).cast<Utf8>(); // Cấp 256 byte cho Tên
    final outTemplateIdPtr = calloc<Uint8>(256).cast<Utf8>(); // Thêm
    final outImposterNamePtr = calloc<Uint8>(256).cast<Utf8>();
    final outScorePtr = calloc<Float>(1); // Cấp 1 ô Float cho Điểm
    final outImposterScorePtr = calloc<Float>(1);

    // 3. Chuyển cho C++ xử lý (C++ sẽ ghi đè dữ liệu vào 2 thùng này)
    final status = _predictFaceNative(
      inputPtr,
      inputPixels.length,
      threshold,
      outNamePtr,
      outTemplateIdPtr,
      outImposterNamePtr,
      outScorePtr,
      outImposterScorePtr,
    );

    RecognitionResult result;
    if (status == 0) {
      result = RecognitionResult("Error", 0.0, true, "", "Unknown", 0.0);
    } else {
      // 4. Mở thùng lấy dữ liệu
      final name = outNamePtr.toDartString();
      final score = outScorePtr.value;
      final isUnknown = (status == 2);
      final matchedTemplateId = outTemplateIdPtr.toDartString();
      final imposterName = outImposterNamePtr.toDartString();
      final imposterScore = outImposterScorePtr.value;

      result = RecognitionResult(
        name,
        score,
        isUnknown,
        matchedTemplateId,
        imposterName,
        imposterScore,
      );
    }

    // Bắt buộc dọn rác
    calloc.free(inputPtr);
    calloc.free(outNamePtr);
    calloc.free(outTemplateIdPtr);
    calloc.free(outImposterNamePtr);
    calloc.free(outScorePtr);
    calloc.free(outImposterScorePtr);

    return result;
  }

  double predictSpoof(List<double> inputPixels) {
    // Ép mảng List<double> xuống Float Pointer C++
    final inputPtr = calloc<Float>(inputPixels.length);
    inputPtr.asTypedList(inputPixels.length).setAll(0, inputPixels);

    // Bắn qua C++
    final score = _predictSpoofNative(inputPtr, inputPixels.length);

    // Bắt buộc dọn rác
    calloc.free(inputPtr);

    return score;
  }

  // ===========================================================================
  // FACE QUALITY FUNCTIONS
  // ===========================================================================

  /// Đọc file .tflite và ném con trỏ byte xuống C++
  Future<bool> initQualityModel(String modelPath) async {
    try {
      final bytes = await _loadAssetBytes(modelPath);

      // Cấp phát vùng nhớ không bị Dart quản lý
      _qualityBuffer = calloc<Uint8>(bytes.length);
      _qualityBuffer!.asTypedList(bytes.length).setAll(0, bytes);

      // Truyền con trỏ xuống C++
      final int encodedDims = _initQualityModelNative(
        _qualityBuffer!.cast<Void>(),
        bytes.length,
      );

      if (encodedDims > 0) {
        // 👉 GIẢI MÃ: Lấy 16 bit đầu làm Width, 16 bit sau làm Height
        int inputWidth = encodedDims >> 16;
        int inputHeight = encodedDims & 0xFFFF;

        AppLog.info(
          "🛡️ Nạp Quality Model thành công! Auto Config: ${inputWidth}x$inputHeight",
        );
        return true;
      } else {
        AppLog.error("❌ C++ nạp Quality Model thất bại!");
        return false;
      }
    } catch (e) {
      AppLog.error("❌ Lỗi nạp Quality Model: $e");
      return false;
    }
  }

  /// Ném mảng pixel ảnh xuống C++ để tính toán
  double predictQuality(List<double> inputPixels) {
    // Ép mảng List<double> xuống Float Pointer C++
    final inputPtr = calloc<Float>(inputPixels.length);
    inputPtr.asTypedList(inputPixels.length).setAll(0, inputPixels);

    // Bắn qua C++
    final score = _predictQualityNative(inputPtr, inputPixels.length);

    // Bắt buộc dọn rác cho mảng ảnh (vì gọi liên tục)
    calloc.free(inputPtr);

    return score;
  }

  /// Dọn sạch RAM C++ (Khi user đăng xuất hoặc xóa Database)
  void clearNativeDatabase() {
    _clearDatabaseNative();
  }

  void removeFaceFromNative(String name) {
    final nativeName = name.toNativeUtf8();
    _removeFaceNative(nativeName);
    calloc.free(nativeName); // Nhớ dọn rác
  }

  // Nhớ giải phóng bộ nhớ khi tắt app
  void dispose() {
    if (_faceBuffer != null) {
      calloc.free(_faceBuffer!);
      _faceBuffer = null;
    }
    if (_spoofBuffer != null) calloc.free(_spoofBuffer!);
  }
}
