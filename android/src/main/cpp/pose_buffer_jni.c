#include <jni.h>
#include <stdint.h>
#include "pose_buffer.h"

JNIEXPORT jlong JNICALL
Java_com_example_npu_1pose_1detection_NativeMotionEngine_nativeAllocBuffer(
    JNIEnv *env, jobject thiz) {
    PoseBuffer* buffer = pose_buffer_alloc();
    return (jlong)(intptr_t)buffer;
}

JNIEXPORT void JNICALL
Java_com_example_npu_1pose_1detection_NativeMotionEngine_nativeFreeBuffer(
    JNIEnv *env, jobject thiz, jlong pointer) {
    PoseBuffer* buffer = (PoseBuffer*)(intptr_t)pointer;
    pose_buffer_free(buffer);
}

JNIEXPORT void JNICALL
Java_com_example_npu_1pose_1detection_NativeMotionEngine_nativeWriteLandmarks(
    JNIEnv *env, jobject thiz, jlong pointer, jint frameId,
    jfloatArray poseLandmarks, jfloatArray worldLandmarks) {
    PoseBuffer* buffer = (PoseBuffer*)(intptr_t)pointer;
    if (!buffer) return;

    jfloat* poseData = (*env)->GetFloatArrayElements(env, poseLandmarks, NULL);
    jfloat* worldData = (*env)->GetFloatArrayElements(env, worldLandmarks, NULL);

    pose_buffer_write(buffer, frameId, poseData, worldData);

    if (poseData) {
        (*env)->ReleaseFloatArrayElements(env, poseLandmarks, poseData, JNI_ABORT);
    }
    if (worldData) {
        (*env)->ReleaseFloatArrayElements(env, worldLandmarks, worldData, JNI_ABORT);
    }
}
