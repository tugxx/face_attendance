#pragma once
#include "tensorflow/lite/c/c_api.h"

class AntiSpoofing {
private:
  TfLiteModel *spoofModel;
  TfLiteInterpreter *spoofInterpreter;

  static AntiSpoofing *instance;

  AntiSpoofing() : spoofModel(nullptr), spoofInterpreter(nullptr) {}

public:
  static AntiSpoofing *GetInstance();

  bool InitSpoofModel(const void *spoofData, int spoofSize);
  float PredictSpoof(const float *inputPixels, int pixelsCount);
};