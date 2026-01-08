import 'dart:ffi'; // Quan trọng
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:ffi/ffi.dart'; // Cần thêm package: flutter pub add ffi
import 'package:flutter/foundation.dart';

// 1. Định nghĩa kiểu hàm trong C
typedef ConvertFunc =
    Void Function(
      Pointer<Uint8> data,
      Pointer<Uint8> outputRGBA,
      Int32 width,
      Int32 height,
    );

// 2. Định nghĩa kiểu hàm trong Dart
typedef ConvertFuncDart =
    void Function(
      Pointer<Uint8> data,
      Pointer<Uint8> outputRGBA,
      int width,
      int height,
    );

class ImageConverterFFI {
  static DynamicLibrary? _lib;
  static ConvertFuncDart? _convertFunc;

  static void init() {
    if (_lib != null) return;

    // Load thư viện .so đã build từ C++
    if (Platform.isAndroid) {
      _lib = DynamicLibrary.open('libnative_convert.so');
    } else if (Platform.isIOS) {
      // iOS cần setup khác một chút trong Podfile, tạm thời tập trung Android trước
      _lib = DynamicLibrary.process();
    }

    if (_lib != null) {
      try {
        _convertFunc = _lib!
            .lookup<NativeFunction<ConvertFunc>>('convertNV21ToRGB')
            .asFunction<ConvertFuncDart>();
      } catch (e) {
        debugPrint("FFI Lookup Error: $e");
      }
    }
  }

  static Uint8List cloneCameraBytes(CameraImage image) {
    // Android YUV420 thường có 3 planes: Y, U, V.
    // Để gửi xuống C++ xử lý kiểu NV21, ta nối chúng lại: Y + V + U (hoặc Y + UV interleaved)
    // Code dưới đây copy toàn bộ bytes liên tiếp để an toàn nhất.

    // Tính tổng kích thước
    int totalSize = 0;
    for (var plane in image.planes) {
      totalSize += plane.bytes.length;
    }

    final buffer = Uint8List(totalSize);
    int offset = 0;

    for (var plane in image.planes) {
      buffer.setRange(offset, offset + plane.bytes.length, plane.bytes);
      offset += plane.bytes.length;
    }

    return buffer;
  }

  // --- HÀM 2: Convert thực tế (Có thể chạy sau await) ---
  // Input là bytes đã clone, KHÔNG phải CameraImage
  static Uint8List? convertYUVBytesToRGB(
    Uint8List yuvBytes,
    int width,
    int height,
  ) {
    if (_convertFunc == null) init();
    if (_convertFunc == null) return null;

    final int totalBytes = yuvBytes.length;

    // Cấp phát bộ nhớ Native
    final Pointer<Uint8> dataPtr = calloc<Uint8>(totalBytes);
    final Pointer<Uint8> outputBuffer = calloc<Uint8>(width * height * 4);

    try {
      // 1. Copy dữ liệu từ Dart (Safe Heap) sang Native (C Heap)
      // Dùng asTypedList để copy nhanh
      final dataList = dataPtr.asTypedList(totalBytes);
      dataList.setAll(0, yuvBytes);

      // 2. Gọi hàm C++
      _convertFunc!(dataPtr, outputBuffer, width, height);

      // 3. Lấy kết quả về
      // .asUint8List() tạo ra một view, ta cần .sublist() hoặc dọn dẹp sau khi return
      // Nhưng để an toàn và Dart quản lý vòng đời, ta copy ra một Uint8List mới của Dart.
      final resultBytes = Uint8List.fromList(
        outputBuffer.asTypedList(width * height * 4),
      );

      return resultBytes;
    } catch (e) {
      debugPrint("❌ FFI Convert Error: $e");
      return null;
    } finally {
      // Dọn dẹp bộ nhớ Native ngay lập tức
      calloc.free(dataPtr);
      calloc.free(outputBuffer);
    }
  }

  // Hàm thực thi chuyển đổi
  static Uint8List? convertCameraImage(CameraImage image) {
    if (_convertFunc == null) init();

    final int width = image.width;
    final int height = image.height;

    if (image.planes.isEmpty || image.planes[0].bytes.isEmpty) {
      return null;
    }

    // NV21 trên Flutter Android: planes[0] chứa TOÀN BỘ dữ liệu (Y + UV)
    // planes[1] và planes[2] chỉ là view ảo, ta không cần dùng.
    final int totalBytes = image.planes[0].bytes.length;

    final Pointer<Uint8> outputBuffer = calloc<Uint8>(width * height * 4);
    final Pointer<Uint8> dataPtr = calloc<Uint8>(totalBytes);

    try {
      // Copy toàn bộ dữ liệu vào vùng nhớ native
      dataPtr.asTypedList(totalBytes).setAll(0, image.planes[0].bytes);

      _convertFunc!(dataPtr, outputBuffer, width, height);

      // Chuyển kết quả từ Pointer về Uint8List để Dart dùng
      final resultBytes = outputBuffer
          .asTypedList(width * height * 4)
          .buffer
          .asUint8List();

      // Phải copy ra mảng mới để return, vì outputBuffer sẽ bị free ngay sau đây
      return Uint8List.fromList(resultBytes);
    } catch (e) {
      debugPrint("FFI Error: $e");
      return null;
    } finally {
      // Dọn dẹp bộ nhớ Native (Cực kỳ quan trọng, không làm là tràn RAM)
      calloc.free(outputBuffer);
      calloc.free(dataPtr);
    }
  }
}
