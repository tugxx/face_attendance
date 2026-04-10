#include <algorithm>

#include "anti_spoofing.h"
#include "app_log.h"
#include "native_face_align.h"

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
  this->spoofSize = this->inputWidth * this->inputHeight * 3;

  this->tfliteInputData = (float *)TfLiteTensorData(inputTensor);
  const TfLiteTensor *outputTensor =
      TfLiteInterpreterGetOutputTensor(spoofInterpreter, 0);
  this->tfliteOutputData = (float *)TfLiteTensorData(outputTensor);

  if (this->sharedBuffer != nullptr) {
    free(this->sharedBuffer);
  }

  this->sharedBuffer = (float *)malloc(this->spoofSize * sizeof(float));

  if (!this->sharedBuffer) {
    LOG_ERROR("❌ Lỗi: Không đủ RAM để cấp phát Shared Buffer cho Spoof!");
    return -1;
  }

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

  bool cropSuccess =
      process_face_crop((uint8_t *)yuvData, imgW, imgH, imgW, rotation, rectX,
                        rectY, rectW, rectH, this->inputWidth,
                        this->inputHeight, 2.0f, true, this->sharedBuffer);

  if (!cropSuccess) {
    LOG_ERROR("Crop Anti-Spoof thất bại");
    return {-1.0f, false};
  }

  SpoofResult result = this->PredictSpoofFromPixels(this->sharedBuffer,
                                                    this->spoofSize, threshold);

  return result;
}

SpoofResult AntiSpoofing::PredictSpoofFromPixels(const float *inputPixels,
                                                 int pixelsCount,
                                                 float threshold) {
  if (spoofInterpreter == nullptr) {
    LOG_ERROR("❌ Lỗi: Spoof Interpreter chưa được khởi tạo!");
    return {-1.0f, false};
  }

  // 🛡️ CHỐT CHẶN AN TOÀN TRƯỚC KHI MEMCPY
  if (pixelsCount != this->spoofSize) {
    LOG_ERROR(
        "🛑 LỖI TÍNH TOÁN RAM: Nhận được %d, nhưng Model cần %d",
        pixelsCount, this->spoofSize);
    return {-1.0f, false};
  }

  memcpy(this->tfliteInputData, inputPixels, pixelsCount * sizeof(float));

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

void AntiSpoofing::Release() {
  if (this->sharedBuffer != nullptr) {
    free(this->sharedBuffer);
    this->sharedBuffer = nullptr;
  }
}
