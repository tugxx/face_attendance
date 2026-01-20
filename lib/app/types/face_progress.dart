import 'dart:ffi'; // Để dùng Pointer, Void, Int32, Float, Uint8
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

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

// ==========================================================
// 2. CLASS GIAO TIẾP VỚI NATIVE
// ==========================================================

class FaceProcessorNative {
  static DynamicLibrary? _lib;

  static ProcessFaceAffineDart? _funcCamera;
  static ProcessFileRawDart? _funcFile;

  static void init() {
    if (_lib != null) return;
    // Tên thư viện phải khớp với CMakeLists (native_face)
    final libName = Platform.isAndroid
        ? 'libnative_face_align.so'
        : 'native_face_align.framework/native_face_align';
    try {
      _lib = DynamicLibrary.open(libName);

      // Load hàm Camera
      try {
        _funcCamera = _lib!
            .lookup<NativeFunction<ProcessFaceAffineFunc>>(
              'process_face_affine',
            )
            .asFunction();
      } catch (_) {
        debugPrint("⚠️ Missing process_face_affine");
      }

      // Load hàm File (Mới)
      try {
        _funcFile = _lib!
            .lookup<NativeFunction<ProcessFileRawFunc>>(
              'process_file_affine_raw',
            )
            .asFunction();
      } catch (_) {
        debugPrint("⚠️ Missing process_file_affine_raw");
      }

      debugPrint("✅ Đã load thư viện C++ thành công: $libName");
    } catch (e) {
      debugPrint("❌ Lỗi load thư viện C++: $e");
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

  static List<double>? process(
    Uint8List yuvBytes,
    int width,
    int height,
    Face face,
    int rotation,
  ) {
    if (_funcCamera == null) init();
    if (_funcCamera == null) return null;

    final ptrLandmarks = _convertLandmarks(face);
    if (ptrLandmarks == null) return null;

    // 2. Cấp phát bộ nhớ cho YUV (Copy dữ liệu ảnh sang C++)
    final Pointer<Uint8> ptrYuv = calloc<Uint8>(yuvBytes.length);
    ptrYuv.asTypedList(yuvBytes.length).setAll(0, yuvBytes);

    // 3. Chuẩn bị Output
    final int outLen = 112 * 112 * 3;
    final Pointer<Float> ptrOut = calloc<Float>(outLen);

    try {
      // 4. 🔥 GỌI C++
      _funcCamera!(ptrYuv, width, height, ptrLandmarks, rotation, ptrOut);

      // 5. Lấy kết quả
      final Float32List result = ptrOut.asTypedList(outLen);
      return List<double>.from(result);
    } catch (e) {
      debugPrint("Native Error: $e");
      return null;
    } finally {
      calloc.free(ptrYuv);
      calloc.free(ptrLandmarks);
      calloc.free(ptrOut);
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
      debugPrint("Native File Error: $e");
      return null;
    } finally {
      calloc.free(ptrPath); // Nhớ free string
      calloc.free(ptrLandmarks);
      calloc.free(ptrOut);
    }
  }
}

Future<List<double>?> isolateFaceProcessor(FaceProcessRequest request) async {
  // 1. Khởi tạo môi trường cho Isolate (Bắt buộc để dùng các platform channel nếu cần)
  if (request.rootToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(request.rootToken!);
  }

  try {
    // YUV -> RGB -> Rotate -> Crop -> Resize -> Normalize
    return FaceProcessorNative.process(
      request.yuvBytes,
      request.width,
      request.height,
      request.face, // Truyền thẳng object Face
      request.sensorOrientation,
    );
  } catch (e) {
    debugPrint("❌ Isolate Error: $e");
    return null;
  }
}
