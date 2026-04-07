#ifndef APP_LOG_H
#define APP_LOG_H

/*
 * Mẹo C++: Dấu ##__VA_ARGS__ là một tính năng mở rộng của Clang/GCC
 * giúp mã không bị lỗi khi bạn chỉ in chuỗi mà không truyền tham số (vd:
 * LOG_INFO("Hello")).
 */

#ifdef __ANDROID__
// ==========================================
// LOG CHO ANDROID (Hiển thị trong Logcat)
// ==========================================
#include <android/log.h>
#define LOG_TAG "NativeFaceAI"

#define LOG_INFO(fmt, ...)                                                     \
  __android_log_print(ANDROID_LOG_INFO, LOG_TAG, "🔵 [INFO]: " fmt,             \
                      ##__VA_ARGS__)
#define LOG_WARN(fmt, ...)                                                     \
  __android_log_print(ANDROID_LOG_WARN, LOG_TAG, "🟠 [WARN]: " fmt,          \
                      ##__VA_ARGS__)
#define LOG_ERROR(fmt, ...)                                                    \
  __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "🔴 [ERROR]: " fmt,           \
                      ##__VA_ARGS__)
#define LOG_SPOOF(fmt, ...)                                                    \
  __android_log_print(ANDROID_LOG_INFO, LOG_TAG, "🛡️ [ANTI-SPOOF]: " fmt, \
                      ##__VA_ARGS__)

#else
// ==========================================
// LOG CHO iOS / DESKTOP (Hiển thị trong Console/Xcode)
// ==========================================
#include <stdio.h>

#define LOG_INFO(fmt, ...) printf("🔵 [INFO]: " fmt "\n", ##__VA_ARGS__)
#define LOG_WARN(fmt, ...) printf("🟠 [WARN]: " fmt "\n", ##__VA_ARGS__)
#define LOG_ERROR(fmt, ...) printf("🔴 [ERROR]: " fmt "\n", ##__VA_ARGS__)
#define LOG_SPOOF(fmt, ...)                                                    \
  printf("🛡️ [ANTI-SPOOF]: " fmt "\n", ##__VA_ARGS__)

#endif

#endif // APP_LOG_H