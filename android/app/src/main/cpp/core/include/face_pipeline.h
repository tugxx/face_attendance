#pragma once

#include "anti_spoofing.h"
#include "face_quality.h"
#include "face_recognizer.h"

class FacePipeline {
private:
  FaceRecognizer *recognizer = nullptr;
  AntiSpoofing *spoofing = nullptr;
  FaceQuality *quality = nullptr;

public:
  FacePipeline() {
    recognizer = new FaceRecognizer();
    spoofing = new AntiSpoofing();
    quality = new FaceQuality();
  }

  ~FacePipeline() {
    if (recognizer)
      delete recognizer;
    if (spoofing)
      delete spoofing;
    if (quality)
      delete quality;
  }

  int InitModels(const void *recogData, int recogSize, const void *spoofData,
                 int spoofSize, const void *qualityData, int qualitySize);

  // 1. Luồng Check-in (Điểm danh)
  int ProcessDualTask(const unsigned char *yuvData, int width, int height,
                      const float *landmarks, int rotation, int rectX,
                      int rectY, int rectW, int rectH,
                      float recognitionThreshold, float spoofThreshold,
                      float qualityThreshold, char *outName,
                      char *outTemplateId, char *outImposterName,
                      float *outScore, float *outImposterScore,
                      float *outSpoofScore, float *outQualityScore,
                      bool *outIsReal);

  // 3. Luồng đăng ký khuôn mặt (Cắt mặt + Nén JPG)
  int ProcessRegistration(const unsigned char *yuvData, int width, int height,
                          const float *landmarks, int rotation,
                          float *outAiPixels, unsigned char *outJpgBytes,
                          int *outJpgSize);

  float ProcessQuality(const unsigned char *yuvData, int width, int height,
                       int rotation, int rectX, int rectY, int rectW,
                       int rectH) {
    return quality->PredictQualityFromYuv(yuvData, width, height, rotation,
                                          rectX, rectY, rectW, rectH);
  }

  // 4. Luồng nén toàn bộ khung hình camera ra JPEG
  int EncodeFullFrameToJpeg(const unsigned char *yuvData, int width, int height,
                            int rotation, unsigned char **outJpegData,
                            int *outJpegSize);

  void RegisterFace(const char *name, const float *embedding, int size,
                    const char *templateId) {
    if (recognizer != nullptr) {
      recognizer->RegisterFace(name, embedding, size, templateId);
    }
  }

  RecognitionResult PredictFromPixels(const float *inputPixels, int pixelsCount,
                                      float threshold) {
    if (recognizer != nullptr) {
      return recognizer->PredictFaceFromPixels(inputPixels, pixelsCount,
                                               threshold);
    }
    return {"Error", -1.0f, true, "", "Unknown", -1.0f};
  }

  bool ExtractFeature(const float *inputPixels, int pixelsCount,
                      float *outFeature) {
    if (recognizer != nullptr) {
      return recognizer->ExtractFaceFeature(inputPixels, pixelsCount,
                                            outFeature);
    }
    return false;
  }
};