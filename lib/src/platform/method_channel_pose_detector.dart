import 'dart:async';

import 'package:flutter/services.dart';

import '../errors/detection_error.dart';
import '../models/acceleration_mode.dart';
import '../models/detector_config.dart';
import '../models/frame_result.dart';
import '../models/pose_result.dart';
import '../models/video_analysis_result.dart';
import 'pose_detector_platform.dart';

/// Method channel implementation of [PoseDetectorPlatform].
class MethodChannelPoseDetector extends PoseDetectorPlatform {
  /// The method channel used to interact with the native platform.
  final MethodChannel _methodChannel = const MethodChannel(
    PoseDetectorChannels.methodChannel,
    StandardMethodCodec(),
  );

  /// The event channel for camera frame streaming.
  final EventChannel _frameEventChannel = const EventChannel(
    PoseDetectorChannels.eventChannel,
  );

  /// The event channel for video analysis progress.
  final EventChannel _videoProgressEventChannel = const EventChannel(
    PoseDetectorChannels.videoProgressChannel,
  );

  bool _isInitialized = false;
  AccelerationMode _accelerationMode = AccelerationMode.unknown;
  StreamController<FrameResult>? _frameStreamController;
  StreamSubscription<dynamic>? _frameEventSubscription;
  StreamController<VideoAnalysisProgress>? _videoProgressController;
  StreamSubscription<dynamic>? _videoProgressSubscription;

  @override
  bool get isInitialized => _isInitialized;

  @override
  AccelerationMode get accelerationMode => _accelerationMode;

  @override
  Future<AccelerationMode> initialize(PoseDetectorConfig config) async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'initialize',
        {'config': config.toJson()},
      );

      if (result == null) {
        throw DetectionError.fromCode(DetectionErrorCode.unknown);
      }

      final success = result['success'] as bool? ?? false;
      if (!success) {
        final error = result['error'] as Map<dynamic, dynamic>?;
        if (error != null) {
          throw DetectionError.fromJson(_convertMap(error));
        }
        throw DetectionError.fromCode(DetectionErrorCode.modelLoadFailed);
      }

      _accelerationMode = AccelerationMode.fromString(
        result['accelerationMode'] as String? ?? 'unknown',
      );
      _isInitialized = true;

      return _accelerationMode;
    } on PlatformException catch (e) {
      throw _handlePlatformException(e);
    }
  }

  @override
  Future<PoseResult> detectPose(Uint8List imageData) async {
    _ensureInitialized();

    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'detectPose',
        {'imageData': imageData, 'imageFormat': 'jpeg'},
      );

      if (result == null) {
        throw DetectionError.fromCode(DetectionErrorCode.unknown);
      }

      final success = result['success'] as bool? ?? false;
      if (!success) {
        final error = result['error'] as Map<dynamic, dynamic>?;
        if (error != null) {
          throw DetectionError.fromJson(_convertMap(error));
        }
        throw DetectionError.fromCode(DetectionErrorCode.inferenceFailed);
      }

      final resultData = result['result'] as Map<dynamic, dynamic>?;
      if (resultData == null) {
        throw DetectionError.fromCode(DetectionErrorCode.unknown);
      }

      return PoseResult.fromJson(_convertMap(resultData));
    } on PlatformException catch (e) {
      throw _handlePlatformException(e);
    }
  }

  @override
  Future<PoseResult> detectPoseFromFile(String filePath) async {
    _ensureInitialized();

    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'detectPoseFromFile',
        {'filePath': filePath},
      );

      if (result == null) {
        throw DetectionError.fromCode(DetectionErrorCode.unknown);
      }

      final success = result['success'] as bool? ?? false;
      if (!success) {
        final error = result['error'] as Map<dynamic, dynamic>?;
        if (error != null) {
          throw DetectionError.fromJson(_convertMap(error));
        }
        throw DetectionError.fromCode(DetectionErrorCode.inferenceFailed);
      }

      final resultData = result['result'] as Map<dynamic, dynamic>?;
      if (resultData == null) {
        throw DetectionError.fromCode(DetectionErrorCode.unknown);
      }

      return PoseResult.fromJson(_convertMap(resultData));
    } on PlatformException catch (e) {
      throw _handlePlatformException(e);
    }
  }

  @override
  Future<void> updateConfig(PoseDetectorConfig config) async {
    _ensureInitialized();

    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'updateConfig',
        {'config': config.toJson()},
      );

      if (result == null) {
        throw DetectionError.fromCode(DetectionErrorCode.unknown);
      }

      final success = result['success'] as bool? ?? false;
      if (!success) {
        final error = result['error'] as Map<dynamic, dynamic>?;
        if (error != null) {
          throw DetectionError.fromJson(_convertMap(error));
        }
      }
    } on PlatformException catch (e) {
      throw _handlePlatformException(e);
    }
  }

  @override
  Future<Map<String, dynamic>> getDeviceCapabilities() async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'getDeviceCapabilities',
        {},
      );

      if (result == null) {
        return {};
      }

      final success = result['success'] as bool? ?? false;
      if (!success) {
        return {};
      }

      final capabilities = result['capabilities'] as Map<dynamic, dynamic>?;
      return capabilities != null ? _convertMap(capabilities) : {};
    } on PlatformException {
      return {};
    }
  }

  @override
  Future<void> dispose() async {
    if (!_isInitialized) return;

    try {
      await _methodChannel.invokeMethod<Map<dynamic, dynamic>>('dispose', {});
    } catch (_) {
      // Ignore disposal errors
    } finally {
      _isInitialized = false;
      _accelerationMode = AccelerationMode.unknown;
    }
  }

  void _ensureInitialized() {
    if (!_isInitialized) {
      throw DetectionError.fromCode(DetectionErrorCode.notInitialized);
    }
  }

  DetectionError _handlePlatformException(PlatformException e) {
    final code = DetectionErrorCode.fromString(e.code);
    return DetectionError(
      code: code,
      message: e.message ?? code.description,
      platformMessage: e.details?.toString(),
      recoverySuggestion: code.recoverySuggestion,
    );
  }

  Map<String, dynamic> _convertMap(Map<dynamic, dynamic> map) {
    return map.map((key, value) {
      if (value is Map) {
        return MapEntry(key.toString(), _convertMap(value));
      } else if (value is List) {
        return MapEntry(key.toString(), _convertList(value));
      }
      return MapEntry(key.toString(), value);
    });
  }

  List<dynamic> _convertList(List<dynamic> list) {
    return list.map((item) {
      if (item is Map) {
        return _convertMap(item);
      } else if (item is List) {
        return _convertList(item);
      }
      return item;
    }).toList();
  }

  @override
  Future<PoseResult> processFrame({
    required List<Map<String, dynamic>> planes,
    required int width,
    required int height,
    required String format,
    int rotation = 0,
  }) async {
    _ensureInitialized();

    try {
      // Encode plane bytes directly
      final encodedPlanes = planes.map((plane) {
        final bytes = plane['bytes'];
        if (bytes is Uint8List) {
          return {
            'bytes': bytes,
            'bytesPerRow': plane['bytesPerRow'] ?? 0,
            'bytesPerPixel': plane['bytesPerPixel'] ?? 1,
          };
        }
        return plane;
      }).toList();

      final result = await _methodChannel
          .invokeMethod<Map<dynamic, dynamic>>('processFrame', {
            'planes': encodedPlanes,
            'width': width,
            'height': height,
            'format': format,
            'rotation': rotation,
          });

      if (result == null) {
        throw DetectionError.fromCode(DetectionErrorCode.unknown);
      }

      final success = result['success'] as bool? ?? false;
      if (!success) {
        final error = result['error'] as Map<dynamic, dynamic>?;
        if (error != null) {
          throw DetectionError.fromJson(_convertMap(error));
        }
        throw DetectionError.fromCode(DetectionErrorCode.inferenceFailed);
      }

      final resultData = result['result'] as Map<dynamic, dynamic>?;
      if (resultData == null) {
        throw DetectionError.fromCode(DetectionErrorCode.unknown);
      }

      return PoseResult.fromJson(_convertMap(resultData));
    } on PlatformException catch (e) {
      throw _handlePlatformException(e);
    }
  }

  @override
  Stream<FrameResult> startCameraDetection() {
    _ensureInitialized();

    // Close any existing stream
    _frameStreamController?.close();
    _frameEventSubscription?.cancel();

    _frameStreamController = StreamController<FrameResult>.broadcast(
      onCancel: () {
        stopCameraDetection();
      },
    );

    // Start native camera detection
    _methodChannel.invokeMethod('startCameraDetection');

    // Listen to event channel
    _frameEventSubscription = _frameEventChannel
        .receiveBroadcastStream()
        .listen(
          (dynamic event) {
            if (event is Map) {
              final type = event['type'] as String?;
              switch (type) {
                case 'frame':
                  final frameResult = FrameResult.fromJson(_convertMap(event));
                  _frameStreamController?.add(frameResult);
                  break;
                case 'error':
                  final error = event['error'] as Map?;
                  if (error != null) {
                    _frameStreamController?.addError(
                      DetectionError.fromJson(_convertMap(error)),
                    );
                  }
                  break;
                case 'end':
                  _frameStreamController?.close();
                  break;
              }
            }
          },
          onError: (error) {
            _frameStreamController?.addError(error);
          },
          onDone: () {
            _frameStreamController?.close();
          },
        );

    return _frameStreamController!.stream;
  }

  @override
  Future<void> stopCameraDetection() async {
    try {
      await _methodChannel.invokeMethod('stopCameraDetection');
    } catch (_) {
      // Ignore errors during stop
    } finally {
      await _frameEventSubscription?.cancel();
      _frameEventSubscription = null;
      await _frameStreamController?.close();
      _frameStreamController = null;
    }
  }

  @override
  Future<VideoAnalysisResult> analyzeVideo(
    String videoPath, {
    int frameInterval = 1,
  }) async {
    _ensureInitialized();

    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'analyzeVideo',
        {'videoPath': videoPath, 'frameInterval': frameInterval},
      );

      if (result == null) {
        throw DetectionError.fromCode(DetectionErrorCode.unknown);
      }

      final success = result['success'] as bool? ?? false;
      if (!success) {
        final error = result['error'] as Map<dynamic, dynamic>?;
        if (error != null) {
          throw DetectionError.fromJson(_convertMap(error));
        }
        throw DetectionError.fromCode(DetectionErrorCode.inferenceFailed);
      }

      final resultData = result['result'] as Map<dynamic, dynamic>?;
      if (resultData == null) {
        throw DetectionError.fromCode(DetectionErrorCode.unknown);
      }

      return VideoAnalysisResult.fromJson(_convertMap(resultData));
    } on PlatformException catch (e) {
      throw _handlePlatformException(e);
    }
  }

  @override
  Stream<VideoAnalysisProgress> get videoAnalysisProgress {
    _videoProgressController?.close();
    _videoProgressSubscription?.cancel();

    _videoProgressController =
        StreamController<VideoAnalysisProgress>.broadcast();

    _videoProgressSubscription = _videoProgressEventChannel
        .receiveBroadcastStream()
        .listen(
          (dynamic event) {
            if (event is Map) {
              final type = event['type'] as String?;
              switch (type) {
                case 'progress':
                  final progress = VideoAnalysisProgress.fromJson(
                    _convertMap(event),
                  );
                  _videoProgressController?.add(progress);
                  break;
                case 'error':
                  final error = event['error'] as Map?;
                  if (error != null) {
                    _videoProgressController?.addError(
                      DetectionError.fromJson(_convertMap(error)),
                    );
                  }
                  break;
                case 'complete':
                case 'cancelled':
                  _videoProgressController?.close();
                  break;
              }
            }
          },
          onError: (error) {
            _videoProgressController?.addError(error);
          },
          onDone: () {
            _videoProgressController?.close();
          },
        );

    return _videoProgressController!.stream;
  }

  @override
  Future<void> cancelVideoAnalysis() async {
    try {
      await _methodChannel.invokeMethod('cancelVideoAnalysis');
    } catch (_) {
      // Ignore errors during cancel
    } finally {
      await _videoProgressSubscription?.cancel();
      _videoProgressSubscription = null;
      await _videoProgressController?.close();
      _videoProgressController = null;
    }
  }

  /// Benchmark different TFLite delegates (QNN, GPU, CPU).
  ///
  /// Returns a map of delegate names to their benchmark results.
  /// Each result contains: success, avgInferenceTimeMs, minInferenceTimeMs,
  /// maxInferenceTimeMs, and errorMessage (if failed).
  Future<Map<String, dynamic>> benchmarkDelegates({int iterations = 10}) async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'benchmarkDelegates',
        {'iterations': iterations},
      );

      if (result == null) {
        return {'success': false, 'error': 'No result returned'};
      }

      final success = result['success'] as bool? ?? false;
      if (!success) {
        final error = result['error'] as Map<dynamic, dynamic>?;
        return {
          'success': false,
          'error': error != null ? _convertMap(error) : 'Unknown error',
        };
      }

      final results = result['results'] as Map<dynamic, dynamic>?;
      return {
        'success': true,
        'results': results != null ? _convertMap(results) : {},
      };
    } on PlatformException catch (e) {
      return {'success': false, 'error': e.message ?? 'Platform exception'};
    }
  }

  // MARK: - Motion Engine

  @override
  Future<Map<String, dynamic>> initializeMotionEngine(
    Map<String, dynamic> config,
  ) async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'initializeMotionEngine',
        {'config': config},
      );

      if (result == null) {
        throw DetectionError.fromCode(DetectionErrorCode.unknown);
      }

      final success = result['success'] as bool? ?? false;
      if (!success) {
        final error = result['error'] as Map<dynamic, dynamic>?;
        if (error != null) {
          throw DetectionError.fromJson(_convertMap(error));
        }
        throw DetectionError.fromCode(DetectionErrorCode.modelLoadFailed);
      }

      return _convertMap(result);
    } on PlatformException catch (e) {
      throw _handlePlatformException(e);
    }
  }

  @override
  Future<void> updateMotionEngineConfig(Map<String, dynamic> config) async {
    try {
      final result = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'updateMotionEngineConfig',
        {'config': config},
      );

      if (result == null) {
        throw DetectionError.fromCode(DetectionErrorCode.unknown);
      }

      final success = result['success'] as bool? ?? false;
      if (!success) {
        final error = result['error'] as Map<dynamic, dynamic>?;
        if (error != null) {
          throw DetectionError.fromJson(_convertMap(error));
        }
      }
    } on PlatformException catch (e) {
      throw _handlePlatformException(e);
    }
  }

  @override
  Future<void> disposeMotionEngine() async {
    try {
      await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'disposeMotionEngine',
      );
    } catch (_) {
      // Ignore errors during disposal
    }
  }
}
