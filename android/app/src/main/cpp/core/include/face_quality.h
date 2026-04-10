#pragma once

#include "tensorflow/lite/c/c_api.h"
#include <algorithm>

class FaceQuality {
private:
  int inputWidth, inputHeight;

  // Pointer giữ Model và Interpreter theo chuẩn C API
  TfLiteModel *qualityModel;
  TfLiteInterpreter *qualityInterpreter;

public:
  FaceQuality() : qualityModel(nullptr), qualityInterpreter(nullptr) {}

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

  // // Vô hiệu hóa Copy Constructor và Assignment Operator để đảm bảo Singleton
  // FaceQuality(const FaceQuality &) = delete;
  // FaceQuality &operator=(const FaceQuality &) = delete;

  // // Cung cấp Instance duy nhất (Thread-safe trong C++11 trở lên)
  // static FaceQuality *GetInstance() {
  //   static FaceQuality instance;
  //   return &instance;
  // }

  int qualitySize;
  float *sharedBuffer = nullptr;
  float *tfliteInputData = nullptr;
  float *tfliteOutputData = nullptr;

  // Khởi tạo model từ mảng byte truyền từ Dart xuống
  int InitQualityModel(const void *modelData, int modelSize);

  float PredictQualityFromYuv(const unsigned char *yuvData, int imgW, int imgH,
                              int rotation, int rectX, int rectY, int rectW,
                              int rectH);

  float PredictQualityFromPixels(const float *inputPixels, int pixelsCount);

  void Release();
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