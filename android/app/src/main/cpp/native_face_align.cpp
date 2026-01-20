#include <jni.h>
#include <math.h>
#include <android/log.h>
#include <algorithm>

#define PI 3.14159265358979323846
#define STB_IMAGE_IMPLEMENTATION
#include "stb_image.h"

// 5 Điểm chuẩn (Reference Points) cho ảnh 112x112
// [Mắt trái, Mắt phải, Mũi, Miệng trái, Miệng phải]
const float REF_X[] = {38.2946f, 73.5318f, 56.0252f, 41.5493f, 70.7299f};
const float REF_Y[] = {51.6963f, 51.6963f, 71.7366f, 92.3655f, 92.3655f};

extern "C" {

    inline int clamp(int v) { return (v < 0) ? 0 : ((v > 255) ? 255 : v); }

    // Hàm đọc pixel từ YUV NV21 có xử lý Xoay (Rotation)
    // Trả về: 0xRRGGBB
    int get_pixel_from_yuv(
        uint8_t* yuv, int width, int height, 
        float logicX, float logicY, int rotation
    ) {
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
        if (realX < 0) realX = 0; if (realX >= width) realX = width - 1;
        if (realY < 0) realY = 0; if (realY >= height) realY = height - 1;

        // Y Index
        int yIdx = realY * width + realX;
        int Y_val = yuv[yIdx] & 0xFF;

        // UV Index
        int uvIdx = width * height + (realY >> 1) * width + (realX & ~1);
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
    void process_face_affine(
        uint8_t* yuvBytes,
        int width, int height,
        float* landmarks,
        int rotation,
        float* outputBuffer
    ) {
        // 1. TÍNH MA TRẬN AFFINE (Dựa trên 2 mắt như code Dart)
        // Src = Landmarks từ Camera
        float src_eye_x = (landmarks[0] + landmarks[2]) / 2.0f; // Tâm mắt trái + phải
        float src_eye_y = (landmarks[1] + landmarks[3]) / 2.0f;
        
        float dx = landmarks[2] - landmarks[0];
        float dy = landmarks[3] - landmarks[1];
        float src_dist = sqrt(dx*dx + dy*dy);
        float src_angle = atan2(dy, dx);

        // Dst = Điểm chuẩn (Ref Points)
        float dst_eye_x = (REF_X[0] + REF_X[1]) / 2.0f;
        float dst_eye_y = (REF_Y[0] + REF_Y[1]) / 2.0f;
        
        float d_dx = REF_X[1] - REF_X[0];
        float d_dy = REF_Y[1] - REF_Y[0];
        float dst_dist = sqrt(d_dx*d_dx + d_dy*d_dy); // = 35.24
        float dst_angle = atan2(d_dy, d_dx); // = 0

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
                int rgb = get_pixel_from_yuv(yuvBytes, width, height, srcX, srcY, rotation);

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
    void process_file_affine_raw(
        char* filePath,       
        float* landmarks,     
        float* outputBuffer   
    ) {
        // 1. Đọc file ảnh bằng stb_image (Siêu nhẹ)
        int width, height, channels;
        // Force load thành 3 kênh màu (RGB) bất kể ảnh gốc là gì
        unsigned char* imgData = stbi_load(filePath, &width, &height, &channels, 3);
        
        if (imgData == NULL) {
            __android_log_print(ANDROID_LOG_ERROR, "NativeFace", "Cannot load image: %s", filePath);
            return;
        }

        // 2. TÍNH TOÁN MA TRẬN AFFINE (Code Toán thuần - Giống Dart)
        // Tâm mắt trái/phải từ Landmarks
        float src_eye_x = (landmarks[0] + landmarks[2]) / 2.0f;
        float src_eye_y = (landmarks[1] + landmarks[3]) / 2.0f;
        
        float dx = landmarks[2] - landmarks[0];
        float dy = landmarks[3] - landmarks[1];
        float src_dist = sqrt(dx*dx + dy*dy);
        float src_angle = atan2(dy, dx);

        // Tâm mắt chuẩn (Ref Points)
        float dst_eye_x = (REF_X[0] + REF_X[1]) / 2.0f;
        float dst_eye_y = (REF_Y[0] + REF_Y[1]) / 2.0f;
        float d_dx = REF_X[1] - REF_X[0];
        float d_dy = REF_Y[1] - REF_Y[0];
        float dst_dist = sqrt(d_dx*d_dx + d_dy*d_dy);
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
                if (realX < 0) realX = 0; if (realX >= width) realX = width - 1;
                if (realY < 0) realY = 0; if (realY >= height) realY = height - 1;

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
    

    // --------------------------------------------------------
    // HÀM XỬ LÝ ANTI-SPOOFING (Scale 2.7 -> Crop 80x80)
    // --------------------------------------------------------
    void process_antispoof_crop(
        uint8_t* yuvBytes,
        int width, int height,
        int x, int y, int w, int h, // Bbox khuôn mặt
        int rotation,
        float* outputBuffer // Output 80x80x3
    ) {
        // 1. Logic tính toán Box mới (Port từ Python CropImage._get_new_box)
        float scale = 2.7f;
        
        // Tính scale logic giống Python
        // scale = min((src_h-1)/box_h, min((src_w-1)/box_w, scale))
        // Ở đây ta dùng kích thước logic sau khi xoay (nếu cần), 
        // nhưng để đơn giản ta tính trên hệ toạ độ gốc của bbox
        
        float new_width = w * scale;
        float new_height = h * scale;
        
        float center_x = x + w / 2.0f;
        float center_y = y + h / 2.0f;

        int left = (int)(center_x - new_width / 2.0f);
        int top = (int)(center_y - new_height / 2.0f);
        
        // 2. Loop 80x80 (Kích thước input MiniFASNet)
        int targetSize = 80;
        int pIdx = 0;
        
        // Tỷ lệ step để lấy mẫu từ ảnh to về 80x80
        float stepX = new_width / (float)targetSize;
        float stepY = new_height / (float)targetSize;

        for (int row = 0; row < targetSize; row++) {
            for (int col = 0; col < targetSize; col++) {
                
                // Tính toạ độ cần lấy trên ảnh gốc
                float srcX = left + col * stepX;
                float srcY = top + row * stepY;

                // Hàm get_pixel_from_yuv (đã viết ở bài trước) cực kỳ hữu dụng ở đây!
                // Nó tự lo việc check biên (padding) và xoay ảnh (rotation)
                int rgb = get_pixel_from_yuv(yuvBytes, width, height, srcX, srcY, rotation);

                int r = (rgb >> 16) & 0xFF;
                int g = (rgb >> 8) & 0xFF;
                int b = rgb & 0xFF;

                // Python: img.astype(np.float32) (Thường là 0-255 hoặc chuẩn hóa tùy lúc train)
                // MiniFASNet gốc thường không normalize về -1..1 mà để 0..255 hoặc 0..1
                // Ở đây tôi để 0..1 (float), nếu model chạy sai thì sửa thành r/1.0f (giữ nguyên 0-255)
                
                // LƯU Ý: TFLite cần input shape [1, 80, 80, 3] (NHWC)
                // Nên ta ghi R, G, B tuần tự
                outputBuffer[pIdx++] = (float)r; // Giả sử model cần 0-255
                outputBuffer[pIdx++] = (float)g;
                outputBuffer[pIdx++] = (float)b;
            }
        }
    }
}