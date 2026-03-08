#define STB_IMAGE_WRITE_IMPLEMENTATION

#include <jni.h>
#include <string.h>

#include "stb_image_write.h"

#include "anti_spoofing.h"
#include "face_recognizer.h"

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

// ==========================================
// LUỒNG DUAL TASK (CROP + AI RECOGNITION + ANTI SPOOFING)
// Hàm này làm TẤT CẢ mọi việc trong 1 lần gọi
// ==========================================
extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
ProcessFrameNative(const unsigned char *yuvData, int width, int height,
                   const float *landmarks, int rotation, int rectX, int rectY,
                   int rectW, int rectH, int spoofW, int spoofH,
                   float threshold, char *outName, float *outDistance,
                   float *outSpoofScore) {

  // 1. Cấp phát bộ nhớ đệm để chứa ảnh đã cắt (112x112 và 80x80)
  int recogSize = 112 * 112 * 3;
  float *recogBuffer = (float *)malloc(recogSize * sizeof(float));

  int spoofSize = spoofW * spoofH * 3;
  float *spoofBuffer = (float *)malloc(spoofSize * sizeof(float));

  if (!recogBuffer || !spoofBuffer) {
    if (recogBuffer) {
      free(recogBuffer);
    }
    if (spoofBuffer) {
      free(spoofBuffer);
    }
    return 0; // Lỗi hết RAM
  }

  // 2. Khai báo chuẩn tên hàm từ file native_face_align
  extern void process_face_affine(uint8_t * yuvBytes, int width, int height,
                                  float *landmarks, int rotation,
                                  float *outputBuffer);
  extern void process_face_crop(uint8_t * yuvPtr, int width, int height,
                                int yStride, int rotation, int rX, int rY,
                                int rW, int rH, int target_width,
                                int target_height, float *outputBuffer);

  process_face_affine((uint8_t *)yuvData, width, height, (float *)landmarks,
                      rotation, recogBuffer);

  // Y Stride mặc định bằng Width cho YUV420
  process_face_crop((uint8_t *)yuvData, width, height, width, rotation, rectX,
                    rectY, rectW, rectH, spoofW, spoofH, spoofBuffer);

  // 3. Chạy AI Nhận Diện
  RecognitionResult res = FaceRecognizer::GetInstance()->PredictFace(
      recogBuffer, recogSize, threshold);

  // 4. Chạy AI Anti-Spoofing
  float spoofScore =
      AntiSpoofing::GetInstance()->PredictSpoof(spoofBuffer, spoofSize);

  // 5. Trả kết quả về Dart qua con trỏ
  if (res.name != "Error") {
    strcpy(outName, res.name.c_str());
  } else {
    strcpy(outName, "Unknown");
  }
  *outDistance = res.distance;
  *outSpoofScore = spoofScore;

  // 6. Dọn dẹp RAM nội bộ
  free(recogBuffer);
  free(spoofBuffer);

  return res.isUnknown ? 2 : 1;
}

// ==========================================
// LUỒNG ĐĂNG KÝ KHUÔN MẶT
// ==========================================

// Struct để hứng byte của JPG nén ra
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

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
ProcessRegistrationNative(const unsigned char *yuvData, int width, int height,
                          const float *landmarks, int rotation,
                          float *outAiPixels, unsigned char *outJpgBytes,
                          int *outJpgSize) {

  int recogSize = 112 * 112 * 3;

  // 1. Cắt ảnh bằng hàm cũ của bạn (Lấy float -1.0 đến 1.0)
  extern void process_face_affine(uint8_t *, int, int, float *, int, float *);
  process_face_affine((uint8_t *)yuvData, width, height, (float *)landmarks,
                      rotation, outAiPixels);

  // 2. Chuyển float thành byte RGB (0-255) để vẽ JPG
  unsigned char *rgbPixels = (unsigned char *)malloc(recogSize);
  for (int i = 0; i < recogSize; i++) {
    int val = (int)((outAiPixels[i] * 128.0f) + 127.5f);
    rgbPixels[i] = (unsigned char)(val < 0 ? 0 : (val > 255 ? 255 : val));
  }

  // 3. Nén thành JPG trực tiếp trên RAM C++
  // 50000 là cấp tối đa 50KB cho 1 cái ảnh 112x112 (thường JPG cỡ này chỉ tốn
  // 3-5KB)
  MemWriter mw = {outJpgBytes, 0, 50000};
  stbi_write_jpg_to_func(WriteCallback, &mw, 112, 112, 3, rgbPixels,
                         100); // 100 là quality

  *outJpgSize = mw.length; // Báo cho Dart biết file JPG nặng bao nhiêu byte

  free(rgbPixels);
  return 1;
}