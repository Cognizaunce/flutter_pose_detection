import 'dart:ui';

import 'landmark_type.dart';

/// Individual body landmark with position and confidence.
///
/// Each landmark represents a specific body point (nose, elbow, etc.)
/// with normalized coordinates and a visibility/confidence score.
///
/// ## Coordinate System
///
/// Coordinates are normalized to the range [0.0, 1.0]:
/// - [x]: 0.0 = left edge, 1.0 = right edge
/// - [y]: 0.0 = top edge, 1.0 = bottom edge
/// - [z]: Depth relative to hip plane (negative = toward camera)
///
/// To convert to pixel coordinates:
/// ```dart
/// final pixelX = landmark.x * imageWidth;
/// final pixelY = landmark.y * imageHeight;
/// ```
///
/// ## Visibility
///
/// The [visibility] score indicates detection confidence:
/// - 0.0: Not detected or fully occluded
/// - 1.0: Fully visible and confident
///
/// Landmarks that cannot be detected by the native framework
/// (e.g., finger landmarks on iOS Vision) will have [visibility] = 0.0.
///
/// ## Example
///
/// ```dart
/// final nose = pose.getLandmark(LandmarkType.nose);
///
/// if (nose.isReliable()) {
///   print('Nose at (${nose.x}, ${nose.y})');
///
///   // Convert to pixel coordinates
///   final offset = nose.toPixelCoordinates(imageWidth, imageHeight);
///   canvas.drawCircle(offset, 5, paint);
/// }
/// ```
class PoseLandmark {
  /// The type of this landmark.
  final LandmarkType type;

  /// X coordinate normalized to [0.0, 1.0] relative to image width.
  ///
  /// 0.0 = left edge, 1.0 = right edge.
  final double x;

  /// Y coordinate normalized to [0.0, 1.0] relative to image height.
  ///
  /// 0.0 = top edge, 1.0 = bottom edge.
  final double y;

  /// Z coordinate (depth) normalized relative to hip width.
  ///
  /// Negative values indicate the landmark is closer to the camera.
  /// Positive values indicate it's further away.
  /// 0.0 is approximately at the hip plane.
  ///
  /// Note: Z estimation may not be available on all platforms.
  final double z;

  /// Visibility/confidence score [0.0, 1.0].
  ///
  /// - 0.0: Not detected or fully occluded
  /// - 1.0: Fully visible and confident
  ///
  /// Check [isDetected] or [isReliable] before using coordinates.
  final double visibility;

  /// Creates a new [PoseLandmark].
  const PoseLandmark({
    required this.type,
    required this.x,
    required this.y,
    this.z = 0.0,
    required this.visibility,
  });

  /// Creates a landmark representing an undetected point.
  ///
  /// Used for landmarks that the native framework cannot detect.
  const PoseLandmark.notDetected(this.type)
    : x = 0.0,
      y = 0.0,
      z = 0.0,
      visibility = 0.0;

  /// Whether this landmark was detected (visibility > 0).
  bool get isDetected => visibility > 0;

  /// Whether this landmark is reliable for use.
  ///
  /// A landmark is considered reliable if its visibility exceeds
  /// the given [threshold] (default: 0.5).
  bool isReliable({double threshold = 0.5}) => visibility >= threshold;

  /// Convert to absolute pixel coordinates.
  ///
  /// Returns an [Offset] with pixel coordinates based on the
  /// provided image dimensions.
  ///
  /// ```dart
  /// final offset = landmark.toPixelCoordinates(1920, 1080);
  /// canvas.drawCircle(offset, 5, paint);
  /// ```
  Offset toPixelCoordinates(int imageWidth, int imageHeight) {
    return Offset(x * imageWidth, y * imageHeight);
  }

  /// Create a [PoseLandmark] from a JSON map.
  factory PoseLandmark.fromJson(Map<String, dynamic> json) {
    return PoseLandmark(
      type: LandmarkType.fromIndex(json['type'] as int),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num?)?.toDouble() ?? 0.0,
      visibility: (json['visibility'] as num).toDouble(),
    );
  }

  /// Convert this landmark to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'type': type.value,
      'x': x,
      'y': y,
      'z': z,
      'visibility': visibility,
    };
  }

  @override
  String toString() {
    return 'PoseLandmark(${type.name}, x: ${x.toStringAsFixed(3)}, '
        'y: ${y.toStringAsFixed(3)}, visibility: ${visibility.toStringAsFixed(2)})';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PoseLandmark &&
        other.type == type &&
        other.x == x &&
        other.y == y &&
        other.z == z &&
        other.visibility == visibility;
  }

  @override
  int get hashCode => Object.hash(type, x, y, z, visibility);
}
