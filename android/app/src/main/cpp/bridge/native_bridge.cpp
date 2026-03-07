#include "anti_spoofing.h"
#include "face_recognizer.h"
#include <jni.h>
#include <string.h>

// ==========================================
// LUỒNG FACE RECOGNITION
// ==========================================
extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
InitFaceModel(const void *faceData, int faceSize) {
  return FaceRecognizer::GetInstance()->InitFaceModel(faceData, faceSize) ? 1
                                                                          : 0;
}

// Đăng ký khuôn mặt
extern "C" __attribute__((visibility("default"))) __attribute__((used)) void
RegisterFace(const char *name, const float *embedding, int size) {
  FaceRecognizer::GetInstance()->RegisterFace(name, embedding, size);
}

// Xóa Database
extern "C" __attribute__((visibility("default"))) __attribute__((used)) void
ClearDatabase() {
  FaceRecognizer::GetInstance()->ClearDatabase();
}

// Hàm trích xuất đặc trưng khuôn mặt (embedding)
extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
ExtractFaceFeature(const float *inputPixels, int pixelsCount,
                   float *outputBuffer) {

  // Gọi class Lõi xử lý
  std::vector<float> result = FaceRecognizer::GetInstance()->ExtractFaceFeature(
      inputPixels, pixelsCount);

  // Nếu mảng rỗng (bị lỗi), báo cho Dart biết (return 0)
  if (result.empty())
    return 0;

  // Thành công: Ghi đè kết quả vào cái khay `outputBuffer` mà Dart truyền sang
  memcpy(outputBuffer, result.data(), result.size() * sizeof(float));

  return 1; // Báo cho Dart biết là thành công
}

// Hàm này trả về Int: 0 (Lỗi), 1 (Nhận diện thành công), 2 (Người lạ - Unknown)
extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
PredictFaceNative(const float *inputPixels, int pixelsCount, float threshold,
                  char *outName, float *outDistance) {

  // Gọi logic AI
  RecognitionResult res = FaceRecognizer::GetInstance()->PredictFace(
      inputPixels, pixelsCount, threshold);

  if (res.name == "Error")
    return 0; // Báo lỗi cho Dart

  // Ghi kết quả vào 2 "thùng rỗng" do Dart cung cấp
  strcpy(outName, res.name.c_str());
  *outDistance = res.distance;

  return res.isUnknown ? 2 : 1;
}

// ==========================================
// LUỒNG ANTI-SPOOFING
// ==========================================

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
InitSpoofModel(const void *spoofData, int spoofSize) {
  return AntiSpoofing::GetInstance()->InitSpoofModel(spoofData, spoofSize) ? 1
                                                                           : 0;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) float
PredictSpoofNative(const float *inputPixels, int pixelsCount) {
  return AntiSpoofing::GetInstance()->PredictSpoof(inputPixels, pixelsCount);
}