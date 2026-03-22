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
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.framework.image.MediaImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.ImageProcessingOptions
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import io.flutter.view.TextureRegistry
import java.util.concurrent.Executors

/**
 * High-performance native motion engine using CameraX + MediaPipe PoseLandmarker.
 *
 * Architecture:
 * - CameraX Preview → Flutter SurfaceTexture (video display, decoupled from inference)
 * - CameraX ImageAnalysis → MediaPipe LIVE_STREAM → C PoseBuffer (FFI)
 * - Dart reads PoseBuffer via FFI (no MethodChannel for pose data)
 *
 * Performance constraints:
 * - No Bitmap conversions
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
        private const val MODEL_ASSET = "pose_landmarker_lite.task"
        private const val NUM_LANDMARKS = 33

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
    private var poseLandmarker: PoseLandmarker? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalysis: ImageAnalysis? = null
    private val analysisExecutor = Executors.newSingleThreadExecutor()

    // Timestamp synchronization — prevents landmark drift
    @Volatile
    private var latestSubmittedTimestamp: Long = 0
    private var frameId: Int = 0

    // Reusable arrays — NO per-frame allocation
    private val poseLandmarkData = FloatArray(NUM_LANDMARKS * 4)
    private val worldLandmarkData = FloatArray(NUM_LANDMARKS * 4)

    // Runtime config
    private var minPoseDetectionConfidence: Float = 0.5f
    private var minTrackingConfidence: Float = 0.5f
    private var minPosePresenceConfidence: Float = 0.5f
    private var numPoses: Int = 1

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
        minPoseDetectionConfidence =
            (config["minPoseDetectionConfidence"] as? Number)?.toFloat() ?: 0.5f
        minTrackingConfidence =
            (config["minTrackingConfidence"] as? Number)?.toFloat() ?: 0.5f
        minPosePresenceConfidence =
            (config["minPosePresenceConfidence"] as? Number)?.toFloat() ?: 0.5f
        numPoses = (config["numPoses"] as? Number)?.toInt() ?: 1
    }

    private fun initializePoseLandmarker() {
        val baseOptions = BaseOptions.builder()
            .setModelAssetPath(MODEL_ASSET)
            .setDelegate(Delegate.GPU)
            .build()

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
     * flattens into reusable arrays, writes to C buffer via JNI.
     */
    private fun handlePoseResult(result: PoseLandmarkerResult, input: MPImage) {
        // Timestamp synchronization: discard stale results
        if (result.timestampMs() < latestSubmittedTimestamp) {
            return
        }

        if (result.landmarks().isEmpty()) return

        val imageLandmarks = result.landmarks()[0]
        val worldLandmarks = result.worldLandmarks()[0]

        // Flatten into reusable arrays: [x, y, z, visibility] × 33
        for (i in 0 until NUM_LANDMARKS) {
            val idx = i * 4
            val lm = imageLandmarks[i]
            poseLandmarkData[idx] = lm.x()
            poseLandmarkData[idx + 1] = lm.y()
            poseLandmarkData[idx + 2] = lm.z()
            poseLandmarkData[idx + 3] = lm.visibility().orElse(0f)

            val wlm = worldLandmarks[i]
            worldLandmarkData[idx] = wlm.x()
            worldLandmarkData[idx + 1] = wlm.y()
            worldLandmarkData[idx + 2] = wlm.z()
            worldLandmarkData[idx + 3] = wlm.visibility().orElse(0f)
        }

        // Write ALL landmark values first, then frameId LAST
        frameId++
        nativeWriteLandmarks(bufferPointer, frameId, poseLandmarkData, worldLandmarkData)
    }

    private fun startCamera() {
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
            .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
            .build()

        imageAnalysis!!.setAnalyzer(analysisExecutor) { imageProxy ->
            processImageProxy(imageProxy)
        }

        val cameraSelector = CameraSelector.DEFAULT_FRONT_CAMERA

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
        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        try {
            // Direct MediaImage → MPImage (NO Bitmap conversion)
            val mpImage = MediaImageBuilder(mediaImage).build()

            val timestampMs = imageProxy.imageInfo.timestamp / 1000 // us → ms
            latestSubmittedTimestamp = timestampMs

            val processingOptions = ImageProcessingOptions.builder()
                .setRotationDegrees(imageProxy.imageInfo.rotationDegrees)
                .build()

            poseLandmarker?.detectAsync(mpImage, processingOptions, timestampMs)
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

        // Destroy current landmarker
        poseLandmarker?.close()
        poseLandmarker = null
        frameId = 0
        latestSubmittedTimestamp = 0

        // Recreate with new config
        initializePoseLandmarker()
        Log.i(TAG, "PoseLandmarker reinitialized with new config")
    }

    fun dispose() {
        // Stop camera
        cameraProvider?.unbindAll()
        cameraProvider = null
        imageAnalysis = null

        // Destroy landmarker
        poseLandmarker?.close()
        poseLandmarker = null

        // Release texture
        textureEntry?.release()
        textureEntry = null

        // Free native buffer
        if (bufferPointer != 0L) {
            nativeFreeBuffer(bufferPointer)
            bufferPointer = 0
        }

        analysisExecutor.shutdown()
        Log.i(TAG, "NativeMotionEngine disposed")
    }
}
