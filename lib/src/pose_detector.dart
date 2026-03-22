import 'dart:async';
import 'dart:typed_data';

import 'models/acceleration_mode.dart';
import 'models/detector_config.dart';
import 'models/frame_result.dart';
import 'models/motion_engine_config.dart';
import 'models/pose_result.dart';
import 'models/video_analysis_result.dart';
import 'native_motion_engine.dart';
import 'platform/method_channel_pose_detector.dart';
import 'platform/pose_detector_platform.dart';

/// Main pose detector class providing hardware-accelerated pose detection.
///
/// ## Basic Usage
///
/// ```dart
/// // Create detector with default configuration
/// final detector = NpuPoseDetector();
///
/// // Initialize (loads ML model)
/// final mode = await detector.initialize();
/// print('Using acceleration: $mode');
///
/// // Detect pose from image
/// final imageBytes = await File('image.jpg').readAsBytes();
/// final result = await detector.detectPose(imageBytes);
///
/// if (result.hasPoses) {
///   final pose = result.firstPose!;
///   print('Detected pose with score ${pose.score}');
/// }
///
/// // Clean up
/// detector.dispose();
/// ```
///
/// ## Custom Configuration
///
/// ```dart
/// final detector = NpuPoseDetector(
///   config: PoseDetectorConfig(
///     mode: DetectionMode.accurate,
///     maxPoses: 3,
///     minConfidence: 0.6,
///   ),
/// );
/// ```
///
/// ## Realtime Configuration
///
/// ```dart
/// final detector = NpuPoseDetector(
///   config: PoseDetectorConfig.realtime(),
/// );
/// ```
class NpuPoseDetector {
  /// Configuration for this detector.
  PoseDetectorConfig _config;

  /// Creates a new pose detector with optional configuration.
  ///
  /// If no [config] is provided, default settings are used.
  NpuPoseDetector({PoseDetectorConfig? config})
    : _config = config ?? const PoseDetectorConfig();

  /// The platform implementation.
  PoseDetectorPlatform get _platform => PoseDetectorPlatform.instance;

  /// Whether the detector is initialized and ready for use.
  bool get isInitialized => _platform.isInitialized;

  /// The current hardware acceleration mode.
  ///
  /// Returns [AccelerationMode.unknown] before initialization.
  AccelerationMode get accelerationMode => _platform.accelerationMode;

  /// The current configuration.
  PoseDetectorConfig get config => _config;

  /// Initialize the detector and load ML models.
  ///
  /// Must be called before any detection operations.
  /// Returns the [AccelerationMode] that will be used.
  ///
  /// Throws [DetectionError] if initialization fails.
  ///
  /// ```dart
  /// final mode = await detector.initialize();
  /// switch (mode) {
  ///   case AccelerationMode.npu:
  ///     print('Using Neural Engine');
  ///     break;
  ///   case AccelerationMode.gpu:
  ///     print('Using GPU');
  ///     break;
  ///   case AccelerationMode.cpu:
  ///     print('Using CPU (slower)');
  ///     break;
  /// }
  /// ```
  Future<AccelerationMode> initialize() async {
    return _platform.initialize(_config);
  }

  /// Detect poses in a static image.
  ///
  /// [imageBytes] should be JPEG or PNG encoded image data.
  ///
  /// Returns a [PoseResult] containing detected poses and metadata.
  /// Throws [DetectionError] on failure.
  ///
  /// ```dart
  /// final imageBytes = await File('photo.jpg').readAsBytes();
  /// final result = await detector.detectPose(imageBytes);
  ///
  /// if (result.hasPoses) {
  ///   for (final pose in result.poses) {
  ///     print('Pose score: ${pose.score}');
  ///   }
  /// }
  /// ```
  Future<PoseResult> detectPose(Uint8List imageBytes) async {
    return _platform.detectPose(imageBytes);
  }

  /// Detect poses from an image file.
  ///
  /// [imagePath] should be an absolute path to a JPEG or PNG image.
  ///
  /// Returns a [PoseResult] containing detected poses and metadata.
  /// Throws [DetectionError] on failure.
  ///
  /// ```dart
  /// final result = await detector.detectPoseFromFile('/path/to/image.jpg');
  /// ```
  Future<PoseResult> detectPoseFromFile(String imagePath) async {
    return _platform.detectPoseFromFile(imagePath);
  }

  /// Update detector configuration.
  ///
  /// Some configuration changes may require the detector to reload models.
  ///
  /// ```dart
  /// await detector.updateConfig(
  ///   detector.config.copyWith(mode: DetectionMode.accurate),
  /// );
  /// ```
  Future<void> updateConfig(PoseDetectorConfig config) async {
    await _platform.updateConfig(config);
    _config = config;
  }

  /// Process a single camera frame.
  ///
  /// Use this for manual frame-by-frame processing when you have
  /// direct access to camera frames from a camera plugin.
  ///
  /// [planes] contains the raw image plane data from the camera.
  /// [width] and [height] are the frame dimensions.
  /// [format] is the image format ('yuv420', 'nv21', or 'bgra8888').
  /// [rotation] is the rotation in degrees (0, 90, 180, 270).
  ///
  /// ```dart
  /// cameraController.startImageStream((CameraImage image) async {
  ///   final planes = image.planes.map((p) => {
  ///     'bytes': p.bytes,
  ///     'bytesPerRow': p.bytesPerRow,
  ///     'bytesPerPixel': p.bytesPerPixel,
  ///   }).toList();
  ///
  ///   final result = await detector.processFrame(
  ///     planes: planes,
  ///     width: image.width,
  ///     height: image.height,
  ///     format: 'yuv420',
  ///     rotation: 90,
  ///   );
  /// });
  /// ```
  Future<PoseResult> processFrame({
    required List<Map<String, dynamic>> planes,
    required int width,
    required int height,
    required String format,
    int rotation = 0,
  }) async {
    return _platform.processFrame(
      planes: planes,
      width: width,
      height: height,
      format: format,
      rotation: rotation,
    );
  }

  /// Start continuous camera detection.
  ///
  /// Returns a stream of [FrameResult] for each processed frame.
  /// The stream includes FPS information and frame timestamps.
  ///
  /// Call [stopCameraDetection] when done to release resources.
  ///
  /// ```dart
  /// final subscription = detector.startCameraDetection().listen(
  ///   (frameResult) {
  ///     print('FPS: ${frameResult.fps.toStringAsFixed(1)}');
  ///     if (frameResult.result.hasPoses) {
  ///       // Draw skeleton overlay
  ///     }
  ///   },
  ///   onError: (error) {
  ///     print('Detection error: $error');
  ///   },
  /// );
  ///
  /// // Later: stop detection
  /// await subscription.cancel();
  /// await detector.stopCameraDetection();
  /// ```
  Stream<FrameResult> startCameraDetection() {
    return _platform.startCameraDetection();
  }

  /// Stop continuous camera detection.
  ///
  /// Call this when done with camera detection to release resources.
  Future<void> stopCameraDetection() async {
    await _platform.stopCameraDetection();
  }

  /// Analyze a video file for poses.
  ///
  /// Processes frames from the video at the specified interval.
  ///
  /// [videoPath] is the absolute path to the video file.
  /// [frameInterval] specifies how many frames to skip between analyses.
  /// - `1` means analyze every frame (most accurate, slowest)
  /// - `2` means every other frame
  /// - Higher values are faster but less detailed
  ///
  /// Use [videoAnalysisProgress] to monitor progress during analysis.
  ///
  /// ```dart
  /// // Subscribe to progress
  /// detector.videoAnalysisProgress.listen((progress) {
  ///   print('${(progress.progress * 100).toStringAsFixed(1)}% complete');
  /// });
  ///
  /// // Start analysis
  /// final result = await detector.analyzeVideo(
  ///   '/path/to/video.mp4',
  ///   frameInterval: 3, // Analyze every 3rd frame
  /// );
  ///
  /// print('Analyzed ${result.analyzedFrames} frames');
  /// print('Detection rate: ${(result.detectionRate * 100).toStringAsFixed(0)}%');
  ///
  /// // Access individual frame results
  /// for (final frame in result.frames) {
  ///   if (frame.result.hasPoses) {
  ///     print('Pose at ${frame.timestampSeconds}s');
  ///   }
  /// }
  /// ```
  Future<VideoAnalysisResult> analyzeVideo(
    String videoPath, {
    int frameInterval = 1,
  }) async {
    return _platform.analyzeVideo(videoPath, frameInterval: frameInterval);
  }

  /// Stream of progress events during video analysis.
  ///
  /// Subscribe to this before calling [analyzeVideo] to receive updates.
  ///
  /// ```dart
  /// detector.videoAnalysisProgress.listen(
  ///   (progress) {
  ///     setState(() {
  ///       _progress = progress.progress;
  ///       _remainingSeconds = progress.estimatedRemainingSeconds;
  ///     });
  ///   },
  ///   onDone: () {
  ///     print('Analysis complete');
  ///   },
  /// );
  /// ```
  Stream<VideoAnalysisProgress> get videoAnalysisProgress =>
      _platform.videoAnalysisProgress;

  /// Cancel ongoing video analysis.
  ///
  /// Call this to stop an in-progress video analysis.
  /// The [analyzeVideo] future will complete with a partial result.
  Future<void> cancelVideoAnalysis() async {
    await _platform.cancelVideoAnalysis();
  }

  /// Release resources.
  ///
  /// Call when done with the detector to free memory.
  /// The detector cannot be used after disposal.
  ///
  /// ```dart
  /// @override
  /// void dispose() {
  ///   detector.dispose();
  ///   super.dispose();
  /// }
  /// ```
  void dispose() {
    _platform.dispose();
  }

  /// Benchmark different TFLite delegates (QNN, GPU, CPU).
  ///
  /// This is a diagnostic tool to measure inference performance across
  /// different hardware acceleration modes. Useful for understanding
  /// device capabilities and optimizing performance.
  ///
  /// [iterations] specifies how many inference runs to average.
  ///
  /// Returns a map containing:
  /// - `success`: Whether the benchmark completed
  /// - `results`: Map of delegate names to their benchmark results
  ///   - Each result contains: `success`, `avgInferenceTimeMs`,
  ///     `minInferenceTimeMs`, `maxInferenceTimeMs`, `errorMessage`
  ///
  /// ```dart
  /// final result = await NpuPoseDetector.benchmarkDelegates(iterations: 10);
  /// if (result['success'] == true) {
  ///   final results = result['results'] as Map<String, dynamic>;
  ///   for (final entry in results.entries) {
  ///     print('${entry.key}: ${entry.value['avgInferenceTimeMs']}ms');
  ///   }
  /// }
  /// ```
  static Future<Map<String, dynamic>> benchmarkDelegates({
    int iterations = 10,
  }) async {
    final platform = PoseDetectorPlatform.instance;
    if (platform is MethodChannelPoseDetector) {
      return platform.benchmarkDelegates(iterations: iterations);
    }
    return {'success': false, 'error': 'Benchmarking not supported'};
  }

  // MARK: - Native Motion Engine

  /// Start the native motion engine for low-latency FFI-based pose detection.
  ///
  /// Returns a [NativeMotionEngine] that provides:
  /// - [NativeMotionEngine.textureId] for displaying the camera feed
  /// - [NativeMotionEngine.readLatestPose] for reading pose data via FFI
  ///
  /// Camera frames NEVER pass through Dart. Pose data is read directly from
  /// shared native memory via FFI, eliminating serialization overhead.
  ///
  /// ```dart
  /// final engine = await detector.startMotionEngine();
  ///
  /// // Display camera
  /// Texture(textureId: engine.textureId)
  ///
  /// // Read poses (e.g., in animation frame callback)
  /// final snapshot = engine.readLatestPose();
  /// if (snapshot != null) {
  ///   final nose = snapshot.poseLandmarks[0];
  ///   print('Nose: (${nose.x}, ${nose.y})');
  /// }
  ///
  /// // Stop when done
  /// await detector.stopMotionEngine();
  /// ```
  Future<NativeMotionEngine> startMotionEngine({
    MotionEngineConfig config = const MotionEngineConfig(),
  }) async {
    final result = await _platform.initializeMotionEngine(config.toJson());
    return NativeMotionEngine.fromPlatformResult(result);
  }

  /// Update the motion engine configuration.
  ///
  /// This stops inference, destroys the landmarker, and recreates it
  /// with the new config. Camera feed continues uninterrupted.
  Future<void> updateMotionEngineConfig(MotionEngineConfig config) async {
    await _platform.updateMotionEngineConfig(config.toJson());
  }

  /// Stop the native motion engine and release all resources.
  Future<void> stopMotionEngine() async {
    await _platform.disposeMotionEngine();
  }
}
