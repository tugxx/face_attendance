import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;

// --- DATA TRANSFER OBJECT (Gói dữ liệu để gửi đi) ---
class FaceProcessRequest {
  final Uint8List yuvBytes;
  final int width;
  final int height;
  final Face face;
  final int cropX, cropY, cropW, cropH;
  final int sensorOrientation;
  final bool isAndroid;
  final String? debugPath;
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

// ĐIỂM CHUẨN (CANONICAL POINTS) CHO ARCFACE/INSIGHTFACE (112x112)
// Thứ tự: Mắt trái, Mắt phải, Mũi, Miệng trái, Miệng phải
final _refPoints = cv.VecPoint2f.fromList([
  cv.Point2f(38.2946, 51.6963),
  cv.Point2f(73.5318, 51.6963),
  cv.Point2f(56.0252, 71.7366),
  cv.Point2f(41.5493, 92.3655),
  cv.Point2f(70.7299, 92.3655),
]);

/// Chuyển đổi YUV Bytes sang BGR Mat và xoay đúng chiều
cv.Mat _convertToBGR(FaceProcessRequest request) {
  // 1. Tạo Mat từ YUV Bytes
  final matYUV = cv.Mat.fromList(
    request.height + request.height ~/ 2, // Chiều cao NV21 = h * 1.5
    request.width,
    cv.MatType.CV_8UC1,
    request.yuvBytes,
  );

  // 2. Convert YUV -> BGR
  final tempBGR = cv.cvtColor(matYUV, cv.COLOR_YUV2BGR_NV21);
  matYUV.dispose(); // Xong việc xóa ngay

  // 3. Xoay ảnh nếu cần (Dựa trên sensorOrientation)
  cv.Mat finalBGR;
  if (request.isAndroid && request.sensorOrientation != 0) {
    switch (request.sensorOrientation) {
      case 90:
        finalBGR = cv.rotate(tempBGR, cv.ROTATE_90_CLOCKWISE);
        break;
      case 270:
        finalBGR = cv.rotate(tempBGR, cv.ROTATE_90_COUNTERCLOCKWISE);
        break;
      case 180:
        finalBGR = cv.rotate(tempBGR, cv.ROTATE_180);
        break;
      default:
        finalBGR = tempBGR.clone();
    }
    tempBGR.dispose(); // Xóa ảnh tạm sau khi xoay
  } else {
    finalBGR = tempBGR; // Không xoay thì dùng luôn
  }

  return finalBGR;
}

/// Căn chỉnh khuôn mặt dùng Affine Transform
cv.Mat? _alignFace(cv.Mat srcImg, Face face) {
  // 1. Kiểm tra đủ landmark
  final lm = face.landmarks;
  if (lm[FaceLandmarkType.leftEye] == null ||
      lm[FaceLandmarkType.rightEye] == null ||
      lm[FaceLandmarkType.noseBase] == null ||
      lm[FaceLandmarkType.leftMouth] == null ||
      lm[FaceLandmarkType.rightMouth] == null) {
    return null;
  }

  // 2. Lấy toạ độ
  // Lưu ý: Logic sắp xếp trái phải của bạn rất cẩn thận, mình giữ nguyên
  // để đề phòng trường hợp Mirror Camera.
  var e1 = lm[FaceLandmarkType.leftEye]!.position;
  var e2 = lm[FaceLandmarkType.rightEye]!.position;
  var n = lm[FaceLandmarkType.noseBase]!.position;
  var m1 = lm[FaceLandmarkType.leftMouth]!.position;
  var m2 = lm[FaceLandmarkType.rightMouth]!.position;

  final srcPoints = cv.VecPoint2f.fromList([
    // Mắt trái (bên trái ảnh)
    cv.Point2f(
      (e1.x < e2.x ? e1 : e2).x.toDouble(),
      (e1.x < e2.x ? e1 : e2).y.toDouble(),
    ),
    // Mắt phải
    cv.Point2f(
      (e1.x < e2.x ? e2 : e1).x.toDouble(),
      (e1.x < e2.x ? e2 : e1).y.toDouble(),
    ),
    // Mũi
    cv.Point2f(n.x.toDouble(), n.y.toDouble()),
    // Miệng trái
    cv.Point2f(
      (m1.x < m2.x ? m1 : m2).x.toDouble(),
      (m1.x < m2.x ? m1 : m2).y.toDouble(),
    ),
    // Miệng phải
    cv.Point2f(
      (m1.x < m2.x ? m2 : m1).x.toDouble(),
      (m1.x < m2.x ? m2 : m1).y.toDouble(),
    ),
  ]);

  // 3. Tính ma trận biến đổi (Estimate Affine)
  // estimateAffinePartial2D tốt hơn getAffineTransform vì nó dùng cả 5 điểm để tối ưu hoá (Least Square)
  final (transMat, _) = cv.estimateAffinePartial2D(srcPoints, _refPoints);

  if (transMat.isEmpty) {
    srcPoints.dispose();
    return null;
  }

  // 4. Cắt và Kéo dãn (Warp)
  final aligned = cv.warpAffine(
    srcImg,
    transMat,
    (112, 112), // Kích thước đích chuẩn ArcFace
    flags: cv.INTER_CUBIC, // Chất lượng ảnh tốt nhất
  );

  // Cleanup
  srcPoints.dispose();
  transMat.dispose();

  return aligned;
}

// /// Hàm lưu ảnh debug (Chỉ chạy nếu có path)
// void _saveDebugImage(cv.Mat img, String? basePath, String suffix) {
//   if (basePath == null) return;
//   try {
//     final parentDir = File(basePath).parent.path;
//     final path = '$parentDir/debug_$suffix';
//     final (success, bytes) = cv.imencode(".jpg", img);
//     if (success) {
//       File(path).writeAsBytesSync(bytes);
//       debugPrint("📸 Debug saved: $path");
//     }
//   } catch (_) {}
// }

// --- HÀM XỬ LÝ NỀN (CHẠY TRONG ISOLATE) ---
Future<List<int>?> isolateFaceProcessor(FaceProcessRequest request) async {
  if (request.rootToken != null) {
    BackgroundIsolateBinaryMessenger.ensureInitialized(request.rootToken!);
  }

  // Khai báo biến ở ngoài để đảm bảo dispose trong finally
  cv.Mat? matBGR;
  cv.Mat? alignedFace;
  // cv.Mat? matGray;

  try {
    final face = request.face;

    // --- GATE 1: CHECK GÓC MẶT ---
    if ((face.headEulerAngleY ?? 0).abs() > 15 ||
        (face.headEulerAngleZ ?? 0).abs() > 15) {
      // debugPrint("⚠️ Mặt nghiêng quá, bỏ qua để đảm bảo chính xác");
      return null;
    }

    // --- BƯỚC 1: CONVERT & XOAY ẢNH ---
    matBGR = _convertToBGR(request);

    // // Debug ảnh gốc (Optional)
    // _saveDebugImage(matBGR, request.debugPath, "01_rotated.jpg");

    // --- BƯỚC 2: CĂN CHỈNH (ALIGNMENT) ---
    alignedFace = _alignFace(matBGR, face);

    if (alignedFace == null || alignedFace.isEmpty) {
      return null;
    }

    // // Debug ảnh kết quả (Optional)
    // _saveDebugImage(alignedFace, request.debugPath, "02_aligned.jpg");

    final (success, encodedBytes) = cv.imencode(".jpg", alignedFace);
    if (success) {
      return encodedBytes.toList(); // Trả về file JPG hoàn chỉnh
    } else {
      return null;
    }
  } catch (e) {
    debugPrint("Isolate Error: $e");
    return null;
  } finally {
    matBGR?.dispose();
    alignedFace?.dispose();
  }
}
