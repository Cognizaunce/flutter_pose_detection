# Flutter Pose Detection

Hardware-accelerated pose detection Flutter plugin using MediaPipe PoseLandmarker with GPU/NPU acceleration.

[![pub package](https://img.shields.io/pub/v/flutter_pose_detection.svg)](https://pub.dev/packages/flutter_pose_detection)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Features

- **MediaPipe PoseLandmarker**: Official Google pose detection API
- **33 Landmarks**: Full body tracking including hands and feet
- **Cross-Platform**: iOS (CoreML/Metal) and Android (GPU/NPU Delegate)
- **NPU Support**: Qualcomm QNN delegate for Snapdragon devices (battery-efficient)
- **Hardware Acceleration**: Automatic GPU fallback to CPU
- **Motion Engine (FFI)**: Zero-serialization real-time pose detection via shared memory — no MethodChannel overhead
- **Real-time**: Camera frame processing with FPS tracking
- **Video Analysis**: Process video files with progress tracking
- **Angle Calculation**: Built-in utilities for body angle measurements

## Performance (Galaxy S25 Ultra)

| Mode | Speed | Power Consumption | Use Case |
|------|-------|-------------------|----------|
| GPU (MediaPipe) | ~3ms | High | Short sessions, maximum performance |
| NPU (QNN) | ~13-16ms | Low | Long-running apps, battery-critical |
| CPU | ~17ms | Medium | Fallback |

## Platform Support

| Platform | ML Framework | Model | Acceleration |
|----------|-------------|-------|--------------|
| iOS 14+ | TFLite 2.14 + CoreML/Metal | pose_detector + pose_landmarks_detector | Neural Engine → GPU → CPU |
| Android API 31+ | MediaPipe Tasks 0.10.32 | pose_landmarker_lite.task | GPU → CPU |
| Android API 31+ (Snapdragon) | TFLite + QNN Delegate | pose_landmarks_detector.tflite | NPU (HTP) → CPU |

## Installation

```yaml
dependencies:
  flutter_pose_detection: ^0.4.0
```

### iOS Setup

Update `ios/Podfile`:
```ruby
platform :ios, '14.0'
```

Add camera permission to `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>Camera access is needed for pose detection</string>
```

### Android Setup

Update `android/app/build.gradle`:
```gradle
android {
    defaultConfig {
        minSdkVersion 31
    }
}
```

Add camera permission to `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.CAMERA" />
```

## Quick Start

```dart
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

// Create and initialize detector
final detector = NpuPoseDetector();
final accelerationMode = await detector.initialize();
print('Running on: $accelerationMode'); // gpu, npu, or cpu

// Detect pose from image
final imageBytes = await File('image.jpg').readAsBytes();
final result = await detector.detectPose(imageBytes);

print('Inference time: ${result.processingTimeMs}ms');

if (result.hasPoses) {
  final pose = result.firstPose!;
  print('Detected ${pose.landmarks.length} landmarks');

  // Access specific landmarks (MediaPipe 33-point format)
  final nose = pose.getLandmark(LandmarkType.nose);
  final leftShoulder = pose.getLandmark(LandmarkType.leftShoulder);
  print('Nose at (${nose.x}, ${nose.y})');
}

// Clean up
detector.dispose();
```

## Configuration

```dart
// Default configuration
final detector = NpuPoseDetector();

// Realtime camera optimization (fast mode, low latency)
final detector = NpuPoseDetector(
  config: PoseDetectorConfig.realtime(),
);

// Accuracy optimization (for still images)
final detector = NpuPoseDetector(
  config: PoseDetectorConfig.accurate(),
);

// Custom configuration
final detector = NpuPoseDetector(
  config: PoseDetectorConfig(
    mode: DetectionMode.accurate,
    maxPoses: 3,
    minConfidence: 0.6,
    enableZEstimation: true,
  ),
);

// NPU acceleration (Snapdragon devices only)
// Use this for battery-efficient long-running detection
final detector = NpuPoseDetector(
  config: PoseDetectorConfig(
    preferredAcceleration: AccelerationMode.npu,
  ),
);
```

### NPU vs GPU Mode

Choose the right acceleration mode for your use case:

```dart
// GPU mode (default) - Fastest inference, higher power consumption
// Best for: Short sessions, real-time camera with high FPS requirements
final gpuDetector = NpuPoseDetector();

// NPU mode - Slower inference, significantly lower power consumption
// Best for: Long-running apps (fitness trackers, running apps)
final npuDetector = NpuPoseDetector(
  config: PoseDetectorConfig(
    preferredAcceleration: AccelerationMode.npu,
  ),
);

// Check which acceleration is actually being used
final mode = await detector.initialize();
print('Running on: ${mode.name}'); // "gpu", "npu", or "cpu"
```

**NPU Requirements (Android only):**
- Snapdragon chipset with Hexagon DSP (Snapdragon 8 series recommended)
- Android API 31+
- QNN libraries must be added manually (see below)

### NPU Setup (Manual)

Due to pub.dev size limits (~100MB), QNN libraries are not included. To enable NPU acceleration:

#### Required Files

| File | Source (QAIRT SDK) | Destination (Your App) | Size |
|------|-------------------|------------------------|------|
| libQnnHtp.so | lib/aarch64-android/ | android/app/src/main/jniLibs/arm64-v8a/ | 2 MB |
| libQnnHtpPrepare.so | lib/aarch64-android/ | android/app/src/main/jniLibs/arm64-v8a/ | 53 MB |
| libQnnHtpV79Stub.so | lib/aarch64-android/ | android/app/src/main/jniLibs/arm64-v8a/ | 682 KB |
| libQnnHtpNetRunExtensions.so | lib/aarch64-android/ | android/app/src/main/jniLibs/arm64-v8a/ | 719 KB |
| libQnnSystem.so | lib/aarch64-android/ | android/app/src/main/jniLibs/arm64-v8a/ | 2 MB |
| libQnnCpu.so | lib/aarch64-android/ | android/app/src/main/jniLibs/arm64-v8a/ | 5 MB |
| libQnnTFLiteDelegate.so | lib/aarch64-android/ | android/app/src/main/jniLibs/arm64-v8a/ | 990 KB |
| libqnn_delegate_jni.so | lib/aarch64-android/ | android/app/src/main/jniLibs/arm64-v8a/ | 272 KB |
| libQnnHtpV79Skel.so | lib/hexagon-v79/unsigned/ | android/app/src/main/assets/qnn_skel/ | 8 MB |
| qnn-delegate.jar | Extract from qtld-release.aar | android/app/libs/ | 24 KB |

**Total: ~72 MB**

#### Installation Steps

1. **Download QAIRT SDK** from [Qualcomm AI Engine Direct SDK](https://qpm.qualcomm.com/#/main/tools/details/Qualcomm_AI_Engine_Direct)
   - Requires Qualcomm Developer account (free)
   - Download version 2.35.0 or later
   - Extract to a known location (e.g., `~/qairt/2.35.0`)

2. **Copy files using script**:

```bash
# Set your QAIRT SDK path
export QAIRT_SDK=~/qairt/2.35.0

# Create directories
mkdir -p android/app/src/main/jniLibs/arm64-v8a
mkdir -p android/app/src/main/assets/qnn_skel
mkdir -p android/app/libs

# Copy JNI libraries
cp $QAIRT_SDK/lib/aarch64-android/libQnnHtp.so android/app/src/main/jniLibs/arm64-v8a/
cp $QAIRT_SDK/lib/aarch64-android/libQnnHtpPrepare.so android/app/src/main/jniLibs/arm64-v8a/
cp $QAIRT_SDK/lib/aarch64-android/libQnnHtpV79Stub.so android/app/src/main/jniLibs/arm64-v8a/
cp $QAIRT_SDK/lib/aarch64-android/libQnnHtpNetRunExtensions.so android/app/src/main/jniLibs/arm64-v8a/
cp $QAIRT_SDK/lib/aarch64-android/libQnnSystem.so android/app/src/main/jniLibs/arm64-v8a/
cp $QAIRT_SDK/lib/aarch64-android/libQnnCpu.so android/app/src/main/jniLibs/arm64-v8a/
cp $QAIRT_SDK/lib/aarch64-android/libQnnTFLiteDelegate.so android/app/src/main/jniLibs/arm64-v8a/
cp $QAIRT_SDK/lib/aarch64-android/libqnn_delegate_jni.so android/app/src/main/jniLibs/arm64-v8a/

# Copy skel library (for Hexagon DSP)
cp $QAIRT_SDK/lib/hexagon-v79/unsigned/libQnnHtpV79Skel.so android/app/src/main/assets/qnn_skel/

# Extract and copy QNN delegate JAR
unzip -o $QAIRT_SDK/lib/aarch64-android/qtld-release.aar -d /tmp/qtld_extracted
cp /tmp/qtld_extracted/classes.jar android/app/libs/qnn-delegate.jar
```

3. **Update android/app/build.gradle**:

```gradle
android {
    sourceSets {
        main {
            jniLibs.srcDirs = ['src/main/jniLibs']
        }
    }
}

dependencies {
    implementation(files("libs/qnn-delegate.jar"))
}
```

#### Supported Chipsets

| Chipset | Skel Library | HTP Version |
|---------|-------------|-------------|
| Snapdragon 8 Elite | libQnnHtpV79Skel.so | V79 |
| Snapdragon 8 Gen 3 | libQnnHtpV75Skel.so | V75 |
| Snapdragon 8 Gen 2 | libQnnHtpV73Skel.so | V73 |
| Snapdragon 8 Gen 1 | libQnnHtpV69Skel.so | V69 |

> Copy additional skel files if you need to support older chipsets.

Without these files, `preferredAcceleration: AccelerationMode.npu` will fall back to CPU

## Motion Engine (FFI)

The Motion Engine is a high-performance path for real-time pose detection. It bypasses MethodChannel entirely — camera frames are processed natively while pose data is written to a shared C buffer that Dart reads directly via FFI.

### Architecture

```
CameraX / AVFoundation
  ├─ Preview  → Flutter SurfaceTexture (display)
  └─ Analysis → MediaPipe GPU (LIVE_STREAM)
                  └─ C PoseBuffer (1060 bytes, shared memory)
                       └─ Dart FFI read (lock-free, torn-read safe)
```

- **No serialization**: Landmarks are written as raw floats to a C struct, read directly by Dart
- **Decoupled pipelines**: Video rendering is independent of inference — no frame drops on UI
- **Zero-copy image path** (Android): CameraX RGBA_8888 ByteBuffer → MediaPipe GPU directly
- **Lock-free reads**: Dart detects torn reads via frameId counter (read-before/after pattern)

### Usage

```dart
import 'package:flutter_pose_detection/flutter_pose_detection.dart';

// 1. Initialize detector
final detector = NpuPoseDetector();
await detector.initialize();

// 2. Start the motion engine
final engine = await detector.startMotionEngine(
  config: MotionEngineConfig(
    minPoseDetectionConfidence: 0.5,
    minTrackingConfidence: 0.5,
  ),
);

// 3. Display camera feed
Texture(textureId: engine.textureId)

// 4. Read pose data (call from animation callback or timer)
final snapshot = engine.readLatestPose();
if (snapshot != null) {
  final nose = snapshot.poseLandmarks[0];
  print('Nose at (${nose.x}, ${nose.y})');

  // World-space landmarks (meters, hip-centered)
  final worldNose = snapshot.worldLandmarks[0];
  print('World nose: ${worldNose.x}m, ${worldNose.y}m, ${worldNose.z}m');
}

// 5. Update config at runtime (re-creates landmarker atomically)
await detector.updateMotionEngineConfig(
  MotionEngineConfig(minPoseDetectionConfidence: 0.7),
);

// 6. Clean up
await detector.stopMotionEngine();
detector.dispose();
```

### Configuration

```dart
MotionEngineConfig(
  minPoseDetectionConfidence: 0.5,  // 0.0–1.0
  minTrackingConfidence: 0.5,       // 0.0–1.0
  minPosePresenceConfidence: 0.5,   // 0.0–1.0
  numPoses: 1,
)
```

### PoseSnapshot

| Field | Type | Description |
|-------|------|-------------|
| `frameId` | `int` | Monotonically increasing frame counter |
| `poseLandmarks` | `List<LandmarkData>` | 33 landmarks in normalized image space (x, y in [0,1]) |
| `worldLandmarks` | `List<LandmarkData>` | 33 landmarks in meters (hip-centered) |

Each `LandmarkData` has `x`, `y`, `z`, and `visibility` fields.

### Skeleton Overlay Example

```dart
class _MotionEnginePageState extends State<MotionEnginePage>
    with SingleTickerProviderStateMixin {
  NativeMotionEngine? _engine;
  PoseSnapshot? _latestPose;
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final snapshot = _engine?.readLatestPose();
      if (snapshot != null) {
        setState(() => _latestPose = snapshot);
      }
    });
    _startEngine();
  }

  Future<void> _startEngine() async {
    final detector = NpuPoseDetector();
    await detector.initialize();
    final engine = await detector.startMotionEngine();
    setState(() => _engine = engine);
    _ticker.start();
  }

  @override
  Widget build(BuildContext context) {
    if (_engine == null) return const CircularProgressIndicator();
    return Stack(
      children: [
        AspectRatio(
          aspectRatio: 3.0 / 4.0,
          child: Texture(textureId: _engine!.textureId),
        ),
        if (_latestPose != null)
          CustomPaint(painter: SkeletonPainter(_latestPose!)),
      ],
    );
  }
}
```

## Camera Stream Processing

```dart
// Process camera frames manually
cameraController.startImageStream((CameraImage image) async {
  final planes = image.planes.map((p) => {
    'bytes': p.bytes,
    'bytesPerRow': p.bytesPerRow,
    'bytesPerPixel': p.bytesPerPixel,
  }).toList();

  final result = await detector.processFrame(
    planes: planes,
    width: image.width,
    height: image.height,
    format: 'yuv420',
    rotation: 90,
  );

  if (result.hasPoses) {
    // Draw skeleton overlay
  }
});

// Or use built-in camera detection stream
final subscription = detector.startCameraDetection().listen(
  (frameResult) {
    print('FPS: ${frameResult.fps.toStringAsFixed(1)}');
    if (frameResult.result.hasPoses) {
      // Process pose
    }
  },
);

// Stop when done
await detector.stopCameraDetection();
```

## Video Analysis

```dart
// Subscribe to progress updates
detector.videoAnalysisProgress.listen((progress) {
  print('${(progress.progress * 100).toStringAsFixed(1)}% complete');
});

// Analyze video file
final result = await detector.analyzeVideo(
  '/path/to/video.mp4',
  frameInterval: 3, // Analyze every 3rd frame
);

print('Analyzed ${result.analyzedFrames} frames');
print('Detection rate: ${(result.detectionRate * 100).toStringAsFixed(0)}%');

// Access individual frame results
for (final frame in result.frames) {
  if (frame.result.hasPoses) {
    print('Pose at ${frame.timestampSeconds}s');
  }
}
```

## Body Angle Calculation

```dart
if (result.hasPoses) {
  final pose = result.firstPose!;

  // Calculate knee angle
  final kneeAngle = pose.calculateAngle(
    LandmarkType.leftHip,
    LandmarkType.leftKnee,
    LandmarkType.leftAnkle,
  );

  if (kneeAngle != null) {
    print('Knee angle: ${kneeAngle.toStringAsFixed(1)}°');
  }

  // Calculate shoulder width
  final shoulderWidth = pose.calculateDistance(
    LandmarkType.leftShoulder,
    LandmarkType.rightShoulder,
  );

  // Get visible landmarks only
  final visibleLandmarks = pose.getVisibleLandmarks(threshold: 0.5);
  print('${visibleLandmarks.length} landmarks visible');
}
```

## MediaPipe 33 Landmarks

| Index | Name | Description |
|-------|------|-------------|
| 0 | nose | Nose tip |
| 1-3 | leftEyeInner, leftEye, leftEyeOuter | Left eye |
| 4-6 | rightEyeInner, rightEye, rightEyeOuter | Right eye |
| 7-8 | leftEar, rightEar | Ears |
| 9-10 | mouthLeft, mouthRight | Mouth corners |
| 11-12 | leftShoulder, rightShoulder | Shoulders |
| 13-14 | leftElbow, rightElbow | Elbows |
| 15-16 | leftWrist, rightWrist | Wrists |
| 17-22 | pinky, index, thumb (L/R) | Hand landmarks |
| 23-24 | leftHip, rightHip | Hips |
| 25-26 | leftKnee, rightKnee | Knees |
| 27-28 | leftAnkle, rightAnkle | Ankles |
| 29-30 | leftHeel, rightHeel | Heels |
| 31-32 | leftFootIndex, rightFootIndex | Foot tips |

## Model Architecture

### iOS (TFLite 2-stage pipeline)

| Stage | Model | Input Size | Output |
|-------|-------|------------|--------|
| 1. Person Detection | pose_detector.tflite | 224x224 | Bounding box |
| 2. Landmark Detection | pose_landmarks_detector.tflite | 256x256 | 33 landmarks (x, y, z, visibility) |

### Android (MediaPipe Tasks)

| Model | Input Size | Output |
|-------|------------|--------|
| pose_landmarker_lite.task | 256x256 | 33 landmarks (x, y, z, visibility, presence) |

## API Reference

### NpuPoseDetector

| Method | Description |
|--------|-------------|
| `initialize()` | Load ML model, returns `AccelerationMode` |
| `detectPose(Uint8List)` | Detect pose from image bytes |
| `detectPoseFromFile(String)` | Detect pose from file path |
| `processFrame(...)` | Process single camera frame |
| `startCameraDetection()` | Start camera stream detection |
| `stopCameraDetection()` | Stop camera detection |
| `startMotionEngine({MotionEngineConfig})` | Start FFI motion engine, returns `NativeMotionEngine` |
| `stopMotionEngine()` | Stop motion engine and release native resources |
| `updateMotionEngineConfig(MotionEngineConfig)` | Update motion engine config at runtime |
| `analyzeVideo(String)` | Analyze video file |
| `cancelVideoAnalysis()` | Cancel ongoing video analysis |
| `updateConfig(PoseDetectorConfig)` | Update configuration |
| `dispose()` | Release resources |

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `isInitialized` | `bool` | Whether detector is ready |
| `accelerationMode` | `AccelerationMode` | Current hardware acceleration |
| `config` | `PoseDetectorConfig` | Current configuration |
| `videoAnalysisProgress` | `Stream<VideoAnalysisProgress>` | Video analysis progress |

### NativeMotionEngine

| Property / Method | Type | Description |
|-------------------|------|-------------|
| `textureId` | `int` | Flutter texture ID for `Texture(textureId:)` |
| `readLatestPose()` | `PoseSnapshot?` | Lock-free FFI read — returns `null` if no new frame or torn read |

## Documentation

- [API Reference](https://pub.dev/documentation/flutter_pose_detection/latest/)
- [CHANGELOG](CHANGELOG.md)

## License

MIT License - see [LICENSE](LICENSE)
