#pragma once

#include "tensorflow/lite/c/c_api.h"
#include <algorithm>

// Include macro LOGI của bạn ở đây. Ví dụ (nếu dùng Android NDK):
// #include <android/log.h>
// #define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "FaceQuality",
// __VA_ARGS__)

class FaceQuality {
private:
  // Constructor Private cho Singleton
  FaceQuality() : qualityModel(nullptr), qualityInterpreter(nullptr) {}

  // Destructor: Dọn rác khi module bị hủy
  ~FaceQuality() {
    if (qualityInterpreter != nullptr) {
      TfLiteInterpreterDelete(qualityInterpreter);
      qualityInterpreter = nullptr;
    }
    if (qualityModel != nullptr) {
      TfLiteModelDelete(qualityModel);
      qualityModel = nullptr;
    }
  }

  // Pointer giữ Model và Interpreter theo chuẩn C API
  TfLiteModel *qualityModel;
  TfLiteInterpreter *qualityInterpreter;

public:
  // Vô hiệu hóa Copy Constructor và Assignment Operator để đảm bảo Singleton
  FaceQuality(const FaceQuality &) = delete;
  FaceQuality &operator=(const FaceQuality &) = delete;

  // Cung cấp Instance duy nhất (Thread-safe trong C++11 trở lên)
  static FaceQuality *GetInstance() {
    static FaceQuality instance;
    return &instance;
  }

  // Khởi tạo model từ mảng byte truyền từ Dart xuống
  bool InitQualityModel(const void *modelData, int modelSize);

  // Nhận mảng float pixel (đã chuẩn hóa) và trả về điểm số chất lượng
  float PredictQuality(const float *inputPixels, int pixelsCount);
};

// ====================================================================
// EXPORT FUNCTIONS CHO DART FFI
// ====================================================================

#ifdef __cplusplus
extern "C" {
#endif

// Hàm khởi tạo Model
__attribute__((visibility("default"))) __attribute__((used)) int
InitQualityModelNative(const void *modelData, int modelSize);

// Hàm dự đoán
__attribute__((visibility("default"))) __attribute__((used)) float
PredictQualityNative(const float *inputPixels, int pixelsCount);

#ifdef __cplusplus
}
#endif