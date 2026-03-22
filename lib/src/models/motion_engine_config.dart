/// Configuration for the native motion engine.
///
/// These parameters control MediaPipe PoseLandmarker behavior.
/// Updating config requires reinitializing the landmarker (stop → destroy → recreate).
///
/// ```dart
/// final config = MotionEngineConfig(
///   minPoseDetectionConfidence: 0.5,
///   minTrackingConfidence: 0.5,
///   minPosePresenceConfidence: 0.5,
///   numPoses: 1,
/// );
/// ```
class MotionEngineConfig {
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
    this.minPoseDetectionConfidence = 0.5,
    this.minTrackingConfidence = 0.5,
    this.minPosePresenceConfidence = 0.5,
    this.numPoses = 1,
  });

  MotionEngineConfig copyWith({
    double? minPoseDetectionConfidence,
    double? minTrackingConfidence,
    double? minPosePresenceConfidence,
    int? numPoses,
  }) {
    return MotionEngineConfig(
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
    'minPoseDetectionConfidence': minPoseDetectionConfidence,
    'minTrackingConfidence': minTrackingConfidence,
    'minPosePresenceConfidence': minPosePresenceConfidence,
    'numPoses': numPoses,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MotionEngineConfig &&
          other.minPoseDetectionConfidence == minPoseDetectionConfidence &&
          other.minTrackingConfidence == minTrackingConfidence &&
          other.minPosePresenceConfidence == minPosePresenceConfidence &&
          other.numPoses == numPoses;

  @override
  int get hashCode => Object.hash(
    minPoseDetectionConfidence,
    minTrackingConfidence,
    minPosePresenceConfidence,
    numPoses,
  );
}
