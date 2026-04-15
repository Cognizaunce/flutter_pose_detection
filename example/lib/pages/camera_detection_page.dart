import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

import '../widgets/pose_overlay_painter.dart';

/// Camera detection page with realtime pose overlay.
class CameraDetectionPage extends StatefulWidget {
  const CameraDetectionPage({super.key});

  @override
  State<CameraDetectionPage> createState() => _CameraDetectionPageState();
}

class _CameraDetectionPageState extends State<CameraDetectionPage> {
  CameraController? _cameraController;
  NpuPoseDetector? _detector;
  bool _isInitialized = false;
  bool _isProcessing = false;
  PoseResult? _currentResult;
  double _fps = 0.0;
  String _status = 'Initializing...';
  AccelerationMode _accelerationMode = AccelerationMode.unknown;

  @override
  void initState() {
    super.initState();
    _initializeDetector();
    _initializeCamera();
  }

  Future<void> _initializeDetector() async {
    try {
      _detector = NpuPoseDetector(
        config: PoseDetectorConfig.realtime(),
      );
      _accelerationMode = await _detector!.initialize();
      setState(() {
        _status = 'Detector ready (${_accelerationMode.name})';
      });
    } catch (e) {
      setState(() {
        _status = 'Detector error: $e';
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _status = 'No cameras available';
        });
        return;
      }

      // Use front camera if available, otherwise use first camera
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });

        // Start image stream for processing
        await _cameraController!.startImageStream(_processFrame);
      }
    } catch (e) {
      setState(() {
        _status = 'Camera error: $e';
      });
    }
  }

  void _processFrame(CameraImage image) async {
    if (_isProcessing || _detector == null || !_detector!.isInitialized) {
      return;
    }

    _isProcessing = true;

    try {
      // Convert CameraImage planes to expected format
      final planes = image.planes.map((plane) {
        return {
          'bytes': plane.bytes,
          'bytesPerRow': plane.bytesPerRow,
          'bytesPerPixel': plane.bytesPerPixel ?? 1,
        };
      }).toList();

      // Determine format based on platform
      final format = image.format.group == ImageFormatGroup.yuv420
          ? 'yuv420'
          : 'bgra8888';

      // Get rotation based on camera orientation
      final rotation = _cameraController?.description.sensorOrientation ?? 0;

      final result = await _detector!.processFrame(
        planes: planes,
        width: image.width,
        height: image.height,
        format: format,
        rotation: rotation,
      );

      // Calculate FPS (simple rolling average)
      final processingMs = result.processingTimeMs;
      _fps = processingMs > 0 ? (1000 / processingMs) * 0.3 + _fps * 0.7 : _fps;

      if (mounted) {
        setState(() {
          _currentResult = result;
        });
      }
    } catch (e) {
      // Ignore processing errors, just continue
    } finally {
      _isProcessing = false;
    }
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _detector?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera Detection'),
        actions: [
          // FPS indicator
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${_fps.toStringAsFixed(1)} FPS',
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
            color: _accelerationMode == AccelerationMode.npu
                ? Colors.green.shade100
                : _accelerationMode == AccelerationMode.gpu
                    ? Colors.blue.shade100
                    : Colors.grey.shade200,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _status,
                  style: const TextStyle(fontSize: 12),
                ),
                if (_currentResult != null)
                  Text(
                    '${_currentResult!.processingTimeMs}ms',
                    style: TextStyle(
                      fontSize: 12,
                      color: _currentResult!.processingTimeMs < 50
                          ? Colors.green
                          : _currentResult!.processingTimeMs < 100
                              ? Colors.orange
                              : Colors.red,
                    ),
                  ),
              ],
            ),
          ),

          // Camera preview with pose overlay
          Expanded(
            child: _isInitialized && _cameraController != null
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // Camera preview
                      CameraPreview(_cameraController!),

                      // Pose overlay
                      if (_currentResult?.hasPoses == true)
                        CustomPaint(
                          painter: PoseOverlayPainter(
                            pose: _currentResult!.firstPose!,
                            // Mirror for front camera
                            mirror: _cameraController!.description.lensDirection ==
                                CameraLensDirection.front,
                          ),
                        ),

                      // Detection info overlay
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: _buildInfoCard(),
                      ),
                    ],
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
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    if (_currentResult == null || !_currentResult!.hasPoses) {
      return Card(
        color: Colors.black54,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'No pose detected',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8)),
          ),
        ),
      );
    }

    final pose = _currentResult!.firstPose!;
    final visibleCount = pose.landmarks.where((l) => l.visibility > 0.5).length;

    return Card(
      color: Colors.black54,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pose detected',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Score: ${(pose.score * 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$visibleCount / 33 landmarks visible',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
