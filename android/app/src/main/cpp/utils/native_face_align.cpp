#include <algorithm>
#include <android/log.h>
#include <cstdint>
#include <jni.h>
#include <math.h>
#include <vector>

#include <android/log.h>
#define LOGD(...)                                                              \
  __android_log_print(ANDROID_LOG_DEBUG, "FaceNative", __VA_ARGS__)

#define PI 3.14159265358979323846
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

// #define STB_IMAGE_RESIZE_IMPLEMENTATION
// #include "stb_image_resize.h"

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize2.h"

// #include "tensorflow/lite/c/c_api.h"
// #define LOGI(...) \
//   __android_log_print(ANDROID_LOG_INFO, "FaceAlignCPP", __VA_ARGS__)

// 5 Điểm chuẩn (Reference Points) cho ảnh 112x112
// [Mắt trái, Mắt phải, Mũi, Miệng trái, Miệng phải]
const float REF_X[] = {38.2946f, 73.5318f, 56.0252f, 41.5493f, 70.7299f};
const float REF_Y[] = {51.6963f, 51.6963f, 71.7366f, 92.3655f, 92.3655f};

extern "C" __attribute__((visibility("default"))) __attribute__((used)) {

  inline int clamp(int v) { return (v < 0) ? 0 : ((v > 255) ? 255 : v); }

  // Hàm đọc pixel từ YUV NV21 có xử lý Xoay (Rotation)
  // Trả về: 0xRRGGBB
  int get_pixel_from_yuv(uint8_t * yuv, int width, int height, float logicX,
                         float logicY, int rotation) {
    int realX, realY;

    // Map từ toạ độ Logic (UI) sang toạ độ Raw YUV
    if (rotation == 270) { // Camera trước
      realX = (int)(width - 1 - logicY);
      realY = (int)logicX;
    } else if (rotation == 90) { // Camera sau
      realX = (int)logicY;
      realY = (int)(height - 1 - logicX);
    } else {
      realX = (int)logicX;
      realY = (int)logicY;
    }

    // Check biên
    if (realX < 0)
      realX = 0;
    if (realX >= width)
      realX = width - 1;
    if (realY < 0)
      realY = 0;
    if (realY >= height)
      realY = height - 1;

    // Y Index
    int yIdx = realY * width + realX;
    int Y_val = yuv[yIdx] & 0xFF;

    // UV Index
    int uvStart = width * height;
    int uvIdx = uvStart + (realY >> 1) * width + (realX & ~1);

    int V_val = yuv[uvIdx] & 0xFF;
    int U_val = yuv[uvIdx + 1] & 0xFF;

    // Convert YUV -> RGB
    int c = Y_val - 16;
    int d = U_val - 128;
    int e = V_val - 128;

    int r = (298 * c + 409 * e + 128) >> 8;
    int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
    int b = (298 * c + 516 * d + 128) >> 8;

    return (clamp(r) << 16) | (clamp(g) << 8) | clamp(b);
  }

  // --- HÀM CHÍNH: ALIGN FACE ---
  // landmarks: Mảng float 10 phần tử [x1, y1, x2, y2...]
  void process_face_affine(uint8_t * yuvBytes, int width, int height,
                           float *landmarks, int rotation,
                           float *outputBuffer) {
    // 1. TÍNH MA TRẬN AFFINE (Dựa trên 2 mắt như code Dart)
    // Src = Landmarks từ Camera
    float src_eye_x =
        (landmarks[0] + landmarks[2]) / 2.0f; // Tâm mắt trái + phải
    float src_eye_y = (landmarks[1] + landmarks[3]) / 2.0f;

    float dx = landmarks[2] - landmarks[0];
    float dy = landmarks[3] - landmarks[1];
    float src_dist = sqrt(dx * dx + dy * dy);
    float src_angle = atan2(dy, dx);

    // Dst = Điểm chuẩn (Ref Points)
    float dst_eye_x = (REF_X[0] + REF_X[1]) / 2.0f;
    float dst_eye_y = (REF_Y[0] + REF_Y[1]) / 2.0f;

    float d_dx = REF_X[1] - REF_X[0];
    float d_dy = REF_Y[1] - REF_Y[0];
    float dst_dist = sqrt(d_dx * d_dx + d_dy * d_dy); // = 35.24
    float dst_angle = atan2(d_dy, d_dx);              // = 0

    // Tính Scale & Rotation
    float scale = dst_dist / src_dist;
    float angle_diff = dst_angle - src_angle;

    float cosR = cos(angle_diff) * scale;
    float sinR = sin(angle_diff) * scale;

    // Tính Translation (Dịch chuyển)
    // tx = dstCenter.x - (srcCenter.x * cosR - srcCenter.y * sinR)
    float tx = dst_eye_x - (src_eye_x * cosR - src_eye_y * sinR);
    float ty = dst_eye_y - (src_eye_x * sinR + src_eye_y * cosR);

    // Ma trận M = [cosR, -sinR, tx]
    //             [sinR,  cosR, ty]

    // 2. TÍNH MA TRẬN NGHỊCH ĐẢO (INVERSE MATRIX)
    // Để mapping từ Output(112x112) ngược về Input(Camera)
    // M_inv = [A, B, C]
    //         [D, E, F]
    float det = cosR * cosR - (-sinR) * sinR; // = scale * scale
    float idet = 1.0f / det;

    float A = cosR * idet;
    float B = -(-sinR) * idet;
    float C = (-sinR * ty - cosR * tx) * idet; // Logic inverse matrix 2x3
    float D = -sinR * idet;
    float E = cosR * idet;
    float F = (sinR * tx - cosR * ty) * idet;

    // 3. WARP LOOP (112x112)
    int targetSize = 112;
    int pIdx = 0;

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {

        // Ánh xạ ngược: Từ (x,y) đích -> (srcX, srcY) nguồn
        // srcX = x * A + y * B + C
        float srcX = x * A + y * B + C;
        float srcY = x * D + y * E + F;

        // Lấy màu tại (srcX, srcY) từ YUV gốc
        // Hàm này đã xử lý việc Camera bị xoay 90/270 độ
        int rgb =
            get_pixel_from_yuv(yuvBytes, width, height, srcX, srcY, rotation);

        int r = (rgb >> 16) & 0xFF;
        int g = (rgb >> 8) & 0xFF;
        int b = rgb & 0xFF;

        // Normalize và gán vào output
        outputBuffer[pIdx++] = (r - 127.5f) / 128.0f;
        outputBuffer[pIdx++] = (g - 127.5f) / 128.0f;
        outputBuffer[pIdx++] = (b - 127.5f) / 128.0f;
      }
    }
  }

  // ----------------------------------------------------------------------
  // HÀM MỚI: XỬ LÝ FILE ẢNH (KHÔNG DÙNG OPENCV)
  // ----------------------------------------------------------------------
  void process_file_affine_raw(char *filePath, float *landmarks,
                               float *outputBuffer) {
    // 1. Đọc file ảnh bằng stb_image (Siêu nhẹ)
    int width, height, channels;
    // Force load thành 3 kênh màu (RGB) bất kể ảnh gốc là gì
    unsigned char *imgData = stbi_load(filePath, &width, &height, &channels, 3);

    if (imgData == NULL) {
      __android_log_print(ANDROID_LOG_ERROR, "NativeFace",
                          "Cannot load image: %s", filePath);
      return;
    }

    // 2. TÍNH TOÁN MA TRẬN AFFINE (Code Toán thuần - Giống Dart)
    // Tâm mắt trái/phải từ Landmarks
    float src_eye_x = (landmarks[0] + landmarks[2]) / 2.0f;
    float src_eye_y = (landmarks[1] + landmarks[3]) / 2.0f;

    float dx = landmarks[2] - landmarks[0];
    float dy = landmarks[3] - landmarks[1];
    float src_dist = sqrt(dx * dx + dy * dy);
    float src_angle = atan2(dy, dx);

    // Tâm mắt chuẩn (Ref Points)
    float dst_eye_x = (REF_X[0] + REF_X[1]) / 2.0f;
    float dst_eye_y = (REF_Y[0] + REF_Y[1]) / 2.0f;
    float d_dx = REF_X[1] - REF_X[0];
    float d_dy = REF_Y[1] - REF_Y[0];
    float dst_dist = sqrt(d_dx * d_dx + d_dy * d_dy);
    float dst_angle = atan2(d_dy, d_dx);

    float scale = dst_dist / src_dist;
    float angle_diff = dst_angle - src_angle;
    float cosR = cos(angle_diff) * scale;
    float sinR = sin(angle_diff) * scale;

    float tx = dst_eye_x - (src_eye_x * cosR - src_eye_y * sinR);
    float ty = dst_eye_y - (src_eye_x * sinR + src_eye_y * cosR);

    // 3. TÍNH MA TRẬN NGHỊCH ĐẢO (INVERSE MAPPING)
    float det = cosR * cosR - (-sinR) * sinR;
    float idet = 1.0f / det;

    float A = cosR * idet;
    float B = sinR * idet;
    float C = (-sinR * ty - cosR * tx) * idet;
    float D = -sinR * idet;
    float E = cosR * idet;
    float F = (sinR * tx - cosR * ty) * idet;

    // 4. VÒNG LẶP WARP & NORMALIZE
    int targetSize = 112;
    int pIdx = 0;
    int stride = width * 3; // Mỗi pixel 3 byte RGB

    for (int y = 0; y < targetSize; y++) {
      for (int x = 0; x < targetSize; x++) {

        // Map ngược từ (x,y) đích -> (srcX, srcY) nguồn
        float srcX = x * A + y * B + C;
        float srcY = x * D + y * E + F;

        int realX = (int)srcX;
        int realY = (int)srcY;

        // Check biên
        if (realX < 0)
          realX = 0;
        if (realX >= width)
          realX = width - 1;
        if (realY < 0)
          realY = 0;
        if (realY >= height)
          realY = height - 1;

        // Lấy pixel từ mảng byte thô (Raw Pointer Arithmetic)
        int idx = realY * stride + realX * 3;

        unsigned char r_val = imgData[idx];
        unsigned char g_val = imgData[idx + 1];
        unsigned char b_val = imgData[idx + 2];

        // Normalize (-1.0 -> 1.0)
        outputBuffer[pIdx++] = (r_val - 127.5f) / 128.0f;
        outputBuffer[pIdx++] = (g_val - 127.5f) / 128.0f;
        outputBuffer[pIdx++] = (b_val - 127.5f) / 128.0f;
      }
    }

    // 5. Giải phóng bộ nhớ ảnh gốc
    stbi_image_free(imgData);
  }

  // Helper: Kẹp giá trị trong khoảng [min, max]
  inline float clamp_v2(float v, float min_v, float max_v) {
    return std::max(min_v, std::min(v, max_v));
  }

  // Helper: Lấy 1 pixel RGB từ YUV (NV21) có xử lý Xoay (Rotation)
  // Hàm này chỉ lấy đúng điểm ảnh (Nearest Neighbor) để trích xuất dữ liệu thô
  void get_pixel_yuv_rotated(const uint8_t *yuv, int width, int height,
                             int stride, int x, int y, int rotation, uint8_t *r,
                             uint8_t *g, uint8_t *b) {

    // 1. Xử lý xoay tọa độ (Mapping tọa độ ảo -> tọa độ thật trên buffer)
    int px = x;
    int py = y;

    if (rotation == 90) {
      px = y;
      py = height - 1 - x;
    } else if (rotation == 270) {
      px = width - 1 - y;
      py = x;
    } else if (rotation == 180) {
      px = width - 1 - x;
      py = height - 1 - y;
    }

    // Clamp tọa độ để không văng app
    px = std::max(0, std::min(px, width - 1));
    py = std::max(0, std::min(py, height - 1));

    // 2. Lấy YUV tại tọa độ đã xoay
    int y_idx = py * stride + px;
    uint8_t Y_val = yuv[y_idx];

    int uv_start = stride * height;
    int uv_idx = uv_start + (py / 2) * stride + (px / 2) * 2;

    uint8_t V_val = yuv[uv_idx];
    uint8_t U_val = yuv[uv_idx + 1];

    // 3. Convert YUV -> RGB
    float y_f = (float)Y_val;
    float u_f = (float)U_val - 128.0f;
    float v_f = (float)V_val - 128.0f;

    *r = (uint8_t)clamp_v2(y_f + 1.370705f * v_f, 0.0f, 255.0f);
    *g = (uint8_t)clamp_v2(y_f - 0.337633f * u_f - 0.698001f * v_f, 0.0f,
                           255.0f);
    *b = (uint8_t)clamp_v2(y_f + 1.732446f * u_f, 0.0f, 255.0f);
  }

  // --------------------------------------------------------
  // HÀM XỬ LÝ ANTI-SPOOFING (Scale -> Crop 80x80)
  // --------------------------------------------------------
  void process_face_crop(uint8_t * yuvPtr, int width, int height, int yStride,
                         int rotation, int rX, int rY, int rW, int rH,
                         int target_width, int target_height, float scale,
                         bool is_bgr, float *outputBuffer) {
    int logical_w = width;
    int logical_h = height;
    if (rotation == 90 || rotation == 270) {
      logical_w = height;
      logical_h = width;
    }

    // --- BƯỚC 1: TÍNH TOÁN VÙNG CROP (SQUARE + SCALE) ---
    float cx = rX + rW / 2.0f;
    float cy = rY + rH / 2.0f;

    int crop_height = (int)(rH * scale);
    // int crop_width = (int)(crop_height * 1.0f / 1.35f);
    int crop_width = (int)(rW * scale);

    int start_x = (int)(cx - crop_width / 2.0f);
    int start_y = (int)(cy - crop_height / 2.0f);
    int end_x = start_x + crop_width;
    int end_y = start_y + crop_height;

    int nx1 = std::max(0, start_x);
    int ny1 = std::max(0, start_y);
    int nx2 = std::min(logical_w, end_x);
    int ny2 = std::min(logical_h, end_y);

    // Kích thước thực tế sau khi cắt (có thể nhỏ hơn desired_bw/bh)
    int real_crop_w = nx2 - nx1;
    int real_crop_h = ny2 - ny1;

    // Safety check: Nếu mặt bay ra khỏi khung hình hoàn toàn
    if (real_crop_w <= 0 || real_crop_h <= 0) {
      return; // Hoặc fill 0 vào outputBuffer
    }

    // --- BƯỚC 2: EXTRACT (CẮT ẢNH) ---
    // Tạo buffer tạm để chứa ảnh RGB cắt từ camera (kích thước gốc crop_size x
    // crop_size)
    std::vector<uint8_t> raw_crop_rgb(real_crop_w * real_crop_h * 3);

    int idx = 0;
    for (int y = 0; y < real_crop_h; y++) {
      int abs_y = ny1 + y;
      for (int x = 0; x < real_crop_w; x++) {
        int abs_x = nx1 + x;

        // Lấy pixel RGB tại tọa độ (có xử lý xoay và padding bên trong)
        uint8_t r, g, b;
        get_pixel_yuv_rotated(yuvPtr, width, height, yStride, abs_x, abs_y,
                              rotation, &r, &g, &b);

        raw_crop_rgb[idx++] = r;
        raw_crop_rgb[idx++] = g;
        raw_crop_rgb[idx++] = b;
      }
    }

    // --- BƯỚC 3: RESIZE (DÙNG THƯ VIỆN STB) ---
    std::vector<uint8_t> resized_rgb(target_width * target_height * 3);

    // // stbir_resize_uint8(input_data, input_w, input_h, input_stride,
    // //                    output_data, output_w, output_h, output_stride,
    // //                    num_channels)
    // stbir_resize_uint8(raw_crop_rgb.data(), real_crop_w, real_crop_h, 0,
    //                    resized_rgb.data(), target_width, target_height, 0,
    //                    3);

    // Dùng hàm _linear hoặc _srgb của v2, truyền thêm STBIR_RGB
    stbir_resize_uint8_linear(raw_crop_rgb.data(), real_crop_w, real_crop_h, 0,
                              resized_rgb.data(), target_width, target_height,
                              0,
                              STBIR_RGB // Khai báo rõ đây là ảnh 3 kênh RGB
    );

    // // Chuẩn ImageNet (RGB)
    // float norm_mean[] = {0.485f, 0.456f, 0.406f};
    // float norm_std[] = {0.229f, 0.224f, 0.225f};

    int pIdx = 0;
    int rIdx = 0;

    for (int i = 0; i < target_width * target_height; i++) {
      // Đọc tuần tự R, G, B từ mảng đã resize
      uint8_t r_byte = resized_rgb[rIdx++];
      uint8_t g_byte = resized_rgb[rIdx++];
      uint8_t b_byte = resized_rgb[rIdx++];

      // uint8_t tmp = r_byte;
      // r_byte = b_byte;
      // b_byte = tmp; // Swap R <-> B for BGR

      // // Ghi tuần tự vào outputBuffer theo thứ tự B, G, R
      // outputBuffer[pIdx++] = (float)b_byte;
      // outputBuffer[pIdx++] = (float)g_byte;
      // outputBuffer[pIdx++] = (float)r_byte;

      if (is_bgr) {
          outputBuffer[pIdx++] = (float)b_byte;
          outputBuffer[pIdx++] = (float)g_byte;
          outputBuffer[pIdx++] = (float)r_byte;
      } else {
          outputBuffer[pIdx++] = (float)r_byte;
          outputBuffer[pIdx++] = (float)g_byte;
          outputBuffer[pIdx++] = (float)b_byte;
      }
    }
  }
}

// extern "C" __attribute__((visibility("default"))) __attribute__((used))
// const char *
// GetTFLiteVersion() {
//   // Gọi thử 1 hàm của TFLite để xem có bị lỗi "symbol not found" không
//   const char *version = TfLiteVersion();
//   LOGI("🔥 Khởi động C++ thành công! Phiên bản TFLite: %s", version);
//   return version;
// }
