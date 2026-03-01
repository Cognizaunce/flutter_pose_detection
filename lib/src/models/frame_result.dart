import 'pose_result.dart';

/// Result for realtime camera frame processing.
///
/// Contains the detection result along with frame metadata useful for
/// tracking performance and synchronization in realtime applications.
class FrameResult {
  /// Detection result for this frame
  final PoseResult result;

  /// Frame sequence number (monotonically increasing)
  final int frameNumber;

  /// Frame timestamp from camera in microseconds
  final int timestampUs;

  /// Current frames per second (rolling average)
  final double fps;

  const FrameResult({
    required this.result,
    required this.frameNumber,
    required this.timestampUs,
    required this.fps,
  });

  /// Create from JSON map (platform channel)
  factory FrameResult.fromJson(Map<String, dynamic> json) {
    return FrameResult(
      result: PoseResult.fromJson(json['result'] as Map<String, dynamic>),
      frameNumber: json['frameNumber'] as int,
      timestampUs: json['timestampUs'] as int,
      fps: (json['fps'] as num).toDouble(),
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() => {
    'result': result.toJson(),
    'frameNumber': frameNumber,
    'timestampUs': timestampUs,
    'fps': fps,
  };

  @override
  String toString() =>
      'FrameResult(frame: $frameNumber, fps: ${fps.toStringAsFixed(1)}, poses: ${result.poses.length})';
}
