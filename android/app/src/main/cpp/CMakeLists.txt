cmake_minimum_required(VERSION 3.4.1)

# 1. Trỏ thư mục include để C++ đọc được file .h
include_directories(
        core
        utils
        third_party/stb
        third_party/tflite/include)

add_library( 
        native_face_align
        SHARED
        bridge/native_bridge.cpp        # Mặt tiền FFI
        utils/native_face_align.cpp     # File cắt ảnh
        core/face_recognizer.cpp        # Nhận diện
        core/anti_spoofing.cpp          # Chống giả mạo
)        

# 2. Báo cho CMake biết ta có thư viện TFLite JNI
add_library(lib_tflite SHARED IMPORTED)
set_target_properties(lib_tflite PROPERTIES IMPORTED_LOCATION
        ${CMAKE_SOURCE_DIR}/third_party/tflite/libs/${ANDROID_ABI}/libtensorflowlite_jni.so
)

# Tìm thư viện log của Android
find_library( 
        log-lib
        log )

target_link_libraries( 
        native_face_align
        ${log-lib} 
        lib_tflite)