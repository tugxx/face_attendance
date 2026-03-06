import 'package:flutter/foundation.dart';

class RegistrationResult {
  final List<double> aiPixels; // Input cho Model AI
  final Uint8List displayBytes; // Ảnh JPG để hiển thị UI

  RegistrationResult(this.aiPixels, this.displayBytes);
}