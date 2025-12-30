import 'dart:typed_data';
import 'package:camera/camera.dart';

// Đặt class này ở file image_converter.dart hoặc file riêng
class CameraImageData {
  final int width;
  final int height;
  final ImageFormatGroup formatGroup;
  final List<PlaneData> planes;

  CameraImageData({
    required this.width,
    required this.height,
    required this.formatGroup,
    required this.planes,
  });

  // Hàm copy dữ liệu từ CameraImage thật sang DTO
  factory CameraImageData.from(CameraImage image) {
    return CameraImageData(
      width: image.width,
      height: image.height,
      formatGroup: image.format.group,
      planes: image.planes.map((p) => PlaneData.from(p)).toList(),
    );
  }
}

class PlaneData {
  final int bytesPerRow;
  final int? bytesPerPixel;
  final Uint8List bytes; // Dữ liệu pixel đã được copy

  PlaneData({
    required this.bytesPerRow,
    this.bytesPerPixel,
    required this.bytes,
  });

  static PlaneData from(Plane plane) {
    return PlaneData(
      bytesPerRow: plane.bytesPerRow,
      bytesPerPixel: plane.bytesPerPixel,
      bytes: Uint8List.fromList(plane.bytes), // Copy dữ liệu an toàn
    );
  }
}

class ConversionResult {
  final int width;
  final int height;
  final Uint8List rgbaBytes; // Chứa dữ liệu ảnh đã convert

  ConversionResult(this.width, this.height, this.rgbaBytes);
}
