#include "anti_spoofing.h"
#include "face_pipeline.h"
#include "face_quality.h"
#include "face_recognizer.h"
#include "native_face_align.h"

// // ==========================================
// // LUỒNG FACE RECOGNITION
// // ==========================================

extern "C" __attribute__((visibility("default"))) __attribute__((used)) void
AddFaceToNativeSession(int64_t sessionHandle, const char *name,
                       const float *embedding, int size,
                       const char *templateId) {

  if (sessionHandle == 0)
    return;

  // 1. Mở khóa đúng cuốn sổ tay (Session)
  FacePipeline *session = reinterpret_cast<FacePipeline *>(sessionHandle);

  // 2. Ghi tên học sinh vào cuốn sổ này
  // Lưu ý: Đảm bảo biến 'recognizer' trong class FacePipeline đang ở dạng
  // public (hoặc dùng hàm bọc)
  session->RegisterFace(name, embedding, size, templateId);
}

// extern "C" __attribute__((visibility("default"))) __attribute__((used)) void
// ClearDatabase() {
//   FaceRecognizer::GetInstance()->ClearDatabase();
// }

// extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
// ExtractFaceFeature(const float *inputPixels, int pixelsCount,
//                    float *outputBuffer) {

//   bool success = FaceRecognizer::GetInstance()->ExtractFaceFeature(
//       inputPixels, pixelsCount, outputBuffer);

//   return success ? 1 : 0;
// }

// extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
// PredictFaceNative(const float *inputPixels, int pixelsCount, float threshold,
//                   char *outName, char *outTemplateId, char *outImposterName,
//                   float *outScore, float *outImposterScore) {

//   RecognitionResult recognitionResult =
//       FaceRecognizer::GetInstance()->PredictFaceFromPixels(
//           inputPixels, pixelsCount, threshold);

//   if (recognitionResult.name == "Error")
//     return 0; // Báo lỗi cho Dart

//   strncpy(outName, recognitionResult.name.c_str(), 255);
//   strncpy(outTemplateId, recognitionResult.matchedTemplateId.c_str(), 255);
//   strncpy(outImposterName, recognitionResult.imposterName.c_str(), 255);

//   *outScore = recognitionResult.score;
//   *outImposterScore = recognitionResult.imposterScore;

//   return recognitionResult.isUnknown ? 2 : 1;
// }

// extern "C" __attribute__((visibility("default"))) __attribute__((used)) void
// RemoveFace(const char *name) {
//   FaceRecognizer::GetInstance()->RemoveFace(name);
// }

// extern "C" __attribute__((visibility("default"))) __attribute__((used)) void
// MergeAndNormalizeNative(const float *vec1, const float *vec2, int size,
//                         float *outVec) {

//   FaceRecognizer::GetInstance()->MergeAndNormalize(vec1, vec2, size, outVec);
// }

// // ==========================================
// // LUỒNG ANTI-SPOOFING
// // ==========================================

// extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
// InitSpoofModel(const void *spoofData, int spoofSize) {
//   return AntiSpoofing::GetInstance()->InitSpoofModel(spoofData, spoofSize);
// }

// extern "C" __attribute__((visibility("default"))) __attribute__((used))
// SpoofResult
// PredictSpoofNative(const float *inputPixels, int pixelsCount, float
// threshold) {
//   return AntiSpoofing::GetInstance()->PredictSpoofFromPixels(
//       inputPixels, pixelsCount, threshold);
// }

// // ==========================================
// // LUỒNG FACE QUALITY ASSESSMENT
// // ==========================================

// extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
// InitQualityModelNative(const void *modelData, int modelSize) {
//   return FaceQuality::GetInstance()->InitQualityModel(modelData, modelSize);
// }

// extern "C" __attribute__((visibility("default"))) __attribute__((used)) float
// PredictQualityNative(const float *inputPixels, int pixelsCount) {
//   return FaceQuality::GetInstance()->PredictQualityFromPixels(inputPixels,
//                                                               pixelsCount);
// }

// ==========================================
// LUỒNG CHẤM ĐIỂM ĐỘ NÉT KHUÔN MẶT
// ==========================================

extern "C" __attribute__((visibility("default"))) __attribute__((used)) float
ProcessQualityNative(int64_t sessionHandle, const unsigned char *yuvData,
                     int width, int height, int rotation, int rectX, int rectY,
                     int rectW, int rectH) {

  if (sessionHandle == 0)
    return -1.0f; // Trả về điểm âm nếu lỗi

  FacePipeline *session = reinterpret_cast<FacePipeline *>(sessionHandle);

  return session->ProcessQuality(yuvData, width, height, rotation, rectX, rectY,
                                 rectW, rectH);
}

// // ==========================================
// // LUỒNG PIPELINE
// // ==========================================

// extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
// ProcessFrameNative(const unsigned char *yuvData, int width, int height,
//                    const float *landmarks, int rotation, int rectX, int
//                    rectY, int rectW, int rectH, float recognitionThreshold,
//                    float spoofThreshold, float qualityThreshold, char
//                    *outName, char *outTemplateId, char *outImposterName,
//                    float *outScore, float *outImposterScore, float
//                    *outSpoofScore, float *outQualityScore, bool *outIsReal) {

//   return FacePipeline::GetInstance()->ProcessDualTask(
//       yuvData, width, height, landmarks, rotation, rectX, rectY, rectW,
//       rectH, recognitionThreshold, spoofThreshold, qualityThreshold, outName,
//       outTemplateId, outImposterName, outScore, outImposterScore,
//       outSpoofScore, outQualityScore, outIsReal);
// }

// // ==========================================
// // LUỒNG ĐĂNG KÝ KHUÔN MẶT
// // ==========================================

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
ProcessRegistrationNative(int64_t sessionHandle, const unsigned char *yuvData,
                          int width, int height, const float *landmarks,
                          int rotation, float *outAiPixels,
                          unsigned char *outJpgBytes, int *outJpgSize) {

  // Khóa van an toàn: Nếu Dart đưa handle sai hoặc rỗng thì chặn ngay
  if (sessionHandle == 0)
    return -1;

  // Mở khóa Session
  FacePipeline *session = reinterpret_cast<FacePipeline *>(sessionHandle);

  return session->ProcessRegistration(yuvData, width, height, landmarks,
                                      rotation, outAiPixels, outJpgBytes,
                                      outJpgSize);
}

// // ==========================================
// // LUỒNG GỬI ẢNH CHỤP KHUÔN MẶT
// // ==========================================

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
EncodeFullFrameToJpegNative(int64_t sessionHandle, const unsigned char *yuvData,
                            int width, int height, int rotation,
                            unsigned char **outJpegData, int *outJpegSize) {

  if (sessionHandle == 0)
    return -1; // Trả về điểm âm nếu lỗi

  FacePipeline *session = reinterpret_cast<FacePipeline *>(sessionHandle);

  return session->EncodeFullFrameToJpeg(yuvData, width, height, rotation,
                                        outJpegData, outJpegSize);
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) void
FreeMemoryNative(void *ptr) {
  if (ptr != nullptr) {
    free(ptr);
  }
}

// 1. DART GỌI HÀM NÀY ĐỂ MỞ PHIÊN VÀ NẠP TẤT CẢ MODEL
extern "C" __attribute__((visibility("default"))) __attribute__((used)) int64_t
CreateFacePipelineSession(const void *recogModel, int recogSize,
                          const void *spoofModel, int spoofSize,
                          const void *qualityModel, int qualitySize) {

  // Tạo 1 object Session mới
  FacePipeline *session = new FacePipeline();

  // Nạp data
  session->InitModels(recogModel, recogSize, spoofModel, spoofSize,
                      qualityModel, qualitySize);

  // Trả về địa chỉ bộ nhớ cho Dart giữ
  return reinterpret_cast<int64_t>(session);
}

// 2. DART GỌI HÀM NÀY MỖI FRAME (Đưa kèm chìa khóa sessionHandle)
extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
ProcessFrameNative(int64_t sessionHandle, const unsigned char *yuvData,
                   int width, int height, const float *landmarks, int rotation,
                   int rectX, int rectY, int rectW, int rectH,
                   float recognitionThreshold, float spoofThreshold,
                   float qualityThreshold, char *outName, char *outTemplateId,
                   char *outImposterName, float *outScore,
                   float *outImposterScore, float *outSpoofScore,
                   float *outQualityScore, bool *outIsReal) {

  // Khóa van an toàn: Nếu Dart đưa handle sai hoặc rỗng thì chặn ngay
  if (sessionHandle == 0)
    return -1;

  // Mở khóa Session
  FacePipeline *session = reinterpret_cast<FacePipeline *>(sessionHandle);

  // Chạy Pipeline từ object này
  return session->ProcessDualTask(
      yuvData, width, height, landmarks, rotation, rectX, rectY, rectW, rectH,
      recognitionThreshold, spoofThreshold, qualityThreshold, outName,
      outTemplateId, outImposterName, outScore, outImposterScore, outSpoofScore,
      outQualityScore, outIsReal);
}

// 3. DART GỌI HÀM NÀY ĐỂ ĐÓNG MÀN HÌNH VÀ DỌN RÁC
extern "C" __attribute__((visibility("default"))) __attribute__((used)) void
DestroyFacePipelineSession(int64_t sessionHandle) {
  if (sessionHandle != 0) {
    FacePipeline *session = reinterpret_cast<FacePipeline *>(sessionHandle);
    delete session; // Tự động gọi Destructor và giải phóng sạch 100% RAM
  }
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
PredictFromPixelsNative(int64_t sessionHandle, const float *inputPixels,
                        int pixelsCount, float threshold, char *outName,
                        char *outTemplateId, char *outImposterName,
                        float *outScore, float *outImposterScore) {

  // 1. Chặn lỗi rỗng
  if (sessionHandle == 0 || inputPixels == nullptr)
    return -1;

  // 2. Ép kiểu Session
  FacePipeline *session = reinterpret_cast<FacePipeline *>(sessionHandle);

  // 3. Gọi hàm từ Pipeline
  RecognitionResult res =
      session->PredictFromPixels(inputPixels, pixelsCount, threshold);

  if (!res.isUnknown && res.name != "Error") {
    strncpy(outName, res.name.c_str(), 255);
    outName[255] = '\0';
    strncpy(outTemplateId, res.matchedTemplateId.c_str(), 255);
    outTemplateId[255] = '\0';
    strncpy(outImposterName, res.imposterName.c_str(), 255);
    outImposterName[255] = '\0';
    *outScore = res.score;
    *outImposterScore = res.imposterScore;
    return 1; // Success
  }

  // Ghi giá trị mặc định nếu Unknown
  *outScore = res.score;
  *outImposterScore = 0.0f;
  return 2;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
ExtractFeatureNative(int64_t sessionHandle, const float *inputPixels,
                     int pixelsCount, float *outFeature) {

  // Chặn lỗi ngay từ cửa
  if (sessionHandle == 0 || inputPixels == nullptr || outFeature == nullptr)
    return 0;

  // Ép kiểu mở khóa Session
  FacePipeline *session = reinterpret_cast<FacePipeline *>(sessionHandle);

  // Trích xuất Vector
  bool success = session->ExtractFeature(inputPixels, pixelsCount, outFeature);

  return success ? 1 : 0; // 1: Thành công, 0: Thất bại
}