#pragma once

#include "tensorflow/lite/c/c_api.h"
#include <algorithm>

class FaceQuality {
private:
  int inputWidth, inputHeight;

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
  int InitQualityModel(const void *modelData, int modelSize);

  float PredictQualityFromYuv(const unsigned char *yuvData, int imgW, int imgH,
                              int rotation, int rectX, int rectY, int rectW,
                              int rectH);

  float PredictQualityFromPixels(const float *inputPixels, int pixelsCount);
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