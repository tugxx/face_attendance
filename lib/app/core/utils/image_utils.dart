import 'package:image/image.dart' as img;
import 'package:flutter/foundation.dart';


/// Hàm này sẽ chạy trong một Isolate riêng biệt.
/// Nó nhận vào mảng byte (ảnh đã nén) và trả về đối tượng ảnh đã decode sạch sẽ.
img.Image? processImageInIsolate(Uint8List compressedBytes) {
  try {
    // 1. Decode ảnh (Tốn nhiều RAM nhất là ở bước này)
    // Vì chạy ở Isolate nên RAM này tách biệt hoàn toàn với App chính
    img.Image? decoded = img.decodeImage(compressedBytes);

    if (decoded == null) return null;

    // 2. Chuẩn hóa format ảnh (Fix lỗi sai màu trên một số dòng máy)
    // AI thường yêu cầu format uint8 và 3 kênh màu (RGB)
    if (decoded.numChannels < 3 || decoded.format != img.Format.uint8) {
      final cleanImage = img.Image(
        width: decoded.width,
        height: decoded.height,
        numChannels: 3, // Ép về RGB
        format: img.Format.uint8, // Ép về Uint8
      );
      // Vẽ ảnh cũ lên ảnh mới đã chuẩn hóa
      img.compositeImage(cleanImage, decoded);
      return cleanImage;
    }

    return decoded;
  } catch (e) {
    debugPrint("Lỗi trong Isolate xử lý ảnh: $e");
    return null;
  }
}