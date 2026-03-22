import Flutter
import UIKit
import Vision
import CoreMedia
import CoreVideo

/// Flutter plugin for NPU-accelerated pose detection on iOS.
///
/// Uses MediaPipe with CoreML/Metal delegates for Neural Engine/GPU acceleration.
public class NpuPoseDetectionPlugin: NSObject, FlutterPlugin {

    // MARK: - Properties

    private var mediaPipeDetector: MediaPipePoseDetector?
    private var config: DetectorConfig = DetectorConfig()
    private var nativeMotionEngine: NativeMotionEngine?
    private var textureRegistry: FlutterTextureRegistry?

    /// Returns the active pose detector.
    private var poseDetector: PoseDetectorProtocol? {
        return mediaPipeDetector
    }
    private var frameEventSink: FlutterEventSink?
    private var videoProgressEventSink: FlutterEventSink?
    private var isStreamingActive = false
    private var frameCount: Int = 0
    private var fpsCalculator = FPSCalculator()
    private var videoProcessor: VideoProcessor?

    // MARK: - Channel Names

    private static let methodChannelName = "com.example.flutter_pose_detection/methods"
    private static let eventChannelName = "com.example.flutter_pose_detection/frames"
    private static let videoProgressChannelName = "com.example.flutter_pose_detection/video_progress"

    // MARK: - Plugin Registration

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: methodChannelName,
            binaryMessenger: registrar.messenger()
        )
        let instance = NpuPoseDetectionPlugin()
        instance.textureRegistry = registrar.textures()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)

        // Setup EventChannel for camera frame streaming
        let eventChannel = FlutterEventChannel(
            name: eventChannelName,
            binaryMessenger: registrar.messenger()
        )
        eventChannel.setStreamHandler(instance)

        // Setup EventChannel for video analysis progress
        let videoProgressChannel = FlutterEventChannel(
            name: videoProgressChannelName,
            binaryMessenger: registrar.messenger()
        )
        videoProgressChannel.setStreamHandler(VideoProgressStreamHandler(plugin: instance))
    }

    // MARK: - Method Call Handler

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "initialize":
            handleInitialize(call, result: result)
        case "detectPose":
            handleDetectPose(call, result: result)
        case "detectPoseFromFile":
            handleDetectPoseFromFile(call, result: result)
        case "processFrame":
            handleProcessFrame(call, result: result)
        case "startCameraDetection":
            handleStartCameraDetection(call, result: result)
        case "stopCameraDetection":
            handleStopCameraDetection(result: result)
        case "analyzeVideo":
            handleAnalyzeVideo(call, result: result)
        case "cancelVideoAnalysis":
            handleCancelVideoAnalysis(result: result)
        case "updateConfig":
            handleUpdateConfig(call, result: result)
        case "getDeviceCapabilities":
            handleGetDeviceCapabilities(result: result)
        case "initializeMotionEngine":
            handleInitializeMotionEngine(call, result: result)
        case "updateMotionEngineConfig":
            handleUpdateMotionEngineConfig(call, result: result)
        case "disposeMotionEngine":
            handleDisposeMotionEngine(result: result)
        case "dispose":
            handleDispose(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Initialize

    private func handleInitialize(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let configDict = args["config"] as? [String: Any] else {
            result(errorResponse(code: "invalidArguments", message: "Missing config"))
            return
        }

        config = DetectorConfig.from(dictionary: configDict)

        // Run initialization on background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let mediaPipe = MediaPipePoseDetector(config: config)
            do {
                let mode = try mediaPipe.initialize()
                self.mediaPipeDetector = mediaPipe
                DispatchQueue.main.async {
                    result([
                        "success": true,
                        "accelerationMode": mode.rawValue,
                        "modelVersion": "mediapipe_pose_landmarker",
                        "numLandmarks": 33
                    ])
                }
            } catch {
                print("[NpuPoseDetectionPlugin] MediaPipe initialization failed: \(error)")
                DispatchQueue.main.async {
                    result(self.errorResponse(
                        code: "modelLoadFailed",
                        message: "Failed to initialize MediaPipe pose detector",
                        platformMessage: error.localizedDescription
                    ))
                }
            }
        }
    }

    // MARK: - Detect Pose

    private func handleDetectPose(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let detector = poseDetector else {
            result(errorResponse(code: "notInitialized", message: "Detector not initialized"))
            return
        }

        guard let args = call.arguments as? [String: Any],
            let typedData = args["imageData"] as? FlutterStandardTypedData else {
            result(errorResponse(code: "invalidImageFormat", message: "Invalid image data"))
            return
        }

        let imageData = typedData.data

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let poseResult = try detector.detectPose(imageData: imageData)
                DispatchQueue.main.async {
                    result([
                        "success": true,
                        "result": poseResult.toDictionary()
                    ])
                }
            } catch {
                DispatchQueue.main.async {
                    result(self.errorResponse(
                        code: "inferenceFailed",
                        message: "Pose detection failed",
                        platformMessage: error.localizedDescription
                    ))
                }
            }
        }
    }

    // MARK: - Detect Pose From File

    private func handleDetectPoseFromFile(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let detector = poseDetector else {
            result(errorResponse(code: "notInitialized", message: "Detector not initialized"))
            return
        }

        guard let args = call.arguments as? [String: Any],
              let filePath = args["filePath"] as? String else {
            result(errorResponse(code: "invalidArguments", message: "Missing file path"))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let poseResult = try detector.detectPose(filePath: filePath)
                DispatchQueue.main.async {
                    result([
                        "success": true,
                        "result": poseResult.toDictionary()
                    ])
                }
            } catch {
                DispatchQueue.main.async {
                    result(self.errorResponse(
                        code: "inferenceFailed",
                        message: "Pose detection failed",
                        platformMessage: error.localizedDescription
                    ))
                }
            }
        }
    }

    // MARK: - Update Config

    private func handleUpdateConfig(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let configDict = args["config"] as? [String: Any] else {
            result(errorResponse(code: "invalidArguments", message: "Missing config"))
            return
        }

        config = DetectorConfig.from(dictionary: configDict)
        poseDetector?.updateConfig(config)

        result([
            "success": true,
            "requiresReinitialize": false
        ])
    }

    // MARK: - Device Capabilities

    private func handleGetDeviceCapabilities(result: @escaping FlutterResult) {
        let device = UIDevice.current
        let hasNeuralEngine = hasNeuralEngineSupport()

        result([
            "success": true,
            "capabilities": [
                "platform": "ios",
                "osVersion": device.systemVersion,
                "deviceModel": getDeviceModel(),
                "npuInfo": [
                    "type": "neural_engine",
                    "isAvailable": hasNeuralEngine,
                    "performanceTier": hasNeuralEngine ? "high" : "low"
                ],
                "hasGpuSupport": true,
                "recommendedMode": "npu"
            ]
        ])
    }

    // MARK: - Process Frame

    private func handleProcessFrame(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let detector = poseDetector else {
            result(errorResponse(code: "notInitialized", message: "Detector not initialized"))
            return
        }

        guard let args = call.arguments as? [String: Any],
              let planes = args["planes"] as? [[String: Any]],
              let width = args["width"] as? Int,
              let height = args["height"] as? Int else {
            result(errorResponse(code: "invalidArguments", message: "Missing frame data"))
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // Create pixel buffer from plane data
                guard let pixelBuffer = self.createPixelBuffer(
                    from: planes,
                    width: width,
                    height: height
                ) else {
                    DispatchQueue.main.async {
                        result(self.errorResponse(code: "invalidImageFormat", message: "Failed to create pixel buffer"))
                    }
                    return
                }

                let poseResult = try detector.processFrame(pixelBuffer: pixelBuffer)
                DispatchQueue.main.async {
                    result([
                        "success": true,
                        "result": poseResult.toDictionary()
                    ])
                }
            } catch {
                DispatchQueue.main.async {
                    result(self.errorResponse(
                        code: "inferenceFailed",
                        message: "Frame processing failed",
                        platformMessage: error.localizedDescription
                    ))
                }
            }
        }
    }

    // MARK: - Camera Detection

    private func handleStartCameraDetection(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard poseDetector != nil else {
            result(errorResponse(code: "notInitialized", message: "Detector not initialized"))
            return
        }

        isStreamingActive = true
        frameCount = 0
        fpsCalculator.reset()

        result(["success": true])
    }

    private func handleStopCameraDetection(result: @escaping FlutterResult) {
        isStreamingActive = false

        // Send end event
        frameEventSink?([
            "type": "end",
            "reason": "stopped"
        ])

        result(["success": true])
    }

    /// Process a frame and send result through event channel.
    /// Called from Dart side when a camera frame is available.
    func processFrameForStream(planes: [[String: Any]], width: Int, height: Int, timestampUs: Int) {
        guard isStreamingActive, let detector = poseDetector else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let pixelBuffer = self.createPixelBuffer(
                    from: planes,
                    width: width,
                    height: height
                ) else { return }

                let poseResult = try detector.processFrame(pixelBuffer: pixelBuffer)

                self.frameCount += 1
                let fps = self.fpsCalculator.update()

                DispatchQueue.main.async {
                    self.frameEventSink?([
                        "type": "frame",
                        "frameNumber": self.frameCount,
                        "timestampUs": timestampUs,
                        "fps": fps,
                        "result": poseResult.toDictionary()
                    ])
                }
            } catch {
                DispatchQueue.main.async {
                    self.frameEventSink?([
                        "type": "error",
                        "error": [
                            "code": "inferenceFailed",
                            "message": "Frame processing failed",
                            "platformMessage": error.localizedDescription
                        ]
                    ])
                }
            }
        }
    }

    // MARK: - Pixel Buffer Creation

    private func createPixelBuffer(from planes: [[String: Any]], width: Int, height: Int) -> CVPixelBuffer? {
        guard let firstPlane = planes.first,
            let typedData = firstPlane["bytes"] as? FlutterStandardTypedData else {
            return nil
        }

        let bytes = typedData.data

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        if let baseAddress = CVPixelBufferGetBaseAddress(buffer) {
            bytes.copyBytes(to: baseAddress.assumingMemoryBound(to: UInt8.self), count: bytes.count)
        }

        return buffer
    }

    // MARK: - Video Analysis

    private func handleAnalyzeVideo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let detector = poseDetector else {
            result(errorResponse(code: "notInitialized", message: "Detector not initialized"))
            return
        }

        guard let args = call.arguments as? [String: Any],
              let videoPath = args["videoPath"] as? String else {
            result(errorResponse(code: "invalidArguments", message: "Missing video path"))
            return
        }

        let frameInterval = args["frameInterval"] as? Int ?? 1

        videoProcessor = VideoProcessor(detector: detector)

        videoProcessor?.analyzeVideo(
            at: videoPath,
            frameInterval: frameInterval,
            progress: { [weak self] progress in
                self?.videoProgressEventSink?(progress.toDictionary())
            },
            completion: { [weak self] analysisResult in
                switch analysisResult {
                case .success(let videoResult):
                    self?.videoProgressEventSink?([
                        "type": "complete"
                    ])
                    result([
                        "success": true,
                        "result": videoResult.toDictionary()
                    ])
                case .failure(let error):
                    self?.videoProgressEventSink?([
                        "type": "error",
                        "error": [
                            "code": "videoAnalysisFailed",
                            "message": error.localizedDescription
                        ]
                    ])
                    result(self?.errorResponse(
                        code: "videoAnalysisFailed",
                        message: "Video analysis failed",
                        platformMessage: error.localizedDescription
                    ))
                }
            }
        )
    }

    private func handleCancelVideoAnalysis(result: @escaping FlutterResult) {
        videoProcessor?.cancel()
        videoProgressEventSink?([
            "type": "cancelled"
        ])
        result(["success": true])
    }

    // MARK: - Dispose

    private func handleDispose(result: @escaping FlutterResult) {
        isStreamingActive = false
        videoProcessor?.cancel()
        videoProcessor = nil
        mediaPipeDetector?.dispose()
        mediaPipeDetector = nil
        nativeMotionEngine?.dispose()
        nativeMotionEngine = nil
        result(["success": true])
    }

    // MARK: - Motion Engine

    private func handleInitializeMotionEngine(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let registry = textureRegistry else {
            result(errorResponse(code: "notInitialized", message: "TextureRegistry not available"))
            return
        }

        let args = call.arguments as? [String: Any]
        let config = args?["config"] as? [String: Any] ?? [:]

        nativeMotionEngine?.dispose()
        nativeMotionEngine = NativeMotionEngine(textureRegistry: registry)
        let engineResult = nativeMotionEngine!.initialize(config: config)

        result([
            "success": true,
            "textureId": engineResult["textureId"] as Any,
            "pointerAddress": engineResult["pointerAddress"] as Any
        ])
    }

    private func handleUpdateMotionEngineConfig(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let engine = nativeMotionEngine else {
            result(errorResponse(code: "notInitialized", message: "Motion engine not initialized"))
            return
        }

        let args = call.arguments as? [String: Any]
        let config = args?["config"] as? [String: Any] ?? [:]

        engine.updateConfig(config)
        result(["success": true])
    }

    private func handleDisposeMotionEngine(result: @escaping FlutterResult) {
        nativeMotionEngine?.dispose()
        nativeMotionEngine = nil
        result(["success": true])
    }

    // MARK: - Helpers

    private func errorResponse(
        code: String,
        message: String,
        platformMessage: String? = nil,
        recoverySuggestion: String? = nil
    ) -> [String: Any] {
        var error: [String: Any] = [
            "code": code,
            "message": message
        ]
        if let pm = platformMessage {
            error["platformMessage"] = pm
        }
        if let rs = recoverySuggestion {
            error["recoverySuggestion"] = rs
        }
        return [
            "success": false,
            "error": error
        ]
    }

    private func hasNeuralEngineSupport() -> Bool {
        // Neural Engine available on A12+ chips (iPhone XS and later)
        if #available(iOS 14.0, *) {
            return true
        }
        return false
    }

    private func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
}

// MARK: - FlutterStreamHandler

extension NpuPoseDetectionPlugin: FlutterStreamHandler {
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        frameEventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        frameEventSink = nil
        isStreamingActive = false
        return nil
    }
}

// MARK: - Video Progress Stream Handler

class VideoProgressStreamHandler: NSObject, FlutterStreamHandler {
    weak var plugin: NpuPoseDetectionPlugin?

    init(plugin: NpuPoseDetectionPlugin) {
        self.plugin = plugin
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        plugin?.setVideoProgressEventSink(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        plugin?.setVideoProgressEventSink(nil)
        return nil
    }
}

extension NpuPoseDetectionPlugin {
    func setVideoProgressEventSink(_ sink: FlutterEventSink?) {
        videoProgressEventSink = sink
    }
}

// MARK: - FPS Calculator

class FPSCalculator {
    private var timestamps: [CFAbsoluteTime] = []
    private let windowSize = 30

    func reset() {
        timestamps.removeAll()
    }

    func update() -> Double {
        let now = CFAbsoluteTimeGetCurrent()
        timestamps.append(now)

        // Keep only recent timestamps
        if timestamps.count > windowSize {
            timestamps.removeFirst()
        }

        // Calculate FPS from time window
        guard timestamps.count >= 2 else { return 0 }

        let elapsed = timestamps.last! - timestamps.first!
        guard elapsed > 0 else { return 0 }

        return Double(timestamps.count - 1) / elapsed
    }
}
