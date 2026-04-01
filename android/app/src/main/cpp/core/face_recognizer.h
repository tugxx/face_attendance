#pragma once // Chống include lặp vòng

#include <string>
#include <unordered_map>
#include <vector>

#include "tensorflow/lite/c/c_api.h"

// Struct chứa kết quả trả về
struct RecognitionResult {
  std::string name;
  float distance;
  bool isUnknown;
};

class FaceRecognizer {
private:
  TfLiteModel *faceModel;
  TfLiteInterpreter *faceInterpreter;

  // Database lưu trên RAM
  std::unordered_map<std::string, std::vector<float>> faceDatabase;

  // Singleton instance
  static FaceRecognizer *instance;

  // Private constructor (Singleton)
  FaceRecognizer() : faceModel(nullptr), faceInterpreter(nullptr) {}

  void L2Normalize(std::vector<float> &embedding);

  float CosineSimilarity(const std::vector<float> &v1,
                         const std::vector<float> &v2);

public:
  static FaceRecognizer *GetInstance();

  // Các hàm xử lý
  bool InitFaceModel(const void *faceData, int faceSize);

  void RegisterFace(const char *name, const float *embedding, int size);
  void ClearDatabase();

  std::vector<float> ExtractFaceFeature(const float *inputPixels,
                                        int pixelsCount);

  RecognitionResult PredictFace(const float *inputPixels, int pixelsCount,
                                float threshold);

  void RemoveFace(const char *name);
};