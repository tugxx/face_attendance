#pragma once

class FacePipeline {
private:
  static FacePipeline *instance;
  FacePipeline() {}

public:
  static FacePipeline *GetInstance();

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

  // 4. Luồng nén toàn bộ khung hình camera ra JPEG
  int EncodeFullFrameToJpeg(const unsigned char *yuvData, int width, int height,
                            int rotation, unsigned char **outJpegData,
                            int *outJpegSize);
};