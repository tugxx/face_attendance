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

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize.h"

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

  // // Hàm lấy pixel thô sử dụng Stride để chính xác tuyệt đối
  // inline int get_pixel_raw(uint8_t * yuv, int width, int height, int yStride,
  //                          int uvStride, int x, int y) {
  //   // if (x < 0)
  //   //   x = 0;
  //   // if (x >= width)
  //   //   x = width - 1;
  //   // if (y < 0)
  //   //   y = 0;
  //   // if (y >= height)
  //   //   y = height - 1;

  //   if (x < 0 || x >= width || y < 0 || y >= height) {
  //     return 0; // Black pixel
  //   }

  //   int yIdx = y * yStride + x;
  //   int Y_val = yuv[yIdx] & 0xFF;

  //   int uvStart = yStride * height;
  //   int uvIdx = uvStart + (y >> 1) * uvStride + (x & ~1);

  //   int V_val = yuv[uvIdx] & 0xFF;
  //   int U_val = yuv[uvIdx + 1] & 0xFF;

  //   int c = Y_val - 16;
  //   int d = U_val - 128;
  //   int e = V_val - 128;

  //   int r = (298 * c + 409 * e + 128) >> 8;
  //   int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
  //   int b = (298 * c + 516 * d + 128) >> 8;

  //   return (clamp(r) << 16) | (clamp(g) << 8) | clamp(b);
  // }

  // // Hàm nội suy tuyến tính (Bilinear) để khử răng cưa
  // int get_pixel_bilinear(uint8_t * yuv, int width, int height, int yStride,
  //                        int uvStride, float lx, float ly, int rotation) {
  //   float srcX, srcY;
  //   if (rotation == 270) {
  //     srcX = width - 1 - ly;
  //     srcY = lx;
  //   } else if (rotation == 90) {
  //     srcX = ly;
  //     srcY = height - 1 - lx;
  //   } else {
  //     srcX = lx;
  //     srcY = ly;
  //   }

  //   int x1 = (int)floor(srcX);
  //   int y1 = (int)floor(srcY);
  //   int x2 = (x1 + 1 < width) ? x1 + 1 : x1;
  //   int y2 = (y1 + 1 < height) ? y1 + 1 : y1;

  //   float dx = srcX - x1;
  //   float dy = srcY - y1;

  //   int p11 = get_pixel_raw(yuv, width, height, yStride, uvStride, x1, y1);
  //   int p21 = get_pixel_raw(yuv, width, height, yStride, uvStride, x2, y1);
  //   int p12 = get_pixel_raw(yuv, width, height, yStride, uvStride, x1, y2);
  //   int p22 = get_pixel_raw(yuv, width, height, yStride, uvStride, x2, y2);

  //   auto interp = [&](int c11, int c21, int c12, int c22) {
  //     return (int)((1 - dx) * (1 - dy) * c11 + dx * (1 - dy) * c21 +
  //                  (1 - dx) * dy * c12 + dx * dy * c22);
  //   };

  //   int r = interp((p11 >> 16) & 0xFF, (p21 >> 16) & 0xFF, (p12 >> 16) &
  //   0xFF,
  //                  (p22 >> 16) & 0xFF);
  //   int g = interp((p11 >> 8) & 0xFF, (p21 >> 8) & 0xFF, (p12 >> 8) & 0xFF,
  //                  (p22 >> 8) & 0xFF);
  //   int b = interp(p11 & 0xFF, p21 & 0xFF, p12 & 0xFF, p22 & 0xFF);

  //   return (clamp(r) << 16) | (clamp(g) << 8) | clamp(b);
  // }

  // Helper: Kẹp giá trị trong khoảng [min, max]
  inline float clamp_test(float v, float min_v, float max_v) {
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

    *r = (uint8_t)clamp_test(y_f + 1.370705f * v_f, 0.0f, 255.0f);
    *g = (uint8_t)clamp_test(y_f - 0.337633f * u_f - 0.698001f * v_f, 0.0f,
                             255.0f);
    *b = (uint8_t)clamp_test(y_f + 1.732446f * u_f, 0.0f, 255.0f);
  }

  // --------------------------------------------------------
  // HÀM XỬ LÝ ANTI-SPOOFING (Scale 2.7 -> Crop 80x80)
  // --------------------------------------------------------
  void process_face_crop(uint8_t * yuvPtr, int width, int height, int yStride,
                         int uvStride, float *landmarks, int landmark_count,
                         int rotation, int rX, int rY, int rW, int rH,
                         int target_width, int target_height, int model_type,
                         float *outputBuffer) {
    int logical_w = width;
    int logical_h = height;
    if (rotation == 90 || rotation == 270) {
      logical_w = height;
      logical_h = width;
    }

    // --- BƯỚC 1: TÍNH TOÁN VÙNG CROP (SQUARE + SCALE) ---
    float cx = rX + rW / 2.0f;
    float cy = rY + rH / 2.0f;

    // float shift_y_ratio = 0.8f;
    // cy = cy - (rH * shift_y_ratio);

    // Scale
    float scale = 1.0f;
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
    // crop_size) Tương đương: face_img = frame[y:y+h, x:x+w]
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
    // Tương đương: resized_img = cv2.resize(face_img, (224, 224))
    std::vector<uint8_t> resized_rgb(target_width * target_height * 3);

    // stbir_resize_uint8(input_data, input_w, input_h, input_stride,
    //                    output_data, output_w, output_h, output_stride,
    //                    num_channels)
    stbir_resize_uint8(raw_crop_rgb.data(), real_crop_w, real_crop_h, 0,
                       resized_rgb.data(), target_width, target_height, 0, 3);

    // // Chuẩn ImageNet (RGB)
    // float norm_mean[] = {0.485f, 0.456f, 0.406f};
    // float norm_std[] = {0.229f, 0.224f, 0.225f};

    // int pIdx = 0;
    // int rIdx = 0;

    // for (int i = 0; i < target_width * target_height; i++) {
    //   uint8_t r_byte = resized_rgb[rIdx++];
    //   uint8_t g_byte = resized_rgb[rIdx++];
    //   uint8_t b_byte = resized_rgb[rIdx++];

    //   // uint8_t tmp = r_byte;
    //   // r_byte = b_byte;
    //   // b_byte = tmp; // Swap R <-> B for BGR

    //   outputBuffer[pIdx++] =
    //       ((r_byte / 255.0f) - norm_mean[0]) / norm_std[0]; // R
    //   outputBuffer[pIdx++] =
    //       ((g_byte / 255.0f) - norm_mean[1]) / norm_std[1]; // G
    //   outputBuffer[pIdx++] =
    //       ((b_byte / 255.0f) - norm_mean[2]) / norm_std[2]; // B
    // }

    int pIdx = 0;
    int rIdx = 0;

    for (int i = 0; i < target_width * target_height; i++) {
      // Đọc tuần tự R, G, B từ mảng đã resize
      uint8_t r_byte = resized_rgb[rIdx++];
      uint8_t g_byte = resized_rgb[rIdx++];
      uint8_t b_byte = resized_rgb[rIdx++];

      // Ghi tuần tự vào outputBuffer theo thứ tự B, G, R
      outputBuffer[pIdx++] = (float)b_byte; 
      outputBuffer[pIdx++] = (float)g_byte; 
      outputBuffer[pIdx++] = (float)r_byte; 
    }

    /* // LỰA CHỌN 2: Dành cho Input TFLite shape [1, 3, 128, 128] (CHW - Gốc
    của PyTorch)
    // NẾU Dart báo lỗi Shape Mismatch, bác comment Lựa chọn 1 lại và dùng khối
    này: int channel_size = target_width * target_height; for (int i = 0; i <
    total_pixels; i++) { float r = resized_rgb[i * 3 + 0] / 255.0f; float g =
    resized_rgb[i * 3 + 1] / 255.0f; float b = resized_rgb[i * 3 + 2] / 255.0f;

      outputBuffer[i]                  = (r - norm_mean[0]) / norm_std[0];
      outputBuffer[i + channel_size]   = (g - norm_mean[1]) / norm_std[1];
      outputBuffer[i + 2*channel_size] = (b - norm_mean[2]) / norm_std[2];
    }
    */

    // for (int y = 0; y < target_height; y++) {
    //   float srcY = start_y + y * step;
    //   for (int x = 0; x < target_width; x++) {
    //     float srcX = start_x + x * step;

    //     // Tách màu và đưa về [0, 1]
    //     float r = ((rgb >> 16) & 0xFF) / 255.0f;
    //     float g = ((rgb >> 8) & 0xFF) / 255.0f;
    //     float b = (rgb & 0xFF) / 255.0f;

    //     // Kênh 0: Blue
    //     outputBuffer[pIdx++] = (b - norm_mean[0]) / norm_std[0];

    //     // Kênh 1: Green
    //     outputBuffer[pIdx++] = (g - norm_mean[1]) / norm_std[1];

    //     // Kênh 2: Red
    //     outputBuffer[pIdx++] = (r - norm_mean[2]) / norm_std[2];

    //     // } else {
    //     //   // MiniFASNet để nguyên 0..1 hoặc 0..255
    //     //   outputBuffer[pIdx++] = r;
    //     //   outputBuffer[pIdx++] = g;
    //     //   outputBuffer[pIdx++] = b;
    //     // }
    //   }
    // }
  }
}