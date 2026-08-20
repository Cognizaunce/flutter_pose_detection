# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Migrated the Android plugin and example app to AGP 9 built-in Kotlin.
- Updated the minimum supported Flutter SDK to 3.44 and Dart SDK to 3.12.

## [0.4.1] - 2026-01-02

### Fixed
- Fixed incorrect model name in Platform Support table (movenet_lightning → pose_landmarks_detector)

## [0.4.0] - 2026-01-02

### Added
- **NPU Support (Android)**: Qualcomm QNN delegate for Snapdragon devices
  - Battery-efficient inference on Hexagon DSP (HTP backend)
  - ~13-16ms inference time with significantly lower power consumption
  - Automatic skel library extraction from bundled assets
  - Supports Snapdragon 8 series (V68-V79 HTP versions)
- New `preferredAcceleration` config option for explicit backend selection
  - `AccelerationMode.npu` - Force NPU (Snapdragon only)
  - `AccelerationMode.gpu` - Force GPU (default behavior)
  - `null` - Auto-select best available
- Backend switching between MediaPipe (GPU) and TFLite+QNN (NPU)
- Example app with NPU toggle switch and benchmark functionality

### Changed
- `NpuPoseDetector` now supports runtime backend selection
- Updated README with NPU documentation and performance comparison table

## [0.3.3] - 2026-01-02

### Fixed
- Fixed Dart formatter issues for pub.dev static analysis
- Updated plugin_platform_interface constraint (^2.0.2 → ^2.1.0) for downgrade compatibility

## [0.3.2] - 2026-01-02

### Fixed
- Fixed Android minSdkVersion in README (24 → 31)
- Separated Model Architecture section for iOS and Android

## [0.3.1] - 2026-01-02

### Changed
- Updated README with comprehensive API documentation
- Added Configuration, Camera Stream, Video Analysis, and Angle Calculation sections
- Fixed Quick Start code examples (MediaPipeLandmarkType → LandmarkType)
- Added API Reference table with all methods and properties
- Improved MediaPipe 33 Landmarks documentation with structured table

### Fixed
- Corrected library documentation (Vision Framework → MediaPipe PoseLandmarker)
- Fixed Pose class comment (17 landmarks → 33 landmarks)

## [0.3.0] - 2026-01-01

### Changed
- **BREAKING**: Migrated from LiteRT/MoveNet to MediaPipe PoseLandmarker API
- **Android**: Uses official MediaPipe Tasks Vision library with GPU delegate
  - `pose_landmarker_lite.task` model for 33-landmark detection
  - Automatic GPU → CPU fallback
- **iOS**: Uses TFLite with CoreML/Metal delegates for ANE/GPU acceleration
  - `pose_detector.tflite` + `pose_landmarks_detector.tflite` 2-stage pipeline
  - Automatic ANE → GPU → CPU fallback

### Removed
- LiteRT/MoveNet fallback code (simplified architecture)
- `LiteRtPoseDetector.swift` - MediaPipe only
- `movenet_lightning.tflite`, `movenet_thunder.tflite` - replaced by MediaPipe models
- `hrnetpose_w8a8.tflite`, `HRNetPose.mlpackage` - no longer needed

### Fixed
- iOS main thread blocking during initialization (moved to background thread)
- iOS coordinate normalization (pixel space 0-256 → normalized 0-1)
- Android model loading with ByteBuffer instead of file path

## [0.2.2] - 2025-12-31

### Fixed
- **Critical**: Fixed pose coordinate mismatch with video aspect ratio
  - Added letterboxing (padding) during image preprocessing to maintain original aspect ratio
  - Previously, images were stretched to 192x256 input size, causing coordinate distortion
  - Coordinates now correctly map back to original image dimensions
- **Android**: Implemented `letterboxBitmap()` and `transformKeypointsFromLetterbox()` in `LiteRtPoseDetector.kt`
- **iOS**: Implemented `letterboxAndExtractRGB()` and `transformKeypointsFromLetterbox()` in `CoreMLPoseDetector.swift`

## [0.2.1] - 2025-12-31

### Fixed
- **Android**: Updated QNN SDK from 2.34.0 to 2.41.0
  - Fixes `NoSuchMethodError: getBackendType()I` crash on Snapdragon 8 Elite
  - Resolves native JNI method signature mismatch with newer Android firmware

### Added
- **Android**: `ChipsetDetector` for runtime SoC detection (Snapdragon, Exynos, Tensor, MediaTek)
- **iOS**: `CoreMLPoseDetector` for native Core ML inference with ANE optimization
  - Direct MLModel API usage (no Vision framework overhead)
  - ImageNet normalization for HRNet models

## [0.2.0] - 2024-12-31

### Changed
- **BREAKING**: Migrated from TensorFlow Lite to LiteRT 2.1.0 (Google's successor to TFLite)
- **Android**: New `LiteRtPoseDetector` using CompiledModel API with NPU/GPU/CPU fallback
  - Replaces `TFLitePoseDetector` and `DelegateFactory`
  - Uses `Accelerator.NPU`, `Accelerator.GPU` for hardware acceleration
  - Automatic fallback chain: NPU → GPU → CPU
- **iOS**: New `LiteRtPoseDetector` using TensorFlowLiteSwift 2.14.0
  - Replaces `VisionPoseDetector` with MoveNet-based detection
  - CoreML delegate for Neural Engine (A12+), Metal delegate for GPU
  - Automatic fallback chain: Neural Engine → Metal → CPU
- **Both Platforms**: Now use same MoveNet Lightning/Thunder models for consistent results
  - Cross-platform landmark positions match within 5% variance
  - Lightning (192x192) for fast mode, Thunder (256x256) for accurate mode

### Removed
- `TFLitePoseDetector.kt` - replaced by `LiteRtPoseDetector.kt`
- `DelegateFactory.kt` - accelerator selection now handled by CompiledModel API
- `VisionPoseDetector.swift` - replaced by `LiteRtPoseDetector.swift`

### Fixed
- Consistent 17-landmark COCO format output across platforms
- Proper resource cleanup on dispose()

## [0.1.0] - 2024-12-30

### Added
- Initial release of NPU Pose Detection plugin
- **iOS Support**: Apple Vision Framework with Neural Engine acceleration
  - Automatic NPU/GPU acceleration on A12+ devices
  - VNDetectHumanBodyPoseRequest for 17 body landmarks
  - Landmark mapping to MediaPipe 33-point format
- **Android Support**: TensorFlow Lite with MoveNet Lightning model
  - GPU Delegate for hardware acceleration
  - NNAPI support for devices API 27-34 (Depreciated on 35+)
  - CPU fallback with XNNPack optimization
- **Core Features**:
  - Static image pose detection (`detectPose`, `detectPoseFromFile`)
  - Real-time camera frame processing (`processFrame`, `startCameraDetection`)
  - Video file analysis (`analyzeVideo` with progress tracking)
  - Configurable detection parameters (`PoseDetectorConfig`)
- **Data Models**:
  - `Pose` with 33 MediaPipe-compatible landmarks
  - `PoseLandmark` with normalized coordinates (0-1) and confidence scores
  - `BoundingBox` for detected person region
  - `LandmarkType` enum for easy landmark access
- **Error Handling**:
  - Typed `DetectionError` with error codes
  - Graceful fallback from NPU to GPU to CPU
- **Example App**:
  - Image detection demo with gallery picker
  - Real-time camera detection with pose overlay
  - Video analysis with progress UI
