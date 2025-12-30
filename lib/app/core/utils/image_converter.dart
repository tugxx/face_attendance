import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../../data/models/camera_image.dart';

class ImageConverter {
  static Future<img.Image?> convertCameraImage(CameraImage cameraImage) async {
    try {
      final startTime = DateTime.now();

      // DEBUG: Kiểm tra format đầu vào ngay tại Main Thread
      debugPrint(
        "📸 Input Format: ${cameraImage.format.group}, Planes: ${cameraImage.planes.length}",
      );

      debugPrint("STEP 1: Bắt đầu copy dữ liệu...");
      // 1. Copy dữ liệu ở Main Thread (Nhanh, không tốn nhiều CPU)
      final data = CameraImageData.from(cameraImage);

      debugPrint("STEP 2: Gửi vào Isolate...");

      // 2. Gửi dữ liệu thuần (data) vào Isolate để tính toán nặng
      final result = await compute(_convertInternal, data);

      if (result == null) return null;

      // 3. Đóng gói thành ảnh tại Main Thread (Rất nhanh vì bytes đã có sẵn)
      final image = img.Image.fromBytes(
        width: result.width,
        height: result.height,
        bytes: result.rgbaBytes.buffer,
        order: img
            .ChannelOrder
            .rgba, // Quan trọng: Khớp với thứ tự ghi trong Isolate
      );

      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      debugPrint("✅ Convert xong trong: ${elapsed}ms");

      return image;
    } catch (e) {
      debugPrint("Lỗi khi chuẩn bị dữ liệu convert: $e");
      return null;
    }
  }

  static ConversionResult? _convertInternal(CameraImageData data) {
    try {
      Uint8List? rawBytes;

      if (Platform.isAndroid) {
        if (data.planes.length == 3) {
          rawBytes = _yuv420ToRgbaBytes(data);
        } else if (data.planes.length == 1) {
          rawBytes = _nv21ToRgbaBytes(data);
        }
      } else if (Platform.isIOS) {
         // iOS BGRA -> RGBA (Hoặc giữ nguyên tùy logic)
         if (data.planes.isNotEmpty) {
           // iOS thường là BGRA, ta trả về luôn để Image.fromBytes xử lý
           return ConversionResult(data.width, data.height, data.planes[0].bytes);
         }
      }

      // Fallback
      if (rawBytes == null) {
         if (data.planes.length == 3) rawBytes = _yuv420ToRgbaBytes(data);
         if (data.planes.length == 1) rawBytes = _nv21ToRgbaBytes(data);
      }

      if (rawBytes != null) {
        return ConversionResult(data.width, data.height, rawBytes);
      }
      
      debugPrint("⚠️ Format lạ: ${data.formatGroup}, Planes: ${data.planes.length}");
      return null;

    } catch (e, stack) {
      debugPrint("❌ CRASH Isolate: $e");
      debugPrint(stack.toString());
      return null;
    }
  }

  static Uint8List _nv21ToRgbaBytes(CameraImageData data) {
    final width = data.width;
    final height = data.height;
    final bytes = data.planes[0].bytes;
    final int uvRowStride = data.planes[0].bytesPerRow;
    final int uvPixelStride = 2;

    // Tạo mảng đích: width * height * 4 kênh màu (R, G, B, A)
    final Uint8List rgba = Uint8List(width * height * 4);
    
    // Tối ưu vòng lặp
    int byteIndex = 0;

    for (int y = 0; y < height; y++) {
      // Tính sẵn các biến không đổi trong hàng
      final int uvRowIndex = (height * uvRowStride) + (y >> 1) * uvRowStride;
      final int yRowIndex = y * uvRowStride;

      for (int x = 0; x < width; x++) {
        final int uvIndex = uvRowIndex + (x >> 1) * uvPixelStride;
        final int yIndex = yRowIndex + x;

        // Bounds Check nhanh
        if (yIndex >= bytes.length || uvIndex >= bytes.length - 1) {
          // Điền màu đen nếu lỗi
          rgba[byteIndex++] = 0; // R
          rgba[byteIndex++] = 0; // G
          rgba[byteIndex++] = 0; // B
          rgba[byteIndex++] = 255; // A
          continue;
        }

        final yp = bytes[yIndex];
        final vp = bytes[uvIndex];      // V
        final up = bytes[uvIndex + 1];  // U

        // Convert YUV -> RGB
        // Dùng phép dịch bit (bit shift) và số nguyên để tối ưu tốc độ thay vì số thực
        int r = (yp + (vp - 128) * 1436 ~/ 1024 - 179).clamp(0, 255);
        int g = (yp - (up - 128) * 46549 ~/ 131072 + 44 - (vp - 128) * 93604 ~/ 131072 + 91).clamp(0, 255);
        int b = (yp + (up - 128) * 1814 ~/ 1024 - 227).clamp(0, 255);

        // Ghi trực tiếp vào mảng byte (Nhanh gấp 10 lần setPixelRgb)
        rgba[byteIndex++] = r;
        rgba[byteIndex++] = g;
        rgba[byteIndex++] = b;
        rgba[byteIndex++] = 255; // Alpha
      }
    }
    return rgba;
  }

  // --- LOGIC YUV420 (3 Planes) -> RGBA Bytes ---
  static Uint8List _yuv420ToRgbaBytes(CameraImageData data) {
    final width = data.width;
    final height = data.height;
    final uvRowStride = data.planes[1].bytesPerRow;
    final uvPixelStride = data.planes[1].bytesPerPixel ?? 1;

    final yBytes = data.planes[0].bytes;
    final uBytes = data.planes[1].bytes;
    final vBytes = data.planes[2].bytes;

    final Uint8List rgba = Uint8List(width * height * 4);
    int byteIndex = 0;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int yIndex = y * width + x;
        final int uvIndex = uvPixelStride * (x >> 1) + uvRowStride * (y >> 1);

        if (yIndex >= yBytes.length || uvIndex >= uBytes.length || uvIndex >= vBytes.length) {
           rgba[byteIndex++] = 0; rgba[byteIndex++] = 0; rgba[byteIndex++] = 0; rgba[byteIndex++] = 255;
           continue;
        }

        final yp = yBytes[yIndex];
        final up = uBytes[uvIndex];
        final vp = vBytes[uvIndex];

        int r = (yp + (vp - 128) * 1436 ~/ 1024 - 179).clamp(0, 255);
        int g = (yp - (up - 128) * 46549 ~/ 131072 + 44 - (vp - 128) * 93604 ~/ 131072 + 91).clamp(0, 255);
        int b = (yp + (up - 128) * 1814 ~/ 1024 - 227).clamp(0, 255);

        rgba[byteIndex++] = r;
        rgba[byteIndex++] = g;
        rgba[byteIndex++] = b;
        rgba[byteIndex++] = 255;
      }
    }
    return rgba;
  }

    // static img.Image? _convertInternal(CameraImageData data) {
  //   try {
  //     debugPrint(
  //       "STEP 3: Đã vào Isolate. Format: ${data.formatGroup}, Planes: ${data.planes.length}",
  //     );

  //     Uint8List? rawBytes;

  //     if (Platform.isAndroid) {
  //       if (data.planes.length == 3) {
  //         return _convertYuv420ThreePlanes(data);
  //       } else if (data.planes.length == 1) {
  //         return _convertNv21OnePlane(data);
  //       }
  //     } else if (Platform.isIOS) {
  //       if (data.formatGroup == ImageFormatGroup.bgra8888 ||
  //           data.planes.length == 1) {
  //         return _convertBGRA8888ToImage(data);
  //       }
  //     }

  //     if (data.planes.length == 3) return _convertYuv420ThreePlanes(data);
  //     if (data.planes.length == 1) return _convertNv21OnePlane(data);

  //     debugPrint(
  //       "⚠️ Unknown Format Structure: Planes=${data.planes.length}, Group=${data.formatGroup}",
  //     );
  //     return null;
  //   } catch (e, stackTrace) {
  //     debugPrint("Isolate Crash: $e"); // In lỗi nếu có trong isolate
  //     debugPrint(stackTrace.toString());
  //     return null;
  //   }
  // }

  /// Convert cho Android (YUV420)
  // static img.Image _convertYuv420ThreePlanes(CameraImageData data) {
  //   final int width = data.width;
  //   final int height = data.height;
  //   final int uvRowStride = data.planes[1].bytesPerRow;
  //   final int uvPixelStride = data.planes[1].bytesPerPixel ?? 1; // Có thể null

  //   final Uint8List yBytes = data.planes[0].bytes;
  //   final Uint8List uBytes = data.planes[1].bytes;
  //   final Uint8List vBytes = data.planes[2].bytes;

  //   var imgBuffer = img.Image(width: width, height: height);

  //   for (int y = 0; y < height; y++) {
  //     for (int x = 0; x < width; x++) {
  //       final int yIndex = y * width + x;
  //       final int uvIndex =
  //           uvPixelStride * (x / 2).floor() + uvRowStride * (y / 2).floor();

  //       if (yIndex >= yBytes.length ||
  //           uvIndex >= uBytes.length ||
  //           uvIndex >= vBytes.length) {
  //         continue;
  //       }

  //       final yp = yBytes[yIndex];
  //       final up = uBytes[uvIndex];
  //       final vp = vBytes[uvIndex];

  //       _setPixel(imgBuffer, x, y, yp, up, vp);
  //     }
  //   }
  //   return imgBuffer;
  // }

  // static img.Image _convertNv21OnePlane(CameraImageData data) {
  //   final width = data.width;
  //   final height = data.height;
  //   final bytes = data.planes[0].bytes; // Tất cả dữ liệu nằm trong plane 0

  //   final int uvRowStride = data.planes[0].bytesPerRow;
  //   final int uvPixelStride = 2;

  //   var imgBuffer = img.Image(width: width, height: height);

  //   for (int y = 0; y < height; y++) {
  //     for (int x = 0; x < width; x++) {
  //       final int yIndex = y * uvRowStride + x;

  //       // Công thức NV21 offset
  //       final int uvIndex =
  //           (uvRowStride * height) +
  //           (y ~/ 2) * uvRowStride +
  //           (x ~/ 2) * uvPixelStride;

  //       // Bounds Check an toàn
  //       if (yIndex >= bytes.length || uvIndex >= bytes.length - 1) continue;

  //       final yp = bytes[yIndex];

  //       // NV21 thường là V trước U sau (hoặc ngược lại tùy máy, nhưng cứ lấy cặp là có màu)
  //       final vp = bytes[uvIndex];
  //       final up = bytes[uvIndex + 1];

  //       _setPixel(imgBuffer, x, y, yp, up, vp);
  //     }
  //   }
  //   return imgBuffer;
  // }

  // /// Convert cho iOS (BGRA8888)
  // static img.Image _convertBGRA8888ToImage(CameraImageData data) {
  //   return img.Image.fromBytes(
  //     width: data.width,
  //     height: data.height,
  //     bytes: data.planes[0].bytes.buffer,
  //     order: img.ChannelOrder.bgra,
  //   );
  // }

  // // Hàm phụ để tính toán RGB và gán vào ảnh
  // static void _setPixel(img.Image image, int x, int y, int yp, int up, int vp) {
  //   int r = (yp + (vp - 128) * 1.402).toInt();
  //   int g = (yp - (up - 128) * 0.34414 - (vp - 128) * 0.71414).toInt();
  //   int b = (yp + (up - 128) * 1.772).toInt();

  //   image.setPixelRgb(x, y, r.clamp(0, 255), g.clamp(0, 255), b.clamp(0, 255));
  // }

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
