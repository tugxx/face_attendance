import 'dart:math';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:opencv_dart/opencv_dart.dart' as cv;
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

class FaceAlignerCV {
  // ✅ FIX 1: Dùng VecPoint2f thay vì Mat cho điểm chuẩn
  static final refPoints = cv.VecPoint2f.fromList([
    cv.Point2f(38.2946, 51.6963), // Left Eye
    cv.Point2f(73.5318, 51.6963), // Right Eye
    cv.Point2f(56.0252, 71.7366), // Nose
    cv.Point2f(41.5493, 92.3655), // Left Mouth
    cv.Point2f(70.7299, 92.3655), // Right Mouth
  ]);

  static Future<cv.Mat?> alignFace(
    String imagePath,
    Face face, {
    int targetSize = 112,
    bool saveDebug = false, // Bật cái này lên để lưu ảnh check
    String? debugName,
  }) async {
    try {
      // 1. Đọc ảnh
      var img = cv.imread(imagePath);
      if (img.isEmpty) return null;

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

      final lm = face.landmarks;
      if (lm[FaceLandmarkType.leftEye] == null ||
          lm[FaceLandmarkType.rightEye] == null ||
          lm[FaceLandmarkType.noseBase] == null ||
          lm[FaceLandmarkType.leftMouth] == null ||
          lm[FaceLandmarkType.rightMouth] == null) {
        return null;
      }

      // 2. Auto-Sort Landmarks (Chống ngược - Best Practice)
      // So sánh toạ độ X để biết đâu là trái/phải thực tế trên ảnh
      var e1 = lm[FaceLandmarkType.leftEye]!.position;
      var e2 = lm[FaceLandmarkType.rightEye]!.position;
      var m1 = lm[FaceLandmarkType.leftMouth]!.position;
      var m2 = lm[FaceLandmarkType.rightMouth]!.position;
      var nose = lm[FaceLandmarkType.noseBase]!.position;

      Point leftEye = (e1.x < e2.x) ? e1 : e2;
      Point rightEye = (e1.x < e2.x) ? e2 : e1;
      Point leftMouth = (m1.x < m2.x) ? m1 : m2;
      Point rightMouth = (m1.x < m2.x) ? m2 : m1;

      final srcPoints = cv.VecPoint2f.fromList([
        cv.Point2f(leftEye.x.toDouble(), leftEye.y.toDouble()),
        cv.Point2f(rightEye.x.toDouble(), rightEye.y.toDouble()),
        cv.Point2f(nose.x.toDouble(), nose.y.toDouble()),
        cv.Point2f(leftMouth.x.toDouble(), leftMouth.y.toDouble()),
        cv.Point2f(rightMouth.x.toDouble(), rightMouth.y.toDouble()),
      ]);

      debugPrint("hey có vào đây koooooooooooooooooooooo");
      // --- 📸 DEBUG: VẼ LANDMARK LÊN ẢNH GỐC ĐỂ CHECK ---
      if (saveDebug && debugName != null) {
        cv.Mat debugImg = img.clone();
        for (int i = 0; i < srcPoints.length; i++) {
          // Vẽ chấm đỏ tại các điểm landmark
          cv.circle(
            debugImg,
            cv.Point(srcPoints[i].x.toInt(), srcPoints[i].y.toInt()),
            5,
            cv.Scalar(0, 0, 255, 0),
            thickness: -1,
          );
          // Vẽ số thứ tự để biết đâu là mắt trái/phải
          cv.putText(
            debugImg,
            "$i",
            cv.Point(srcPoints[i].x.toInt(), srcPoints[i].y.toInt()),
            cv.FONT_HERSHEY_SIMPLEX,
            1.0,
            cv.Scalar(0, 255, 0, 0),
            thickness: 2,
          );
        }

        final extDir = await getExternalStorageDirectory();
        final debugDir = Directory('${extDir!.path}/debug_seeder');
        if (!await debugDir.exists()) {
          await debugDir.create(recursive: true);
        }
        final debugPath =
            '${extDir.path}/debug_seeder/${debugName}_landmarks.jpg';
        debugPrint("Chế độ debug: Lưu ảnh landmarks tại $debugPath");
        cv.imwrite(debugPath, debugImg);
        debugImg.dispose();
      }

      // 3. Tính Ma trận biến đổi
      // ✅ FIX 3: Hàm này trả về Tuple (transformation, inliers), cần tách ra
      final (transformMatrix, inliers) = cv.estimateAffinePartial2D(
        srcPoints,
        refPoints,
      );

      if (transformMatrix.isEmpty) {
        srcPoints.dispose();
        transformMatrix.dispose();
        return null;
      }

      // // 4. Warp Affine
      // // ✅ FIX 4: Truyền transformMatrix (đã tách từ tuple ở trên) vào
      // var alignedInfo = cv.warpAffine(img, transformMatrix, (
      //   targetSize,
      //   targetSize,
      // ), flags: cv.INTER_CUBIC);

      // 4. Warp Affine (Cắt ảnh)
      cv.Mat alignedMat = cv.warpAffine(
        img,
        transformMatrix,
        (targetSize, targetSize),
        flags: cv.INTER_CUBIC, // Cubic cho chất lượng ảnh tốt nhất
      );

      // Cleanup
      srcPoints.dispose();
      transformMatrix.dispose();
      img.dispose();

      // // 5. Encode kết quả ra JPG
      // final (success, buffer) = cv.imencode(".jpg", alignedInfo);

      // return success ? buffer : null;

      return alignedMat;
    } catch (e) {
      debugPrint("OpenCV Error: $e");
      return null;
    }
  }
}
