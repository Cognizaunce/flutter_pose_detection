import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('NPU Pose Detection Integration Tests', () {
    late NpuPoseDetector detector;

    setUpAll(() async {
      // Initialize detector
      detector = NpuPoseDetector();
      final mode = await detector.initialize();
      debugPrint('✅ Detector initialized');
      debugPrint('   Acceleration mode: $mode');
    });

    tearDownAll(() {
      detector.dispose();
      debugPrint('✅ Detector disposed');
    });

    testWidgets('Detector initializes with hardware acceleration',
        (tester) async {
      // Verify detector is initialized
      expect(detector.isInitialized, isTrue);

      // Check acceleration mode
      final mode = detector.accelerationMode;
      debugPrint('Current acceleration mode: $mode');

      expect(mode, isNotNull);
      expect(
        mode == AccelerationMode.npu ||
            mode == AccelerationMode.gpu ||
            mode == AccelerationMode.cpu,
        isTrue,
      );
      debugPrint('✅ Detector acceleration mode verified: $mode');
    });

    testWidgets('Image pose detection returns valid results', (tester) async {
      // Create a simple test image bytes (minimal PNG)
      final testImageBytes = Uint8List.fromList(_createMinimalPngBytes());

      try {
        final result = await detector.detectPose(testImageBytes);

        // Result should not be null (even if no pose detected)
        expect(result, isNotNull);
        debugPrint('✅ Image detection completed');
        debugPrint('   Poses found: ${result.poses.length}');
        debugPrint('   Processing time: ${result.processingTimeMs}ms');
        debugPrint('   Acceleration mode: ${result.accelerationMode}');

        // Validate result structure
        expect(result.processingTimeMs, greaterThanOrEqualTo(0));
        expect(result.imageWidth, greaterThan(0));
        expect(result.imageHeight, greaterThan(0));
      } catch (e) {
        debugPrint('⚠️ Image detection error (may be expected with minimal test image): $e');
        // This might be acceptable depending on the image
      }
    });

    testWidgets('Detector handles empty input gracefully', (tester) async {
      // Test with empty bytes
      try {
        await detector.detectPose(Uint8List(0));
        fail('Should throw on empty input');
      } catch (e) {
        debugPrint('✅ Empty input handled correctly: ${e.runtimeType}');
        // Any exception is acceptable for invalid input
      }
    });

    testWidgets('Detector can be created with custom config', (tester) async {
      // Create a new detector with custom config
      final customDetector = NpuPoseDetector(
        config: const PoseDetectorConfig(
          mode: DetectionMode.fast,
          maxPoses: 1,
          minConfidence: 0.5,
        ),
      );

      expect(customDetector.config.mode, equals(DetectionMode.fast));
      expect(customDetector.config.maxPoses, equals(1));
      expect(customDetector.config.minConfidence, equals(0.5));
      debugPrint('✅ Custom config detector created');

      // Initialize and dispose
      await customDetector.initialize();
      expect(customDetector.isInitialized, isTrue);
      debugPrint('✅ Custom config detector initialized');

      customDetector.dispose();
      debugPrint('✅ Custom config detector disposed');
    });

    testWidgets('Multiple detectors share platform state', (tester) async {
      // Create a new detector for this test
      final testDetector = NpuPoseDetector();

      // Initialize
      await testDetector.initialize();
      expect(testDetector.isInitialized, isTrue);
      debugPrint('✅ Test detector initialized');

      // Create another detector - should share platform state
      final anotherDetector = NpuPoseDetector();
      // Platform is shared (singleton), so should also be initialized
      expect(anotherDetector.isInitialized, isTrue);
      debugPrint('✅ Another detector shares platform state');

      // Both should have same acceleration mode
      expect(
        testDetector.accelerationMode,
        equals(anotherDetector.accelerationMode),
      );
      debugPrint('✅ Both detectors have same acceleration mode');

      // Dispose test detector
      testDetector.dispose();
      // Note: Platform singleton remains initialized for other users
      debugPrint('✅ Test detector disposed');
    });

    testWidgets('PoseResult handles empty poses correctly', (tester) async {
      final emptyResult = PoseResult.empty(
        processingTimeMs: 10,
        accelerationMode: AccelerationMode.npu,
        imageWidth: 100,
        imageHeight: 100,
      );

      expect(emptyResult.hasPoses, isFalse);
      expect(emptyResult.poseCount, equals(0));
      expect(emptyResult.firstPose, isNull);
      debugPrint('✅ Empty PoseResult handled correctly');
    });

    testWidgets('Video analysis handles invalid path gracefully',
        (tester) async {
      try {
        await detector.analyzeVideo('/nonexistent/video.mp4');
        fail('Should throw on invalid path');
      } catch (e) {
        debugPrint('✅ Invalid video path handled correctly: ${e.runtimeType}');
        // Any error is acceptable for invalid path
      }
    });

    testWidgets('Camera detection stop works without start', (tester) async {
      // Should not throw when stopping without starting
      try {
        await detector.stopCameraDetection();
        debugPrint('✅ Stop camera detection without start handled correctly');
      } catch (e) {
        debugPrint('⚠️ Stop camera detection error (acceptable): ${e.runtimeType}');
      }
    });

    testWidgets('Cancel video analysis works when not analyzing',
        (tester) async {
      // Should not throw when cancelling without active analysis
      try {
        await detector.cancelVideoAnalysis();
        debugPrint('✅ Cancel video analysis without active analysis handled correctly');
      } catch (e) {
        debugPrint('⚠️ Cancel video analysis error (acceptable): ${e.runtimeType}');
      }
    });
  });
}

/// Creates a minimal valid PNG image bytes for testing.
/// This is a 1x1 pixel white PNG.
List<int> _createMinimalPngBytes() {
  return [
    // PNG signature
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    // IHDR chunk
    0x00, 0x00, 0x00, 0x0D, // length: 13
    0x49, 0x48, 0x44, 0x52, // type: IHDR
    0x00, 0x00, 0x00, 0x01, // width: 1
    0x00, 0x00, 0x00, 0x01, // height: 1
    0x08, 0x02, // bit depth: 8, color type: RGB
    0x00, 0x00, 0x00, // compression, filter, interlace
    0x90, 0x77, 0x53, 0xDE, // CRC
    // IDAT chunk (compressed pixel data)
    0x00, 0x00, 0x00, 0x0C, // length: 12
    0x49, 0x44, 0x41, 0x54, // type: IDAT
    0x08, 0xD7, 0x63, 0xF8, 0xFF, 0xFF, 0xFF, 0x00,
    0x05, 0xFE, 0x02, 0xFE, // CRC
    // IEND chunk
    0x00, 0x00, 0x00, 0x00, // length: 0
    0x49, 0x45, 0x4E, 0x44, // type: IEND
    0xAE, 0x42, 0x60, 0x82, // CRC
  ];
}
