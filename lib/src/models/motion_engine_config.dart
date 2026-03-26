/// MediaPipe PoseLandmarker model complexity.
///
/// Higher complexity = more accurate but slower inference.
enum ModelComplexity {
  /// Fastest. ~3ms on GPU. Good for real-time applications.
  lite,

  /// Balanced. More accurate landmark positions.
  full,

  /// Most accurate. Best for slow / offline analysis.
  heavy,
}

/// Which camera to use.
enum CameraFacing {
  /// Front-facing (selfie) camera.
  front,

  /// Rear-facing camera.
  back,
}

/// Configuration for the native motion engine.
///
/// These parameters control MediaPipe PoseLandmarker behavior.
/// Updating config requires reinitializing the landmarker (stop → destroy → recreate).
///
/// ```dart
/// final config = MotionEngineConfig(
///   modelComplexity: ModelComplexity.full,
///   targetFps: 30,
///   minPoseDetectionConfidence: 0.5,
///   minTrackingConfidence: 0.5,
///   minPosePresenceConfidence: 0.5,
///   numPoses: 1,
/// );
/// ```
class MotionEngineConfig {
  /// Model complexity. Default: [ModelComplexity.lite].
  final ModelComplexity modelComplexity;

  /// Which camera to use. Default: [CameraFacing.front].
  final CameraFacing cameraFacing;

  /// Maximum inference frames per second. Frames arriving faster are skipped.
  /// Use 0 for unlimited (process every frame). Default: 0.
  final int targetFps;

  /// Minimum confidence for initial pose detection.
  /// Range: 0.0–1.0. Default: 0.5.
  final double minPoseDetectionConfidence;

  /// Minimum confidence for pose tracking between frames.
  /// Range: 0.0–1.0. Default: 0.5.
  final double minTrackingConfidence;

  /// Minimum confidence for pose presence.
  /// Range: 0.0–1.0. Default: 0.5.
  final double minPosePresenceConfidence;

  /// Number of poses to detect. Default: 1.
  final int numPoses;

  const MotionEngineConfig({
    this.modelComplexity = ModelComplexity.lite,
    this.cameraFacing = CameraFacing.front,
    this.targetFps = 0,
    this.minPoseDetectionConfidence = 0.5,
    this.minTrackingConfidence = 0.5,
    this.minPosePresenceConfidence = 0.5,
    this.numPoses = 1,
  });

  MotionEngineConfig copyWith({
    ModelComplexity? modelComplexity,
    CameraFacing? cameraFacing,
    int? targetFps,
    double? minPoseDetectionConfidence,
    double? minTrackingConfidence,
    double? minPosePresenceConfidence,
    int? numPoses,
  }) {
    return MotionEngineConfig(
      modelComplexity: modelComplexity ?? this.modelComplexity,
      cameraFacing: cameraFacing ?? this.cameraFacing,
      targetFps: targetFps ?? this.targetFps,
      minPoseDetectionConfidence:
          minPoseDetectionConfidence ?? this.minPoseDetectionConfidence,
      minTrackingConfidence:
          minTrackingConfidence ?? this.minTrackingConfidence,
      minPosePresenceConfidence:
          minPosePresenceConfidence ?? this.minPosePresenceConfidence,
      numPoses: numPoses ?? this.numPoses,
    );
  }

  Map<String, dynamic> toJson() => {
    'modelComplexity': modelComplexity.name,
    'cameraFacing': cameraFacing.name,
    'targetFps': targetFps,
    'minPoseDetectionConfidence': minPoseDetectionConfidence,
    'minTrackingConfidence': minTrackingConfidence,
    'minPosePresenceConfidence': minPosePresenceConfidence,
    'numPoses': numPoses,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MotionEngineConfig &&
          other.modelComplexity == modelComplexity &&
          other.cameraFacing == cameraFacing &&
          other.targetFps == targetFps &&
          other.minPoseDetectionConfidence == minPoseDetectionConfidence &&
          other.minTrackingConfidence == minTrackingConfidence &&
          other.minPosePresenceConfidence == minPosePresenceConfidence &&
          other.numPoses == numPoses;

  @override
  int get hashCode => Object.hash(
    modelComplexity,
    cameraFacing,
    targetFps,
    minPoseDetectionConfidence,
    minTrackingConfidence,
    minPosePresenceConfidence,
    numPoses,
  );
}
