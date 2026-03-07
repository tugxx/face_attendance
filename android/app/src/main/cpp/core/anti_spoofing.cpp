#include "anti_spoofing.h"
#include <algorithm>
#include <android/log.h>
#include <cmath>

#define LOGI(...)                                                              \
  __android_log_print(ANDROID_LOG_INFO, "AntiSpoofing", __VA_ARGS__)

AntiSpoofing *AntiSpoofing::instance = nullptr;

AntiSpoofing *AntiSpoofing::GetInstance() {
  if (instance == nullptr) {
    instance = new AntiSpoofing();
  }
  return instance;
}

bool AntiSpoofing::InitSpoofModel(const void *spoofData, int spoofSize) {
  if (spoofData == nullptr)
    return false;

  LOGI("🛡️ Nạp Anti-Spoof Model...");
  TfLiteInterpreterOptions *options = TfLiteInterpreterOptionsCreate();
  TfLiteInterpreterOptionsSetNumThreads(
      options, 2); // Spoof model nhẹ hơn, 2 luồng là đủ

  spoofModel = TfLiteModelCreate(spoofData, spoofSize);
  spoofInterpreter = TfLiteInterpreterCreate(spoofModel, options);
  TfLiteInterpreterAllocateTensors(spoofInterpreter);

  TfLiteInterpreterOptionsDelete(options);
  return spoofInterpreter != nullptr;
}

float AntiSpoofing::PredictSpoof(const float *inputPixels, int pixelsCount) {
  if (spoofInterpreter == nullptr) {
    LOGI("❌ Lỗi: Spoof Interpreter chưa được khởi tạo!");
    return -1.0f;
  }

  TfLiteTensor *inputTensor =
      TfLiteInterpreterGetInputTensor(spoofInterpreter, 0);
  int expectedSize = TfLiteTensorByteSize(inputTensor) /
                     sizeof(float); // Thường là 80x80x3 = 19200

  if (pixelsCount != expectedSize) {
    LOGI("🛑 LỖI INPUT SPOOF: Nhận được %d, nhưng Model cần %d",
         pixelsCount, expectedSize);
    return -1.0f;
  }

  // 1. Đưa dữ liệu ảnh vào Tensor
  float *inputData = (float *)TfLiteTensorData(inputTensor);
  memcpy(inputData, inputPixels, pixelsCount * sizeof(float));

  // 2. Chạy Model (Inference)
  if (TfLiteInterpreterInvoke(spoofInterpreter) != kTfLiteOk) {
    LOGI("❌ Lỗi Invoke Anti-Spoof Model!");
    return -1.0f;
  }

  // 3. Lấy Output (Logits: mảng 3 phần tử)
  const TfLiteTensor *outputTensor =
      TfLiteInterpreterGetOutputTensor(spoofInterpreter, 0);
  float *logits = (float *)TfLiteTensorData(outputTensor);

  // 4. Tính toán Softmax thủ công cực nhanh (Không cấp phát RAM động)
  float maxVal = std::max({logits[0], logits[1], logits[2]});
  float sumExp = 0.0f;
  float exps[3];

  for (int i = 0; i < 3; ++i) {
    exps[i] = std::exp(logits[i] - maxVal);
    sumExp += exps[i];
  }

  // 5. Trích xuất xác suất của Class 1 (Real)
  float scoreReal = exps[1] / sumExp;

  return scoreReal;
}
