/*
 * PoseBuffer - Shared memory structure for FFI pose data exchange.
 *
 * Layout: single contiguous buffer allocated once via malloc.
 * Written by native (Swift via C interop), read by Dart via FFI.
 *
 * Thread safety: lock-free via frameId torn-read detection.
 * Dart reads frameId, copies data, re-checks frameId. If changed, retry.
 */

#ifndef POSE_BUFFER_H
#define POSE_BUFFER_H

#ifdef __cplusplus
extern "C" {
#endif

#include <stdlib.h>
#include <string.h>

#define POSE_NUM_LANDMARKS 33
#define POSE_LANDMARK_DIMS 4

typedef struct {
    int frameId;
    float pose_landmarks[POSE_NUM_LANDMARKS][POSE_LANDMARK_DIMS];   /* x, y, z, visibility */
    float world_landmarks[POSE_NUM_LANDMARKS][POSE_LANDMARK_DIMS];  /* x, y, z, visibility */
} PoseBuffer;

/* Allocate a zeroed PoseBuffer. Pointer remains valid for app lifetime. */
PoseBuffer* pose_buffer_alloc(void);

/* Free the PoseBuffer. Call only on app teardown. */
void pose_buffer_free(PoseBuffer* buffer);

/*
 * Write landmark data and frameId atomically (frameId written LAST).
 * pose_data and world_data must each be arrays of POSE_NUM_LANDMARKS * POSE_LANDMARK_DIMS floats.
 */
void pose_buffer_write(PoseBuffer* buffer, int frameId,
                       const float* pose_data, const float* world_data);

#ifdef __cplusplus
}
#endif

#endif /* POSE_BUFFER_H */
