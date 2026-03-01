import 'dart:math' as math;

import 'bounding_box.dart';
import 'landmark_type.dart';
import 'pose_landmark.dart';

/// A single detected human pose with 33 landmarks.
///
/// Each [Pose] contains a list of 33 [PoseLandmark]s following the
/// MediaPipe BlazePose 33-keypoint topology, along with an overall confidence score.
///
/// ## Accessing Landmarks
///
/// ```dart
/// // By type
/// final nose = pose.getLandmark(LandmarkType.nose);
///
/// // By index
/// final leftEye = pose[2];
///
/// // Get all visible landmarks
/// final visible = pose.getVisibleLandmarks(threshold: 0.5);
/// ```
///
/// ## Calculating Angles
///
/// Use [calculateAngle] for body angle measurements:
///
/// ```dart
/// // Calculate knee angle
/// final kneeAngle = pose.calculateAngle(
///   LandmarkType.leftHip,
///   LandmarkType.leftKnee,
///   LandmarkType.leftAnkle,
/// );
/// ```
class Pose {
  /// All 33 landmarks in MediaPipe BlazePose order.
  ///
  /// The list always contains exactly 33 landmarks.
  /// Undetected landmarks will have [PoseLandmark.visibility] = 0.0.
  final List<PoseLandmark> landmarks;

  /// Overall detection confidence score (0.0-1.0).
  final double score;

  /// Bounding box of the detected person (optional).
  ///
  /// May be null if the native framework doesn't provide bounding boxes.
  final BoundingBox? boundingBox;

  /// Creates a new [Pose].
  ///
  /// Note: landmarks list must have exactly [LandmarkType.count] elements.
  const Pose({required this.landmarks, required this.score, this.boundingBox});

  /// Get a landmark by its type.
  ///
  /// ```dart
  /// final nose = pose.getLandmark(LandmarkType.nose);
  /// ```
  PoseLandmark getLandmark(LandmarkType type) => landmarks[type.value];

  /// Get a landmark by its index (0-16).
  ///
  /// ```dart
  /// final nose = pose[0]; // Same as getLandmark(LandmarkType.nose)
  /// ```
  PoseLandmark operator [](int index) => landmarks[index];

  /// Get all landmarks with visibility above the threshold.
  ///
  /// ```dart
  /// final visible = pose.getVisibleLandmarks(threshold: 0.5);
  /// print('${visible.length} landmarks visible');
  /// ```
  List<PoseLandmark> getVisibleLandmarks({double threshold = 0.5}) {
    return landmarks.where((l) => l.visibility >= threshold).toList();
  }

  /// Calculate the angle between three landmarks in degrees.
  ///
  /// The angle is measured at [vertex], between the lines from
  /// [vertex] to [point1] and from [vertex] to [point2].
  ///
  /// Returns null if any of the landmarks are not detected.
  ///
  /// ```dart
  /// // Calculate knee angle
  /// final kneeAngle = pose.calculateAngle(
  ///   LandmarkType.leftHip,
  ///   LandmarkType.leftKnee,    // vertex
  ///   LandmarkType.leftAnkle,
  /// );
  ///
  /// if (kneeAngle != null) {
  ///   print('Knee angle: ${kneeAngle.toStringAsFixed(1)}°');
  /// }
  /// ```
  double? calculateAngle(
    LandmarkType point1,
    LandmarkType vertex,
    LandmarkType point2,
  ) {
    final p1 = getLandmark(point1);
    final v = getLandmark(vertex);
    final p2 = getLandmark(point2);

    // Check if all landmarks are detected
    if (!p1.isDetected || !v.isDetected || !p2.isDetected) {
      return null;
    }

    // Calculate vectors
    final v1x = p1.x - v.x;
    final v1y = p1.y - v.y;
    final v2x = p2.x - v.x;
    final v2y = p2.y - v.y;

    // Calculate dot product and magnitudes
    final dotProduct = v1x * v2x + v1y * v2y;
    final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
    final mag2 = math.sqrt(v2x * v2x + v2y * v2y);

    if (mag1 == 0 || mag2 == 0) return null;

    // Calculate angle in degrees
    final cosAngle = (dotProduct / (mag1 * mag2)).clamp(-1.0, 1.0);
    return math.acos(cosAngle) * 180 / math.pi;
  }

  /// Calculate the distance between two landmarks (normalized).
  ///
  /// Returns null if either landmark is not detected.
  ///
  /// ```dart
  /// final shoulderWidth = pose.calculateDistance(
  ///   LandmarkType.leftShoulder,
  ///   LandmarkType.rightShoulder,
  /// );
  /// ```
  double? calculateDistance(LandmarkType point1, LandmarkType point2) {
    final p1 = getLandmark(point1);
    final p2 = getLandmark(point2);

    if (!p1.isDetected || !p2.isDetected) {
      return null;
    }

    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Create a [Pose] from a JSON map.
  factory Pose.fromJson(Map<String, dynamic> json) {
    final landmarkList = json['landmarks'] as List<dynamic>;
    final landmarks = landmarkList
        .map((l) => PoseLandmark.fromJson(l as Map<String, dynamic>))
        .toList();

    // Validate landmark count
    if (landmarks.length != LandmarkType.count) {
      throw ArgumentError(
        'Invalid landmark count: expected ${LandmarkType.count}, got ${landmarks.length}. '
        'This may indicate a detector mismatch (MoveNet returns 17, MediaPipe returns 33).',
      );
    }

    return Pose(
      landmarks: landmarks,
      score: (json['score'] as num).toDouble(),
      boundingBox: json['boundingBox'] != null
          ? BoundingBox.fromJson(json['boundingBox'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Convert this pose to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'landmarks': landmarks.map((l) => l.toJson()).toList(),
      'score': score,
      if (boundingBox != null) 'boundingBox': boundingBox!.toJson(),
    };
  }

  @override
  String toString() {
    final visible = getVisibleLandmarks().length;
    return 'Pose(score: ${score.toStringAsFixed(2)}, '
        'visible: $visible/${LandmarkType.count} landmarks)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Pose) return false;
    if (other.score != score || other.boundingBox != boundingBox) return false;
    if (other.landmarks.length != landmarks.length) return false;
    for (var i = 0; i < landmarks.length; i++) {
      if (other.landmarks[i] != landmarks[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(landmarks), score, boundingBox);
}
