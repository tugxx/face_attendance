import 'dart:io';
// import 'dart:typed_data';
import 'dart:math';

import 'package:flutter/material.dart';
// import 'package:image/image.dart' as img;
// import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

// import '../../core/services/image_converter_ffi.dart';

// --- DATA TRANSFER OBJECT (Gói dữ liệu để gửi đi) ---
class FaceProcessRequest {
  final Uint8List yuvBytes;
  final int width;
  final int height;
  final Face face;
  final int cropX, cropY, cropW, cropH;
  final int sensorOrientation;
  final bool isAndroid;
  final String? debugPath; // Nếu muốn lưu ảnh debug
  final RootIsolateToken? rootToken;

  FaceProcessRequest({
    required this.yuvBytes,
    required this.width,
    required this.height,
    required this.face,
    required this.cropX,
    required this.cropY,
    required this.cropW,
    required this.cropH,
    required this.sensorOrientation,
    required this.isAndroid,
    this.debugPath,
    this.rootToken,
  });
}

// // --- HÀM HELPER: XOAY TỌA ĐỘ (Clean Code) ---
// cv.Point2f _rotatePoint({
//   required double x,
//   required double y,
//   required double imgW,
//   required double imgH,
//   required int angle,
// }) {
//   if (angle == 90) {
//     return cv.Point2f(imgH - y, x); // Xoay 90 độ
//   } else if (angle == 270) {
//     return cv.Point2f(y, imgW - x); // Xoay 270 độ (Cam trước thường dùng)
//   } else if (angle == 180) {
//     return cv.Point2f(imgW - x, imgH - y);
//   }
//   return cv.Point2f(x, y);
// }

// --- HÀM XỬ LÝ NỀN (CHẠY TRONG ISOLATE) ---
Future<List<int>?> isolateFaceProcessor(FaceProcessRequest request) async {
  if (request.rootToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(request.rootToken!);
  }

  // Khai báo biến ở ngoài để đảm bảo dispose trong finally
  cv.Mat? matYUV;
  cv.Mat? matBGR;
  // cv.Mat? matGray;
  cv.Mat? alignedBGR;
  // cv.Mat? floatMat;
  cv.Mat? debugMat;

  try {
    final face = request.face;

    // --- 🛑 GATE 1: KIỂM TRA GÓC MẶT (HEAD POSE) ---
    // Chỉ nhận diện khi nhìn thẳng. Nếu nghiêng quá -> Bỏ qua
    // headEulerAngleY: Quay trái/phải (Yaw)
    // headEulerAngleZ: Nghiêng đầu (Roll)
    if ((face.headEulerAngleY ?? 0).abs() > 15 ||
        (face.headEulerAngleZ ?? 0).abs() > 15) {
      // debugPrint("⚠️ Mặt nghiêng quá, bỏ qua để đảm bảo chính xác");
      return null;
    }

    // --- 1. PREPARE IMAGE ---
    // Tạo Mat từ YUV Bytes (Raw)
    matYUV = cv.Mat.fromList(
      request.height + request.height ~/ 2,
      request.width,
      cv.MatType.CV_8UC1,
      request.yuvBytes,
    );

    // Convert sang BGR tạm thời
    // Lưu ý: Dùng COLOR_YUV2BGR_NV21 thay vì RGB
    cv.Mat tempBGR = cv.cvtColor(matYUV, cv.COLOR_YUV2BGR_NV21);

    // --- 🛑 XOAY ẢNH VỀ ĐÚNG HƯỚNG (PORTRAIT) ---
    // Logic: Xoay tempBGR -> Lưu vào matBGR
    if (request.isAndroid && request.sensorOrientation != 0) {
      if (request.sensorOrientation == 90) {
        matBGR = cv.rotate(tempBGR, cv.ROTATE_90_CLOCKWISE);
      } else if (request.sensorOrientation == 270) {
        matBGR = cv.rotate(tempBGR, cv.ROTATE_90_COUNTERCLOCKWISE);
      } else if (request.sensorOrientation == 180) {
        matBGR = cv.rotate(tempBGR, cv.ROTATE_180);
      } else {
        matBGR = tempBGR.clone();
      }
    } else {
      matBGR = tempBGR.clone();
    }

    // Dispose tempBGR ngay vì không dùng nữa
    tempBGR.dispose();

    // // --- 🛑 GATE 2: KIỂM TRA ĐỘ NÉT (BLUR CHECK) ---
    // // Chuyển sang ảnh xám để tính Laplacian (độ biến thiên của pixel)
    // matGray = cv.cvtColor(matRGB, cv.COLOR_RGB2GRAY);
    // var laplacian = cv.Laplacian(matGray, cv.MatType.CV_64F);

    // var (mean, stddev) = cv.meanStdDev(laplacian);
    // double blurScore = stddev.val1 * stddev.val1; // Variance
    // laplacian.dispose();

    // // Ngưỡng: < 100 thường là mờ. Tuy nhiên tính toán này tốn thêm khoảng 10-20ms.
    // // Nếu máy yếu có thể bỏ qua bước này.
    // if (blurScore < 100) {
    //   return null; // Ảnh mờ quá
    // }

    // --- 📸 DEBUG 1: LƯU ẢNH GỐC ĐÃ XOAY (GHI ĐÈ) ---
    try {
      if (request.debugPath != null) {
        // Lấy thư mục cha từ debugPath
        final parentDir = File(request.debugPath!).parent.path;
        // Đặt tên cố định để GHI ĐÈ mỗi lần chạy -> Không tốn bộ nhớ
        final fixedPath = '$parentDir/debug_01_input_rotated.jpg';

        debugMat = cv.cvtColor(matBGR, cv.COLOR_RGB2BGR);
        final (success, bytes) = cv.imencode(".jpg", matBGR);
        if (success) {
          File(fixedPath).writeAsBytesSync(bytes);
          debugPrint("📸 Saved debug: $fixedPath");
        }
        debugMat.dispose();
      }
    } catch (_) {}

    // // --- 2. ALIGNMENT (KHÔNG XOAY TAY NỮA) ---
    // // Chúng ta dùng chính ảnh Raw (Landscape) và Landmark Raw (Landscape).
    // // Affine Transform sẽ tự động xoay ảnh về đúng hướng 112x112.

    // if (face.landmarks[FaceLandmarkType.leftEye] == null ||
    //     face.landmarks[FaceLandmarkType.rightEye] == null ||
    //     face.landmarks[FaceLandmarkType.noseBase] == null ||
    //     face.landmarks[FaceLandmarkType.leftMouth] == null ||
    //     face.landmarks[FaceLandmarkType.rightMouth] == null) {
    //   return null;
    // }

    // // 2. Chuẩn bị Landmark từ ML Kit
    // final landmarks = [
    //   face.landmarks[FaceLandmarkType.leftEye]!.position,
    //   face.landmarks[FaceLandmarkType.rightEye]!.position,
    //   face.landmarks[FaceLandmarkType.noseBase]!.position,
    //   face.landmarks[FaceLandmarkType.leftMouth]!.position,
    //   face.landmarks[FaceLandmarkType.rightMouth]!.position,
    // ];

    // // ✅ FIX 2: Convert toạ độ sang List<Point2f> rồi tạo VecPoint2f
    // final srcPointList = landmarks
    //     .map((p) => cv.Point2f(p.x.toDouble(), p.y.toDouble()))
    //     .toList();
    // final srcPoints = cv.VecPoint2f.fromList(srcPointList);

    // --- 2. LẤY LANDMARK & DEBUG ---
    // Cần check null kỹ
    if (face.landmarks[FaceLandmarkType.leftEye] == null ||
        face.landmarks[FaceLandmarkType.rightEye] == null ||
        face.landmarks[FaceLandmarkType.noseBase] == null ||
        face.landmarks[FaceLandmarkType.leftMouth] == null ||
        face.landmarks[FaceLandmarkType.rightMouth] == null) {
      return null;
    }

    var eye1 = face.landmarks[FaceLandmarkType.leftEye]!.position;
    var eye2 = face.landmarks[FaceLandmarkType.rightEye]!.position;
    var nose = face.landmarks[FaceLandmarkType.noseBase]!.position;
    var mouth1 = face.landmarks[FaceLandmarkType.leftMouth]!.position;
    var mouth2 = face.landmarks[FaceLandmarkType.rightMouth]!.position;

    // Logic sắp xếp trái phải (như cũ)
    Point leftImgEye = (eye1.x < eye2.x) ? eye1 : eye2;
    Point rightImgEye = (eye1.x < eye2.x) ? eye2 : eye1;
    Point leftImgMouth = (mouth1.x < mouth2.x) ? mouth1 : mouth2;
    Point rightImgMouth = (mouth1.x < mouth2.x) ? mouth2 : mouth1;

    // --- 🕵️ THÊM: VẼ LANDMARK LÊN ẢNH ĐỂ CHECK ---
    // Clone ra một ảnh để vẽ debug (không vẽ lên ảnh gốc dùng để nhận diện)
    debugMat = matBGR.clone();

    // Vẽ 5 điểm landmark màu đỏ (BGR: 0, 0, 255)
    final debugPoints = [
      leftImgEye,
      rightImgEye,
      nose,
      leftImgMouth,
      rightImgMouth,
    ];
    for (var p in debugPoints) {
      cv.circle(
        debugMat,
        cv.Point(p.x.toInt(), p.y.toInt()),
        5,
        cv.Scalar(0, 0, 255, 0),
        thickness: -1,
      );
    }

    try {
      if (request.debugPath != null) {
        final parentDir = File(request.debugPath!).parent.path;
        final fixedPath = '$parentDir/debug_01_input_check.jpg';
        final (success, bytes) = cv.imencode(".jpg", debugMat);
        if (success) {
          File(fixedPath).writeAsBytesSync(bytes);
          debugPrint("📸 Saved debug: $fixedPath");
        }
      }
    } catch (_) {}

    final srcPointList = [
      cv.Point2f(leftImgEye.x.toDouble(), leftImgEye.y.toDouble()),
      cv.Point2f(rightImgEye.x.toDouble(), rightImgEye.y.toDouble()),
      cv.Point2f(nose.x.toDouble(), nose.y.toDouble()),
      cv.Point2f(leftImgMouth.x.toDouble(), leftImgMouth.y.toDouble()),
      cv.Point2f(rightImgMouth.x.toDouble(), rightImgMouth.y.toDouble()),
    ];
    final srcPoints = cv.VecPoint2f.fromList(srcPointList);

    // Điểm chuẩn (Canonical Points - Upright 112x112)
    final refPoints = cv.VecPoint2f.fromList([
      cv.Point2f(38.2946, 51.6963),
      cv.Point2f(73.5318, 51.6963),
      cv.Point2f(56.0252, 71.7366),
      cv.Point2f(41.5493, 92.3655),
      cv.Point2f(70.7299, 92.3655),
    ]);

    // OpenCV Magic: Tìm ma trận biến đổi từ "Nghiêng/Xoay" -> "Thẳng"
    final (transformMatrix, _) = cv.estimateAffinePartial2D(
      srcPoints,
      refPoints,
    );

    if (transformMatrix.isEmpty) {
      return null;
    }

    // Cắt và Căn chỉnh
    // Lúc này alignedFace sẽ TỰ ĐỘNG được xoay thẳng đứng 112x112
    alignedBGR = cv.warpAffine(matBGR, transformMatrix, (
      112,
      112,
    ), flags: cv.INTER_CUBIC);

    // Dispose Matrix tạm
    transformMatrix.dispose();

    // --- 📸 DEBUG 2: LƯU ẢNH KẾT QUẢ CUỐI (GHI ĐÈ) ---
    try {
      if (request.debugPath != null && !alignedBGR.isEmpty) {
        final parentDir = File(request.debugPath!).parent.path;
        // Tên cố định -> Ghi đè
        final fixedPath = '$parentDir/debug_02_output_aligned.jpg';

        final (success, bytes) = cv.imencode(".jpg", alignedBGR);
        if (success) {
          File(fixedPath).writeAsBytesSync(bytes);
          debugPrint("📸 Saved debug: $fixedPath");
        }
      }
    } catch (_) {}

    // // 👉 QUAN TRỌNG: THỬ NGHIỆM ĐẢO KÊNH MÀU CHO AI
    // // Nếu Distance vẫn cao (0.9), hãy thử uncomment dòng dưới để chuyển input AI sang BGR
    // // Vì alignedBGR đang là BGR.
    // cv.Mat alignedRGB = cv.cvtColor(alignedBGR, cv.COLOR_BGR2RGB);

    // // --- 3. NORMALIZE & CONVERT ---
    // // Normalize: (pixel - 127.5) / 128.0
    // floatMat = alignedRGB.convertTo(
    //   cv.MatType.CV_32FC3,
    //   alpha: 1.0 / 128.0,
    //   beta: -127.5 / 128.0,
    // );

    // alignedRGB.dispose();

    // final floatBytes = floatMat.data;

    // final floatList = Float32List.fromList(Float32List.view(floatBytes.buffer));

    // return floatList;

    ///////////////////////////////////////////////////////////////////////

    // // 👉 BƯỚC QUAN TRỌNG NHẤT: CHUYỂN ĐỔI DỮ LIỆU CHO AI
    // // Model InsightFace/ArcFace yêu cầu:
    // // 1. Color Space: RGB
    // // 2. Normalization: (pixel - 127.5) / 128.0
    // // 3. Layout: NCHW (Planar) - ĐÂY LÀ CÁI BẠN ĐANG THIẾU

    // // A. Convert sang RGB trước (Vì alignedBGR đang là BGR)
    // cv.Mat rgbMat = cv.cvtColor(alignedBGR, cv.COLOR_BGR2RGB);
  
    // // B. Convert sang Float32 và Normalize
    // cv.Mat floatMat = alignedBGR.convertTo(
    //   cv.MatType.CV_32FC3,
    //   alpha: 1.0 / 255.0, 
    //   beta: 0.0,
    // );

    // // C. Lấy dữ liệu thô (đang là HWC: R,G,B, R,G,B...)
    // final byteData = floatMat.data;

    // // ⚠️ Dùng offsetInBytes để tránh Crash SIGSEGV (Lỗi bộ nhớ)
    // final inputFloatList = Float32List.view(
    //   byteData.buffer,
    //   byteData.offsetInBytes,
    //   byteData.lengthInBytes ~/ 4,
    // );

    // // Copy ra mảng mới để trả về Main Thread (Isolate ko gửi được View của Pointer)
    // final resultList = Float32List.fromList(inputFloatList);

    // return resultList;

    // --- 🟢 THAY ĐỔI QUAN TRỌNG TẠI ĐÂY ---
    // Thay vì Normalize ở đây, ta chỉ trả về Raw Bytes của ảnh BGR
    // Để Service bên ngoài tự lo việc Normalize (Consistency)
    
    // Copy dữ liệu ra List<int> để gửi về Main Isolate an toàn
    final rawBytes = alignedBGR.data.toList(); 

    return rawBytes;
  } catch (e) {
    debugPrint("Isolate Error: $e");
    // In stacktrace để debug nếu vẫn lỗi (nhưng khó lỗi lắm)
    if (e is Error) {
      debugPrintStack(stackTrace: e.stackTrace);
    }
    return null;
  } finally {
    matYUV?.dispose();
    matBGR?.dispose();
    // matGray?.dispose();
    alignedBGR?.dispose();
    // floatMat?.dispose();
  }
}
