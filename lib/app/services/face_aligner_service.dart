// import 'dart:math';

// import 'package:flutter/foundation.dart';
// import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
// import 'package:image/image.dart' as img;
// // import 'package:path_provider/path_provider.dart';

// class AlignmentResult {
//   final List<double> aiPixels; // Input cho AI (Vector chuẩn hóa)
//   final img.Image alignedImage; // Ảnh Bitmap đã xoay thẳng (Để hiển thị UI)

//   AlignmentResult(this.aiPixels, this.alignedImage);
// }

// /// Class xử lý cắt & căn chỉnh khuôn mặt chuẩn "ArcFace/InsightFace"
// /// Sử dụng thuật toán Similarity Transformation (Affine) bằng Dart thuần.
// class FaceAligner {
//   // --- 1. ĐỊNH NGHĨA ĐIỂM CHUẨN (STANDARD LANDMARKS) CHO ẢNH 112x112 ---
//   // Đây là toạ độ chuẩn mà các model MobileFaceNet/ArcFace được train.
//   // Mắt trái, Mắt phải, Mũi, Miệng trái, Miệng phải
//   static const List<Point<double>> _refPoints = [
//     Point(38.2946, 51.6963), // Left Eye
//     Point(73.5318, 51.6963), // Right Eye
//     Point(56.0252, 71.7366), // Nose
//     Point(41.5493, 92.3655), // Left Mouth
//     Point(70.7299, 92.3655), // Right Mouth
//   ];

//   // static Future<void> _saveDebugImage(img.Image image, String name) async {
//   //   try {
//   //     final extDir = await getExternalStorageDirectory();
//   //     if (extDir == null) return;

//   //     final debugDir = Directory('${extDir.path}/debug_align');
//   //     if (!await debugDir.exists()) {
//   //       await debugDir.create(recursive: true);
//   //     }

//   //     final path =
//   //         '${debugDir.path}/${name}_${DateTime.now().millisecondsSinceEpoch}.jpg';
//   //     await File(path).writeAsBytes(img.encodeJpg(image));
//   //     debugPrint("📸 Saved Debug Align: $path");
//   //   } catch (e) {
//   //     debugPrint("⚠️ Cannot save debug image: $e");
//   //   }
//   // }

//   // --- CÁC HÀM XỬ LÝ TOÁN HỌC (MATH CORE) ---

//   /// Lấy danh sách 5 điểm landmark từ Face
//   static List<Point<double>>? _getLandmarks(Face face) {
//     final lm = face.landmarks;
//     var e1 = lm[FaceLandmarkType.leftEye]?.position;
//     var e2 = lm[FaceLandmarkType.rightEye]?.position;
//     var nose = lm[FaceLandmarkType.noseBase]?.position;
//     var m1 = lm[FaceLandmarkType.leftMouth]?.position;
//     var m2 = lm[FaceLandmarkType.rightMouth]?.position;

//     if (e1 == null || e2 == null || nose == null || m1 == null || m2 == null) {
//       return null;
//     }

//     // Đảm bảo LeftEye thực sự nằm bên trái (x nhỏ hơn)
//     // Đề phòng trường hợp Camera Selfie bị Mirror
//     Point<int> leftEye = (e1.x < e2.x) ? e1 : e2;
//     Point<int> rightEye = (e1.x < e2.x) ? e2 : e1;
//     Point<int> leftMouth = (m1.x < m2.x) ? m1 : m2;
//     Point<int> rightMouth = (m1.x < m2.x) ? m2 : m1;

//     // Convert sang Point<double>
//     return [
//       Point(leftEye.x.toDouble(), leftEye.y.toDouble()),
//       Point(rightEye.x.toDouble(), rightEye.y.toDouble()),
//       Point(nose.x.toDouble(), nose.y.toDouble()),
//       Point(leftMouth.x.toDouble(), leftMouth.y.toDouble()),
//       Point(rightMouth.x.toDouble(), rightMouth.y.toDouble()),
//     ];
//   }

//   /// Ước lượng ma trận Similarity Transform (Scale + Rotation + Translation)
//   /// Đây là phiên bản rút gọn của thuật toán Umeyama hoặc cv2.estimateAffinePartial2D
//   static List<double> _estimateSimilarityTransform(
//     List<Point<double>> src,
//     List<Point<double>> dst,
//   ) {
//     // Để đơn giản và nhanh trong Dart (tránh giải hệ phương trình phức tạp),
//     // ta sẽ tính dựa trên 2 mắt (quan trọng nhất cho Face ID).

//     // 1. Tính tâm của 2 mắt (Source vs Destination)
//     final srcCenter = Point(
//       (src[0].x + src[1].x) / 2,
//       (src[0].y + src[1].y) / 2,
//     );
//     final dstCenter = Point(
//       (dst[0].x + dst[1].x) / 2,
//       (dst[0].y + dst[1].y) / 2,
//     );

//     // 2. Tính sự chênh lệch toạ độ
//     final srcDeltaX = src[1].x - src[0].x;
//     final srcDeltaY = src[1].y - src[0].y;
//     final dstDeltaX = dst[1].x - dst[0].x;
//     final dstDeltaY = dst[1].y - dst[0].y;

//     // 3. Tính Scale (Tỷ lệ khoảng cách giữa 2 mắt)
//     final srcDist = sqrt(pow(srcDeltaX, 2) + pow(srcDeltaY, 2));
//     final dstDist = sqrt(pow(dstDeltaX, 2) + pow(dstDeltaY, 2));
//     final scale = dstDist / srcDist;

//     // 4. Tính Góc xoay (Rotation)
//     final srcAngle = atan2(srcDeltaY, srcDeltaX);
//     final dstAngle = atan2(dstDeltaY, dstDeltaX);
//     final rotation = dstAngle - srcAngle;

//     // 5. Tạo Ma trận [ a  b  tx ]
//     //                [ -b a  ty ]
//     final cosR = cos(rotation) * scale;
//     final sinR = sin(rotation) * scale;

//     // Tính Translation (Dịch chuyển)
//     // tx = dstCenter.x - (srcCenter.x * cosR - srcCenter.y * sinR)
//     final tx = dstCenter.x - (srcCenter.x * cosR - srcCenter.y * sinR);
//     final ty = dstCenter.y - (srcCenter.x * sinR + srcCenter.y * cosR);

//     // Ma trận 2x3 dạng phẳng: [a, b, tx, -b, a, ty]
//     // Lưu ý: Dart image dùng toạ độ khác chút, nhưng ta sẽ dùng logic Inverse Mapping ở dưới.
//     return [cosR, -sinR, tx, sinR, cosR, ty];
//   }

//   /// Hàm Warp Affine (Mô phỏng OpenCV) dùng Inverse Mapping + Bilinear Interpolation
//   static img.Image _warpAffine(img.Image src, List<double> M, int size) {
//     final dst = img.Image(width: size, height: size); // Ảnh đích 112x112

//     // Ma trận nghịch đảo (Inverse Matrix) để mapping từ Destination -> Source
//     // M = [a, b, c]
//     //     [d, e, f]
//     // Inverse det = a*e - b*d
//     final a = M[0], b = M[1], c = M[2];
//     final d = M[3], e = M[4], f = M[5];

//     final det = a * e - b * d;
//     if (det == 0) return dst; // Không thể nghịch đảo

//     // Tính ma trận nghịch đảo
//     final idet = 1.0 / det;
//     final ra = e * idet;
//     final rb = -b * idet;
//     final rc = (b * f - c * e) * idet;
//     final rd = -d * idet;
//     final re = a * idet;
//     final rf = (c * d - a * f) * idet;

//     // Duyệt qua từng pixel của ảnh ĐÍCH (Target)
//     for (int y = 0; y < size; y++) {
//       for (int x = 0; x < size; x++) {
//         // Tìm toạ độ tương ứng trên ảnh NGUỒN (Source)
//         final srcX = x * ra + y * rb + rc;
//         final srcY = x * rd + y * re + rf;

//         // Lấy màu tại (srcX, srcY) dùng Bilinear Interpolation (Nội suy)
//         // để ảnh mượt hơn, không bị răng cưa.
//         final pixel = src.getPixelInterpolate(
//           srcX,
//           srcY,
//           interpolation: img.Interpolation.linear,
//         );

//         dst.setPixel(x, y, pixel);
//       }
//     }
//     return dst;
//   }

//   /// Chuẩn hóa Tensor
//   static List<double> _imageToFloatList(img.Image image) {
//     var buffer = Float32List(112 * 112 * 3);
//     int pixelIndex = 0;
//     for (var y = 0; y < 112; y++) {
//       for (var x = 0; x < 112; x++) {
//         var pixel = image.getPixel(x, y);
//         // MobileFaceNet chuẩn: (x - 128) / 128
//         buffer[pixelIndex++] = (pixel.r - 128) / 128.0;
//         buffer[pixelIndex++] = (pixel.g - 128) / 128.0;
//         buffer[pixelIndex++] = (pixel.b - 128) / 128.0;
//       }
//     }
//     return buffer.toList();
//   }

//   /// Hàm chính: Căn chỉnh khuôn mặt
//   static Future<List<double>?> alignFace(
//     img.Image srcImage,
//     Face face, {
//     int targetSize = 112,
//     bool saveDebug = false,
//     String debugName = "debug",
//   }) async {
//     try {
//       // // 1. Decode ảnh (Nặng nhất, nên chạy Isolate nếu cần)
//       // final bytes = await File(imagePath).readAsBytes();
//       // final srcImage = img.decodeImage(bytes);
//       // if (srcImage == null) return null;

//       // 2. Lấy 5 điểm landmarks từ Face Object
//       final landmarks = _getLandmarks(face);
//       if (landmarks == null) {
//         debugPrint("⚠️ Không đủ 5 điểm landmark, bỏ qua.");
//         return null;
//       }

//       // 3. Tính toán Ma trận biến đổi (Transformation Matrix)
//       // Mục tiêu: Tìm ma trận M để biến đổi 5 điểm landmarks -> 5 điểm chuẩn (_refPoints)
//       // Sử dụng phương pháp ước lượng: Least Squares Similarity Transform
//       final matrix = _estimateSimilarityTransform(landmarks, _refPoints);

//       // 4. Warp Affine (Biến đổi ảnh theo ma trận)
//       // Tương đương cv2.warpAffine nhưng viết bằng Dart
//       final alignedImage = _warpAffine(srcImage, matrix, targetSize);

//       // if (saveDebug) {
//       //   await _saveDebugImage(alignedImage, debugName);
//       // }

//       // 5. Chuẩn hóa về Tensor [-1, 1] cho AI
//       return _imageToFloatList(alignedImage);
//     } catch (e) {
//       debugPrint("❌ Align Error: $e");
//       return null;
//     }
//   }

//   static Future<AlignmentResult?> alignFaceFromImageReturningImage(
//     img.Image srcImage,
//     Face face, {
//     int targetSize = 112,
//   }) async {
//     try {
//       // 1. Lấy Landmarks & Ma trận biến đổi (Tái sử dụng logic cũ)
//       final landmarks = _getLandmarks(face);
//       if (landmarks == null) return null;

//       final matrix = _estimateSimilarityTransform(landmarks, _refPoints);

//       // 2. Warp Affine -> Ra ảnh đã xoay thẳng tắp 112x112
//       final alignedImage = _warpAffine(srcImage, matrix, targetSize);

//       // 3. Convert sang pixels [-1, 1] cho AI
//       final aiPixels = _imageToFloatList(alignedImage);

//       // Trả về cả hai
//       return AlignmentResult(aiPixels, alignedImage);
//     } catch (e) {
//       debugPrint("❌ Align Error: $e");
//       return null;
//     }
//   }
// }
