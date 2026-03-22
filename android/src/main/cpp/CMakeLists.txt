cmake_minimum_required(VERSION 3.18.1)
project(pose_buffer C)

add_library(pose_buffer SHARED
    pose_buffer.c
    pose_buffer_jni.c
)

target_include_directories(pose_buffer PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
)
