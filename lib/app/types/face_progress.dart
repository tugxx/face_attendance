import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../services/log_service.dart';

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

// C. Cho Spoofing
// typedef ProcessFaceNative =
//     Void Function(
//       Pointer<Uint8> yuvBytes,
//       Int32 width,
//       Int32 height,
//       Pointer<Float> landmarks,
//       Int32 landmarkCount,
//       Int32 rotation,
//       Int32 targetWidth,
//       Int32 targetHeight,
//       Int32 modelType,
//       Pointer<Float> output,
//     );

typedef ProcessFaceNative =
    Void Function(
      Pointer<Uint8> ptrYuv,
      Int32 width,
      Int32 height,
      Int32 yStride,
      // Int32 uvStride,
      // Pointer<Float> landmarks,
      // Int32 landmarkCount,
      Int32 rectX,
      Int32 rectY,
      Int32 rectW,
      Int32 rectH,
      Int32 rotation,
      Int32 targetWidth,
      Int32 targetHeight,
      // Int32 modelType,
      Pointer<Float> output,
    );

// typedef ProcessFaceDart =
//     void Function(
//       Pointer<Uint8> yuvBytes,
//       int width,
//       int height,
//       Pointer<Float> landmarks,
//       int landmarkCount,
//       int rotation,
//       int targetWidth,
//       int targetHeight,
//       int modelType,
//       Pointer<Float> output,
//     );

typedef ProcessFaceDart =
    void Function(
      Pointer<Uint8> ptrYuv,
      int width,
      int height,
      int yStride,
      // int uvStride,
      // Pointer<Float> landmarks,
      // int landmarkCount,
      int rectX,
      int rectY,
      int rectW,
      int rectH,
      int rotation,
      int targetWidth,
      int targetHeight,
      // int modelType,
      Pointer<Float> output,
    );

// ==========================================================
// 2. CLASS GIAO TIẾP VỚI NATIVE
// ==========================================================

class FaceProcessorNative {
  static DynamicLibrary? _lib;

  static ProcessFaceAffineDart? _funcCamera;
  static ProcessFileRawDart? _funcFile;
  static ProcessFaceDart? _funcSpoof;

  static void init() {
    if (_lib != null) return;
    // final sw = Stopwatch()..start(); // ⏱️ Bắt đầu đo

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
        AppLog.error("⚠️ Missing process_face_affine");
      }

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

      try {
        _funcSpoof = _lib!
            .lookup<NativeFunction<ProcessFaceNative>>('process_face_crop')
            .asFunction();
      } catch (_) {
        AppLog.error("⚠️ Missing spoofing");
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

  static List<double>? processRegistration({
    required Pointer<Uint8> ptrYuv,
    required int width,
    required int height,
    required List<double> landmarks, // Nhận mảng số thực giống hệt Dual Task
    required int rotation,
  }) {
    if (_funcCamera == null) init();
    if (_funcCamera == null) return null;

    // 1. Chuyển List<double> landmarks thành Pointer<Float> cho C++
    final Pointer<Float> ptrLandmarks = calloc<Float>(landmarks.length);
    for (int i = 0; i < landmarks.length; i++) {
      ptrLandmarks[i] = landmarks[i];
    }

    // // 2. Cấp phát bộ nhớ cho YUV (Copy dữ liệu ảnh sang C++)
    // final Pointer<Uint8> ptrYuv = calloc<Uint8>(yuvBytes.length);
    // ptrYuv.asTypedList(yuvBytes.length).setAll(0, yuvBytes);

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
      AppLog.error("Native Error: $e");
      return null;
    } finally {
      // calloc.free(ptrYuv);
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
      AppLog.error("Native File Error: $e");
      return null;
    } finally {
      calloc.free(ptrPath);
      calloc.free(ptrLandmarks);
      calloc.free(ptrOut);
    }
  }

  // static List<double>? processWithRawLandmarks(
  //   Uint8List yuvBytes,
  //   int width,
  //   int height,
  //   List<double> landmarksList, // Nhận List trực tiếp
  //   int rotation,
  // ) {
  //   if (_funcCamera == null) init();
  //   if (_funcCamera == null) return null;

  //   // Cấp phát Landmark từ List có sẵn
  //   final Pointer<Float> ptrLandmarks = calloc<Float>(10);
  //   final list = ptrLandmarks.asTypedList(10);
  //   list.setAll(0, landmarksList);

  //   // Cấp phát YUV
  //   final Pointer<Uint8> ptrYuv = calloc<Uint8>(yuvBytes.length);
  //   ptrYuv.asTypedList(yuvBytes.length).setAll(0, yuvBytes);

  //   final int outLen = 112 * 112 * 3;
  //   final Pointer<Float> ptrOut = calloc<Float>(outLen);

  //   try {
  //     _funcCamera!(ptrYuv, width, height, ptrLandmarks, rotation, ptrOut);
  //     final Float32List result = ptrOut.asTypedList(outLen);
  //     return List<double>.from(result);
  //   } catch (e) {
  //     return null;
  //   } finally {
  //     calloc.free(ptrYuv);
  //     calloc.free(ptrLandmarks);
  //     calloc.free(ptrOut);
  //   }
  // }

  // static List<double>? processAntiSpoofRaw(
  //   Uint8List yuvBytes,
  //   int width,
  //   int height,
  //   List<double> landmarks, // Dùng landmarks để lấy box (hoặc truyền box riêng)
  //   int rotation,
  //   int targetSize,
  // ) {
  //   if (_funcSpoof == null) init();

  //   // Lưu ý: Hàm C++ process_antispoof_crop đang nhận x, y, w, h
  //   // Ta cần tính Box bao quanh các landmark để làm input cho nó
  //   // (Hoặc sửa C++ để nhận landmarks luôn).
  //   // Ở đây ta tính nhanh box từ landmarks:

  //   double minX = 10000, minY = 10000, maxX = 0, maxY = 0;

  //   // Landmarks có 5 điểm (10 số)
  //   for (int i = 0; i < 10; i += 2) {
  //     double lx = landmarks[i];
  //     double ly = landmarks[i + 1];
  //     if (lx < minX) minX = lx;
  //     if (lx > maxX) maxX = lx;
  //     if (ly < minY) minY = ly;
  //     if (ly > maxY) maxY = ly;
  //   }

  //   // Box thô (chưa padding)
  //   double wData = maxX - minX;
  //   double hData = maxY - minY;

  //   // Theo kinh nghiệm cộng đồng: Landmarks 5 điểm thường hẹp hơn Box thật của Face Detector.
  //   // Ta cần padding nhẹ để Box này tương đương với Box của Face Detection.
  //   int cx = (minX + wData / 2).toInt();
  //   int cy = (minY + hData / 2).toInt();

  //   // Giả lập Box Detection từ Landmarks (mở rộng khoảng 1.5 lần so với cụm mắt mũi miệng)
  //   int wBox = (wData * 1.5).toInt();
  //   int hBox = (hData * 1.5).toInt();

  //   int x = cx - (wBox ~/ 2);
  //   int y = cy - (hBox ~/ 2);

  //   // -------------------------------------------------------------
  //   // BƯỚC 2: GỌI C++ ĐỂ CROP & SCALE (Logic Scale 2.7 nằm trong C++)
  //   // -------------------------------------------------------------

  //   final Pointer<Uint8> ptrYuv = calloc<Uint8>(yuvBytes.length);
  //   ptrYuv.asTypedList(yuvBytes.length).setAll(0, yuvBytes);

  //   final int outLen = targetSize * targetSize * 3;
  //   final Pointer<Float> ptrOut = calloc<Float>(outLen);

  //   try {
  //     _funcSpoof!(
  //       ptrYuv,
  //       width,
  //       height,
  //       x,
  //       y,
  //       wBox,
  //       hBox,
  //       rotation,
  //       targetSize,
  //       targetSize,
  //       ptrOut,
  //     );

  //     final Float32List result = ptrOut.asTypedList(outLen);
  //     return List<double>.from(result);
  //   } catch (e) {
  //     return null;
  //   } finally {
  //     calloc.free(ptrYuv);
  //     calloc.free(ptrOut);
  //   }
  // }

  static Map<String, List<double>?> processDualTask({
    required Pointer<Uint8> ptrYuv,
    required int width,
    required int height,
    required int yStride,
    // required int uvStride,
    required List<double> landmarks,
    required int rotation,
    required int rectX,
    required int rectY,
    required int rectW,
    required int rectH,
    required int spoofWidth,
    required int spoofHeight,
    // required int spoofModelType,
  }) {
    if (_funcCamera == null || _funcSpoof == null) init();

    // // 1. Cấp phát YUV duy nhất 1 lần cho cả 2 task
    // final ptrYuv = calloc<Uint8>(yuvBytes.length);
    // ptrYuv.asTypedList(yuvBytes.length).setAll(0, yuvBytes);

    // 2. Cấp phát Landmark
    final ptrLandmarks = calloc<Float>(10);
    ptrLandmarks.asTypedList(10).setAll(0, landmarks);

    // 3. Chuẩn bị Buffer đầu ra cho cả 2
    final int recogLen = 112 * 112 * 3;
    final ptrOutRecog = calloc<Float>(recogLen);

    final int spoofLen = spoofWidth * spoofHeight * 3;
    final ptrOutSpoof = calloc<Float>(spoofLen);

    try {
      // TASK 1: Gọi hàm Affine (Recognition)
      _funcCamera!(ptrYuv, width, height, ptrLandmarks, rotation, ptrOutRecog);

      // TASK 2: Gọi Spoof
      _funcSpoof!(
        ptrYuv,
        width,
        height,
        yStride,
        // uvStride,
        rotation,
        rectX,
        rectY,
        rectW,
        rectH,
        spoofWidth,
        spoofHeight,
        ptrOutSpoof,
      );

      // 4. Gom kết quả
      return {
        'recog': Float32List.fromList(ptrOutRecog.asTypedList(recogLen)),
        'spoof': Float32List.fromList(ptrOutSpoof.asTypedList(spoofLen)),
      };
    } catch (e) {
      AppLog.error("Dual Task Error: $e");
      return {'recog': null, 'spoof': null};
    } finally {
      // 5. Giải phóng toàn bộ 1 lượt
      calloc.free(ptrLandmarks);
      calloc.free(ptrOutRecog);
      calloc.free(ptrOutSpoof);
    }
  }
}

// Future<List<double>?> isolateFaceProcessor(FaceProcessRequest request) async {
//   // 1. Khởi tạo môi trường cho Isolate (Bắt buộc để dùng các platform channel nếu cần)
//   if (request.rootToken != null) {
//     BackgroundIsolateBinaryMessenger.ensureInitialized(request.rootToken!);
//   }

//   try {
//     // YUV -> RGB -> Rotate -> Crop -> Resize -> Normalize
//     return FaceProcessorNative.process(
//       request.yuvBytes,
//       request.width,
//       request.height,
//       request.face, // Truyền thẳng object Face
//       request.sensorOrientation,
//     );
//   } catch (e) {
//     AppLog.error("❌ Isolate Error: $e");
//     return null;
//   }
// }
