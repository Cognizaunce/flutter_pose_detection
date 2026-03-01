import 'acceleration_mode.dart';
import 'pose.dart';

/// Result from a pose detection operation.
///
/// Contains detected poses along with metadata about the detection.
///
/// ## Example
///
/// ```dart
/// final result = await detector.detectPose(imageBytes);
///
/// print('Processing time: ${result.processingTimeMs}ms');
/// print('Acceleration: ${result.accelerationMode}');
///
/// if (result.hasPoses) {
///   final pose = result.firstPose!;
///   print('Detected pose with score ${pose.score}');
/// }
/// ```
class PoseResult {
  /// List of detected poses (empty if no person detected).
  final List<Pose> poses;

  /// Processing time in milliseconds.
  final int processingTimeMs;

  /// Hardware acceleration mode used for this detection.
  final AccelerationMode accelerationMode;

  /// Timestamp when detection was performed.
  final DateTime timestamp;

  /// Original input image width in pixels.
  final int imageWidth;

  /// Original input image height in pixels.
  final int imageHeight;

  /// Creates a new [PoseResult].
  const PoseResult({
    required this.poses,
    required this.processingTimeMs,
    required this.accelerationMode,
    required this.timestamp,
    required this.imageWidth,
    required this.imageHeight,
  });

  /// Creates an empty result (no poses detected).
  factory PoseResult.empty({
    required int processingTimeMs,
    required AccelerationMode accelerationMode,
    required int imageWidth,
    required int imageHeight,
  }) {
    return PoseResult(
      poses: const [],
      processingTimeMs: processingTimeMs,
      accelerationMode: accelerationMode,
      timestamp: DateTime.now(),
      imageWidth: imageWidth,
      imageHeight: imageHeight,
    );
  }

  /// Whether any poses were detected.
  bool get hasPoses => poses.isNotEmpty;

  /// Get the first (most confident) pose, or null if none detected.
  Pose? get firstPose => poses.isNotEmpty ? poses.first : null;

  /// Number of poses detected.
  int get poseCount => poses.length;

  /// Create a [PoseResult] from a JSON map.
  factory PoseResult.fromJson(Map<String, dynamic> json) {
    final poseList = json['poses'] as List<dynamic>? ?? [];
    final poses = poseList
        .map((p) => Pose.fromJson(p as Map<String, dynamic>))
        .toList();

    return PoseResult(
      poses: poses,
      processingTimeMs: json['processingTimeMs'] as int? ?? 0,
      accelerationMode: AccelerationMode.fromString(
        json['accelerationMode'] as String? ?? 'unknown',
      ),
      timestamp: json['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int)
          : DateTime.now(),
      imageWidth: json['imageWidth'] as int? ?? 0,
      imageHeight: json['imageHeight'] as int? ?? 0,
    );
  }

  /// Convert this result to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'poses': poses.map((p) => p.toJson()).toList(),
      'processingTimeMs': processingTimeMs,
      'accelerationMode': accelerationMode.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'imageWidth': imageWidth,
      'imageHeight': imageHeight,
    };
  }

  @override
  String toString() {
    return 'PoseResult(poses: ${poses.length}, '
        'time: ${processingTimeMs}ms, '
        'mode: $accelerationMode)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PoseResult) return false;
    if (other.processingTimeMs != processingTimeMs ||
        other.accelerationMode != accelerationMode ||
        other.imageWidth != imageWidth ||
        other.imageHeight != imageHeight) {
      return false;
    }
    if (other.poses.length != poses.length) return false;
    for (var i = 0; i < poses.length; i++) {
      if (other.poses[i] != poses[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    Object.hashAll(poses),
    processingTimeMs,
    accelerationMode,
    imageWidth,
    imageHeight,
  );
}
