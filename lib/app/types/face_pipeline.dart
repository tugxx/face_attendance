import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../services/log_service.dart';
import '../../data/models/registration_result.dart';

class FaceProcessRequest {
  final Uint8List yuvBytes;
  final int width;
  final int height;
  final Face face;
  final int sensorOrientation;
  final bool isAndroid;
  final RootIsolateToken? rootToken;

  FaceProcessRequest({
    required this.yuvBytes,
    required this.width,
    required this.height,
    required this.face,
    required this.sensorOrientation,
    required this.isAndroid,
    required this.rootToken,
  });
}

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

// ==========================================================
// 1. ĐỊNH NGHĨA CÁC HÀM C++ (FFI TYPES)
// ==========================================================

// A. Cho Camera (Nhận YUV Bytes)
typedef ProcessFaceAffineFunc =
    Void Function(
      Pointer<Uint8> yuvBytes,
      Int32 width,
      Int32 height,
      Pointer<Float> landmarks, // Mảng 10 phần tử
      Int32 rotation,
      Pointer<Float> output,
    );

// Định nghĩa kiểu hàm Dart
typedef ProcessFaceAffineDart =
    void Function(
      Pointer<Uint8> yuvBytes,
      int width,
      int height,
      Pointer<Float> landmarks,
      int rotation,
      Pointer<Float> output,
    );

// B. Cho File Ảnh (Nhận File Path String)
typedef ProcessFileRawFunc =
    Void Function(
      Pointer<Utf8> filePath,
      Pointer<Float> landmarks,
      Pointer<Float> output,
    );

typedef ProcessFileRawDart =
    void Function(
      Pointer<Utf8> filePath,
      Pointer<Float> landmarks,
      Pointer<Float> output,
    );
typedef ProcessFaceNative =
    Void Function(
      Pointer<Uint8> ptrYuv,
      Int32 width,
      Int32 height,
      Int32 yStride,
      Int32 rectX,
      Int32 rectY,
      Int32 rectW,
      Int32 rectH,
      Int32 rotation,
      Int32 targetWidth,
      Int32 targetHeight,
      Pointer<Float> output,
    );

typedef ProcessFaceDart =
    void Function(
      Pointer<Uint8> ptrYuv,
      int width,
      int height,
      int yStride,
      int rectX,
      int rectY,
      int rectW,
      int rectH,
      int rotation,
      int targetWidth,
      int targetHeight,
      Pointer<Float> output,
    );

typedef ProcessFrameNativeC =
    Int32 Function(
      Int64 sessionHandle,
      Pointer<Uint8> yuvData,
      Int32 width,
      Int32 height,
      Pointer<Float> landmarks,
      Int32 rotation,
      Int32 rectX,
      Int32 rectY,
      Int32 rectW,
      Int32 rectH,
      Float recognitionThreshold,
      Float spoofThreshold,
      Float qualityThreshold,
      Pointer<Utf8> outName,
      Pointer<Utf8> outTemplateId,
      Pointer<Utf8> outImposterName,
      Pointer<Float> outScore,
      Pointer<Float> outImposterScore,
      Pointer<Float> outSpoofScore,
      Pointer<Float> outQualityScore,
      Pointer<Bool> outIsRealPtr,
    );

typedef ProcessFrameNativeDart =
    int Function(
      int sessionHandle,
      Pointer<Uint8> yuvData,
      int width,
      int height,
      Pointer<Float> landmarks,
      int rotation,
      int rectX,
      int rectY,
      int rectW,
      int rectH,
      double recognitionThreshold,
      double spoofThreshold,
      double qualityThreshold,
      Pointer<Utf8> outName,
      Pointer<Utf8> outTemplateId,
      Pointer<Utf8> outImposterName,
      Pointer<Float> outScore,
      Pointer<Float> outImposterScore,
      Pointer<Float> outSpoofScore,
      Pointer<Float> outQualityScore,
      Pointer<Bool> outIsRealPtr,
    );

typedef ProcessRegistrationC =
    Int32 Function(
      Int64 sessionHandle,
      Pointer<Uint8> yuvData,
      Int32 width,
      Int32 height,
      Pointer<Float> landmarks,
      Int32 rotation,
      Pointer<Float> outAiPixels,
      Pointer<Uint8> outJpgBytes,
      Pointer<Int32> outJpgSize,
    );

typedef ProcessRegistrationDart =
    int Function(
      int sessionHandle,
      Pointer<Uint8> yuvData,
      int width,
      int height,
      Pointer<Float> landmarks,
      int rotation,
      Pointer<Float> outAiPixels,
      Pointer<Uint8> outJpgBytes,
      Pointer<Int32> outJpgSize,
    );

typedef EncodeJpegC =
    Int32 Function(
      Int64 sessionHandle,
      Pointer<Uint8> yuvData,
      Int32 width,
      Int32 height,
      Int32 rotation,
      Pointer<Pointer<Uint8>> outJpegData,
      Pointer<Int32> outJpegSize,
    );

typedef EncodeJpegDart =
    int Function(
      int sessionHandle,
      Pointer<Uint8> yuvData,
      int width,
      int height,
      int rotation,
      Pointer<Pointer<Uint8>> outJpegData,
      Pointer<Int32> outJpegSize,
    );

typedef FreeMemoryC = Void Function(Pointer<Void> ptr);

typedef FreeMemoryDart = void Function(Pointer<Void> ptr);

typedef ProcessQualityC =
    Float Function(
      Int64 sessionHandle,
      Pointer<Uint8> yuvData,
      Int32 width,
      Int32 height,
      Int32 rotation,
      Int32 rectX,
      Int32 rectY,
      Int32 rectW,
      Int32 rectH,
    );
typedef ProcessQualityDart =
    double Function(
      int sessionHandle,
      Pointer<Uint8> yuvData,
      int width,
      int height,
      int rotation,
      int rectX,
      int rectY,
      int rectW,
      int rectH,
    );

typedef CreateFacePipelineSessionC =
    Int64 Function(
      Pointer<Void> recogModel,
      Int32 recogSize,
      Pointer<Void> spoofModel,
      Int32 spoofSize,
      Pointer<Void> qualityModel,
      Int32 qualitySize,
    );

typedef CreateFacePipelineSessionDart =
    int Function(
      Pointer<Void> recogModel,
      int recogSize,
      Pointer<Void> spoofModel,
      int spoofSize,
      Pointer<Void> qualityModel,
      int qualitySize,
    );

typedef DestroyFacePipelineSessionC = Void Function(Int64 sessionHandle);
typedef DestroyFacePipelineSessionDart = void Function(int sessionHandle);

typedef AddFaceNativeSessionC =
    Void Function(
      Int64 sessionHandle,
      Pointer<Utf8> name,
      Pointer<Float> embedding,
      Int32 size,
      Pointer<Utf8> templateId,
    );
typedef AddFaceNativeSessionDart =
    void Function(
      int sessionHandle,
      Pointer<Utf8> name,
      Pointer<Float> embedding,
      int size,
      Pointer<Utf8> templateId,
    );

typedef _PredictFromPixelsC =
    Int32 Function(
      Int64 sessionHandle,
      Pointer<Float> inputPixels,
      Int32 pixelsCount,
      Float threshold,
      Pointer<Utf8> outName,
      Pointer<Utf8> outTemplateId,
      Pointer<Utf8> outImposterName,
      Pointer<Float> outScore,
      Pointer<Float> outImposterScore,
    );
typedef _PredictFromPixelsDart =
    int Function(
      int sessionHandle,
      Pointer<Float> inputPixels,
      int pixelsCount,
      double threshold,
      Pointer<Utf8> outName,
      Pointer<Utf8> outTemplateId,
      Pointer<Utf8> outImposterName,
      Pointer<Float> outScore,
      Pointer<Float> outImposterScore,
    );

typedef _ExtractFeatureC =
    Int32 Function(
      Int64 sessionHandle,
      Pointer<Float> inputPixels,
      Int32 pixelsCount,
      Pointer<Float> outFeature,
    );

// 2. Chữ ký Dart
typedef _ExtractFeatureDart =
    int Function(
      int sessionHandle,
      Pointer<Float> inputPixels,
      int pixelsCount,
      Pointer<Float> outFeature,
    );

// ==========================================================
// 2. CLASS GIAO TIẾP VỚI NATIVE
// ==========================================================

class FaceImagePipelineNative {
  static DynamicLibrary? _lib;

  static ProcessFileRawDart? _funcFile;

  static ProcessFrameNativeDart? _funcProcessFrame;

  static ProcessRegistrationDart? _funcProcessRegistration;

  static EncodeJpegDart? _funcEncodeJpeg;

  static FreeMemoryDart? _funcFreeMemoryNative;

  static ProcessQualityDart? _funcProcessQuality;

  static CreateFacePipelineSessionDart? _funcCreateSession;

  static DestroyFacePipelineSessionDart? _funcDestroySession;

  static AddFaceNativeSessionDart? _addFaceNativeSession;

  static _PredictFromPixelsDart? _predictFromPixelsNative;

  static _ExtractFeatureDart? _extractFeatureNative;

  static final Map<int, Pointer<Uint8>> _sessionBuffers = {};

  static void init() {
    if (_lib != null) return;

    // Tên thư viện phải khớp với CMakeLists (native_face)
    final libName = Platform.isAndroid
        ? 'libnative_face_align.so'
        : 'native_face_align.framework/native_face_align';

    try {
      _lib = DynamicLibrary.open(libName);
      try {
        _funcFile = _lib!
            .lookup<NativeFunction<ProcessFileRawFunc>>(
              'process_file_affine_raw',
            )
            .asFunction();
      } catch (_) {
        AppLog.error("⚠️ Missing process_file_affine_raw");
      }

      try {
        _funcProcessFrame = _lib!
            .lookupFunction<ProcessFrameNativeC, ProcessFrameNativeDart>(
              'ProcessFrameNative',
            );
      } catch (_) {
        AppLog.error("⚠️ Missing spoofing");
      }

      try {
        _funcProcessRegistration = _lib!
            .lookupFunction<ProcessRegistrationC, ProcessRegistrationDart>(
              'ProcessRegistrationNative',
            );
      } catch (e) {
        AppLog.error("⚠️ Missing ProcessRegistrationNative: $e");
      }

      try {
        _funcEncodeJpeg = _lib!.lookupFunction<EncodeJpegC, EncodeJpegDart>(
          'EncodeFullFrameToJpegNative',
        );
      } catch (_) {
        AppLog.error("⚠️ Không tìm thấy hàm EncodeFullFrameToJpeg trong C++");
      }

      try {
        _funcFreeMemoryNative = _lib!
            .lookupFunction<FreeMemoryC, FreeMemoryDart>('FreeMemoryNative');
      } catch (e) {
        AppLog.error("⚠️ Không tìm thấy FreeMemoryNative: $e");
      }

      try {
        _funcProcessQuality = _lib!
            .lookupFunction<ProcessQualityC, ProcessQualityDart>(
              'ProcessQualityNative',
            );
      } catch (e) {
        AppLog.error("⚠️ Không tìm thấy ProcessQualityNative: $e");
      }

      try {
        _funcCreateSession = _lib!
            .lookupFunction<
              CreateFacePipelineSessionC,
              CreateFacePipelineSessionDart
            >('CreateFacePipelineSession');
      } catch (e) {
        AppLog.error("⚠️ Missing CreateFacePipelineSession: $e");
      }

      try {
        _funcDestroySession = _lib!
            .lookupFunction<
              DestroyFacePipelineSessionC,
              DestroyFacePipelineSessionDart
            >('DestroyFacePipelineSession');
      } catch (e) {
        AppLog.error("⚠️ Missing DestroyFacePipelineSession: $e");
      }

      try {
        _addFaceNativeSession = _lib!
            .lookupFunction<AddFaceNativeSessionC, AddFaceNativeSessionDart>(
              'AddFaceToNativeSession',
            );
      } catch (e) {
        AppLog.error("⚠️ Missing AddFaceToNativeSession: $e");
      }

      try {
        _predictFromPixelsNative = _lib!
            .lookup<NativeFunction<_PredictFromPixelsC>>(
              'PredictFromPixelsNative',
            )
            .asFunction<_PredictFromPixelsDart>();
      } catch (e) {
        AppLog.error("⚠️ Missing PredictFromPixelsNative: $e");
      }

      try {
        _extractFeatureNative = _lib!
            .lookup<NativeFunction<_ExtractFeatureC>>('ExtractFeatureNative')
            .asFunction<_ExtractFeatureDart>();
      } catch (e) {
        AppLog.error("⚠️ Missing ExtractFeatureNative: $e");
      }
    } catch (e) {
      AppLog.error("❌ Lỗi load thư viện C++: $e");
    }
  }

  // --------------------------------------------------------
  // HELPER: Convert Landmarks từ ML Kit -> Mảng Float C++
  // --------------------------------------------------------
  static Pointer<Float>? _convertLandmarks(Face face) {
    final lm = face.landmarks;
    final leftEye = lm[FaceLandmarkType.leftEye]?.position;
    final rightEye = lm[FaceLandmarkType.rightEye]?.position;

    // Yêu cầu tối thiểu phải có 2 mắt để tính góc xoay
    if (leftEye == null || rightEye == null) return null;

    final ptr = calloc<Float>(10);
    final list = ptr.asTypedList(10);

    list[0] = leftEye.x.toDouble();
    list[1] = leftEye.y.toDouble();
    list[2] = rightEye.x.toDouble();
    list[3] = rightEye.y.toDouble();

    // Các điểm phụ (nếu có)
    final nose = lm[FaceLandmarkType.noseBase]?.position;
    if (nose != null) {
      list[4] = nose.x.toDouble();
      list[5] = nose.y.toDouble();
    }

    final lMouth = lm[FaceLandmarkType.leftMouth]?.position;
    if (lMouth != null) {
      list[6] = lMouth.x.toDouble();
      list[7] = lMouth.y.toDouble();
    }

    final rMouth = lm[FaceLandmarkType.rightMouth]?.position;
    if (rMouth != null) {
      list[8] = rMouth.x.toDouble();
      list[9] = rMouth.y.toDouble();
    }

    return ptr;
  }

  static RegistrationResult? processRegistration({
    required int sessionHandle,
    required Pointer<Uint8> ptrYuv,
    required int width,
    required int height,
    required List<double> landmarks, // Nhận mảng số thực giống hệt Dual Task
    required int rotation,
    required int recogPixelSize,
  }) {
    if (_funcProcessRegistration == null) init();

    // 1. Chuyển List<double> landmarks thành Pointer<Float> cho C++
    final Pointer<Float> ptrLandmarks = calloc<Float>(10);
    ptrLandmarks.asTypedList(10).setAll(0, landmarks);

    // Cấp 3 thùng chứa
    final outAiPixels = calloc<Float>(recogPixelSize);
    final outJpgBuffer = calloc<Uint8>(50000);
    final outJpgSize = calloc<Int32>(1);

    try {
      final status = _funcProcessRegistration!(
        sessionHandle,
        ptrYuv,
        width,
        height,
        ptrLandmarks,
        rotation,
        outAiPixels,
        outJpgBuffer,
        outJpgSize,
      );

      if (status == 0) return null;

      // Hốt dữ liệu mang về
      final aiList = Float32List.fromList(
        outAiPixels.asTypedList(112 * 112 * 3),
      );
      final jpgBytes = Uint8List.fromList(
        outJpgBuffer.asTypedList(outJpgSize.value),
      );

      return RegistrationResult(aiList, jpgBytes);
    } catch (e) {
      AppLog.error("Native Error: $e");
      return null;
    } finally {
      calloc.free(ptrLandmarks);
      calloc.free(outAiPixels);
      calloc.free(outJpgBuffer);
      calloc.free(outJpgSize);
    }
  }

  static List<double>? processFile(String filePath, Face face) {
    if (_funcFile == null) init();
    if (_funcFile == null) return null;

    final ptrLandmarks = _convertLandmarks(face);
    if (ptrLandmarks == null) return null;

    // Convert String Path -> C String (Utf8)
    final Pointer<Utf8> ptrPath = filePath.toNativeUtf8();

    final int outLen = 112 * 112 * 3;
    final Pointer<Float> ptrOut = calloc<Float>(outLen);

    try {
      // 🔥 GỌI C++ (STB_IMAGE)
      _funcFile!(ptrPath, ptrLandmarks, ptrOut);

      final Float32List result = ptrOut.asTypedList(outLen);
      return List<double>.from(result);
    } catch (e) {
      AppLog.error("Native File Error: $e");
      return null;
    } finally {
      calloc.free(ptrPath);
      calloc.free(ptrLandmarks);
      calloc.free(ptrOut);
    }
  }

  static int createFacePipelineSession({
    required Uint8List recogBytes,
    required Uint8List spoofBytes,
    required Uint8List qualityBytes,
  }) {
    if (_funcCreateSession == null) init();

    // 1. Tính tổng kích thước miếng đất
    final totalSize =
        recogBytes.length + spoofBytes.length + qualityBytes.length;

    // 2. Xin ĐÚNG 1 MIẾNG ĐẤT TO (Contiguous Memory)
    final sessionBufferPtr = calloc<Uint8>(totalSize);

    // Tạo một List ảo để ghi đè dữ liệu vào miếng đất này
    final bufferView = sessionBufferPtr.asTypedList(totalSize);

    // Lô 1: Nạp Face (Bắt đầu từ index 0)
    bufferView.setAll(0, recogBytes);
    final recogPtr = sessionBufferPtr;

    // Lô 2: Nạp Spoof (Bắt đầu từ vị trí ngay sau Face)
    final spoofOffset = recogBytes.length;
    if (spoofBytes.isNotEmpty) {
      bufferView.setAll(spoofOffset, spoofBytes);
    }
    final spoofPtr = sessionBufferPtr + spoofOffset;

    // Lô 3: Nạp Quality (Bắt đầu từ vị trí ngay sau Spoof)
    final qualityOffset = spoofOffset + spoofBytes.length;
    bufferView.setAll(qualityOffset, qualityBytes);
    final qualityPtr = sessionBufferPtr + qualityOffset;

    // 2. Gọi xuống C++
    final handle = _funcCreateSession!(
      recogPtr.cast<Void>(),
      recogBytes.length,
      spoofPtr.cast<Void>(),
      spoofBytes.length,
      qualityPtr.cast<Void>(),
      qualityBytes.length,
    );

    // 3. Xử lý giữ mạng cho Pointer
    if (handle != 0) {
      // Nếu thành công, lưu vào Map để TFLite xài từ từ
      _sessionBuffers[handle] = sessionBufferPtr;
    } else {
      // Nếu thất bại (hết RAM), dọn dẹp ngay lập tức
      calloc.free(sessionBufferPtr);
      AppLog.error("❌ C++ trả về Handle = 0 (Lỗi khởi tạo)");
    }

    return handle;
  }

  static void destroyFacePipelineSession(int sessionHandle) {
    if (sessionHandle == 0) return;
    if (_funcDestroySession == null) init();

    // 1. Gọi C++ xóa Object (Delete FacePipeline)
    _funcDestroySession!(sessionHandle);

    // 2. Gọi Dart giải phóng 3 cục TFLite khổng lồ đã nạp
    if (_sessionBuffers.containsKey(sessionHandle)) {
      final sessionBufferPtr = _sessionBuffers[sessionHandle]!;

      if (sessionBufferPtr != nullptr) {
        calloc.free(sessionBufferPtr);
      }
      _sessionBuffers.remove(sessionHandle);
      AppLog.info("🗑️ Đã giải phóng RAM cho Session: $sessionHandle");
    }
  }

  static Map<String, dynamic>? processDualTask({
    required int sessionHandle,
    required Pointer<Uint8> ptrYuv,
    required int width,
    required int height,
    required int yStride,
    required List<double> landmarks,
    required int rotation,
    required int rectX,
    required int rectY,
    required int rectW,
    required int rectH,
    required double recognitionThreshold,
    required double spoofThreshold,
    required double qualityThreshold,
  }) {
    if (sessionHandle == 0) {
      AppLog.error("LỖI: sessionHandle = 0, chưa khởi tạo C++ Session!");
      return null;
    }

    if (_funcProcessFrame == null) init();

    final ptrLandmarks = calloc<Float>(10);
    ptrLandmarks.asTypedList(10).setAll(0, landmarks);

    // Thùng rỗng hứng kết quả
    final outNamePtr = calloc<Uint8>(256).cast<Utf8>();
    final outTemplateIdPtr = calloc<Uint8>(256).cast<Utf8>();
    final outImposterNamePtr = calloc<Uint8>(256).cast<Utf8>();

    final outScorePtr = calloc<Float>(1);
    final outImposterScorePtr = calloc<Float>(1);

    final outSpoofPtr = calloc<Float>(1);
    final outQualityPtr = calloc<Float>(1);

    final outIsRealPtr = calloc<Bool>(1);

    try {
      final status = _funcProcessFrame!(
        sessionHandle,
        ptrYuv,
        width,
        height,
        ptrLandmarks,
        rotation,
        rectX,
        rectY,
        rectW,
        rectH,
        recognitionThreshold,
        spoofThreshold,
        qualityThreshold,
        outNamePtr,
        outTemplateIdPtr,
        outImposterNamePtr,
        outScorePtr,
        outImposterScorePtr,
        outSpoofPtr,
        outQualityPtr,
        outIsRealPtr,
      );

      if (status == 0) return null;

      final double qScore = outQualityPtr.value;
      if (status == 3) {
        return {'status': 'blurry', 'qualityScore': qScore};
      }

      final name = outNamePtr.toDartString();
      final templateId = outTemplateIdPtr.toDartString();
      final imposterName = outImposterNamePtr.toDartString();
      final isUnknown = (status == 2);

      // Trả về thông tin ngắn gọn
      return {
        'status': 'success',
        'name': name,
        'matchedTemplateId': templateId.isEmpty ? null : templateId,
        'score': outScorePtr.value,

        'imposterName': imposterName.isEmpty ? null : imposterName,
        'imposterScore': outImposterScorePtr.value,

        'isUnknown': isUnknown,
        'spoofScore': outSpoofPtr.value,
        'isRealPerson': outIsRealPtr.value,
        'qualityScore': qScore,
      };
    } finally {
      calloc.free(ptrLandmarks);
      calloc.free(outNamePtr);
      calloc.free(outTemplateIdPtr);
      calloc.free(outImposterNamePtr);
      calloc.free(outScorePtr);
      calloc.free(outImposterScorePtr);
      calloc.free(outSpoofPtr);
      calloc.free(outQualityPtr);
      calloc.free(outIsRealPtr);
    }
  }

  static Uint8List? encodeYuvToJpeg({
    required int sessionHandle,
    required Pointer<Uint8> ptrYuv,
    required int width,
    required int height,
    required int rotation,
  }) {
    if (_funcEncodeJpeg == null) init(); // Hoặc biến check init của bạn

    // Cấp phát 2 con trỏ rỗng để hứng dữ liệu từ C++ trả về
    final outJpegDataPtr = calloc<Pointer<Uint8>>();
    final outJpegSizePtr = calloc<Int32>();

    Pointer<Uint8> jpegPointer = nullptr;

    try {
      // 1. Gọi hàm C++ (Lúc này C++ sẽ nén ảnh và nhét data vào 2 con trỏ trên)
      final status = _funcEncodeJpeg!(
        sessionHandle,
        ptrYuv,
        width,
        height,
        rotation,
        outJpegDataPtr,
        outJpegSizePtr,
      );

      if (status != 1 || outJpegSizePtr.value <= 0) return null;

      // 2. Lấy kích thước và địa chỉ bộ nhớ chứa ảnh JPEG
      final size = outJpegSizePtr.value;
      final jpegPointer = outJpegDataPtr.value;

      // 3. Clone mảng byte từ C++ sang thế giới của Dart
      // Dùng Uint8List.fromList để copy đứt đoạn ra, an toàn 100%
      final dartJpegBytes = Uint8List.fromList(jpegPointer.asTypedList(size));

      return dartJpegBytes;
    } finally {
      if (jpegPointer != nullptr && _funcFreeMemoryNative != null) {
        _funcFreeMemoryNative!(jpegPointer.cast<Void>());
      }

      calloc.free(outJpegDataPtr);
      calloc.free(outJpegSizePtr);
    }
  }

  static double processQuality({
    required int sessionHandle,
    required Pointer<Uint8> ptrYuv,
    required int width,
    required int height,
    required int rotation,
    required int rectX,
    required int rectY,
    required int rectW,
    required int rectH,
  }) {
    if (_funcProcessQuality == null) init();
    try {
      return _funcProcessQuality!(
        sessionHandle,
        ptrYuv,
        width,
        height,
        rotation,
        rectX,
        rectY,
        rectW,
        rectH,
      );
    } catch (e) {
      AppLog.error("Lỗi Native Quality: $e");
      return -1.0;
    }
  }

  static void addFaceToNativeSession({
    required int sessionHandle,
    required String name,
    required List<double> embedding,
    required String templateId,
  }) {
    if (_addFaceNativeSession == null) init();

    // Chuyển String Dart thành char* C++
    final nativeName = name.toNativeUtf8();
    final nativeTemplateId = templateId.toNativeUtf8();

    // Cấp phát bộ nhớ C++ và copy List<double> sang Float*
    final pointer = calloc<Float>(embedding.length);
    pointer.asTypedList(embedding.length).setAll(0, embedding);

    // Gửi xuống C++
    _addFaceNativeSession!(
      sessionHandle,
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

  static RecognitionResult predictFromPixels({
    required int sessionHandle,
    required List<double> inputPixels,
    required double threshold,
  }) {
    if (_predictFromPixelsNative == null) init();

    if (sessionHandle == 0 || inputPixels.isEmpty) {
      return RecognitionResult("Error", 0.0, true, "", "Unknown", 0.0);
    }

    // 1. Chuẩn bị ảnh đầu vào (Làm việc với Pointer ở đây)
    final inputPtr = calloc<Float>(inputPixels.length);
    inputPtr.asTypedList(inputPixels.length).setAll(0, inputPixels);

    // 2. Chuẩn bị thùng chứa
    final outNamePtr = calloc<Uint8>(256).cast<Utf8>();
    final outTemplateIdPtr = calloc<Uint8>(256).cast<Utf8>();
    final outImposterNamePtr = calloc<Uint8>(256).cast<Utf8>();
    final outScorePtr = calloc<Float>(1);
    final outImposterScorePtr = calloc<Float>(1);

    try {
      final status = _predictFromPixelsNative!(
        sessionHandle,
        inputPtr,
        inputPixels.length,
        threshold,
        outNamePtr,
        outTemplateIdPtr,
        outImposterNamePtr,
        outScorePtr,
        outImposterScorePtr,
      );

      if (status == 1) {
        return RecognitionResult(
          outNamePtr.toDartString(),
          outScorePtr.value,
          false,
          outTemplateIdPtr.toDartString(),
          outImposterNamePtr.toDartString(),
          outImposterScorePtr.value,
        );
      } else {
        return RecognitionResult(
          "Unknown",
          outScorePtr.value,
          true,
          "",
          "",
          0.0,
        );
      }
    } catch (e) {
      AppLog.error("Lỗi khi Predict Native: $e");
      return RecognitionResult("Error", 0.0, true, "", "Unknown", 0.0);
    } finally {
      // 4. LUÔN LUÔN DỌN RÁC Ở ĐÂY (Dùng try-finally để đảm bảo an toàn tuyệt đối)
      calloc.free(inputPtr);
      calloc.free(outNamePtr);
      calloc.free(outTemplateIdPtr);
      calloc.free(outImposterNamePtr);
      calloc.free(outScorePtr);
      calloc.free(outImposterScorePtr);
    }
  }

  static List<double>? extractFeature({
    required int sessionHandle,
    required List<double> inputPixels,
  }) {
    // 1. Kiểm tra khởi tạo thư viện
    if (_extractFeatureNative == null) init();

    // 2. Guard Clause bảo vệ
    if (sessionHandle == 0 || inputPixels.isEmpty) return null;

    // 3. Cấp phát vùng nhớ cho C++ đọc (Dữ liệu đầu vào)
    final inputPointer = calloc<Float>(inputPixels.length);
    inputPointer.asTypedList(inputPixels.length).setAll(0, inputPixels);

    // 4. Cấp phát vùng nhớ cho C++ ghi (Dữ liệu đầu ra - 192 chiều)
    final outputPointer = calloc<Float>(192);

    try {
      // 5. Gọi hàm qua cầu nối FFI
      final status = _extractFeatureNative!(
        sessionHandle,
        inputPointer,
        inputPixels.length,
        outputPointer,
      );

      // 6. Đọc kết quả nếu thành công
      if (status == 1) {
        return outputPointer.asTypedList(192).toList();
      }

      return null; // Trả về null nếu AI báo lỗi bên C++
    } catch (e) {
      AppLog.error("❌ Lỗi khi Extract Feature Native: $e");
      return null;
    } finally {
      // 7. BẮT BUỘC DỌN RÁC (Chạy trong mọi trường hợp, dù lỗi hay không)
      calloc.free(inputPointer);
      calloc.free(outputPointer);
    }
  }
}
