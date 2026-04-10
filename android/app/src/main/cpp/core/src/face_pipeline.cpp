#include "face_pipeline.h"
#include "anti_spoofing.h"
#include "app_log.h"
#include "face_quality.h"
#include "face_recognizer.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#include "stb_image_write.h"

#include "native_face_align.h"

namespace {
struct MemWriter {
  unsigned char *buffer;
  int length;
  int max_length;
};

void WriteCallback(void *context, void *data, int size) {
  MemWriter *mw = (MemWriter *)context;
  if (mw->length + size <= mw->max_length) {
    memcpy(mw->buffer + mw->length, data, size);
    mw->length += size;
  }
}
} // namespace

namespace {
void stbi_write_mem(void *context, void *data, int size) {
  std::vector<uint8_t> *buffer = (std::vector<uint8_t> *)context;
  buffer->insert(buffer->end(), (uint8_t *)data, (uint8_t *)data + size);
}
} // namespace

extern "C" void get_pixel_yuv_rotated(const uint8_t *yuv, int width, int height,
                                      int stride, int x, int y, int rotation,
                                      uint8_t *r, uint8_t *g, uint8_t *b);

int FacePipeline::InitModels(const void *recogData, int recogSize,
                             const void *spoofData, int spoofSize,
                             const void *qualityData, int qualitySize) {
  if (recogData && recogSize > 0)
    recognizer->InitFaceModel(recogData, recogSize);
  if (spoofData && spoofSize > 0)
    spoofing->InitSpoofModel(spoofData, spoofSize);
  if (qualityData && qualitySize > 0)
    quality->InitQualityModel(qualityData, qualitySize);
  return 1;
}

int FacePipeline::ProcessDualTask(const unsigned char *yuvData, int width,
                                  int height, const float *landmarks,
                                  int rotation, int rectX, int rectY, int rectW,
                                  int rectH, float recognitionThreshold,
                                  float spoofThreshold, float qualityThreshold,
                                  char *outName, char *outTemplateId,
                                  char *outImposterName, float *outScore,
                                  float *outImposterScore, float *outSpoofScore,
                                  float *outQualityScore, bool *outIsReal) {

  // 1. CHẠY FACE QUALITY
  float qualityScore = this->quality->PredictQualityFromYuv(
      yuvData, width, height, rotation, rectX, rectY, rectW, rectH);
  *outQualityScore = qualityScore;

  if (qualityScore < qualityThreshold) {
    return 3; // Status: Blurry
  }

  // 3. CHẠY AI PIPELINE
  RecognitionResult recognitionResult = this->recognizer->PredictFaceFromYuv(
      yuvData, width, height, landmarks, rotation, rectX, rectY, rectW, rectH,
      recognitionThreshold);

  SpoofResult spoofResult = this->spoofing->PredictSpoofFromYuv(
      yuvData, width, height, rotation, rectX, rectY, rectW, rectH,
      spoofThreshold);

  // 4. GHI KẾT QUẢ VÀO CON TRỎ CHO DART
  if (recognitionResult.name != "Error" && !recognitionResult.isUnknown) {
    strncpy(outName, recognitionResult.name.c_str(), 255);
    outName[255] = '\0'; // Đảm bảo luôn có null-terminator
    strncpy(outTemplateId, recognitionResult.matchedTemplateId.c_str(), 255);
    outTemplateId[255] = '\0';
  } else {
    strncpy(outName, "Unknown", 255);
    outName[255] = '\0';
    outTemplateId[0] = '\0'; // Chuỗi rỗng
  }

  strncpy(outImposterName, recognitionResult.imposterName.c_str(), 255);
  outImposterName[255] = '\0';
  *outImposterScore = recognitionResult.imposterScore;

  *outScore = recognitionResult.score;
  *outSpoofScore = spoofResult.score;
  *outIsReal = spoofResult.isReal;

  // 6. TRẢ VỀ STATUS (1: Success, 2: Unknown)
  return recognitionResult.isUnknown ? 2 : 1;
}

int FacePipeline::ProcessRegistration(const unsigned char *yuvData, int width,
                                      int height, const float *landmarks,
                                      int rotation, float *outAiPixels,
                                      unsigned char *outJpgBytes,
                                      int *outJpgSize) {

  int recogW = this->recognizer->inputWidth;
  int recogH = this->recognizer->inputHeight;
  int recogSize = recogW * recogH * 3;

  // 1. Cắt ảnh bằng hàm Affine
  bool alignSuccess =
      process_face_affine((uint8_t *)yuvData, width, height, (float *)landmarks,
                          rotation, recogW, recogH, outAiPixels);

  if (!alignSuccess) {
    LOG_ERROR("Căn chỉnh khuôn mặt thất bại (ProcessRegistration)");
    return 0;
  }

  // 2. Chuyển float thành byte RGB (0-255) để vẽ JPG
  unsigned char *rgbPixels = (unsigned char *)malloc(recogSize);
  if (!rgbPixels)
    return 0; // CHECK LỖI OUT OF MEMORY (Quan trọng)

  for (int i = 0; i < recogSize; i++) {
    int val = (int)((outAiPixels[i] * 128.0f) + 127.5f);
    rgbPixels[i] = (unsigned char)(val < 0 ? 0 : (val > 255 ? 255 : val));
  }

  // 3. Nén thành JPG trực tiếp trên RAM C++
  MemWriter mw = {outJpgBytes, 0, 50000};
  stbi_write_jpg_to_func(WriteCallback, &mw, recogW, recogH, 3, rgbPixels, 100);

  // 4. Trả kích thước về cho Dart
  *outJpgSize = mw.length;

  free(rgbPixels);
  return 1;
}

int FacePipeline::EncodeFullFrameToJpeg(const unsigned char *yuvData, int width,
                                        int height, int rotation,
                                        unsigned char **outJpegData,
                                        int *outJpegSize) {
  // Tùy góc xoay camera
  int logical_w = (rotation == 90 || rotation == 270) ? height : width;
  int logical_h = (rotation == 90 || rotation == 270) ? width : height;

  std::vector<uint8_t> rgb(logical_w * logical_h * 3);

  // Convert YUV -> RGB
  int idx = 0;
  for (int y = 0; y < logical_h; y++) {
    for (int x = 0; x < logical_w; x++) {
      uint8_t r, g, b;
      get_pixel_yuv_rotated(yuvData, width, height, width, x, y, rotation, &r,
                            &g, &b);
      rgb[idx++] = r;
      rgb[idx++] = g;
      rgb[idx++] = b;
    }
  }

  // Nén RGB thành JPEG (Quality = 85%)
  std::vector<uint8_t> jpegBuf;
  stbi_write_jpg_to_func(stbi_write_mem, &jpegBuf, logical_w, logical_h, 3,
                         rgb.data(), 85);

  // Cấp phát và copy kết quả (TRÁCH NHIỆM FREE THUỘC VỀ DART)
  *outJpegSize = jpegBuf.size();
  *outJpegData = (unsigned char *)malloc(*outJpegSize);
  memcpy(*outJpegData, jpegBuf.data(), *outJpegSize);

  return 1;
}
