#define STB_IMAGE_WRITE_IMPLEMENTATION

#include <jni.h>
#include <string.h>

#include "stb_image_write.h"

#include "anti_spoofing.h"
#include "face_quality.h"
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
// LUỒNG FACE QUALITY ASSESSMENT
// ==========================================

extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
InitQualityModelNative(const void *modelData, int modelSize) {
  return FaceQuality::GetInstance()->InitQualityModel(modelData, modelSize) ? 1
                                                                            : 0;
}

extern "C" __attribute__((visibility("default"))) __attribute__((used)) float
PredictQualityNative(const float *inputPixels, int pixelsCount) {
  return FaceQuality::GetInstance()->PredictQuality(inputPixels, pixelsCount);
}

extern "C" void process_face_affine(uint8_t *yuvBytes, int width, int height,
                                    float *landmarks, int rotation,
                                    float *outputBuffer);
extern "C" void process_face_crop(uint8_t *yuvPtr, int width, int height,
                                  int yStride, int rotation, int rX, int rY,
                                  int rW, int rH, int target_width,
                                  int target_height, float scale, bool is_bgr,
                                  float *outputBuffer);

// ==========================================
// LUỒNG CHẤM ĐIỂM ĐỘ NÉT KHUÔN MẶT
// ==========================================

extern "C" __attribute__((visibility("default"))) __attribute__((used)) float
ProcessQualityNative(const unsigned char *yuvData, int width, int height,
                     int rotation, int rectX, int rectY, int rectW, int rectH) {

  int qualityW = 96;
  int qualityH = 96;
  int qualitySize = qualityW * qualityH * 3;

  // Cấp phát RAM cho ảnh 96x96
  float *qualityBuffer = (float *)malloc(qualitySize * sizeof(float));
  if (!qualityBuffer)
    return -1.0f;

  // Cắt khuôn mặt từ YUV, resize về 96x96
  // (Giả sử process_face_crop của bạn đang xuất ra giá trị float trong dải
  // [-1.0, 1.0])
  process_face_crop((uint8_t *)yuvData, width, height, width, rotation, rectX,
                    rectY, rectW, rectH, qualityW, qualityH, 1.2f, false,
                    qualityBuffer);

  // TIỀN XỬ LÝ CHO LIGHTQNET
  // Nếu LightQNet yêu cầu input dải [0.0, 1.0], ta phải chuẩn hóa lại mảng
  for (int i = 0; i < qualitySize; i++) {
    // Đưa từ [-1.0, 1.0] về [0.0, 1.0]
    qualityBuffer[i] = (qualityBuffer[i] - 128.0f) / 128.0f;
  }

  // Chạy AI chấm điểm độ nét
  float score =
      FaceQuality::GetInstance()->PredictQuality(qualityBuffer, qualitySize);

  free(qualityBuffer);
  return score;
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
                   float *outSpoofScore, float *outQualityScore) {

  float qualityScore = ProcessQualityNative(yuvData, width, height, rotation,
                                            rectX, rectY, rectW, rectH);

  *outQualityScore = qualityScore;

  // NẾU ẢNH MỜ -> THOÁT SỚM
  if (qualityScore < 0.4f) {
    return 3;
  }

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
  process_face_affine((uint8_t *)yuvData, width, height, (float *)landmarks,
                      rotation, recogBuffer);

  // Y Stride mặc định bằng Width cho YUV420
  process_face_crop((uint8_t *)yuvData, width, height, width, rotation, rectX,
                    rectY, rectW, rectH, spoofW, spoofH, 2.0f, true,
                    spoofBuffer);

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

extern "C" void process_face_affine(uint8_t *, int, int, float *, int, float *);

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

// ==========================================
// LUỒNG GỬI ẢNH CHỤP KHUÔN MẶT
// ==========================================

extern "C" void get_pixel_yuv_rotated(const uint8_t *yuv, int width, int height,
                                      int stride, int x, int y, int rotation,
                                      uint8_t *r, uint8_t *g, uint8_t *b);

// Callback để stb ghi byte JPEG vào RAM thay vì ghi ra file cứng
void stbi_write_mem(void *context, void *data, int size) {
  std::vector<uint8_t> *buffer = (std::vector<uint8_t> *)context;
  buffer->insert(buffer->end(), (uint8_t *)data, (uint8_t *)data + size);
}

// HÀM MỚI TOANH: Chỉ nhận YUV gốc và trả ra mảng Byte JPEG
extern "C" __attribute__((visibility("default"))) __attribute__((used)) int
EncodeFullFrameToJpeg(const unsigned char *yuvData, int width, int height,
                      int rotation, unsigned char **outJpegData,
                      int *outJpegSize) {

  // Tùy góc xoay camera mà chiều ngang/dọc sẽ đổi chỗ
  int logical_w = (rotation == 90 || rotation == 270) ? height : width;
  int logical_h = (rotation == 90 || rotation == 270) ? width : height;

  std::vector<uint8_t> rgb(logical_w * logical_h * 3);

  // Convert toàn bộ khung hình YUV -> RGB
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

  // Dùng stb nén RGB thành mảng byte JPEG siêu nhẹ (Quality = 85%)
  std::vector<uint8_t> jpegBuf;
  stbi_write_jpg_to_func(stbi_write_mem, &jpegBuf, logical_w, logical_h, 3,
                         rgb.data(), 85);

  // Bắn mảng byte đó lên cho Dart
  *outJpegSize = jpegBuf.size();
  *outJpegData = (unsigned char *)malloc(*outJpegSize);
  memcpy(*outJpegData, jpegBuf.data(), *outJpegSize);

  return 1;
}
