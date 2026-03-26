import 'dart:ffi';

/// FFI struct matching the C PoseBuffer layout.
///
/// Memory layout:
/// ```
/// int   frameId                       (4 bytes)
/// float pose_landmarks[33][4]         (528 bytes)
/// float world_landmarks[33][4]        (528 bytes)
/// ```
/// Total: 1060 bytes
///
/// Thread safety contract:
/// - Native writes all landmarks first, then frameId LAST
/// - Dart reads frameId, copies data, re-checks frameId
/// - If frameId changed → torn read → retry
final class PoseBufferFFI extends Struct {
  @Int32()
  external int frameId;

  /// Image-space landmarks: 33 landmarks × 4 floats (x, y, z, visibility).
  @Array(132)
  external Array<Float> poseLandmarks;

  /// World-space landmarks: 33 landmarks × 4 floats (x, y, z, visibility).
  @Array(132)
  external Array<Float> worldLandmarks;
}

/// A single landmark with coordinates and visibility.
class LandmarkData {
  final double x;
  final double y;
  final double z;
  final double visibility;

  const LandmarkData({
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });

  @override
  String toString() =>
      'LandmarkData(x: ${x.toStringAsFixed(3)}, y: ${y.toStringAsFixed(3)}, '
      'z: ${z.toStringAsFixed(3)}, vis: ${visibility.toStringAsFixed(3)})';
}

/// Snapshot of pose data read from the shared PoseBuffer via FFI.
///
/// Contains both image-space and world-space landmarks for all 33 body points.
class PoseSnapshot {
  /// Frame identifier. Monotonically increasing.
  final int frameId;

  /// 33 landmarks in image (normalized) space: x, y in [0,1], z relative depth.
  final List<LandmarkData> poseLandmarks;

  /// 33 landmarks in world space (meters, hip-centered).
  final List<LandmarkData> worldLandmarks;

  PoseSnapshot({
    required this.frameId,
    required this.poseLandmarks,
    required this.worldLandmarks,
  });
}

/// High-performance FFI-based pose reader.
///
/// Reads structured pose data directly from shared native memory.
/// No MethodChannel, no serialization, no Dart heap copies of frames.
///
/// ## Usage
///
/// ```dart
/// // Initialize engine (returns textureId + pointer)
/// final engine = await detector.startMotionEngine();
///
/// // Display camera in Flutter
/// Texture(textureId: engine.textureId)
///
/// // Read pose data (call in animation frame or timer)
/// final snapshot = engine.readLatestPose();
/// if (snapshot != null) {
///   final nose = snapshot.poseLandmarks[0]; // Landmark 0 = nose
///   print('Nose at (${nose.x}, ${nose.y})');
/// }
/// ```
class NativeMotionEngine {
  /// Flutter texture ID for displaying the camera feed.
  /// Use with `Texture(textureId: textureId)`.
  final int textureId;

  final Pointer<PoseBufferFFI> _buffer;
  int _lastFrameId = -1;

  NativeMotionEngine._(this.textureId, this._buffer);

  /// Create from platform result containing textureId and pointerAddress.
  factory NativeMotionEngine.fromPlatformResult(Map<String, dynamic> result) {
    final textureId = result['textureId'] as int;
    final pointerAddress = result['pointerAddress'] as int;
    return NativeMotionEngine._(
      textureId,
      Pointer<PoseBufferFFI>.fromAddress(pointerAddress),
    );
  }

  /// Read the latest pose data from the shared buffer.
  ///
  /// Returns `null` if:
  /// - No new frame since the last read
  /// - A torn read was detected (data inconsistency)
  ///
  /// This is safe to call at any frequency (e.g., 60 FPS animation callback).
  /// Reading is lock-free and does not block the native inference pipeline.
  PoseSnapshot? readLatestPose() {
    final ref = _buffer.ref;
    final frameId = ref.frameId;

    // No new data
    if (frameId == _lastFrameId) return null;

    // Copy all landmark data
    final poseData = List<double>.generate(132, (i) => ref.poseLandmarks[i]);
    final worldData = List<double>.generate(132, (i) => ref.worldLandmarks[i]);

    // Torn read detection: re-check frameId
    if (_buffer.ref.frameId != frameId) return null;

    _lastFrameId = frameId;

    return PoseSnapshot(
      frameId: frameId,
      poseLandmarks: _parseLandmarks(poseData),
      worldLandmarks: _parseLandmarks(worldData),
    );
  }

  static List<LandmarkData> _parseLandmarks(List<double> data) {
    return List<LandmarkData>.generate(33, (i) {
      final offset = i * 4;
      return LandmarkData(
        x: data[offset],
        y: data[offset + 1],
        z: data[offset + 2],
        visibility: data[offset + 3],
      );
    });
  }
}
