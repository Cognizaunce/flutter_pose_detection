import 'pose_result.dart';

/// Result of analyzing a video file frame by frame.
class VideoAnalysisResult {
  /// List of frame results (one per analyzed frame)
  final List<VideoFrameResult> frames;

  /// Total number of frames in the video
  final int totalFrames;

  /// Number of frames actually analyzed
  final int analyzedFrames;

  /// Video duration in seconds
  final double durationSeconds;

  /// Video frame rate (FPS)
  final double frameRate;

  /// Video width in pixels
  final int width;

  /// Video height in pixels
  final int height;

  /// Total analysis time in milliseconds
  final int totalAnalysisTimeMs;

  const VideoAnalysisResult({
    required this.frames,
    required this.totalFrames,
    required this.analyzedFrames,
    required this.durationSeconds,
    required this.frameRate,
    required this.width,
    required this.height,
    required this.totalAnalysisTimeMs,
  });

  /// Average FPS achieved during analysis
  double get analysisSpeed => totalAnalysisTimeMs > 0
      ? analyzedFrames / (totalAnalysisTimeMs / 1000)
      : 0;

  /// Percentage of frames with pose detected
  double get detectionRate {
    if (analyzedFrames == 0) return 0;
    final detected = frames.where((f) => f.result.hasPoses).length;
    return detected / analyzedFrames;
  }

  /// Create from JSON map
  factory VideoAnalysisResult.fromJson(Map<String, dynamic> json) {
    return VideoAnalysisResult(
      frames: (json['frames'] as List)
          .map((f) => VideoFrameResult.fromJson(f as Map<String, dynamic>))
          .toList(),
      totalFrames: json['totalFrames'] as int,
      analyzedFrames: json['analyzedFrames'] as int,
      durationSeconds: (json['durationSeconds'] as num).toDouble(),
      frameRate: (json['frameRate'] as num).toDouble(),
      width: json['width'] as int,
      height: json['height'] as int,
      totalAnalysisTimeMs: json['totalAnalysisTimeMs'] as int,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() => {
    'frames': frames.map((f) => f.toJson()).toList(),
    'totalFrames': totalFrames,
    'analyzedFrames': analyzedFrames,
    'durationSeconds': durationSeconds,
    'frameRate': frameRate,
    'width': width,
    'height': height,
    'totalAnalysisTimeMs': totalAnalysisTimeMs,
  };
}

/// Result for a single video frame
class VideoFrameResult {
  /// Frame index (0-based)
  final int frameIndex;

  /// Timestamp in the video (seconds)
  final double timestampSeconds;

  /// Pose detection result for this frame
  final PoseResult result;

  const VideoFrameResult({
    required this.frameIndex,
    required this.timestampSeconds,
    required this.result,
  });

  /// Create from JSON map
  factory VideoFrameResult.fromJson(Map<String, dynamic> json) {
    return VideoFrameResult(
      frameIndex: json['frameIndex'] as int,
      timestampSeconds: (json['timestampSeconds'] as num).toDouble(),
      result: PoseResult.fromJson(json['result'] as Map<String, dynamic>),
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() => {
    'frameIndex': frameIndex,
    'timestampSeconds': timestampSeconds,
    'result': result.toJson(),
  };
}

/// Progress event during video analysis
class VideoAnalysisProgress {
  /// Current frame being processed
  final int currentFrame;

  /// Total frames to process
  final int totalFrames;

  /// Current timestamp in video (seconds)
  final double currentTimeSeconds;

  /// Video duration (seconds)
  final double durationSeconds;

  /// Estimated time remaining (seconds)
  final double? estimatedRemainingSeconds;

  const VideoAnalysisProgress({
    required this.currentFrame,
    required this.totalFrames,
    required this.currentTimeSeconds,
    required this.durationSeconds,
    this.estimatedRemainingSeconds,
  });

  /// Progress as percentage (0.0 to 1.0)
  double get progress => totalFrames > 0 ? currentFrame / totalFrames : 0;

  /// Create from JSON map
  factory VideoAnalysisProgress.fromJson(Map<String, dynamic> json) {
    return VideoAnalysisProgress(
      currentFrame: json['currentFrame'] as int,
      totalFrames: json['totalFrames'] as int,
      currentTimeSeconds: (json['currentTimeSeconds'] as num).toDouble(),
      durationSeconds: (json['durationSeconds'] as num).toDouble(),
      estimatedRemainingSeconds: (json['estimatedRemainingSeconds'] as num?)
          ?.toDouble(),
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() => {
    'currentFrame': currentFrame,
    'totalFrames': totalFrames,
    'currentTimeSeconds': currentTimeSeconds,
    'durationSeconds': durationSeconds,
    'estimatedRemainingSeconds': estimatedRemainingSeconds,
  };
}
