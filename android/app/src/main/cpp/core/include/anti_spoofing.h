#pragma once
#include "tensorflow/lite/c/c_api.h"

struct SpoofResult {
  float score;
  bool isReal;
};

class AntiSpoofing {
private:
  TfLiteModel *spoofModel;
  TfLiteInterpreter *spoofInterpreter;
  int inputWidth, inputHeight;

public:
  AntiSpoofing() : spoofModel(nullptr), spoofInterpreter(nullptr) {}

  int spoofSize = 0;
  float *sharedBuffer = nullptr;
  float *tfliteInputData = nullptr;
  float *tfliteOutputData = nullptr;

  int InitSpoofModel(const void *spoofData, int spoofSize);
  SpoofResult PredictSpoofFromYuv(const unsigned char *yuvData, int imgW,
                                  int imgH, int rotation, int rectX, int rectY,
                                  int rectW, int rectH, float threshold);

  SpoofResult PredictSpoofFromPixels(const float *inputPixels, int pixelsCount,
                                     float threshold);

  void Release();
};