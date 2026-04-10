#pragma once

#include <algorithm>
#include <string>
#include <vector>

#include "tensorflow/lite/c/c_api.h"

struct FaceTemplateData {
  std::string name;
  std::string templateId;
  std::vector<float> features;
};

// Struct chứa kết quả trả về
struct RecognitionResult {
  std::string name;
  float score;
  bool isUnknown;
  std::string matchedTemplateId;
  std::string imposterName;
  float imposterScore;
};

class FaceRecognizer {
private:
  TfLiteModel *faceModel;
  TfLiteInterpreter *faceInterpreter;

  std::vector<FaceTemplateData> faceDatabase;

  // static FaceRecognizer *instance;

  int featureSize = 0;

  // FaceRecognizer() : faceModel(nullptr), faceInterpreter(nullptr) {}

  void L2Normalize(float *embedding, int size);
  float CosineSimilarity(const std::vector<float> &v1,
                         const std::vector<float> &v2);

public:
  FaceRecognizer() : faceModel(nullptr), faceInterpreter(nullptr) {}

  // static FaceRecognizer *GetInstance();
  int inputWidth, inputHeight;

  int recogSize = 0;
  float *sharedBuffer = nullptr;
  float *tfliteInputData = nullptr;
  float *tfliteOutputData = nullptr;

  // Các hàm xử lý
  int InitFaceModel(const void *faceData, int faceSize);

  void RegisterFace(const char *name, const float *embedding, int size,
                    const std::string &templateId);
  void ClearDatabase();

  bool ExtractFaceFeature(const float *inputPixels, int pixelsCount,
                          float *outFeature);

  RecognitionResult PredictFaceFromYuv(const unsigned char *yuvData, int imgW,
                                       int imgH, const float *landmarks,
                                       int rotation, int rectX, int rectY,
                                       int rectW, int rectH, float threshold);

  RecognitionResult PredictFaceFromPixels(const float *inputPixels,
                                          int pixelsCount, float threshold);

  void RemoveFace(const char *name);

  void MergeAndNormalize(const float *v1, const float *v2, int size,
                         float *outVec);

  void Release();
};