import 'acceleration_mode.dart';
import 'detection_mode.dart';

/// Configuration options for pose detection.
///
/// Use this class to customize detector behavior for your specific use case.
///
/// ## Factory Constructors
///
/// For common configurations, use the factory constructors:
/// - [PoseDetectorConfig.realtime] - Optimized for camera streams
/// - [PoseDetectorConfig.accurate] - Optimized for still images
///
/// ## Example
///
/// ```dart
/// // Default configuration
/// final config = PoseDetectorConfig();
///
/// // Realtime camera configuration
/// final config = PoseDetectorConfig.realtime();
///
/// // Custom configuration
/// final config = PoseDetectorConfig(
///   mode: DetectionMode.accurate,
///   maxPoses: 3,
///   minConfidence: 0.6,
/// );
/// ```
class PoseDetectorConfig {
  /// Detection mode controlling speed/accuracy trade-off.
  ///
  /// Default: [DetectionMode.fast]
  final DetectionMode mode;

  /// Maximum number of poses to detect.
  ///
  /// Range: 1-10. Default: 1.
  ///
  /// For single-person applications, keep this at 1 for best performance.
  final int maxPoses;

  /// Minimum confidence threshold for pose detection.
  ///
  /// Range: 0.0-1.0. Default: 0.5.
  ///
  /// Poses with confidence below this threshold are filtered out.
  /// Lower values detect more poses but may include false positives.
  final double minConfidence;

  /// Enable Z-coordinate (depth) estimation.
  ///
  /// Default: true.
  ///
  /// When disabled, all Z values will be 0.0.
  /// Disabling may slightly improve performance.
  final bool enableZEstimation;

  /// Preferred acceleration mode.
  ///
  /// Default: null (auto-select best available).
  ///
  /// Set this to force a specific acceleration mode.
  /// If the preferred mode is not available, the detector will fall back
  /// to the next best option.
  final AccelerationMode? preferredAcceleration;

  /// Directory path for QNN Skel libraries (Android NPU only).
  ///
  /// Required for Qualcomm QNN delegate to find HTP skeleton libraries.
  /// These libraries run on the Hexagon DSP and are required for NPU acceleration.
  ///
  /// If null, the detector will look for skel libraries in default system paths,
  /// which may not be accessible in sandboxed apps.
  ///
  /// Example:
  /// ```dart
  /// final config = PoseDetectorConfig(
  ///   preferredAcceleration: AccelerationMode.npu,
  ///   skelLibraryDir: '/data/local/tmp/qnn',
  /// );
  /// ```
  ///
  /// Note: You need to push the skel libraries to this directory using adb:
  /// ```bash
  /// adb push libQnnHtpV79Skel.so /data/local/tmp/qnn/
  /// ```
  final String? skelLibraryDir;

  /// Creates a new [PoseDetectorConfig] with the given options.
  const PoseDetectorConfig({
    this.mode = DetectionMode.fast,
    this.maxPoses = 1,
    this.minConfidence = 0.5,
    this.enableZEstimation = true,
    this.preferredAcceleration,
    this.skelLibraryDir,
  }) : assert(maxPoses >= 1 && maxPoses <= 10),
       assert(minConfidence >= 0.0 && minConfidence <= 1.0);

  /// Configuration optimized for realtime camera streams.
  ///
  /// Uses fast mode, single pose detection, and lower confidence threshold
  /// for maximum frame rate.
  factory PoseDetectorConfig.realtime() => const PoseDetectorConfig(
    mode: DetectionMode.fast,
    maxPoses: 1,
    minConfidence: 0.3,
    enableZEstimation: false,
  );

  /// Configuration optimized for accuracy.
  ///
  /// Uses accurate mode with higher confidence threshold.
  /// Best for still images or video analysis.
  factory PoseDetectorConfig.accurate() => const PoseDetectorConfig(
    mode: DetectionMode.accurate,
    maxPoses: 5,
    minConfidence: 0.5,
    enableZEstimation: true,
  );

  /// Create a copy of this config with some fields replaced.
  PoseDetectorConfig copyWith({
    DetectionMode? mode,
    int? maxPoses,
    double? minConfidence,
    bool? enableZEstimation,
    AccelerationMode? preferredAcceleration,
    String? skelLibraryDir,
  }) {
    return PoseDetectorConfig(
      mode: mode ?? this.mode,
      maxPoses: maxPoses ?? this.maxPoses,
      minConfidence: minConfidence ?? this.minConfidence,
      enableZEstimation: enableZEstimation ?? this.enableZEstimation,
      preferredAcceleration:
          preferredAcceleration ?? this.preferredAcceleration,
      skelLibraryDir: skelLibraryDir ?? this.skelLibraryDir,
    );
  }

  /// Create a [PoseDetectorConfig] from a JSON map.
  factory PoseDetectorConfig.fromJson(Map<String, dynamic> json) {
    return PoseDetectorConfig(
      mode: DetectionMode.fromString(json['mode'] as String? ?? 'fast'),
      maxPoses: json['maxPoses'] as int? ?? 1,
      minConfidence: (json['minConfidence'] as num?)?.toDouble() ?? 0.5,
      enableZEstimation: json['enableZEstimation'] as bool? ?? true,
      preferredAcceleration: json['preferredAcceleration'] != null
          ? AccelerationMode.fromString(json['preferredAcceleration'] as String)
          : null,
      skelLibraryDir: json['skelLibraryDir'] as String?,
    );
  }

  /// Convert this config to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'mode': mode.name,
      'maxPoses': maxPoses,
      'minConfidence': minConfidence,
      'enableZEstimation': enableZEstimation,
      if (preferredAcceleration != null)
        'preferredAcceleration': preferredAcceleration!.name,
      if (skelLibraryDir != null) 'skelLibraryDir': skelLibraryDir,
    };
  }

  @override
  String toString() {
    return 'PoseDetectorConfig(mode: $mode, maxPoses: $maxPoses, '
        'minConfidence: $minConfidence, enableZ: $enableZEstimation)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PoseDetectorConfig &&
        other.mode == mode &&
        other.maxPoses == maxPoses &&
        other.minConfidence == minConfidence &&
        other.enableZEstimation == enableZEstimation &&
        other.preferredAcceleration == preferredAcceleration &&
        other.skelLibraryDir == skelLibraryDir;
  }

  @override
  int get hashCode => Object.hash(
    mode,
    maxPoses,
    minConfidence,
    enableZEstimation,
    preferredAcceleration,
    skelLibraryDir,
  );
}
