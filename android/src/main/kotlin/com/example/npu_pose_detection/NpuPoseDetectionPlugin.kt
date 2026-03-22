package com.example.npu_pose_detection

import android.app.Activity
import android.content.Context
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.view.TextureRegistry
import kotlinx.coroutines.*
import com.example.npu_pose_detection.models.*

/**
 * Flutter plugin for NPU-accelerated pose detection on Android.
 *
 * Uses MediaPipe PoseLandmarker for 33-landmark detection with GPU acceleration.
 */
class NpuPoseDetectionPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler, ActivityAware {

    companion object {
        private const val TAG = "NpuPoseDetectionPlugin"
        private const val METHOD_CHANNEL = "com.example.flutter_pose_detection/methods"
        private const val EVENT_CHANNEL = "com.example.flutter_pose_detection/frames"
        private const val VIDEO_PROGRESS_CHANNEL = "com.example.flutter_pose_detection/video_progress"
    }

    private lateinit var channel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var videoProgressChannel: EventChannel
    private lateinit var context: Context
    private var textureRegistry: TextureRegistry? = null
    private var activity: Activity? = null
    private var mediaPipeDetector: MediaPipeNpuDetector? = null
    private var tfliteDetector: TFLitePoseDetector? = null
    private var activeDetector: PoseDetectorInterface? = null
    private var nativeMotionEngine: NativeMotionEngine? = null
    private var config: DetectorConfig = DetectorConfig()
    private var useNpuBackend: Boolean = false

    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())

    // Stream handling
    private var frameEventSink: EventChannel.EventSink? = null
    private var videoProgressEventSink: EventChannel.EventSink? = null
    private var isStreamingActive = false
    private var frameCount = 0
    private val fpsCalculator = FPSCalculator()
    private var videoProcessor: VideoProcessor? = null

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        textureRegistry = flutterPluginBinding.textureRegistry
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, METHOD_CHANNEL)
        channel.setMethodCallHandler(this)

        // Setup EventChannel for camera frame streaming
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)

        // Setup EventChannel for video progress
        videoProgressChannel = EventChannel(flutterPluginBinding.binaryMessenger, VIDEO_PROGRESS_CHANNEL)
        videoProgressChannel.setStreamHandler(VideoProgressStreamHandler(this))
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> handleInitialize(call, result)
            "detectPose" -> handleDetectPose(call, result)
            "detectPoseFromFile" -> handleDetectPoseFromFile(call, result)
            "processFrame" -> handleProcessFrame(call, result)
            "startCameraDetection" -> handleStartCameraDetection(result)
            "stopCameraDetection" -> handleStopCameraDetection(result)
            "analyzeVideo" -> handleAnalyzeVideo(call, result)
            "cancelVideoAnalysis" -> handleCancelVideoAnalysis(result)
            "updateConfig" -> handleUpdateConfig(call, result)
            "getDeviceCapabilities" -> handleGetDeviceCapabilities(result)
            "benchmarkDelegates" -> handleBenchmarkDelegates(call, result)
            "initializeMotionEngine" -> handleInitializeMotionEngine(call, result)
            "updateMotionEngineConfig" -> handleUpdateMotionEngineConfig(call, result)
            "disposeMotionEngine" -> handleDisposeMotionEngine(result)
            "dispose" -> handleDispose(result)
            else -> result.notImplemented()
        }
    }

    // StreamHandler implementation
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        frameEventSink = events
    }

    override fun onCancel(arguments: Any?) {
        frameEventSink = null
        isStreamingActive = false
    }

    // MARK: - Initialize

    private fun handleInitialize(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val configMap = args?.get("config") as? Map<*, *>

        if (configMap == null) {
            result.success(errorResponse("invalidArguments", "Missing config"))
            return
        }

        config = DetectorConfig.fromMap(configMap)
        useNpuBackend = config.preferredAcceleration == AccelerationMode.NPU

        scope.launch {
            try {
                if (useNpuBackend) {
                    // Use TFLite + QNN for NPU acceleration (better battery efficiency)
                    Log.i(TAG, "Initializing TFLite with QNN delegate (NPU)...")
                    tfliteDetector = TFLitePoseDetector(context)
                    val mode = withContext(Dispatchers.IO) {
                        tfliteDetector?.initialize(config)
                    }

                    if (tfliteDetector?.isInitialized != true) {
                        throw IllegalStateException("TFLite detector not initialized")
                    }

                    activeDetector = tfliteDetector
                    Log.i(TAG, "✓ TFLite NPU initialized successfully, mode=$mode")
                    result.success(mapOf(
                        "success" to true,
                        "accelerationMode" to (mode?.name?.lowercase() ?: "npu"),
                        "modelVersion" to "tflite_pose_landmarks",
                        "numLandmarks" to 33
                    ))
                } else {
                    // Use MediaPipe for GPU acceleration (faster but more power)
                    Log.i(TAG, "Initializing MediaPipe PoseLandmarker...")
                    mediaPipeDetector = MediaPipeNpuDetector(context)
                    val mode = withContext(Dispatchers.IO) {
                        mediaPipeDetector?.initialize(config)
                    }

                    if (mediaPipeDetector?.isInitialized != true) {
                        throw IllegalStateException("MediaPipe PoseLandmarker not initialized")
                    }

                    activeDetector = mediaPipeDetector
                    Log.i(TAG, "✓ MediaPipe initialized successfully, mode=$mode")
                    result.success(mapOf(
                        "success" to true,
                        "accelerationMode" to (mode?.name?.lowercase() ?: "gpu"),
                        "modelVersion" to "mediapipe_pose_landmarker",
                        "numLandmarks" to 33
                    ))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Initialization failed: ${e.message}", e)
                result.success(errorResponse(
                    "modelLoadFailed",
                    "Failed to initialize pose detector",
                    e.message
                ))
            }
        }
    }

    // MARK: - Detect Pose

    private fun handleDetectPose(call: MethodCall, result: Result) {
        if (!isDetectorReady()) {
            result.success(errorResponse("notInitialized", "Detector not initialized"))
            return
        }

        val args = call.arguments as? Map<*, *>
        val imageData = args?.get("imageData") as? ByteArray

        if (imageData == null) {
            result.success(errorResponse("invalidImageFormat", "Invalid image data"))
            return
        }

        scope.launch {
            try {
                val poseResult = withContext(Dispatchers.IO) {
                    activeDetector?.detectPose(imageData)
                }

                result.success(mapOf(
                    "success" to true,
                    "result" to poseResult?.toMap()
                ))
            } catch (e: Exception) {
                result.success(errorResponse(
                    "inferenceFailed",
                    "Pose detection failed",
                    e.message
                ))
            }
        }
    }

    // MARK: - Detect Pose From File

    private fun handleDetectPoseFromFile(call: MethodCall, result: Result) {
        if (!isDetectorReady()) {
            result.success(errorResponse("notInitialized", "Detector not initialized"))
            return
        }

        val args = call.arguments as? Map<*, *>
        val filePath = args?.get("filePath") as? String

        if (filePath == null) {
            result.success(errorResponse("invalidArguments", "Missing file path"))
            return
        }

        scope.launch {
            try {
                val poseResult = withContext(Dispatchers.IO) {
                    activeDetector?.detectPoseFromFile(filePath)
                }

                result.success(mapOf(
                    "success" to true,
                    "result" to poseResult?.toMap()
                ))
            } catch (e: Exception) {
                result.success(errorResponse(
                    "inferenceFailed",
                    "Pose detection failed",
                    e.message
                ))
            }
        }
    }

    private fun isDetectorReady(): Boolean {
        return activeDetector?.isInitialized == true
    }

    // MARK: - Update Config

    private fun handleUpdateConfig(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val configMap = args?.get("config") as? Map<*, *>

        if (configMap == null) {
            result.success(errorResponse("invalidArguments", "Missing config"))
            return
        }

        config = DetectorConfig.fromMap(configMap)
        mediaPipeDetector?.updateConfig(config)

        result.success(mapOf(
            "success" to true,
            "requiresReinitialize" to false
        ))
    }

    // MARK: - Device Capabilities

    private fun handleGetDeviceCapabilities(result: Result) {
        val hasNnapi = Build.VERSION.SDK_INT in 27..34 // NNAPI is supported on Android 8.1 to 14
        val hasGpu = true // Most devices support GPU delegate

        result.success(mapOf(
            "success" to true,
            "capabilities" to mapOf(
                "platform" to "android",
                "osVersion" to Build.VERSION.RELEASE,
                "deviceModel" to "${Build.MANUFACTURER} ${Build.MODEL}",
                "npuInfo" to mapOf(
                    "type" to "nnapi",
                    "isAvailable" to hasNnapi,
                    "performanceTier" to if (hasNnapi) "medium" else "low"
                ),
                "hasGpuSupport" to hasGpu,
                "recommendedMode" to if (hasGpu) "gpu" else "cpu"
            )
        ))
    }

    // MARK: - Process Frame

    private fun handleProcessFrame(call: MethodCall, result: Result) {
        if (!isDetectorReady()) {
            result.success(errorResponse("notInitialized", "Detector not initialized"))
            return
        }

        val args = call.arguments as? Map<*, *>
        @Suppress("UNCHECKED_CAST")
        val planes = args?.get("planes") as? List<Map<String, Any>>
        val width = args?.get("width") as? Int
        val height = args?.get("height") as? Int
        val format = args?.get("format") as? String ?: "yuv420"
        val rotation = args?.get("rotation") as? Int ?: 0

        if (planes == null || width == null || height == null) {
            result.success(errorResponse("invalidArguments", "Missing frame data"))
            return
        }

        // Extract binary bytes directly
        val decodedPlanes = planes.map { plane ->
            val bytes = plane["bytes"] as? ByteArray ?: ByteArray(0)
            mapOf(
                "bytes" to bytes,
                "bytesPerRow" to (plane["bytesPerRow"] as? Int ?: 0),
                "bytesPerPixel" to (plane["bytesPerPixel"] as? Int ?: 1)
            )
        }

        scope.launch {
            try {
                val poseResult = withContext(Dispatchers.IO) {
                    mediaPipeDetector?.processFrame(decodedPlanes, width, height, format, rotation)
                }

                result.success(mapOf(
                    "success" to true,
                    "result" to poseResult?.toMap()
                ))
            } catch (e: Exception) {
                result.success(errorResponse(
                    "inferenceFailed",
                    "Frame processing failed",
                    e.message
                ))
            }
        }
    }

    // MARK: - Camera Detection

    private fun handleStartCameraDetection(result: Result) {
        if (!isDetectorReady()) {
            result.success(errorResponse("notInitialized", "Detector not initialized"))
            return
        }

        isStreamingActive = true
        frameCount = 0
        fpsCalculator.reset()

        result.success(mapOf("success" to true))
    }

    private fun handleStopCameraDetection(result: Result) {
        isStreamingActive = false

        // Send end event
        frameEventSink?.success(mapOf(
            "type" to "end",
            "reason" to "stopped"
        ))

        result.success(mapOf("success" to true))
    }

    // MARK: - Video Analysis

    private fun handleAnalyzeVideo(call: MethodCall, result: Result) {
        if (!isDetectorReady()) {
            result.success(errorResponse("notInitialized", "Detector not initialized"))
            return
        }

        val args = call.arguments as? Map<*, *>
        val videoPath = args?.get("videoPath") as? String
        val frameInterval = (args?.get("frameInterval") as? Int) ?: 1

        if (videoPath == null) {
            result.success(errorResponse("invalidArguments", "Missing video path"))
            return
        }

        val detector = mediaPipeDetector!! as PoseDetectorInterface

        videoProcessor = VideoProcessor(context, detector)

        scope.launch {
            try {
                val analysisResult = videoProcessor?.analyzeVideo(
                    videoPath,
                    frameInterval
                ) { progress ->
                    videoProgressEventSink?.success(progress.toMap())
                }

                if (analysisResult != null) {
                    videoProgressEventSink?.success(mapOf("type" to "complete"))
                    result.success(mapOf(
                        "success" to true,
                        "result" to analysisResult.toMap()
                    ))
                } else {
                    result.success(errorResponse("videoAnalysisFailed", "Analysis returned null"))
                }
            } catch (e: Exception) {
                videoProgressEventSink?.success(mapOf(
                    "type" to "error",
                    "error" to mapOf(
                        "code" to "videoAnalysisFailed",
                        "message" to (e.message ?: "Unknown error")
                    )
                ))
                result.success(errorResponse(
                    "videoAnalysisFailed",
                    "Video analysis failed",
                    e.message
                ))
            }
        }
    }

    private fun handleCancelVideoAnalysis(result: Result) {
        videoProcessor?.cancel()
        videoProgressEventSink?.success(mapOf("type" to "cancelled"))
        result.success(mapOf("success" to true))
    }

    // MARK: - Benchmark Delegates

    private fun handleBenchmarkDelegates(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val iterations = (args?.get("iterations") as? Int) ?: 10

        Log.i(TAG, "Starting delegate benchmark (iterations=$iterations)...")

        scope.launch {
            try {
                val tfliteDetector = TFLitePoseDetector(context)
                val results = withContext(Dispatchers.IO) {
                    tfliteDetector.benchmarkAll(iterations)
                }
                tfliteDetector.dispose()

                val benchmarkResults = results.map { (delegate, benchResult) ->
                    delegate to mapOf(
                        "success" to benchResult.success,
                        "avgInferenceTimeMs" to benchResult.avgInferenceTimeMs,
                        "minInferenceTimeMs" to benchResult.minInferenceTimeMs,
                        "maxInferenceTimeMs" to benchResult.maxInferenceTimeMs,
                        "errorMessage" to benchResult.errorMessage
                    )
                }.toMap()

                result.success(mapOf(
                    "success" to true,
                    "results" to benchmarkResults
                ))
            } catch (e: Exception) {
                Log.e(TAG, "Benchmark failed: ${e.message}", e)
                result.success(errorResponse(
                    "benchmarkFailed",
                    "Benchmark failed",
                    e.message
                ))
            }
        }
    }

    // MARK: - Dispose

    private fun handleDispose(result: Result) {
        isStreamingActive = false
        videoProcessor?.cancel()
        videoProcessor = null
        activeDetector = null
        mediaPipeDetector?.dispose()
        mediaPipeDetector = null
        tfliteDetector?.dispose()
        tfliteDetector = null
        nativeMotionEngine?.dispose()
        nativeMotionEngine = null
        useNpuBackend = false
        result.success(mapOf("success" to true))
    }

    // MARK: - Motion Engine

    private fun handleInitializeMotionEngine(call: MethodCall, result: Result) {
        val currentActivity = activity
        val currentTextureRegistry = textureRegistry
        if (currentActivity == null || currentTextureRegistry == null) {
            result.success(errorResponse(
                "notInitialized",
                "Activity or TextureRegistry not available"
            ))
            return
        }

        val args = call.arguments as? Map<*, *>
        @Suppress("UNCHECKED_CAST")
        val config = (args?.get("config") as? Map<String, Any>) ?: emptyMap()

        try {
            nativeMotionEngine?.dispose()
            nativeMotionEngine = NativeMotionEngine(context, currentTextureRegistry, currentActivity)
            val engineResult = nativeMotionEngine!!.initialize(config)

            result.success(mapOf(
                "success" to true,
                "textureId" to engineResult["textureId"],
                "pointerAddress" to engineResult["pointerAddress"]
            ))
        } catch (e: Exception) {
            Log.e(TAG, "Motion engine init failed: ${e.message}", e)
            result.success(errorResponse(
                "modelLoadFailed",
                "Failed to initialize motion engine",
                e.message
            ))
        }
    }

    private fun handleUpdateMotionEngineConfig(call: MethodCall, result: Result) {
        val engine = nativeMotionEngine
        if (engine == null) {
            result.success(errorResponse("notInitialized", "Motion engine not initialized"))
            return
        }

        val args = call.arguments as? Map<*, *>
        @Suppress("UNCHECKED_CAST")
        val config = (args?.get("config") as? Map<String, Any>) ?: emptyMap()

        try {
            engine.updateConfig(config)
            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            result.success(errorResponse(
                "inferenceFailed",
                "Config update failed",
                e.message
            ))
        }
    }

    private fun handleDisposeMotionEngine(result: Result) {
        nativeMotionEngine?.dispose()
        nativeMotionEngine = null
        result.success(mapOf("success" to true))
    }

    // MARK: - ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    // Public method for VideoProgressStreamHandler
    fun setVideoProgressEventSink(sink: EventChannel.EventSink?) {
        videoProgressEventSink = sink
    }

    // MARK: - Helpers

    private fun errorResponse(
        code: String,
        message: String,
        platformMessage: String? = null
    ): Map<String, Any> {
        val error = mutableMapOf<String, Any>(
            "code" to code,
            "message" to message
        )
        platformMessage?.let { error["platformMessage"] = it }

        return mapOf(
            "success" to false,
            "error" to error
        )
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        videoProgressChannel.setStreamHandler(null)
        scope.cancel()
        nativeMotionEngine?.dispose()
        nativeMotionEngine = null
        activeDetector = null
        mediaPipeDetector?.dispose()
        mediaPipeDetector = null
        tfliteDetector?.dispose()
        tfliteDetector = null
        textureRegistry = null
    }
}

/**
 * Stream handler for video progress events.
 */
class VideoProgressStreamHandler(
    private val plugin: NpuPoseDetectionPlugin
) : EventChannel.StreamHandler {

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        plugin.setVideoProgressEventSink(events)
    }

    override fun onCancel(arguments: Any?) {
        plugin.setVideoProgressEventSink(null)
    }
}

/**
 * FPS calculator for streaming.
 */
class FPSCalculator {
    private val timestamps = mutableListOf<Long>()
    private val windowSize = 30

    fun reset() {
        timestamps.clear()
    }

    fun update(): Double {
        val now = System.currentTimeMillis()
        timestamps.add(now)

        // Keep only recent timestamps
        while (timestamps.size > windowSize) {
            timestamps.removeAt(0)
        }

        // Calculate FPS from time window
        if (timestamps.size < 2) return 0.0

        val elapsed = timestamps.last() - timestamps.first()
        if (elapsed <= 0) return 0.0

        return (timestamps.size - 1) * 1000.0 / elapsed
    }
}
