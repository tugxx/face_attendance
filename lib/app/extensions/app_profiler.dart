import 'dart:developer';
import 'package:flutter/foundation.dart';

import '../services/log_service.dart';

class AppProfiler {
  /// Hàm bọc (Wrapper) để đo đạc bất kỳ đoạn code bất đồng bộ (Future) nào
  static Future<T> measureAsync<T>(
    String taskName,
    Future<T> Function() task,
  ) async {
    // NẾU LÀ BẢN RELEASE (Đẩy lên CH Play), KHÔNG LÀM GÌ CẢ (Chạy thẳng hàm luôn)
    if (kReleaseMode) {
      return await task();
    }

    // NẾU LÀ DEBUG: Bắt đầu bấm giờ
    final stopwatch = Stopwatch()..start();
    try {
      // Timeline.timeSync giúp vẽ biểu đồ trên Flutter DevTools
      return await Timeline.timeSync(taskName, () async {
        return await task();
      });
    } finally {
      stopwatch.stop();
      AppLog.info(
        "⏱️ [PROFILE] $taskName tốn: ${stopwatch.elapsedMilliseconds}ms",
      );
    }
  }
}
