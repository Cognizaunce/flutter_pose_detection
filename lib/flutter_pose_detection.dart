/// Hardware-accelerated pose detection using MediaPipe PoseLandmarker.
///
/// This library provides pose detection capabilities using:
/// - iOS: TFLite + CoreML delegate (Neural Engine → GPU → CPU fallback)
/// - Android: MediaPipe Tasks Vision with GPU delegate
///
/// ## Quick Start
///
/// ```dart
/// import 'package:flutter_pose_detection/flutter_pose_detection.dart';
///
/// // Create and initialize detector
/// final detector = NpuPoseDetector();
/// final mode = await detector.initialize();
/// print('Running on: $mode'); // gpu, npu, or cpu
///
/// // Detect pose from image
/// final result = await detector.detectPose(imageBytes);
/// if (result.hasPoses) {
///   final pose = result.firstPose!;
///   final nose = pose.getLandmark(LandmarkType.nose);
///   print('Nose at (${nose.x}, ${nose.y})');
/// }
///
/// // Clean up
/// detector.dispose();
/// ```
///
/// ## Features
///
/// - **33 landmarks** in MediaPipe BlazePose format
/// - **Hardware acceleration** (Neural Engine/GPU) with automatic fallback
/// - **Image detection** for static images
/// - **Camera stream** for realtime detection with FPS tracking
/// - **Video analysis** for recorded files with progress updates
/// - **Angle calculation** for body pose analysis
///
/// See also:
/// - [NpuPoseDetector] - Main detector class
/// - [Pose] - Detected pose with landmarks
/// - [PoseLandmark] - Individual body landmark
/// - [LandmarkType] - 33 landmark types (MediaPipe BlazePose)
/// - [PoseDetectorConfig] - Configuration options
library;

// Models
export 'src/models/acceleration_mode.dart';
export 'src/models/bounding_box.dart';
export 'src/models/detection_mode.dart';
export 'src/models/detector_config.dart';
export 'src/models/frame_result.dart';
export 'src/models/landmark_type.dart';
export 'src/models/motion_engine_config.dart';
export 'src/models/pose.dart';
export 'src/models/pose_landmark.dart';
export 'src/models/pose_result.dart';
export 'src/models/video_analysis_result.dart';

// Native Motion Engine
export 'src/native_motion_engine.dart';

// Errors
export 'src/errors/detection_error.dart';

// Main detector
export 'src/pose_detector.dart';

// Platform interface (for platform implementers)
export 'src/platform/pose_detector_platform.dart'
    show PoseDetectorPlatform, PoseDetectorChannels;
