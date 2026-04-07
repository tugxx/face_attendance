#include "anti_spoofing.h"
#include "face_pipeline.h"
#include "face_quality.h"
#include "face_recognizer.h"

// ==========================================
// UTILITY
// ==========================================

extern "C" void process_face_affine(uint8_t *yuvBytes, int width, int height,
                                    float *landmarks, int rotation,
                                    float *outputBuffer);

extern "C" void process_face_crop(uint8_t *yuvPtr, int width, int height,
                                  int yStride, int rotation, int rX, int rY,
                                  int rW, int rH, int target_width,
                                  int target_height, float scale, bool is_bgr,
                                  float *outputBuffer);

// ==========================================
// LUỒNG FACE RECOGNITION
// ==========================================

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
InitFaceModel(const void *faceData, int faceSize) {
  return FaceRecognizer::GetInstance()->InitFaceModel(faceData, faceSize) ? 1
                                                                          : 0;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) void
RegisterFace(const char *name, const float *embedding, int size,
             const char *templateId) {
  FaceRecognizer::GetInstance()->RegisterFace(name, embedding, size,
                                              templateId);
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) void
ClearDatabase() {
  FaceRecognizer::GetInstance()->ClearDatabase();
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
ExtractFaceFeature(const float *inputPixels, int pixelsCount,
                   float *outputBuffer) {

  bool success = FaceRecognizer::GetInstance()->ExtractFaceFeature(
      inputPixels, pixelsCount, outputBuffer);

  return success ? 1 : 0;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
PredictFaceNative(const float *inputPixels, int pixelsCount, float threshold,
                  char *outName, char *outTemplateId, char *outImposterName,
                  float *outScore, float *outImposterScore) {

  RecognitionResult recognitionResult =
      FaceRecognizer::GetInstance()->PredictFaceFromPixels(
          inputPixels, pixelsCount, threshold);

  if (recognitionResult.name == "Error")
    return 0; // Báo lỗi cho Dart

  strncpy(outName, recognitionResult.name.c_str(), 255);
  strncpy(outTemplateId, recognitionResult.matchedTemplateId.c_str(), 255);
  strncpy(outImposterName, recognitionResult.imposterName.c_str(), 255);

  *outScore = recognitionResult.score;
  *outImposterScore = recognitionResult.imposterScore;

  return recognitionResult.isUnknown ? 2 : 1;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) void
RemoveFace(const char *name) {
  FaceRecognizer::GetInstance()->RemoveFace(name);
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) void
MergeAndNormalizeNative(const float *vec1, const float *vec2, int size,
                        float *outVec) {

  FaceRecognizer::GetInstance()->MergeAndNormalize(vec1, vec2, size, outVec);
}

// ==========================================
// LUỒNG ANTI-SPOOFING
// ==========================================

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
InitSpoofModel(const void *spoofData, int spoofSize) {
  return AntiSpoofing::GetInstance()->InitSpoofModel(spoofData, spoofSize) ? 1
                                                                           : 0;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used))
SpoofResult
PredictSpoofNative(const float *inputPixels, int pixelsCount, float threshold) {
  return AntiSpoofing::GetInstance()->PredictSpoofFromPixels(
      inputPixels, pixelsCount, threshold);
}

// ==========================================
// LUỒNG FACE QUALITY ASSESSMENT
// ==========================================

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
InitQualityModelNative(const void *modelData, int modelSize) {
  return FaceQuality::GetInstance()->InitQualityModel(modelData, modelSize) ? 1
                                                                            : 0;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) float
PredictQualityNative(const float *inputPixels, int pixelsCount) {
  return FaceQuality::GetInstance()->PredictQualityFromPixels(inputPixels,
                                                              pixelsCount);
}

// ==========================================
// LUỒNG CHẤM ĐIỂM ĐỘ NÉT KHUÔN MẶT
// ==========================================

extern "C" __attribute__((visibility("default"))) __attribute__((used)) float
ProcessQualityNative(const unsigned char *yuvData, int width, int height,
                     int rotation, int rectX, int rectY, int rectW, int rectH) {

  return FaceQuality::GetInstance()->PredictQualityFromYuv(
      yuvData, width, height, rotation, rectX, rectY, rectW, rectH);
}

// ==========================================
// LUỒNG PIPELINE
// ==========================================

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
ProcessFrameNative(const unsigned char *yuvData, int width, int height,
                   const float *landmarks, int rotation, int rectX, int rectY,
                   int rectW, int rectH, float recognitionThreshold,
                   float spoofThreshold, float qualityThreshold, char *outName,
                   char *outTemplateId, char *outImposterName, float *outScore,
                   float *outImposterScore, float *outSpoofScore,
                   float *outQualityScore, bool *outIsReal) {

  return FacePipeline::GetInstance()->ProcessDualTask(
      yuvData, width, height, landmarks, rotation, rectX, rectY, rectW, rectH,
      recognitionThreshold, spoofThreshold, qualityThreshold, outName,
      outTemplateId, outImposterName, outScore, outImposterScore, outSpoofScore,
      outQualityScore, outIsReal);
}

// ==========================================
// LUỒNG ĐĂNG KÝ KHUÔN MẶT
// ==========================================

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
ProcessRegistrationNative(const unsigned char *yuvData, int width, int height,
                          const float *landmarks, int rotation,
                          float *outAiPixels, unsigned char *outJpgBytes,
                          int *outJpgSize) {

  return FacePipeline::GetInstance()->ProcessRegistration(
      yuvData, width, height, landmarks, rotation, outAiPixels, outJpgBytes,
      outJpgSize);
}

// ==========================================
// LUỒNG GỬI ẢNH CHỤP KHUÔN MẶT
// ==========================================

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
EncodeFullFrameToJpegNative(const unsigned char *yuvData, int width, int height,
                            int rotation, unsigned char **outJpegData,
                            int *outJpegSize) {

  return FacePipeline::GetInstance()->EncodeFullFrameToJpeg(
      yuvData, width, height, rotation, outJpegData, outJpegSize);
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) void
FreeMemoryNative(void *ptr) {
  if (ptr != nullptr) {
    free(ptr);
  }
}
