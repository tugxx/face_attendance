#include "tensorflow/lite/c/c_api.h"
#include <algorithm>
#include <android/log.h>

#include "face_quality.h"
#include "native_face_align.h"

#define LOGI(...)                                                              \
  __android_log_print(ANDROID_LOG_INFO, "FACE_AI_CPP", __VA_ARGS__)

int FaceQuality::InitQualityModel(const void *modelData, int modelSize) {
  if (modelData == nullptr)
    return -1;

  qualityModel = TfLiteModelCreate(modelData, modelSize);
  if (qualityModel == nullptr)
    return -1;

  TfLiteInterpreterOptions *options = TfLiteInterpreterOptionsCreate();
  TfLiteInterpreterOptionsSetNumThreads(options, 2); // 2 luồng là đủ mượt

  qualityInterpreter = TfLiteInterpreterCreate(qualityModel, options);
  TfLiteInterpreterOptionsDelete(options);

  if (qualityInterpreter == nullptr) {
    LOGI("❌ Lỗi: Không thể khởi tạo TfLite Interpreter cho Quality Model!");
    return false;
  }

  if (TfLiteInterpreterAllocateTensors(qualityInterpreter) != kTfLiteOk) {
    return -1;
  }

  TfLiteTensor *inputTensor =
      TfLiteInterpreterGetInputTensor(qualityInterpreter, 0);
  this->inputHeight = TfLiteTensorDim(inputTensor, 1);
  this->inputWidth = TfLiteTensorDim(inputTensor, 2);

  return (this->inputWidth << 16) | this->inputHeight;
}

float FaceQuality::PredictQualityFromYuv(const unsigned char *yuvData, int imgW,
                                         int imgH, int rotation, int rectX,
                                         int rectY, int rectW, int rectH) {
  if (qualityInterpreter == nullptr) {
    LOGI("❌ Lỗi: Quality Interpreter chưa được khởi tạo!");
    return -1.0f;
  }

  // Tự lấy kích thước đã lưu từ lúc Init
  int qualitySize = this->inputWidth * this->inputHeight * 3;
  float *qualityBuffer = (float *)malloc(qualitySize * sizeof(float));

  if (!qualityBuffer)
    return -1.0f;

  // Cắt ảnh (Với scale 1.2f chuyên dụng cho model Quality)
  process_face_crop((uint8_t *)yuvData, imgW, imgH, imgW, rotation, rectX,
                    rectY, rectW, rectH, this->inputWidth, this->inputHeight,
                    1.2f, false, qualityBuffer);

  // TIỀN XỬ LÝ CHUẨN XÁC (Giấu kín logic này bên trong)
  for (int i = 0; i < qualitySize; i++) {
    qualityBuffer[i] = (qualityBuffer[i] - 128.0f) / 128.0f;
  }

  // Chuyển cho Hàm 2 chạy AI
  float score = this->PredictQualityFromPixels(qualityBuffer, qualitySize);

  free(qualityBuffer);
  return score;
}

float FaceQuality::PredictQualityFromPixels(const float *inputPixels,
                                            int pixelsCount) {
  if (qualityInterpreter == nullptr) {
    LOGI("❌ Lỗi: Quality Interpreter chưa được khởi tạo!");
    return -1.0f;
  }

  TfLiteTensor *inputTensor =
      TfLiteInterpreterGetInputTensor(qualityInterpreter, 0);
  int expectedSize = TfLiteTensorByteSize(inputTensor) / sizeof(float);

  if (pixelsCount != expectedSize) {
    LOGI("🛑 LỖI INPUT QUALITY: Nhận được %d, nhưng Model cần %d",
         pixelsCount, expectedSize);
    return -1.0f;
  }

  // 1. Đưa dữ liệu ảnh vào Tensor
  float *inputData = (float *)TfLiteTensorData(inputTensor);
  memcpy(inputData, inputPixels, pixelsCount * sizeof(float));

  // 2. Chạy Model (Inference)
  if (TfLiteInterpreterInvoke(qualityInterpreter) != kTfLiteOk) {
    LOGI("❌ Lỗi Invoke Face Quality Model!");
    return -1.0f;
  }

  // 3. Lấy Output (Một giá trị Float duy nhất)
  const TfLiteTensor *outputTensor =
      TfLiteInterpreterGetOutputTensor(qualityInterpreter, 0);
  float *outputData = (float *)TfLiteTensorData(outputTensor);

  // 4. Trả thẳng điểm số
  return outputData[0];
}
