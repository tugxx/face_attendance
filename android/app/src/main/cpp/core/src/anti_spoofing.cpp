#include <algorithm>

#include "anti_spoofing.h"
#include "app_log.h"
#include "native_face_align.h"

AntiSpoofing *AntiSpoofing::instance = nullptr;

AntiSpoofing *AntiSpoofing::GetInstance() {
  if (instance == nullptr) {
    instance = new AntiSpoofing();
  }
  return instance;
}

int AntiSpoofing::InitSpoofModel(const void *spoofData, int spoofSize) {
  if (spoofData == nullptr) {
    LOG_ERROR("Dữ liệu Spoof Model bị rỗng (null)!");
    return -1;
  }

  spoofModel = TfLiteModelCreate(spoofData, spoofSize);
  if (spoofModel == nullptr) {
    LOG_ERROR("Không thể nạp Spoof Model (File lỗi hoặc sai định dạng)!");
    return -1;
  }

  TfLiteInterpreterOptions *options = TfLiteInterpreterOptionsCreate();
  TfLiteInterpreterOptionsSetNumThreads(options, 2);

  spoofInterpreter = TfLiteInterpreterCreate(spoofModel, options);
  TfLiteInterpreterOptionsDelete(options);

  if (spoofInterpreter == nullptr) {
    LOG_ERROR("Không thể tạo Spoof Interpreter!");
    return -1;
  }

  if (TfLiteInterpreterAllocateTensors(spoofInterpreter) != kTfLiteOk) {
    LOG_ERROR("Lỗi Allocate Tensors cho Spoof Model (Có thể do hết RAM)!");
    return -1;
  }

  TfLiteTensor *inputTensor =
      TfLiteInterpreterGetInputTensor(spoofInterpreter, 0);
  this->inputHeight = TfLiteTensorDim(inputTensor, 1);
  this->inputWidth = TfLiteTensorDim(inputTensor, 2);

  return (this->inputWidth << 16) | this->inputHeight;
}

SpoofResult AntiSpoofing::PredictSpoofFromYuv(const unsigned char *yuvData,
                                              int imgW, int imgH, int rotation,
                                              int rectX, int rectY, int rectW,
                                              int rectH, float threshold) {
  if (spoofInterpreter == nullptr) {
    LOG_ERROR("❌ Lỗi: Spoof Interpreter chưa được khởi tạo!");
    return {-1.0f, false};
  }

  int spoofSize = this->inputWidth * this->inputHeight * 3;
  float *spoofBuffer = (float *)malloc(spoofSize * sizeof(float));

  if (!spoofBuffer)
    return {-1.0f, false};

  process_face_crop((uint8_t *)yuvData, imgW, imgH, imgW, rotation, rectX,
                    rectY, rectW, rectH, this->inputWidth, this->inputHeight,
                    2.0f, true, spoofBuffer);

  SpoofResult result =
      this->PredictSpoofFromPixels(spoofBuffer, spoofSize, threshold);

  free(spoofBuffer);

  return result;
}

SpoofResult AntiSpoofing::PredictSpoofFromPixels(const float *inputPixels,
                                                 int pixelsCount,
                                                 float threshold) {
  if (spoofInterpreter == nullptr) {
    LOG_ERROR("❌ Lỗi: Spoof Interpreter chưa được khởi tạo!");
    return {-1.0f, false};
  }

  TfLiteTensor *inputTensor =
      TfLiteInterpreterGetInputTensor(spoofInterpreter, 0);
  int expectedSize = TfLiteTensorByteSize(inputTensor) / sizeof(float);

  // 🛡️ CHỐT CHẶN AN TOÀN TRƯỚC KHI MEMCPY
  if (pixelsCount != expectedSize) {
    LOG_ERROR(
        "🛑 LỖI TÍNH TOÁN RAM: Nhận được %d, nhưng Model cần %d",
        pixelsCount, expectedSize);
    return {-1.0f, false};
  }

  // 1. Copy an toàn
  float *inputData = (float *)TfLiteTensorData(inputTensor);
  memcpy(inputData, inputPixels, pixelsCount * sizeof(float));

  // 2. Chạy Model
  if (TfLiteInterpreterInvoke(spoofInterpreter) != kTfLiteOk) {
    LOG_ERROR("❌ Lỗi Invoke Anti-Spoof Model!");
    return {-1.0f, false};
  }

  // 3. Lấy Output
  const TfLiteTensor *outputTensor =
      TfLiteInterpreterGetOutputTensor(spoofInterpreter, 0);
  float *logits = (float *)TfLiteTensorData(outputTensor);

  // 4. Softmax thủ công
  float maxVal = std::max({logits[0], logits[1], logits[2]});
  float sumExp = 0.0f;
  float exps[3];

  for (int i = 0; i < 3; ++i) {
    exps[i] = std::exp(logits[i] - maxVal);
    sumExp += exps[i];
  }

  float scoreReal = exps[1] / sumExp;

  return {scoreReal, scoreReal >= threshold};
}
