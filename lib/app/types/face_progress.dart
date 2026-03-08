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
      Pointer<Uint8> yuvData,
      Int32 width,
      Int32 height,
      Pointer<Float> landmarks,
      Int32 rotation,
      Int32 rectX,
      Int32 rectY,
      Int32 rectW,
      Int32 rectH,
      Int32 spoofW,
      Int32 spoofH,
      Float threshold,
      Pointer<Utf8> outName,
      Pointer<Float> outDistance,
      Pointer<Float> outSpoofScore,
    );

typedef ProcessFrameNativeDart =
    int Function(
      Pointer<Uint8> yuvData,
      int width,
      int height,
      Pointer<Float> landmarks,
      int rotation,
      int rectX,
      int rectY,
      int rectW,
      int rectH,
      int spoofW,
      int spoofH,
      double threshold,
      Pointer<Utf8> outName,
      Pointer<Float> outDistance,
      Pointer<Float> outSpoofScore,
    );

typedef ProcessRegistrationC =
    Int32 Function(
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
      Pointer<Uint8> yuvData,
      int width,
      int height,
      Pointer<Float> landmarks,
      int rotation,
      Pointer<Float> outAiPixels,
      Pointer<Uint8> outJpgBytes,
      Pointer<Int32> outJpgSize,
    );

// ==========================================================
// 2. CLASS GIAO TIẾP VỚI NATIVE
// ==========================================================

class FaceProcessorNative {
  static DynamicLibrary? _lib;

  // static ProcessFaceAffineDart? _funcCamera;
  static ProcessFileRawDart? _funcFile;
  // static ProcessFaceDart? _funcSpoof;

  static ProcessFrameNativeDart? _funcProcessFrame;

  static ProcessRegistrationDart? _funcProcessRegistration;

  static void init() {
    if (_lib != null) return;
    // final sw = Stopwatch()..start(); // ⏱️ Bắt đầu đo

    // Tên thư viện phải khớp với CMakeLists (native_face)
    final libName = Platform.isAndroid
        ? 'libnative_face_align.so'
        : 'native_face_align.framework/native_face_align';

    try {
      _lib = DynamicLibrary.open(libName);

      // // Load hàm Camera
      // try {
      //   _funcCamera = _lib!
      //       .lookup<NativeFunction<ProcessFaceAffineFunc>>(
      //         'process_face_affine',
      //       )
      //       .asFunction();
      // } catch (_) {
      //   AppLog.error("⚠️ Missing process_face_affine");
      // }

      // Load hàm File (Mới)
      try {
        _funcFile = _lib!
            .lookup<NativeFunction<ProcessFileRawFunc>>(
              'process_file_affine_raw',
            )
            .asFunction();
      } catch (_) {
        AppLog.error("⚠️ Missing process_file_affine_raw");
      }

      // try {
      //   _funcSpoof = _lib!
      //       .lookup<NativeFunction<ProcessFaceNative>>('process_face_crop')
      //       .asFunction();
      // } catch (_) {
      //   AppLog.error("⚠️ Missing spoofing");
      // }

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

      // AppLog.info("✅ Đã load thư viện C++ thành công: $libName");
    } catch (e) {
      AppLog.error("❌ Lỗi load thư viện C++: $e");
    }

    // sw.stop(); // ⏱️ Dừng đo
    // AppLog.info("⏱️ Thời gian Load C++ thực tế: ${sw.elapsedMilliseconds}ms");
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
    required Pointer<Uint8> ptrYuv,
    required int width,
    required int height,
    required List<double> landmarks, // Nhận mảng số thực giống hệt Dual Task
    required int rotation,
  }) {
    if (_funcProcessRegistration == null) init();

    // 1. Chuyển List<double> landmarks thành Pointer<Float> cho C++
    final Pointer<Float> ptrLandmarks = calloc<Float>(10);
    ptrLandmarks.asTypedList(10).setAll(0, landmarks);

    // Cấp 3 thùng chứa
    final outAiPixels = calloc<Float>(112 * 112 * 3);
    final outJpgBuffer = calloc<Uint8>(50000); // Thùng chứa JPG max 50KB
    final outJpgSize = calloc<Int32>(1);

    try {
      final status = _funcProcessRegistration!(
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

  // static Map<String, List<double>?> processDualTask({
  //   required Pointer<Uint8> ptrYuv,
  //   required int width,
  //   required int height,
  //   required int yStride,
  //   required List<double> landmarks,
  //   required int rotation,
  //   required int rectX,
  //   required int rectY,
  //   required int rectW,
  //   required int rectH,
  //   required int spoofWidth,
  //   required int spoofHeight,
  // }) {
  //   if (_funcCamera == null || _funcSpoof == null) init();

  //   // // 1. Cấp phát YUV duy nhất 1 lần cho cả 2 task
  //   // final ptrYuv = calloc<Uint8>(yuvBytes.length);
  //   // ptrYuv.asTypedList(yuvBytes.length).setAll(0, yuvBytes);

  //   // 2. Cấp phát Landmark
  //   final ptrLandmarks = calloc<Float>(10);
  //   ptrLandmarks.asTypedList(10).setAll(0, landmarks);

  //   // 3. Chuẩn bị Buffer đầu ra cho cả 2
  //   final int recogLen = 112 * 112 * 3;
  //   final ptrOutRecog = calloc<Float>(recogLen);

  //   final int spoofLen = spoofWidth * spoofHeight * 3;
  //   final ptrOutSpoof = calloc<Float>(spoofLen);

  //   try {
  //     // TASK 1: Gọi hàm Affine (Recognition)
  //     _funcCamera!(ptrYuv, width, height, ptrLandmarks, rotation, ptrOutRecog);

  //     // TASK 2: Gọi Spoof
  //     _funcSpoof!(
  //       ptrYuv,
  //       width,
  //       height,
  //       yStride,
  //       rotation,
  //       rectX,
  //       rectY,
  //       rectW,
  //       rectH,
  //       spoofWidth,
  //       spoofHeight,
  //       ptrOutSpoof,
  //     );

  //     // 4. Gom kết quả
  //     return {
  //       'recog': Float32List.fromList(ptrOutRecog.asTypedList(recogLen)),
  //       'spoof': Float32List.fromList(ptrOutSpoof.asTypedList(spoofLen)),
  //     };
  //   } catch (e) {
  //     AppLog.error("Dual Task Error: $e");
  //     return {'recog': null, 'spoof': null};
  //   } finally {
  //     // 5. Giải phóng toàn bộ 1 lượt
  //     calloc.free(ptrLandmarks);
  //     calloc.free(ptrOutRecog);
  //     calloc.free(ptrOutSpoof);
  //   }
  // }

  static Map<String, dynamic>? processDualTask({
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
    required int spoofWidth,
    required int spoofHeight,
    required double threshold,
  }) {
    if (_funcProcessFrame == null) init();

    final ptrLandmarks = calloc<Float>(10);
    ptrLandmarks.asTypedList(10).setAll(0, landmarks);

    // Thùng rỗng hứng kết quả
    final outNamePtr = calloc<Uint8>(256).cast<Utf8>();
    final outDistPtr = calloc<Float>(1);
    final outSpoofPtr = calloc<Float>(1);

    try {
      final status = _funcProcessFrame!(
        ptrYuv,
        width,
        height,
        ptrLandmarks,
        rotation,
        rectX,
        rectY,
        rectW,
        rectH,
        spoofWidth,
        spoofHeight,
        threshold,
        outNamePtr,
        outDistPtr,
        outSpoofPtr,
      );

      if (status == 0) return null;

      final name = outNamePtr.toDartString();
      final isUnknown = (status == 2);

      // Trả về thông tin ngắn gọn
      return {
        'name': name,
        'distance': outDistPtr.value,
        'isUnknown': isUnknown,
        'spoofScore': outSpoofPtr.value,
      };
    } finally {
      calloc.free(ptrLandmarks);
      calloc.free(outNamePtr);
      calloc.free(outDistPtr);
      calloc.free(outSpoofPtr);
    }
  }
}
