#include <algorithm>
#include <cmath>

#include "app_log.h"
#include "face_recognizer.h"
#include "native_face_align.h"

FaceRecognizer *FaceRecognizer::instance = nullptr;

FaceRecognizer *FaceRecognizer::GetInstance() {
  if (instance == nullptr) {
    instance = new FaceRecognizer();
  }
  return instance;
}

int FaceRecognizer::InitFaceModel(const void *faceData, int faceSize) {
  if (faceData == nullptr)
    return -1;

  faceModel = TfLiteModelCreate(faceData, faceSize);
  if (faceModel == nullptr) {
    LOG_ERROR("❌ Lỗi: Định dạng file TFLite không hợp lệ hoặc bị hỏng!");
    return -1;
  }

  TfLiteInterpreterOptions *options = TfLiteInterpreterOptionsCreate();
  TfLiteInterpreterOptionsSetNumThreads(options, 4);

  faceInterpreter = TfLiteInterpreterCreate(faceModel, options);
  TfLiteInterpreterOptionsDelete(options);

  if (faceInterpreter == nullptr) {
    LOG_ERROR("❌ Lỗi: Không thể khởi tạo TfLite Interpreter!");
    return -1;
  }

  if (TfLiteInterpreterAllocateTensors(faceInterpreter) != kTfLiteOk) {
    LOG_ERROR("❌ Lỗi: Không thể Allocate Tensors. Có thể do hết RAM!");
    return -1;
  }

  const TfLiteTensor *outputTensor =
      TfLiteInterpreterGetOutputTensor(faceInterpreter, 0);
  this->featureSize = TfLiteTensorByteSize(outputTensor) / sizeof(float);

  TfLiteTensor *inputTensor =
      TfLiteInterpreterGetInputTensor(faceInterpreter, 0);
  this->inputHeight = TfLiteTensorDim(inputTensor, 1);
  this->inputWidth = TfLiteTensorDim(inputTensor, 2);

  return (this->inputWidth << 16) | this->inputHeight;
}

void FaceRecognizer::RegisterFace(const char *name, const float *embedding,
                                  int size, const std::string &templateId) {
  FaceTemplateData data;
  data.name = std::string(name);
  data.templateId = templateId;
  data.features = std::vector<float>(embedding, embedding + size);

  faceDatabase.push_back(data);
}

void FaceRecognizer::ClearDatabase() { faceDatabase.clear(); }

void FaceRecognizer::L2Normalize(float *embedding, int size) {
  float squareSum = 0.0f;
  for (int i = 0; i < size; ++i) {
    squareSum += embedding[i] * embedding[i];
  }

  float invNorm = 1.0f / std::sqrt(std::max(squareSum, 1e-10f));

  for (int i = 0; i < size; ++i) {
    embedding[i] *= invNorm;
  }
}

bool FaceRecognizer::ExtractFaceFeature(const float *inputPixels,
                                        int pixelsCount, float *outFeature) {
  if (faceInterpreter == nullptr) {
    LOG_ERROR("❌ Lỗi: Face Interpreter chưa được khởi tạo!");
    return false;
  }

  // Lấy Input Tensor để kiểm tra kích thước
  TfLiteTensor *inputTensor =
      TfLiteInterpreterGetInputTensor(faceInterpreter, 0);
  int expectedSize = TfLiteTensorByteSize(inputTensor) / sizeof(float);

  if (pixelsCount != expectedSize) {
    LOG_ERROR(
        "🛑 LỖI INPUT MODEL: Nhận được %d, nhưng Model cần %d",
        pixelsCount, expectedSize);
    return false;
  }

  // 2. Đưa dữ liệu vào Model (Thay cho bước Reshape ở Dart)
  // memcpy copy toàn bộ mảng trong nháy mắt
  float *inputData = (float *)TfLiteTensorData(inputTensor);
  memcpy(inputData, inputPixels, pixelsCount * sizeof(float));

  // 3. Run Inference (Chạy AI)
  if (TfLiteInterpreterInvoke(faceInterpreter) != kTfLiteOk) {
    LOG_ERROR("❌ Lỗi khi chạy Invoke Face Model!");
    return false;
  }

  // 4. Lấy kết quả ra (Thay cho bước Flatten ở Dart)
  const TfLiteTensor *outputTensor =
      TfLiteInterpreterGetOutputTensor(faceInterpreter, 0);
  float *outputData = (float *)TfLiteTensorData(outputTensor);
  int outputSize = TfLiteTensorByteSize(outputTensor) / sizeof(float);

  if (outputSize != this->featureSize) {
    LOG_ERROR("❌ Lỗi: Size output thay đổi bất thường!");
    return false;
  }

  memcpy(outFeature, outputData, outputSize * sizeof(float));

  // 5. L2 Normalize (Bắt buộc)
  L2Normalize(outFeature, outputSize);

  return true;
}

float FaceRecognizer::CosineSimilarity(const std::vector<float> &v1,
                                       const std::vector<float> &v2) {
  float dot = 0.0f;
  int size = v1.size();
  for (int i = 0; i < size; ++i) {
    dot += v1[i] * v2[i];
  }
  return dot;
}

RecognitionResult FaceRecognizer::PredictFaceFromYuv(
    const unsigned char *yuvData, int imgW, int imgH, const float *landmarks,
    int rotation, int rectX, int rectY, int rectW, int rectH, float threshold) {
  RecognitionResult result = {"Unknown", -1.0f, true, "", "Unknown", -1.0f};

  if (faceInterpreter == nullptr)
    return result;

  int recogSize = this->inputWidth * this->inputHeight * 3;
  float *recogBuffer = (float *)malloc(recogSize * sizeof(float));
  if (!recogBuffer)
    return result;

  // 2. Tự Affine Transform
  process_face_affine((uint8_t *)yuvData, imgW, imgH, (float *)landmarks,
                      rotation, recogBuffer);

  result = this->PredictFaceFromPixels(recogBuffer, recogSize, threshold);
  free(recogBuffer);

  return result;
}

RecognitionResult
FaceRecognizer::PredictFaceFromPixels(const float *inputPixels, int pixelsCount,
                                      float threshold) {
  RecognitionResult result = {"Unknown", -1.0f, true, "", "Unknown", -1.0f};
  if (faceInterpreter == nullptr)
    return result;

  // 1. Trích xuất (Extract)
  std::vector<float> embedding(this->featureSize);
  bool success = ExtractFaceFeature(inputPixels, pixelsCount, embedding.data());

  if (!success) {
    result.name = "Error";
    return result;
  }

  // 2. Tìm kiếm (Match)
  float bestScore = -1.0f;
  std::string bestMatch = "Unknown";
  std::string bestTemplateId = "";
  float secondBestScore = -1.0f;
  std::string secondBestMatch = "Unknown";

  for (const auto &tmpl : faceDatabase) {
    float score = CosineSimilarity(embedding, tmpl.features);

    if (score > bestScore) {
      if (tmpl.name != bestMatch) {
        secondBestScore = bestScore;
        secondBestMatch = bestMatch;
      }
      bestScore = score;
      bestMatch = tmpl.name;
      bestTemplateId = tmpl.templateId;
    } else if (score > secondBestScore && tmpl.name != bestMatch) {
      secondBestScore = score;
      secondBestMatch = tmpl.name;
    }
  }

  // 3. Đóng gói kết quả
  result.imposterName = secondBestMatch;
  result.imposterScore = secondBestScore;
  result.score = bestScore;

  if (bestScore >= threshold) {
    result.name = bestMatch;
    result.isUnknown = false;
    result.matchedTemplateId = bestTemplateId;
  }

  return result;
}

void FaceRecognizer::RemoveFace(const char *name) {
  std::string target(name);

  faceDatabase.erase(std::remove_if(faceDatabase.begin(), faceDatabase.end(),
                                    [&target](const FaceTemplateData &data) {
                                      return data.name == target;
                                    }),
                     faceDatabase.end());

  LOG_INFO("Đã xóa khuôn mặt: %s khỏi RAM", name);
}

void FaceRecognizer::MergeAndNormalize(const float *v1, const float *v2,
                                       int size, float *outVec) {
  float squareSum = 0.0f;

  // 1. Cộng 2 vector và tính Tổng bình phương trong 1 vòng lặp duy nhất
  for (int i = 0; i < size; ++i) {
    outVec[i] = v1[i] + v2[i];
    squareSum += outVec[i] * outVec[i];
  }

  // 2. Tính số nghịch đảo chuẩn hóa L2
  float invNorm = 1.0f / std::sqrt(std::max(squareSum, 1e-10f));

  // 3. Nhân chuẩn hóa và ghi đè thẳng vào kết quả đầu ra
  for (int i = 0; i < size; ++i) {
    outVec[i] *= invNorm;
  }
}
