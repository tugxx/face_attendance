import 'package:flutter/foundation.dart';

class AppLog {
  // 1. Log thông tin bình thường (Màu xanh)
  static void info(String message) {
    if (kDebugMode) {
      debugPrint('🔵 [INFO]: $message');
    }
  }

  // 2. Log cảnh báo (Màu cam)
  static void warning(String message) {
    if (kDebugMode) {
      debugPrint('🟠 [WARN]: $message');
    }
  }

  // 3. Log lỗi (Màu đỏ) - Hỗ trợ in luôn cả object Exception
  static void error(String message, [dynamic error]) {
    if (kDebugMode) {
      debugPrint('🔴 [ERROR]: $message');
      if (error != null) {
        debugPrint('   ↳ Chi tiết: $error');
      }
    }
  }

  // 4. (Bonus) Log chuyên dụng cho Anti-Spoofing để dễ lọc
  static void spoof(String message) {
    if (kDebugMode) {
      debugPrint('🛡️ [ANTI-SPOOF]: $message');
    }
  }
}
