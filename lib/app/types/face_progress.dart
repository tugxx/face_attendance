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

// class FaceProcessorDart {
//   /// Hàm chính xử lý tất cả: YUV -> RGB -> Rotate -> Align -> Normalize
//   /// Trả về: List double sẵn sàng đưa vào Model
//   static Future<List<double>?> process(FaceProcessRequest request) async {
//     try {
//       // 1. Convert YUV (NV21) sang Image (RGB)
//       img.Image? image = convertNV21ToImage(
//         request.yuvBytes,
//         request.width,
//         request.height,
//       );

//       // 2. Xoay ảnh theo Sensor (để mặt đứng thẳng)
//       // Android thường bị xoay 90 hoặc 270 độ
//       if (request.isAndroid && request.sensorOrientation != 0) {
//         image = img.copyRotate(image, angle: request.sensorOrientation);
//       }

//       // 3. GỌI FACE ALIGNER
//       return FaceAligner.alignFace(
//         image,
//         request.face,
//         targetSize: 112,
//         // saveDebug: true, // Có thể bật debug trong này nếu muốn check từng frame
//         // debugName: "live_frame"
//       );
//     } catch (e) {
//       debugPrint("❌ Error processing face: $e");
//       return null;
//     }
//   }

//   /// CHUYỂN ĐỔI NV21 (YUV) SANG RGB
//   static img.Image convertNV21ToImage(Uint8List yuv, int width, int height) {
//     final img.Image image = img.Image(width: width, height: height);
//     final int frameSize = width * height;

//     // Duyệt từng pixel
//     for (int y = 0; y < height; y++) {
//       for (int x = 0; x < width; x++) {
//         int yIndex = y * width + x;

//         // NV21 cấu trúc: Y plane full, sau đó là VU xen kẽ
//         int uvIndex = frameSize + (y >> 1) * width + (x & ~1);

//         int Y = yuv[yIndex] & 0xff;
//         int V = yuv[uvIndex] & 0xff; // NV21 thì V nằm trước
//         int U = yuv[uvIndex + 1] & 0xff; // Sau đó là U

//         // Công thức YUV -> RGB
//         int r = (Y + 1.402 * (V - 128)).toInt();
//         int g = (Y - 0.344136 * (U - 128) - 0.714136 * (V - 128)).toInt();
//         int b = (Y + 1.772 * (U - 128)).toInt();

//         // Clamp về [0, 255]
//         r = r.clamp(0, 255);
//         g = g.clamp(0, 255);
//         b = b.clamp(0, 255);

//         // Set pixel vào Image
//         image.setPixelRgb(x, y, r, g, b);
//       }
//     }
//     return image;
//   }
// }

// Định nghĩa hàm C++
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

class FaceProcessorNative {
  static DynamicLibrary? _lib;
  static ProcessFaceAffineDart? _func;

  static void init() {
    if (_lib != null) return;
    // Tên thư viện phải khớp với CMakeLists (native_face)
    final libName = Platform.isAndroid
        ? 'libnative_face_align.so'
        : 'native_face_align.framework/native_face_align';
    try {
      _lib = DynamicLibrary.open(libName);

      _func = _lib!
          .lookup<NativeFunction<ProcessFaceAffineFunc>>('process_face_affine')
          .asFunction();
      debugPrint("✅ Đã load thư viện C++ thành công: $libName");
    } catch (e) {
      debugPrint("❌ Lỗi load thư viện C++: $e");
    }
  }

  static List<double>? process(
    Uint8List yuvBytes,
    int width,
    int height,
    Face face,
    int rotation,
  ) {
    if (_func == null) init();
    if (_func == null) return null;

    // 1. Trích xuất Landmarks (5 điểm)
    // Map từ ML Kit Face -> Flat Array
    final lm = face.landmarks;
    final leftEye = lm[FaceLandmarkType.leftEye]?.position;
    final rightEye = lm[FaceLandmarkType.rightEye]?.position;
    final nose = lm[FaceLandmarkType.noseBase]?.position;
    final leftMouth = lm[FaceLandmarkType.leftMouth]?.position;
    final rightMouth = lm[FaceLandmarkType.rightMouth]?.position;

    // Nếu thiếu điểm quan trọng -> Return null
    if (leftEye == null || rightEye == null) return null;

    // Tạo mảng Landmarks cho C++ (10 số float)
    final Pointer<Float> ptrLandmarks = calloc<Float>(10);
    final listLm = ptrLandmarks.asTypedList(10);

    // Gán dữ liệu (X, Y)
    listLm[0] = leftEye.x.toDouble();
    listLm[1] = leftEye.y.toDouble();
    listLm[2] = rightEye.x.toDouble();
    listLm[3] = rightEye.y.toDouble();
    // Các điểm còn lại nếu C++ cần dùng (hiện tại code C++ trên chỉ dùng 2 mắt)
    // Nhưng cứ truyền đủ cho đúng cấu trúc
    if (nose != null) {
      listLm[4] = nose.x.toDouble();
      listLm[5] = nose.y.toDouble();
    }
    if (leftMouth != null) {
      listLm[6] = leftMouth.x.toDouble();
      listLm[7] = leftMouth.y.toDouble();
    }
    if (rightMouth != null) {
      listLm[8] = rightMouth.x.toDouble();
      listLm[9] = rightMouth.y.toDouble();
    }

    // 2. Cấp phát bộ nhớ cho YUV (Copy dữ liệu ảnh sang C++)
    final Pointer<Uint8> ptrYuv = calloc<Uint8>(yuvBytes.length);
    ptrYuv.asTypedList(yuvBytes.length).setAll(0, yuvBytes);

    // 3. Chuẩn bị Output
    final int outLen = 112 * 112 * 3;
    final Pointer<Float> ptrOut = calloc<Float>(outLen);

    try {
      // 4. 🔥 GỌI C++
      _func!(ptrYuv, width, height, ptrLandmarks, rotation, ptrOut);

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
