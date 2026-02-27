import 'dart:ui';

class BBoxSmoother {
  Rect? _smoothedRect;

  // Hệ số làm mượt (Từ 0.0 đến 1.0)
  // - Càng gần 0: Khung hình càng mượt, ít rung, nhưng bám theo mặt hơi trễ (lag).
  // - Càng gần 1: Bám sát mặt ngay lập tức, nhưng dễ bị rung.
  // 0.3 là "điểm ngọt" (sweet spot) cho nhận diện khuôn mặt.
  final double alpha = 0.3;

  Rect smooth(Rect currentRect) {
    if (_smoothedRect == null) {
      _smoothedRect = currentRect;
      return currentRect;
    }

    // Nếu người dùng giật mặt ra chỗ khác đột ngột (khoảng cách giữa 2 khung quá lớn)
    // -> Reset lại bộ lọc để tránh khung hình bị "trôi" từ từ theo.
    double dx = (currentRect.center.dx - _smoothedRect!.center.dx).abs();
    double dy = (currentRect.center.dy - _smoothedRect!.center.dy).abs();
    if (dx > currentRect.width * 0.5 || dy > currentRect.height * 0.5) {
      _smoothedRect = currentRect;
      return currentRect;
    }

    // Công thức EMA (Exponential Moving Average)
    double newLeft =
        _smoothedRect!.left + alpha * (currentRect.left - _smoothedRect!.left);
    double newTop =
        _smoothedRect!.top + alpha * (currentRect.top - _smoothedRect!.top);
    double newRight =
        _smoothedRect!.right +
        alpha * (currentRect.right - _smoothedRect!.right);
    double newBottom =
        _smoothedRect!.bottom +
        alpha * (currentRect.bottom - _smoothedRect!.bottom);

    _smoothedRect = Rect.fromLTRB(newLeft, newTop, newRight, newBottom);
    return _smoothedRect!;
  }

  void reset() {
    _smoothedRect = null;
  }
}
