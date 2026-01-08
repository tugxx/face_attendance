cmake_minimum_required(VERSION 3.4.1)

add_library( 
    native_convert
    SHARED
    image_converter.cpp 
)

find_library( 
    log-lib
    log 
)

target_link_libraries( 
    native_convert
    ${log-lib} 
)