import 'dart:async';
import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../models/acceleration_mode.dart';
import '../models/detector_config.dart';
import '../models/frame_result.dart';
import '../models/pose_result.dart';
import '../models/video_analysis_result.dart';
import 'method_channel_pose_detector.dart';

/// Platform channel identifiers.
class PoseDetectorChannels {
  /// Method channel for request-response operations.
  static const String methodChannel =
      'com.example.flutter_pose_detection/methods';

  /// Event channel for realtime camera frame streaming.
  static const String eventChannel =
      'com.example.flutter_pose_detection/frames';

  /// Event channel for video analysis progress.
  static const String videoProgressChannel =
      'com.example.flutter_pose_detection/video_progress';
}

/// Platform interface for pose detection.
///
/// This class defines the interface that platform-specific implementations
/// must implement to provide pose detection functionality.
abstract class PoseDetectorPlatform extends PlatformInterface {
  /// Constructs a PoseDetectorPlatform.
  PoseDetectorPlatform() : super(token: _token);

  static final Object _token = Object();

  static PoseDetectorPlatform _instance = MethodChannelPoseDetector();

  /// The default instance of [PoseDetectorPlatform] to use.
  static PoseDetectorPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [PoseDetectorPlatform].
  static set instance(PoseDetectorPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Initialize the detector with configuration.
  ///
  /// Returns the acceleration mode that will be used.
  Future<AccelerationMode> initialize(PoseDetectorConfig config);

  /// Detect poses in image data.
  ///
  /// [imageData] should be JPEG or PNG encoded bytes.
  Future<PoseResult> detectPose(Uint8List imageData);

  /// Detect poses from a file path.
  Future<PoseResult> detectPoseFromFile(String filePath);

  /// Update detector configuration.
  Future<void> updateConfig(PoseDetectorConfig config);

  /// Get device capabilities.
  Future<Map<String, dynamic>> getDeviceCapabilities();

  /// Dispose the detector and release resources.
  Future<void> dispose();

  /// Check if detector is initialized.
  bool get isInitialized;

  /// Get current acceleration mode.
  AccelerationMode get accelerationMode;

  /// Process a single camera frame.
  ///
  /// [planes] contains the raw image plane data.
  /// [width] and [height] are the frame dimensions.
  /// [format] is the image format (yuv420, nv21, bgra8888).
  /// [rotation] is the rotation in degrees (0, 90, 180, 270).
  Future<PoseResult> processFrame({
    required List<Map<String, dynamic>> planes,
    required int width,
    required int height,
    required String format,
    int rotation = 0,
  });

  /// Start camera detection stream.
  ///
  /// Returns a stream of [FrameResult] for each processed frame.
  Stream<FrameResult> startCameraDetection();

  /// Stop camera detection stream.
  Future<void> stopCameraDetection();

  /// Analyze a video file for poses.
  ///
  /// [videoPath] is the absolute path to the video file.
  /// [frameInterval] specifies how many frames to skip between analyses.
  /// A value of 1 means analyze every frame, 2 means every other frame, etc.
  ///
  /// Returns a [VideoAnalysisResult] with all detected poses.
  Future<VideoAnalysisResult> analyzeVideo(
    String videoPath, {
    int frameInterval = 1,
  });

  /// Stream video analysis progress.
  ///
  /// Returns a stream of [VideoAnalysisProgress] events during analysis.
  Stream<VideoAnalysisProgress> get videoAnalysisProgress;

  /// Cancel ongoing video analysis.
  Future<void> cancelVideoAnalysis();

  /// Initialize the native motion engine.
  ///
  /// Returns a map with 'textureId' (int) and 'pointerAddress' (int).
  Future<Map<String, dynamic>> initializeMotionEngine(
    Map<String, dynamic> config,
  );

  /// Update the motion engine configuration (requires landmarker reinit).
  Future<void> updateMotionEngineConfig(Map<String, dynamic> config);

  /// Dispose the motion engine and release all resources.
  Future<void> disposeMotionEngine();
}
