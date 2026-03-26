import 'package:flutter/material.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

import 'pages/camera_detection_page.dart';
import 'pages/image_detection_page.dart';
import 'pages/motion_engine_page.dart';
import 'pages/video_analysis_page.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NPU Pose Detection Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _accelerationMode = 'Not initialized';
  bool _isInitializing = false;
  bool _isBenchmarking = false;
  String _benchmarkResult = '';
  NpuPoseDetector? _detector;
  bool _useNpu = false; // Toggle for NPU vs GPU

  @override
  void initState() {
    super.initState();
    _initializeDetector();
  }

  Future<void> _initializeDetector() async {
    setState(() {
      _isInitializing = true;
    });

    try {
      _detector?.dispose();

      final config = PoseDetectorConfig(
        preferredAcceleration: _useNpu ? AccelerationMode.npu : null,
      );

      _detector = NpuPoseDetector(config: config);
      final mode = await _detector!.initialize();

      if (mounted) {
        setState(() {
          _accelerationMode = mode.name.toUpperCase();
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _accelerationMode = 'Error: $e';
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _toggleAccelerationMode() async {
    setState(() {
      _useNpu = !_useNpu;
    });
    await _initializeDetector();
  }

  Future<void> _runBenchmark() async {
    setState(() {
      _isBenchmarking = true;
      _benchmarkResult = 'Running benchmark...';
    });

    try {
      final result =
          await NpuPoseDetector.benchmarkDelegates(iterations: 10);

      if (result['success'] == true) {
        final results = result['results'] as Map<String, dynamic>? ?? {};
        final buffer = StringBuffer();
        buffer.writeln('Benchmark Results:');

        for (final entry in results.entries) {
          final delegate = entry.key.toUpperCase();
          final data = entry.value as Map<String, dynamic>? ?? {};
          if (data['success'] == true) {
            final avg = (data['avgInferenceTimeMs'] as num?)?.toStringAsFixed(2) ?? 'N/A';
            final min = (data['minInferenceTimeMs'] as num?)?.toStringAsFixed(2) ?? 'N/A';
            final max = (data['maxInferenceTimeMs'] as num?)?.toStringAsFixed(2) ?? 'N/A';
            buffer.writeln('$delegate: ${avg}ms (min: ${min}ms, max: ${max}ms)');
          } else {
            final error = data['errorMessage'] ?? 'Unknown error';
            buffer.writeln('$delegate: FAILED - $error');
          }
        }

        if (mounted) {
          setState(() {
            _benchmarkResult = buffer.toString();
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _benchmarkResult = 'Benchmark failed: ${result['error']}';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _benchmarkResult = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isBenchmarking = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _detector?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NPU Pose Detection'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Text('Acceleration Mode: '),
                        if (_isInitializing)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Text(
                            _accelerationMode,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _accelerationMode.contains('Error')
                                  ? Colors.red
                                  : Colors.green,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Use NPU (Battery Efficient): '),
                        Switch(
                          value: _useNpu,
                          onChanged: _isInitializing
                              ? null
                              : (value) => _toggleAccelerationMode(),
                        ),
                      ],
                    ),
                    Text(
                      _useNpu
                          ? 'NPU: ~13ms, lower power consumption'
                          : 'GPU: ~3ms, higher power consumption',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isBenchmarking ? null : _runBenchmark,
              icon: _isBenchmarking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.speed),
              label: Text(_isBenchmarking ? 'Benchmarking...' : 'Run Delegate Benchmark'),
            ),
            if (_benchmarkResult.isNotEmpty) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.grey[100],
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    _benchmarkResult,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'Detection Modes',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildFeatureCard(
              context,
              icon: Icons.image,
              title: 'Image Detection',
              description: 'Detect poses in static images',
              onTap: _detector != null
                  ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ImageDetectionPage(detector: _detector!),
                        ),
                      )
                  : null,
            ),
            const SizedBox(height: 12),
            _buildFeatureCard(
              context,
              icon: Icons.videocam,
              title: 'Camera Detection',
              description: 'Real-time pose detection from camera',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CameraDetectionPage(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildFeatureCard(
              context,
              icon: Icons.speed,
              title: 'Motion Engine (FFI)',
              description: 'High-performance native camera + FFI pose data',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const MotionEnginePage(),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _buildFeatureCard(
              context,
              icon: Icons.movie,
              title: 'Video Analysis',
              description: 'Analyze poses in video files',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const VideoAnalysisPage(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(
          icon,
          size: 40,
          color: enabled
              ? Theme.of(context).colorScheme.primary
              : Colors.grey,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: enabled ? null : Colors.grey,
          ),
        ),
        subtitle: Text(
          description,
          style: TextStyle(
            color: enabled ? null : Colors.grey,
          ),
        ),
        trailing: enabled
            ? const Icon(Icons.chevron_right)
            : const Text('Coming Soon', style: TextStyle(color: Colors.grey)),
        onTap: onTap,
        enabled: enabled,
      ),
    );
  }
}
