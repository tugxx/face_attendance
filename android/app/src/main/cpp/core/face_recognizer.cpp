#include "face_recognizer.h"
#include <algorithm>
#include <android/log.h>
#include <cmath>

#define LOGI(...)                                                              \
  __android_log_print(ANDROID_LOG_INFO, "FaceRecognizer", __VA_ARGS__)

FaceRecognizer *FaceRecognizer::instance = nullptr;

FaceRecognizer *FaceRecognizer::GetInstance() {
  if (instance == nullptr) {
    instance = new FaceRecognizer();
  }
  return instance;
}

bool FaceRecognizer::InitFaceModel(const void *faceData, int faceSize) {
  if (faceData == nullptr)
    return false;

  LOGI("🧠 Nạp Face Model...");
  TfLiteInterpreterOptions *options = TfLiteInterpreterOptionsCreate();
  TfLiteInterpreterOptionsSetNumThreads(options, 4); // Nhận diện dùng 4 luồng

  faceModel = TfLiteModelCreate(faceData, faceSize);
  faceInterpreter = TfLiteInterpreterCreate(faceModel, options);
  TfLiteInterpreterAllocateTensors(faceInterpreter);

  TfLiteInterpreterOptionsDelete(options);
  return faceInterpreter != nullptr;
}

void FaceRecognizer::RegisterFace(const char *name, const float *embedding,
                                  int size) {
  std::vector<float> vec(embedding, embedding + size);
  faceDatabase[std::string(name)] = vec;
}

void FaceRecognizer::ClearDatabase() { faceDatabase.clear(); }

void FaceRecognizer::L2Normalize(std::vector<float> &embedding) {
  float squareSum = 0.0f;
  for (float x : embedding) {
    squareSum += x * x;
  }

  // std::max để tránh lỗi chia cho 0 (1e-10)
  float xInvNorm = std::sqrt(std::max(squareSum, 1e-10f));

  for (float &x : embedding) {
    x /= xInvNorm;
  }
}

// Hàm Extract Embedding
std::vector<float> FaceRecognizer::ExtractFaceFeature(const float *inputPixels,
                                                      int pixelsCount) {
  // 1. Kiểm tra Model đã load chưa
  if (faceInterpreter == nullptr) {
    LOGI("❌ Lỗi: Face Interpreter chưa được khởi tạo!");
    return {}; // Trả về vector rỗng giống Dart
  }

  // Lấy Input Tensor để kiểm tra kích thước
  TfLiteTensor *inputTensor =
      TfLiteInterpreterGetInputTensor(faceInterpreter, 0);
  int expectedSize = TfLiteTensorByteSize(inputTensor) /
                     sizeof(float); // Thường là 112x112x3 = 37632

  if (pixelsCount != expectedSize) {
    LOGI("🛑 LỖI INPUT MODEL: Nhận được %d, nhưng Model cần %d",
         pixelsCount, expectedSize);
    return {};
  }

  // 2. Đưa dữ liệu vào Model (Thay cho bước Reshape ở Dart)
  // memcpy copy toàn bộ mảng trong nháy mắt
  float *inputData = (float *)TfLiteTensorData(inputTensor);
  memcpy(inputData, inputPixels, pixelsCount * sizeof(float));

  // 3. Run Inference (Chạy AI)
  if (TfLiteInterpreterInvoke(faceInterpreter) != kTfLiteOk) {
    LOGI("❌ Lỗi khi chạy Invoke Face Model!");
    return {};
  }

  // 4. Lấy kết quả ra (Thay cho bước Flatten ở Dart)
  const TfLiteTensor *outputTensor =
      TfLiteInterpreterGetOutputTensor(faceInterpreter, 0);
  float *outputData = (float *)TfLiteTensorData(outputTensor);
  int outputSize =
      TfLiteTensorByteSize(outputTensor) / sizeof(float); // Thường là 192

  // Khởi tạo std::vector từ con trỏ kết quả
  std::vector<float> resultVector(outputData, outputData + outputSize);

  // 5. L2 Normalize (Bắt buộc)
  L2Normalize(resultVector);

  return resultVector;
}

float FaceRecognizer::CosineSimilarity(const std::vector<float> &v1,
                                       const std::vector<float> &v2) {
  float dot = 0.0f;
  // Bỏ qua rủi ro out-of-bounds nếu kích thước 2 vector bằng nhau (đã check ở
  // Dart)
  int size = v1.size();
  for (int i = 0; i < size; ++i) {
    dot += v1[i] * v2[i];
  }
  return dot;
}

// 2. Dịch hàm predict & _findClosestMatch
RecognitionResult FaceRecognizer::PredictFace(const float *inputPixels,
                                              int pixelsCount,
                                              float threshold) {
  RecognitionResult result = {"Unknown", 0.0f, true};

  // Lấy vector đặc trưng (Sử dụng hàm ExtractFaceFeature ta đã viết ở bước
  // trước)
  std::vector<float> embedding = ExtractFaceFeature(inputPixels, pixelsCount);

  if (embedding.empty()) {
    result.name = "Error";
    return result; // Lỗi trích xuất
  }

  // TÌM NGƯỜI GIỐNG NHẤT (Tìm Max Cosine)
  float maxScore = -1.0f;
  std::string bestMatch = "Unknown";

  for (const auto &pair : faceDatabase) {
    float score = CosineSimilarity(embedding, pair.second);
    if (score > maxScore) {
      maxScore = score;
      bestMatch = pair.first;
    }
  }

  // So sánh với Threshold
  result.distance = maxScore;
  if (maxScore >= threshold) {
    result.name = bestMatch;
    result.isUnknown = false;
  } else {
    result.name = "Unknown";
    result.isUnknown = true;
  }

  return result;
}
