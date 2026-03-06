import 'dart:ui';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../../app/services/log_service.dart';

class CameraUtils {
  // Đặt private constructor để ngăn khởi tạo class này (CameraUtils() -> Lỗi)
  // Vì đây là class tiện ích chỉ chứa hàm static.
  CameraUtils._();

  /// Hàm chuyển đổi từ ảnh Camera (của Flutter) sang ảnh Input (của ML Kit)
  static InputImage? convertCameraImageToInputImage(
    CameraImage image,
    CameraDescription camera,
  ) {
    // 1. Ghép dữ liệu ảnh (Bytes Concatenation)
    // CameraImage trả về ảnh dưới dạng các lớp (planes) rời rạc (Y, U, V).
    // ML Kit cần một mảng bytes liền mạch.
    final WriteBuffer allBytes = WriteBuffer();
    for (final Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final Uint8List bytes = allBytes.done().buffer.asUint8List();

    // 2. Lấy kích thước ảnh gốc
    final Size imageSize = Size(
      image.width.toDouble(),
      image.height.toDouble(),
    );

    // 3. Xử lý góc xoay (Rotation)
    final InputImageRotation? imageRotation =
        InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (imageRotation == null) return null;

    // 4. Xử lý định dạng (Format)
    final InputImageFormat? inputImageFormat =
        InputImageFormatValue.fromRawValue(image.format.raw);
    if (inputImageFormat == null) return null;

    // 5. Tạo Metadata (Thông tin phụ trợ)
    // Đây là "tờ hướng dẫn sử dụng" để ML Kit biết cách đọc mảng 'bytes' ở trên.
    // bytesPerRow: Số byte trên một dòng (để xử lý padding nếu có).
    final inputImageMetadata = InputImageMetadata(
      size: imageSize,
      rotation: imageRotation,
      format: inputImageFormat,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    // 6. Đóng gói thành InputImage hoàn chỉnh
    return InputImage.fromBytes(bytes: bytes, metadata: inputImageMetadata);
  }

  // Hàm hỗ trợ Clone dữ liệu ảnh
  static Uint8List cloneCameraBytes(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int targetSize = (width * height * 1.5).toInt();
    final buffer = Uint8List(targetSize);

    try {
      // --- TRƯỜNG HỢP 1: ANDROID (3 Planes - Y, U, V) ---
      // Thường là định dạng YUV420 hoặc NV21
      if (image.planes.length == 3) {
        final yPlane = image.planes[0];
        final vPlane = image.planes[2];

        // 1. Copy Y (Luminance)
        buffer.setRange(0, width * height, yPlane.bytes);

        // 2. Copy UV (Chrominance)
        // Kiểm tra stride = 2 (nghĩa là 2 byte liên tiếp là V-U-V-U...) -> Chuẩn NV21
        if (vPlane.bytesPerPixel == 2) {
          final int uvOffset = width * height;
          final int bytesToCopy = vPlane.bytes.length;

          // Chỉ copy phần dữ liệu vừa đủ với targetSize để tránh lỗi tràn bộ nhớ
          final int copyLength = (uvOffset + bytesToCopy > targetSize)
              ? targetSize - uvOffset
              : bytesToCopy;

          buffer.setRange(uvOffset, uvOffset + copyLength, vPlane.bytes);
        } else {
          // Fallback: Nếu không phải NV21 chuẩn, tạm thời để trống vùng UV (Ảnh đen trắng)
          // để tránh crash, vì việc ghép tay U và V riêng lẻ rất tốn CPU.
          AppLog.warning("⚠️ Warning: Camera format not generic NV21.");
        }
      }
      // --- TRƯỜNG HỢP 2: iOS / Một số máy Android (1 Plane) ---
      // Dữ liệu gộp chung, cần xử lý Row Padding (Stride)
      else if (image.planes.length == 1) {
        final plane = image.planes[0];
        final int rowStride = plane.bytesPerRow;

        // TH A: Dữ liệu sạch (Stride == Width)
        if (rowStride == width) {
          final int copyLength = (plane.bytes.length > targetSize)
              ? targetSize
              : plane.bytes.length;
          buffer.setRange(0, copyLength, plane.bytes);
        }
        // TH B: Có Padding (RowStride > Width) -> Phải lọc bỏ rác ở cuối mỗi dòng
        else {
          // A. Copy vùng Y (Luminance)
          for (int row = 0; row < height; row++) {
            int srcPos = row * rowStride;
            int dstPos = row * width;

            buffer.setRange(dstPos, dstPos + width, plane.bytes, srcPos);
          }

          // Copy vùng UV bắt đầu ngay sau vùng Y (tính theo stride gốc)
          int uvSrcStart = height * rowStride;
          int uvDstStart = width * height;
          final int uvHeight = height ~/ 2;

          for (int row = 0; row < uvHeight; row++) {
            int srcPos = uvSrcStart + (row * rowStride);
            int dstPos = uvDstStart + (row * width);

            // Kiểm tra biên để không crash nếu buffer thiếu
            if (srcPos + width <= plane.bytes.length &&
                dstPos + width <= buffer.length) {
              buffer.setRange(dstPos, dstPos + width, plane.bytes, srcPos);
            }
          }
        }
      }
    } catch (e) {
      AppLog.warning("⚠️ Lỗi copy bytes: $e");
      // Trả về buffer rỗng
      return Uint8List(targetSize);
    }

    return buffer;
  }

  static Rect calculateCropRect(Face face, int imgWidth, int imgHeight) {
    double centerX = face.boundingBox.center.dx;
    double centerY = face.boundingBox.center.dy;

    // Scale factor 0.5 (Lấy rộng ra 50%)
    double maxSide = max(face.boundingBox.width, face.boundingBox.height);
    double sideLength = maxSide * 1.5;

    double x = centerX - sideLength / 2;
    double y = centerY - sideLength / 2;

    Rect proposedRect = Rect.fromLTWH(x, y, sideLength, sideLength);
    Rect imageRect = Rect.fromLTWH(
      0,
      0,
      imgWidth.toDouble(),
      imgHeight.toDouble(),
    );

    // Lấy phần giao nhau để đảm bảo không crash do crop ra ngoài ảnh
    return proposedRect.intersect(imageRect);
  }
}
