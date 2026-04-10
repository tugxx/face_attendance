#pragma once
#include <cstdint>

extern "C" {
bool process_face_affine(uint8_t *yuvBytes, int width, int height,
                         float *landmarks, int rotation, int inputWidth,
                         int inputHeight, float *outputBuffer);

bool process_face_crop(uint8_t *yuvPtr, int width, int height, int yStride,
                       int rotation, int rX, int rY, int rW, int rH,
                       int target_width, int target_height, float scale,
                       bool is_bgr, float *outputBuffer);
}