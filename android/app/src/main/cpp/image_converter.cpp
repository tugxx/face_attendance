#include <stdint.h>
#include <stdlib.h>
#include <math.h>

// Macro để giới hạn giá trị màu từ 0-255 (tránh bị nhiễu hạt)
#define CLAMP(x) (x < 0 ? 0 : (x > 255 ? 255 : x))

extern "C" {

    // Hàm chuyển đổi YUV420 sang RGB (Zero-Copy logic)
    // Chúng ta dùng pointer (*) để truy cập trực tiếp vùng nhớ, không copy giá trị.
    __attribute__((visibility("default")))
    void convertNV21ToRGB(
        uint8_t* data,
        uint8_t* outputRGBA, // Output buffer (int32 để chứa ARGB)
        int width, 
        int height
    ) {
        int frameSize = width * height;
        int y, u, v;
        int r, g, b;

        for (int j = 0; j < height; j++) {
            for (int i = 0; i < width; i++) {
                // 1. Lấy Y
                int yIndex = j * width + i;
                y = (0xff & ((int)data[yIndex]));

                // 2. Lấy UV (Giả định định dạng NV21: V trước U sau)
                // index: frameSize + (row/2 * width) + (col/2 * 2)
                int uvIndex = frameSize + (j >> 1) * width + (i & ~1);
                
                // NV21 layout: V trước, U sau (V, U)
                v = (0xff & ((int)data[uvIndex])) - 128;
                u = (0xff & ((int)data[uvIndex + 1])) - 128;

                // 3. Convert YUV -> RGB
                int y1192 = 1192 * (y - 16);
                if (y1192 < 0) y1192 = 0;

                r = CLAMP((y1192 + 1634 * v) >> 10);
                g = CLAMP((y1192 - 833 * v - 400 * u) >> 10);
                b = CLAMP((y1192 + 2066 * u) >> 10);

                // GHI TỪNG BYTE (R -> G -> B -> A)
                // Đảm bảo đúng chuẩn RGBA
                int outIndex = yIndex * 4;
                
                outputRGBA[outIndex]     = (uint8_t)r;
                outputRGBA[outIndex + 1] = (uint8_t)g;
                outputRGBA[outIndex + 2] = (uint8_t)b;
                outputRGBA[outIndex + 3] = 255; // Alpha
            }
        }
    }
}