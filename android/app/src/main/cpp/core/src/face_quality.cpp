#include "tensorflow/lite/c/c_api.h"
#include <algorithm>

#include "app_log.h"
#include "face_quality.h"
#include "native_face_align.h"

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
    LOG_ERROR(
        "❌ Lỗi: Không thể khởi tạo TfLite Interpreter cho Quality Model!");
    return false;
  }

  if (TfLiteInterpreterAllocateTensors(qualityInterpreter) != kTfLiteOk) {
    return -1;
  }

  TfLiteTensor *inputTensor =
      TfLiteInterpreterGetInputTensor(qualityInterpreter, 0);
  this->inputHeight = TfLiteTensorDim(inputTensor, 1);
  this->inputWidth = TfLiteTensorDim(inputTensor, 2);
  this->qualitySize = this->inputWidth * this->inputHeight * 3;

  this->tfliteInputData = (float *)TfLiteTensorData(inputTensor);
  const TfLiteTensor *outputTensor =
      TfLiteInterpreterGetOutputTensor(qualityInterpreter, 0);
  this->tfliteOutputData = (float *)TfLiteTensorData(outputTensor);

  if (this->sharedBuffer) {
    free(this->sharedBuffer); // Đề phòng Init gọi nhiều lần
  }
  this->sharedBuffer = (float *)malloc(this->qualitySize * sizeof(float));

  if (!this->sharedBuffer)
    return -1;

  return (this->inputWidth << 16) | this->inputHeight;
}

float FaceQuality::PredictQualityFromYuv(const unsigned char *yuvData, int imgW,
                                         int imgH, int rotation, int rectX,
                                         int rectY, int rectW, int rectH) {
  if (qualityInterpreter == nullptr) {
    LOG_ERROR("❌ Lỗi: Quality Interpreter chưa được khởi tạo!");
    return -1.0f;
  }

  // Cắt ảnh (Với scale 1.2f chuyên dụng cho model Quality)
  bool cropSuccess =
      process_face_crop((uint8_t *)yuvData, imgW, imgH, imgW, rotation, rectX,
                        rectY, rectW, rectH, this->inputWidth,
                        this->inputHeight, 1.2f, false, this->sharedBuffer);

  if (!cropSuccess) {
    LOG_ERROR("Crop FaceQuality thất bại!");
    return -1.0f;
  }

  // TIỀN XỬ LÝ CHUẨN XÁC (Giấu kín logic này bên trong)
  for (int i = 0; i < qualitySize; i++) {
    this->sharedBuffer[i] = (this->sharedBuffer[i] - 128.0f) / 128.0f;
  }

  // Chuyển cho Hàm 2 chạy AI
  float score =
      this->PredictQualityFromPixels(this->sharedBuffer, this->qualitySize);

  return score;
}

float FaceQuality::PredictQualityFromPixels(const float *inputPixels,
                                            int pixelsCount) {
  if (qualityInterpreter == nullptr) {
    LOG_ERROR("❌ Lỗi: Quality Interpreter chưa được khởi tạo!");
    return -1.0f;
  }

  if (pixelsCount != this->qualitySize) {
    LOG_ERROR(
        "🛑 LỖI INPUT QUALITY: Nhận được %d, nhưng Model cần %d",
        pixelsCount, this->qualitySize);
    return -1.0f;
  }

  memcpy(this->tfliteInputData, inputPixels, pixelsCount * sizeof(float));

  // 2. Chạy Model (Inference)
  if (TfLiteInterpreterInvoke(qualityInterpreter) != kTfLiteOk) {
    LOG_ERROR("❌ Lỗi Invoke Face Quality Model!");
    return -1.0f;
  }

  // 4. Trả thẳng điểm số
  return this->tfliteOutputData[0];
}

void FaceQuality::Release() {
  if (sharedBuffer) {
    free(sharedBuffer);
    sharedBuffer = nullptr;
  }
}
