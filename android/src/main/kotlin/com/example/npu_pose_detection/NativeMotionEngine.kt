package com.example.npu_pose_detection

import android.app.Activity
import android.content.Context
import android.util.Log
import android.util.Size
import android.view.Surface
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.ImageProcessingOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import io.flutter.view.TextureRegistry
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * High-performance native motion engine using CameraX + MediaPipe PoseLandmarker.
 *
 * Architecture:
 * - CameraX Preview → Flutter SurfaceTexture (video display, decoupled from inference)
 * - CameraX ImageAnalysis → MediaPipe LIVE_STREAM → C PoseBuffer (FFI)
 * - Dart reads PoseBuffer via FFI (no MethodChannel for pose data)
 *
 * Performance constraints:
 * - Zero-copy ByteBuffer path (CameraX RGBA_8888 → MediaPipe GPU)
 * - No per-frame allocation (reusable FloatArrays)
 * - No frame queuing (KEEP_ONLY_LATEST)
 * - Timestamp synchronization prevents drift
 */
class NativeMotionEngine(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
    private val activity: Activity
) {

    companion object {
        private const val TAG = "NativeMotionEngine"
        private const val NUM_LANDMARKS = 33

        private val MODEL_ASSETS = mapOf(
            "lite" to "pose_landmarker_lite.task",
            "full" to "pose_landmarker_full.task",
            "heavy" to "pose_landmarker_heavy.task",
        )

        init {
            System.loadLibrary("pose_buffer")
        }
    }

    // JNI native methods — backed by pose_buffer_jni.c
    private external fun nativeAllocBuffer(): Long
    private external fun nativeFreeBuffer(pointer: Long)
    private external fun nativeWriteLandmarks(
        pointer: Long, frameId: Int,
        poseLandmarks: FloatArray, worldLandmarks: FloatArray
    )

    // State
    private var bufferPointer: Long = 0
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    @Volatile private var poseLandmarker: PoseLandmarker? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var analysisExecutor = Executors.newSingleThreadExecutor()
    private val bufferLock = Any()
    private val landmarkerLock = Any()

    // Timestamp synchronization — prevents landmark drift
    @Volatile
    private var latestSubmittedTimestamp: Long = 0
    private var frameId: Int = 0
    @Volatile
    private var currentRotationDegrees: Int = 0

    // Reusable arrays — NO per-frame allocation
    private val poseLandmarkData = FloatArray(NUM_LANDMARKS * 4)
    private val worldLandmarkData = FloatArray(NUM_LANDMARKS * 4)

    // Runtime config
    private var modelComplexity: String = "lite"
    private var cameraFacing: String = "front"
    private var targetFps: Int = 0
    private var minPoseDetectionConfidence: Float = 0.5f
    private var minTrackingConfidence: Float = 0.5f
    private var minPosePresenceConfidence: Float = 0.5f
    private var numPoses: Int = 1

    // FPS throttle
    private var minFrameIntervalMs: Long = 0
    private var lastInferenceTimestampMs: Long = 0

    /**
     * Initialize the engine. Returns textureId + pointerAddress for Dart.
     */
    fun initialize(config: Map<String, Any>): Map<String, Any> {
        applyConfig(config)

        // 1. Allocate C buffer (once, NEVER reallocated)
        bufferPointer = nativeAllocBuffer()
        if (bufferPointer == 0L) {
            throw IllegalStateException("Failed to allocate native PoseBuffer")
        }
        Log.i(TAG, "Allocated PoseBuffer at 0x${bufferPointer.toString(16)}")

        // 2. Register Flutter texture
        textureEntry = textureRegistry.createSurfaceTexture()
        val textureId = textureEntry!!.id()
        Log.i(TAG, "Registered Flutter texture: $textureId")

        // 3. Initialize MediaPipe PoseLandmarker (LIVE_STREAM, GPU)
        initializePoseLandmarker()

        // 4. Start CameraX (async — camera binds after provider is ready)
        startCamera()

        return mapOf(
            "textureId" to textureId,
            "pointerAddress" to bufferPointer
        )
    }

    private fun applyConfig(config: Map<String, Any>) {
        modelComplexity = (config["modelComplexity"] as? String) ?: "lite"
        cameraFacing = (config["cameraFacing"] as? String) ?: "front"
        targetFps = (config["targetFps"] as? Number)?.toInt() ?: 0
        minFrameIntervalMs = if (targetFps > 0) 1000L / targetFps else 0
        minPoseDetectionConfidence =
            (config["minPoseDetectionConfidence"] as? Number)?.toFloat() ?: 0.5f
        minTrackingConfidence =
            (config["minTrackingConfidence"] as? Number)?.toFloat() ?: 0.5f
        minPosePresenceConfidence =
            (config["minPosePresenceConfidence"] as? Number)?.toFloat() ?: 0.5f
        numPoses = (config["numPoses"] as? Number)?.toInt() ?: 1
    }

    private fun initializePoseLandmarker() {
        val modelAsset = MODEL_ASSETS[modelComplexity] ?: MODEL_ASSETS["lite"]!!
        val baseOptions = BaseOptions.builder()
            .setModelAssetPath(modelAsset)
            .setDelegate(Delegate.GPU)
            .build()
        Log.i(TAG, "Loading model: $modelAsset")

        val options = PoseLandmarker.PoseLandmarkerOptions.builder()
            .setBaseOptions(baseOptions)
            .setRunningMode(RunningMode.LIVE_STREAM)
            .setMinPoseDetectionConfidence(minPoseDetectionConfidence)
            .setMinPosePresenceConfidence(minPosePresenceConfidence)
            .setMinTrackingConfidence(minTrackingConfidence)
            .setNumPoses(numPoses)
            .setResultListener(this::handlePoseResult)
            .setErrorListener { error ->
                Log.e(TAG, "MediaPipe error: ${error.message}")
            }
            .build()

        poseLandmarker = PoseLandmarker.createFromOptions(context, options)
        Log.i(TAG, "PoseLandmarker initialized (LIVE_STREAM, GPU)")
    }

    /**
     * MediaPipe result callback — extracts all 33 landmarks + world landmarks,
     * transforms from sensor coordinates to display coordinates,
     * flattens into reusable arrays, writes to C buffer via JNI.
     */
    private fun handlePoseResult(result: PoseLandmarkerResult, input: MPImage) {
        if (result.landmarks().isEmpty()) return
        if (result.worldLandmarks().isEmpty()) return

        val imageLandmarks = result.landmarks()[0]
        val worldLandmarks = result.worldLandmarks()[0]
        val rotation = currentRotationDegrees

        // Flatten into reusable arrays: [x, y, z, visibility] × 33
        // Transform image-space landmarks from sensor coordinates to portrait display space.
        // MediaPipe returns normalized coords in the original (unrotated) image space.
        for (i in 0 until NUM_LANDMARKS) {
            val idx = i * 4
            val lm = imageLandmarks[i]
            val sx = lm.x()
            val sy = lm.y()

            // Rotate normalized coords to match upright display
            when (rotation) {
                90 -> {
                    poseLandmarkData[idx] = 1f - sy
                    poseLandmarkData[idx + 1] = sx
                }
                180 -> {
                    poseLandmarkData[idx] = 1f - sx
                    poseLandmarkData[idx + 1] = 1f - sy
                }
                270 -> {
                    poseLandmarkData[idx] = sy
                    poseLandmarkData[idx + 1] = 1f - sx
                }
                else -> {
                    poseLandmarkData[idx] = sx
                    poseLandmarkData[idx + 1] = sy
                }
            }
            poseLandmarkData[idx + 2] = lm.z()
            poseLandmarkData[idx + 3] = lm.visibility().orElse(0f)

            // World landmarks are in meters (hip-centered) — rotation-independent
            val wlm = worldLandmarks[i]
            worldLandmarkData[idx] = wlm.x()
            worldLandmarkData[idx + 1] = wlm.y()
            worldLandmarkData[idx + 2] = wlm.z()
            worldLandmarkData[idx + 3] = wlm.visibility().orElse(0f)
        }

        // Write ALL landmark values first, then frameId LAST
        frameId++
        synchronized(bufferLock) {
            if (bufferPointer != 0L) {
                nativeWriteLandmarks(bufferPointer, frameId, poseLandmarkData, worldLandmarkData)
            }
        }
    }

    fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            cameraProvider = cameraProviderFuture.get()
            bindCameraUseCases()
        }, ContextCompat.getMainExecutor(context))
    }

    private fun bindCameraUseCases() {
        val provider = cameraProvider ?: return
        val entry = textureEntry ?: return
        val lifecycleOwner = activity as? LifecycleOwner ?: return

        // Preview → Flutter SurfaceTexture (decoupled from inference)
        val preview = Preview.Builder().build()
        preview.setSurfaceProvider { request ->
            val surfaceTexture = entry.surfaceTexture()
            surfaceTexture.setDefaultBufferSize(
                request.resolution.width,
                request.resolution.height
            )
            val surface = Surface(surfaceTexture)
            request.provideSurface(surface, ContextCompat.getMainExecutor(context)) { }
        }

        // ImageAnalysis → MediaPipe inference (independent pipeline)
        imageAnalysis = ImageAnalysis.Builder()
            .setTargetResolution(Size(640, 480))
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
            .build()

        imageAnalysis!!.setAnalyzer(analysisExecutor) { imageProxy ->
            processImageProxy(imageProxy)
        }

        val cameraSelector = if (cameraFacing == "back") {
            CameraSelector.DEFAULT_BACK_CAMERA
        } else {
            CameraSelector.DEFAULT_FRONT_CAMERA
        }

        provider.unbindAll()
        provider.bindToLifecycle(
            lifecycleOwner,
            cameraSelector,
            preview,
            imageAnalysis!!
        )

        Log.i(TAG, "CameraX bound: Preview + ImageAnalysis")
    }

    private fun processImageProxy(imageProxy: ImageProxy) {
        try {
            val timestampMs = imageProxy.imageInfo.timestamp / 1000 // us → ms

            // FPS throttle: skip frame if too soon since last inference
            if (minFrameIntervalMs > 0 && timestampMs - lastInferenceTimestampMs < minFrameIntervalMs) {
                return
            }

            // CameraX RGBA_8888 → MPImage. Prefer zero-copy ByteBuffer when stride is tight;
            // fall back to Bitmap path if the row stride has padding.
            val plane = imageProxy.planes[0]
            val mpImage = if (plane.rowStride == imageProxy.width * 4) {
                val buffer = plane.buffer
                buffer.rewind()
                ByteBufferImageBuilder(buffer, imageProxy.width, imageProxy.height, MPImage.IMAGE_FORMAT_RGBA).build()
            } else {
                BitmapImageBuilder(imageProxy.toBitmap()).build()
            }

            // Store rotation for landmark coordinate transform in handlePoseResult
            currentRotationDegrees = imageProxy.imageInfo.rotationDegrees

            // Tell MediaPipe how the sensor image is rotated relative to upright display.
            val rotation = imageProxy.imageInfo.rotationDegrees
            val processingOptions = ImageProcessingOptions.builder()
                .setRotationDegrees(rotation)
                .build()

            synchronized(landmarkerLock) {
                val landmarker = poseLandmarker ?: return
                // Guard monotonic timestamp inside lock to prevent races with updateConfig reset
                if (timestampMs <= latestSubmittedTimestamp) return
                latestSubmittedTimestamp = timestampMs
                lastInferenceTimestampMs = timestampMs
                landmarker.detectAsync(mpImage, processingOptions, timestampMs)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Inference error: ${e.message}")
        } finally {
            imageProxy.close() // ALWAYS close
        }
    }

    /**
     * Update configuration. Requires destroying and recreating the landmarker.
     * Process: Stop inference → Destroy landmarker → Recreate with new config.
     */
    fun updateConfig(config: Map<String, Any>) {
        applyConfig(config)

        synchronized(landmarkerLock) {
            // Close current landmarker while holding lock — blocks processImageProxy
            poseLandmarker?.close()
            poseLandmarker = null
            frameId = 0
            latestSubmittedTimestamp = 0
            lastInferenceTimestampMs = 0

            // Recreate with new config (still under lock so no frames sneak in)
            initializePoseLandmarker()
        }
        Log.i(TAG, "PoseLandmarker reinitialized with new config")
    }

    fun dispose() {
        // 1. Stop camera — no new frames enter the pipeline
        cameraProvider?.unbindAll()
        cameraProvider = null
        imageAnalysis = null

        // 2. Drain executor — wait for in-flight processImageProxy/detectAsync calls
        analysisExecutor.shutdown()
        try {
            analysisExecutor.awaitTermination(2, TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
        // Recreate executor so engine can be re-initialized if needed
        analysisExecutor = Executors.newSingleThreadExecutor()

        // 3. Close landmarker after executor is idle — no detectAsync in-flight
        synchronized(landmarkerLock) {
            poseLandmarker?.close()
            poseLandmarker = null
        }

        // 4. Release texture
        textureEntry?.release()
        textureEntry = null

        // 5. Free native buffer under lock — prevents write-after-free
        synchronized(bufferLock) {
            if (bufferPointer != 0L) {
                nativeFreeBuffer(bufferPointer)
                bufferPointer = 0
            }
        }

        Log.i(TAG, "NativeMotionEngine disposed")
    }
}
