#include "face_quality.h"
#include "tensorflow/lite/c/c_api.h"
#include <algorithm>
// #include <android/log.h>
// #define LOGI(...)                                                              \
//   __android_log_print(ANDROID_LOG_INFO, "FACE_AI_CPP", __VA_ARGS__)

// Giả sử bạn có class FaceQuality có cấu trúc Singleton tương tự
// AntiSpoofing
bool FaceQuality::InitQualityModel(const void *modelData, int modelSize) {
  if (modelData == nullptr)
    return false;

  // LOGI("🌟 Nạp Face Quality Model (LightQNet)...");
  TfLiteInterpreterOptions *options = TfLiteInterpreterOptionsCreate();
  TfLiteInterpreterOptionsSetNumThreads(options, 2); // 2 luồng là đủ mượt

  qualityModel = TfLiteModelCreate(modelData, modelSize);
  qualityInterpreter = TfLiteInterpreterCreate(qualityModel, options);
  TfLiteInterpreterAllocateTensors(qualityInterpreter);

  TfLiteInterpreterOptionsDelete(options);
  return qualityInterpreter != nullptr;
}

float FaceQuality::PredictQuality(const float *inputPixels, int pixelsCount) {
  if (qualityInterpreter == nullptr) {
    // LOGI("❌ Lỗi: Quality Interpreter chưa được khởi tạo!");
    return -1.0f;
  }

  TfLiteTensor *inputTensor =
      TfLiteInterpreterGetInputTensor(qualityInterpreter, 0);

  // Kích thước chuẩn của LightQNet là 96x96x3 = 27648
  int expectedSize = TfLiteTensorByteSize(inputTensor) / sizeof(float);

  if (pixelsCount != expectedSize) {
    // LOGI("🛑 LỖI INPUT QUALITY: Nhận được %d, nhưng Model cần %d",
    //      pixelsCount, expectedSize);
    return -1.0f;
  }

  // 1. Đưa dữ liệu ảnh vào Tensor
  float *inputData = (float *)TfLiteTensorData(inputTensor);
  memcpy(inputData, inputPixels, pixelsCount * sizeof(float));

  // 2. Chạy Model (Inference)
  if (TfLiteInterpreterInvoke(qualityInterpreter) != kTfLiteOk) {
    // LOGI("❌ Lỗi Invoke Face Quality Model!");
    return -1.0f;
  }

  // 3. Lấy Output (Một giá trị Float duy nhất)
  const TfLiteTensor *outputTensor =
      TfLiteInterpreterGetOutputTensor(qualityInterpreter, 0);
  float *outputData = (float *)TfLiteTensorData(outputTensor);

  // 4. Trả thẳng điểm số (Không cần tính Softmax)
  float qualityScore = outputData[0];
  return qualityScore;
}