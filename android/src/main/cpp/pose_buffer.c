#include "pose_buffer.h"

PoseBuffer* pose_buffer_alloc(void) {
    PoseBuffer* buffer = (PoseBuffer*)malloc(sizeof(PoseBuffer));
    if (buffer) {
        memset(buffer, 0, sizeof(PoseBuffer));
    }
    return buffer;
}

void pose_buffer_free(PoseBuffer* buffer) {
    if (buffer) {
        free(buffer);
    }
}

void pose_buffer_write(PoseBuffer* buffer, int frameId,
                       const float* pose_data, const float* world_data) {
    if (!buffer) return;
    if (pose_data) {
        memcpy(buffer->pose_landmarks, pose_data,
               POSE_NUM_LANDMARKS * POSE_LANDMARK_DIMS * sizeof(float));
    }
    if (world_data) {
        memcpy(buffer->world_landmarks, world_data,
               POSE_NUM_LANDMARKS * POSE_LANDMARK_DIMS * sizeof(float));
    }
    /* Write frameId LAST — Dart uses this for torn-read detection */
    buffer->frameId = frameId;
}
