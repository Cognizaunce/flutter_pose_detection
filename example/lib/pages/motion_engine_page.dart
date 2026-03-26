import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

/// High-performance pose detection using NativeMotionEngine + FFI.
///
/// Camera frames never pass through Dart. Pose data is read directly
/// from shared native memory via FFI — no MethodChannel, no serialization.
class MotionEnginePage extends StatefulWidget {
  const MotionEnginePage({super.key});

  @override
  State<MotionEnginePage> createState() => _MotionEnginePageState();
}

class _MotionEnginePageState extends State<MotionEnginePage>
    with SingleTickerProviderStateMixin {
  NpuPoseDetector? _detector;
  NativeMotionEngine? _engine;
  PoseSnapshot? _latestSnapshot;
  String _status = 'Initializing...';
  bool _isInitialized = false;
  Ticker? _ticker;

  // FPS tracking
  int _inferenceFrameCount = 0;
  int _displayFrameCount = 0;
  double _inferenceFps = 0;
  double _displayFps = 0;
  DateTime _lastFpsUpdate = DateTime.now();

  // Config
  double _detectionConfidence = 0.5;
  double _trackingConfidence = 0.5;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _detector = NpuPoseDetector(
        config: PoseDetectorConfig.realtime(),
      );
      await _detector!.initialize();

      final engine = await _detector!.startMotionEngine(
        config: MotionEngineConfig(
          cameraFacing: CameraFacing.back,
          modelComplexity: ModelComplexity.full,
          targetFps: 30,
          minPoseDetectionConfidence: _detectionConfidence,
          minTrackingConfidence: _trackingConfidence,
        ),
      );

      if (!mounted) return;

      setState(() {
        _engine = engine;
        _isInitialized = true;
        _status = 'Running';
      });

      // Start reading pose data at display refresh rate
      _ticker = createTicker(_onTick)..start();
    } catch (e) {
      if (mounted) {
        setState(() => _status = 'Error: $e');
      }
    }
  }

  void _onTick(Duration elapsed) {
    final snapshot = _engine?.readLatestPose();
    if (snapshot != null) {
      setState(() => _latestSnapshot = snapshot);
      _inferenceFrameCount++;
    }
    _displayFrameCount++;

    // Update FPS counter
    final now = DateTime.now();
    final diff = now.difference(_lastFpsUpdate).inMilliseconds;
    if (diff >= 1000) {
      setState(() {
        _inferenceFps = _inferenceFrameCount * 1000 / diff;
        _displayFps = _displayFrameCount * 1000 / diff;
        _inferenceFrameCount = 0;
        _displayFrameCount = 0;
        _lastFpsUpdate = now;
      });
    }
  }

  Future<void> _updateConfig() async {
    try {
      await _detector?.updateMotionEngineConfig(
        MotionEngineConfig(
          minPoseDetectionConfidence: _detectionConfidence,
          minTrackingConfidence: _trackingConfidence,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Config update failed: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _detector?.stopMotionEngine();
    _detector?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Motion Engine (FFI)'),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${_inferenceFps.toStringAsFixed(0)} / ${_displayFps.toStringAsFixed(0)} FPS',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(8),
            color: Colors.blue.shade100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_status, style: const TextStyle(fontSize: 12)),
                if (_latestSnapshot != null)
                  Text(
                    'Frame #${_latestSnapshot!.frameId}',
                    style: const TextStyle(fontSize: 12),
                  ),
              ],
            ),
          ),

          // Camera + overlay
          Expanded(
            child: _isInitialized && _engine != null
                ? Center(
                    child: AspectRatio(
                      // CameraX Preview selects 1600x1200 (4:3) on Pixel 6.
                      // Front camera is portrait, so displayed aspect is 3:4.
                      aspectRatio: 3.0 / 4.0,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          // Native camera texture
                          Texture(textureId: _engine!.textureId),

                          // Pose skeleton overlay
                          if (_latestSnapshot != null)
                            CustomPaint(
                              painter: _SnapshotOverlayPainter(
                                snapshot: _latestSnapshot!,
                                mirror: true, // flip for front camera
                              ),
                            ),

                          // Info card
                          Positioned(
                            bottom: 16,
                            left: 16,
                            right: 16,
                            child: _buildInfoCard(),
                          ),
                        ],
                      ),
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(_status),
                      ],
                    ),
                  ),
          ),

          // Config sliders
          _buildConfigPanel(),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    final snapshot = _latestSnapshot;
    if (snapshot == null) {
      return Card(
        color: Colors.black54,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'No pose detected',
            style: TextStyle(color: Colors.white.withOpacity(0.8)),
          ),
        ),
      );
    }

    final visibleCount =
        snapshot.poseLandmarks.where((l) => l.visibility > 0.5).length;

    return Card(
      color: Colors.black54,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pose detected (FFI)',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$visibleCount / 33 landmarks visible',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigPanel() {
    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const SizedBox(width: 100, child: Text('Detection', style: TextStyle(fontSize: 12))),
                Expanded(
                  child: Slider(
                    value: _detectionConfidence,
                    min: 0.1,
                    max: 0.9,
                    onChanged: (v) => setState(() => _detectionConfidence = v),
                    onChangeEnd: (_) => _updateConfig(),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    _detectionConfidence.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                const SizedBox(width: 100, child: Text('Tracking', style: TextStyle(fontSize: 12))),
                Expanded(
                  child: Slider(
                    value: _trackingConfidence,
                    min: 0.1,
                    max: 0.9,
                    onChanged: (v) => setState(() => _trackingConfidence = v),
                    onChangeEnd: (_) => _updateConfig(),
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    _trackingConfidence.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Skeleton connections (same as PoseOverlayPainter)
const _connections = <List<int>>[
  // Face
  [7, 3], [3, 0], [0, 4], [4, 8],
  // Torso
  [11, 12], [11, 23], [12, 24], [23, 24],
  // Left arm
  [11, 13], [13, 15],
  // Right arm
  [12, 14], [14, 16],
  // Left leg
  [23, 25], [25, 27], [27, 29],
  // Right leg
  [24, 26], [26, 28], [28, 30],
];

/// Overlay painter that draws directly from a PoseSnapshot (FFI data).
class _SnapshotOverlayPainter extends CustomPainter {
  final PoseSnapshot snapshot;
  final bool mirror;
  final double minVisibility;

  _SnapshotOverlayPainter({
    required this.snapshot,
    this.mirror = false,
    this.minVisibility = 0.3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.fill;

    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final landmarks = snapshot.poseLandmarks;

    Offset toOffset(LandmarkData lm) {
      final x = mirror ? (1.0 - lm.x) * size.width : lm.x * size.width;
      return Offset(x, lm.y * size.height);
    }

    // Draw connections
    for (final conn in _connections) {
      final lm1 = landmarks[conn[0]];
      final lm2 = landmarks[conn[1]];
      if (lm1.visibility >= minVisibility && lm2.visibility >= minVisibility) {
        canvas.drawLine(toOffset(lm1), toOffset(lm2), linePaint);
      }
    }

    // Draw points
    for (final lm in landmarks) {
      if (lm.visibility >= minVisibility) {
        final offset = toOffset(lm);
        canvas.drawCircle(offset, 6, pointPaint);
        canvas.drawCircle(offset, 3, innerPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SnapshotOverlayPainter oldDelegate) {
    return oldDelegate.snapshot.frameId != snapshot.frameId;
  }
}
