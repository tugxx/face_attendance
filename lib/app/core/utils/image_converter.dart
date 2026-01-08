import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

// import '../../data/models/camera_image.dart';

class ImageConverter {
  static Future<img.Image?> convertCameraImage(CameraImage image) async {
    try {
      // Chỉ hỗ trợ Android NV21 (dạng phổ biến nhất)
      if (Platform.isAndroid && image.format.group == ImageFormatGroup.nv21) {
        return _convertNV21ToRGB(image);
      }
      // Hỗ trợ iOS BGRA8888
      else if (Platform.isIOS &&
          image.format.group == ImageFormatGroup.bgra8888) {
        return _convertBGRA8888ToRGB(image);
      }

      debugPrint("⚠️ Định dạng ảnh không hỗ trợ: ${image.format.group}");
      return null;
    } catch (e) {
      debugPrint("❌ Lỗi convert ảnh: $e");
      return null;
    }
  }

  // --- LOGIC CHUYỂN ĐỔI MỚI (Dùng thư viện ảnh chuẩn) ---

  // 1. Cho Android (NV21)
  static img.Image _convertNV21ToRGB(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final img.Image rgbImage = img.Image(width: width, height: height);

    // TRƯỜNG HỢP 1: Máy cũ (Redmi 5 Plus) trả về 1 cục byte duy nhất chứa cả Y và UV
    if (image.planes.length == 1) {
      final Uint8List bytes = image.planes[0].bytes;
      final int uvOffset = width * height; // UV bắt đầu ngay sau vùng Y

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * width + x;

          // Tính chỉ số UV (NV21: V trước, U sau)
          // UV giảm mẫu 2x2, nên chia đôi tọa độ
          final int uvIndex = uvOffset + (y >> 1) * width + (x & ~1);

          // Kiểm tra bounds để tránh crash (quan trọng cho máy cũ)
          if (yIndex >= bytes.length || uvIndex + 1 >= bytes.length) {
            continue;
          }

          final int yp = bytes[yIndex];
          final int vp = bytes[uvIndex]; // V nằm trước
          final int up = bytes[uvIndex + 1]; // U nằm sau

          _yuvToRgb(yp, up, vp, x, y, rgbImage);
        }
      }
    }
    // TRƯỜNG HỢP 2: Máy tiêu chuẩn trả về Plane riêng biệt (Y riêng, UV riêng)
    else {
      final Uint8List yPlane = image.planes[0].bytes;
      final Uint8List uvPlane = image.planes[1].bytes;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 2;

      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * width + x;
          final int uvIndex = (y >> 1) * uvRowStride + (x >> 1) * uvPixelStride;

          final int yp = yPlane[yIndex];
          final int vp = uvPlane[uvIndex]; // V
          final int up = uvPlane[uvIndex + 1]; // U

          _yuvToRgb(yp, up, vp, x, y, rgbImage);
        }
      }
    }
    return rgbImage;
  }

  // Hàm tính toán màu chung (Công thức chuẩn)
  static void _yuvToRgb(int y, int u, int v, int x, int h, img.Image target) {
    // Nếu U, V = 0 hết (lỗi xanh lè), ta ép về 128 để ra ảnh đen trắng (Grayscale)
    // Ảnh đen trắng AI vẫn nhận diện tốt, còn ảnh xanh thì không.
    if (u == 0 && v == 0) {
      u = 128;
      v = 128;
    }

    int r = (y + 1.370705 * (v - 128)).round().clamp(0, 255);
    int g = (y - 0.337633 * (u - 128) - 0.698001 * (v - 128)).round().clamp(
      0,
      255,
    );
    int b = (y + 1.732446 * (u - 128)).round().clamp(0, 255);

    target.setPixelRgba(x, h, r, g, b, 255);
  }

  // 2. Cho iOS (BGRA8888) - Đơn giản hơn nhiều
  static img.Image _convertBGRA8888ToRGB(CameraImage image) {
    return img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.planes[0].bytes.buffer,
      order: img.ChannelOrder.bgra, // iOS dùng BGRA
    );
  }

  /// Cắt (Crop) khuôn mặt từ ảnh gốc dựa trên BoundingBox
  static img.Image cropFace(
    img.Image originalImage,
    double left,
    double top,
    double width,
    double height,
  ) {
    // Cần đảm bảo tọa độ không vượt quá kích thước ảnh
    int x = left.toInt().clamp(0, originalImage.width - 1);
    int y = top.toInt().clamp(0, originalImage.height - 1);
    int w = width.toInt().clamp(1, originalImage.width - x);
    int h = height.toInt().clamp(1, originalImage.height - y);

    return img.copyCrop(originalImage, x: x, y: y, width: w, height: h);
  }
}
