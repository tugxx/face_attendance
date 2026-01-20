cmake_minimum_required(VERSION 3.4.1)

add_library( 
        native_face_align
        SHARED
        native_face_align.cpp) # Tên file C++ của bạn

# Tìm thư viện log của Android
find_library( 
        log-lib
        log )

target_link_libraries( 
        native_face_align
        ${log-lib} )