import 'dart:developer';
import 'package:flutter/foundation.dart';

import '../services/log_service.dart';

class AppProfiler {
  final Stopwatch _totalWatch = Stopwatch();
  final Stopwatch _stepWatch = Stopwatch();
  final Map<String, int> _metrics = {};

  void start() {
    if (kReleaseMode) return; // Không tốn CPU trên Production
    _totalWatch.start();
    _stepWatch.start();
  }

  Future<T> measureStep<T>(String stepName, Future<T> Function() task) async {
    // NẾU LÀ BẢN RELEASE (Đẩy lên CH Play), KHÔNG LÀM GÌ CẢ (Chạy thẳng hàm luôn)
    if (kReleaseMode) {
      return await task();
    }

    return await Timeline.timeSync(stepName, () async {
      final result = await task();

      // Bây giờ hàm này có thể thoải mái truy cập _metrics và _stepWatch
      _metrics[stepName] = _stepWatch.elapsedMilliseconds;
      _stepWatch.reset();
      _stepWatch.start();

      return result;
    });
  }

  static Future<T> measureAsync<T>(
    String taskName,
    Future<T> Function() task,
  ) async {
    if (kReleaseMode) return await task();

    final stopwatch = Stopwatch()..start();
    try {
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

  void report() {
    if (kReleaseMode) return;
    _totalWatch.stop();
    final details = _metrics.entries
        .map((e) => "${e.key}: ${e.value}ms")
        .join(" | ");

    // Đổ ra đúng 1 dòng Log
    AppLog.info(
      "⏱️ [FRAME_PIPELINE] Tổng: ${_totalWatch.elapsedMilliseconds}ms 👉 $details",
    );
  }

  int? getMetric(String key) => _metrics[key];
}
