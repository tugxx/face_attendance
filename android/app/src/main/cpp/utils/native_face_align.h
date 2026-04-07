#pragma once
#include <cstdint>

// Bao bọc bằng extern "C" để file C++ khác gọi được hàm của C
extern "C" {
void process_face_affine(uint8_t *yuvBytes, int width, int height,
                         float *landmarks, int rotation, float *outputBuffer);

void process_face_crop(uint8_t *yuvPtr, int width, int height, int yStride,
                       int rotation, int rX, int rY, int rW, int rH,
                       int target_width, int target_height, float scale,
                       bool is_bgr, float *outputBuffer);
}