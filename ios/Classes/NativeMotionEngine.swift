import AVFoundation
import Flutter
import MediaPipeTasksVision

/// High-performance native motion engine using AVFoundation + MediaPipe PoseLandmarker.
///
/// Architecture:
/// - AVCaptureVideoDataOutput → camera frames (background queue)
/// - FlutterTexture → raw camera preview (decoupled from inference)
/// - PoseLandmarker (LIVE_STREAM, GPU) → pose inference
/// - C PoseBuffer → shared memory for FFI reading by Dart
///
/// Rules:
/// - Do NOT convert to UIImage
/// - Do NOT queue frames (alwaysDiscardsLateVideoFrames = true)
/// - Timestamp sync prevents landmark drift
class NativeMotionEngine: NSObject {

    private static let TAG = "NativeMotionEngine"
    private static let NUM_LANDMARKS = 33

    // Camera
    private var captureSession: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "com.example.npu_pose_detection.session")
    private let inferenceQueue = DispatchQueue(label: "com.example.npu_pose_detection.inference")

    // Flutter texture
    private var cameraTexture: CameraFlutterTexture?
    private var textureId: Int64 = -1
    private weak var textureRegistry: FlutterTextureRegistry?

    // MediaPipe — accessed only on inferenceQueue
    private var poseLandmarker: PoseLandmarker?

    // C buffer — protected by bufferQueue
    private var bufferPointer: UnsafeMutablePointer<PoseBuffer>?
    private let bufferQueue = DispatchQueue(label: "com.example.npu_pose_detection.buffer")

    // Timestamp synchronization
    private var latestSubmittedTimestamp: Int = 0
    private var frameId: Int32 = 0

    // Reusable arrays (no per-frame allocation)
    private var poseLandmarkData = [Float](repeating: 0, count: NativeMotionEngine.NUM_LANDMARKS * 4)
    private var worldLandmarkData = [Float](repeating: 0, count: NativeMotionEngine.NUM_LANDMARKS * 4)

    // Runtime config
    private var modelComplexity: String = "lite"
    private var cameraFacing: String = "front"
    private var targetFps: Int = 0
    private var minPoseDetectionConfidence: Float = 0.5
    private var minTrackingConfidence: Float = 0.5
    private var minPosePresenceConfidence: Float = 0.5
    private var numPoses: Int = 1

    // FPS throttle
    private var minFrameIntervalMs: Int = 0
    private var lastInferenceTimestampMs: Int = 0

    init(textureRegistry: FlutterTextureRegistry) {
        self.textureRegistry = textureRegistry
        super.init()
    }

    /// Initialize the engine. Returns textureId + pointerAddress for Dart.
    func initialize(config: [String: Any]) -> [String: Any] {
        applyConfig(config)

        // 1. Allocate C buffer (once, NEVER reallocated)
        bufferPointer = pose_buffer_alloc()
        guard let ptr = bufferPointer else {
            fatalError("[\(Self.TAG)] Failed to allocate PoseBuffer")
        }
        let address = Int(bitPattern: ptr)
        print("[\(Self.TAG)] Allocated PoseBuffer at \(String(format: "0x%lx", address))")

        // 2. Register Flutter texture
        cameraTexture = CameraFlutterTexture()
        textureId = textureRegistry!.register(cameraTexture!)
        print("[\(Self.TAG)] Registered Flutter texture: \(textureId)")

        // 3. Initialize MediaPipe PoseLandmarker (LIVE_STREAM, GPU)
        initializePoseLandmarker()

        // 4. Start camera (async on session queue)
        startCamera()

        return [
            "textureId": textureId,
            "pointerAddress": address
        ]
    }

    private func applyConfig(_ config: [String: Any]) {
        modelComplexity = config["modelComplexity"] as? String ?? "lite"
        cameraFacing = config["cameraFacing"] as? String ?? "front"
        targetFps = config["targetFps"] as? Int ?? 0
        minFrameIntervalMs = targetFps > 0 ? 1000 / targetFps : 0
        minPoseDetectionConfidence = (config["minPoseDetectionConfidence"] as? NSNumber)?.floatValue ?? 0.5
        minTrackingConfidence = (config["minTrackingConfidence"] as? NSNumber)?.floatValue ?? 0.5
        minPosePresenceConfidence = (config["minPosePresenceConfidence"] as? NSNumber)?.floatValue ?? 0.5
        numPoses = config["numPoses"] as? Int ?? 1
    }

    private func initializePoseLandmarker() {
        let modelName = "pose_landmarker_\(modelComplexity)"
        guard let modelPath = getModelPath(name: modelName) else {
            print("[\(Self.TAG)] ERROR: \(modelName).task not found")
            return
        }
        print("[\(Self.TAG)] Loading model: \(modelName).task")

        let options = PoseLandmarkerOptions()
        options.baseOptions.modelAssetPath = modelPath
        options.baseOptions.delegate = .GPU
        options.runningMode = .liveStream
        options.minPoseDetectionConfidence = minPoseDetectionConfidence
        options.minPosePresenceConfidence = minPosePresenceConfidence
        options.minTrackingConfidence = minTrackingConfidence
        options.numPoses = numPoses
        options.poseLandmarkerLiveStreamDelegate = self

        do {
            poseLandmarker = try PoseLandmarker(options: options)
            print("[\(Self.TAG)] PoseLandmarker initialized (LIVE_STREAM, GPU)")
        } catch {
            print("[\(Self.TAG)] PoseLandmarker init failed: \(error)")
        }
    }

    private func getModelPath(name: String) -> String? {
        let podBundle = Bundle(for: type(of: self))

        // Try resource bundle (CocoaPods resource_bundles)
        if let resourceBundlePath = podBundle.path(forResource: "flutter_pose_detection", ofType: "bundle"),
           let resourceBundle = Bundle(path: resourceBundlePath),
           let path = resourceBundle.path(forResource: name, ofType: "task") {
            return path
        }

        // Try plugin bundle directly
        if let path = podBundle.path(forResource: name, ofType: "task") {
            return path
        }

        // Try main bundle
        if let path = Bundle.main.path(forResource: name, ofType: "task") {
            return path
        }

        return nil
    }

    // MARK: - Camera

    private func startCamera() {
        sessionQueue.async { [weak self] in
            self?.configureCaptureSession()
        }
    }

    private func configureCaptureSession() {
        let session = AVCaptureSession()
        session.sessionPreset = .medium

        let position: AVCaptureDevice.Position = cameraFacing == "back" ? .back : .front
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("[\(Self.TAG)] Failed to configure camera input")
            return
        }

        guard session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: inferenceQueue)

        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        self.captureSession = session
        session.startRunning()
        print("[\(Self.TAG)] Camera started")
    }

    // MARK: - Config Update

    /// Update configuration. Destroys and recreates the landmarker.
    /// Synchronized on inferenceQueue to prevent racing with captureOutput.
    func updateConfig(_ config: [String: Any]) {
        applyConfig(config)

        inferenceQueue.sync {
            poseLandmarker = nil
            frameId = 0
            latestSubmittedTimestamp = 0
            lastInferenceTimestampMs = 0
            initializePoseLandmarker()
        }
        print("[\(Self.TAG)] PoseLandmarker reinitialized with new config")
    }

    // MARK: - Dispose

    func dispose() {
        // 1. Stop camera — no new frames enter the pipeline
        sessionQueue.sync {
            captureSession?.stopRunning()
            captureSession = nil
        }

        // 2. Drain inferenceQueue — waits for in-flight captureOutput + detectAsync
        inferenceQueue.sync {
            poseLandmarker = nil
        }

        // 3. Drain bufferQueue — waits for in-flight pose_buffer_write
        bufferQueue.sync {
            if let ptr = bufferPointer {
                pose_buffer_free(ptr)
                bufferPointer = nil
            }
        }

        // 4. Release Flutter texture
        if cameraTexture != nil {
            textureRegistry?.unregisterTexture(textureId)
        }
        cameraTexture = nil
        textureId = -1

        print("[\(Self.TAG)] NativeMotionEngine disposed")
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension NativeMotionEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Update Flutter texture (decoupled from inference — MUST NOT wait)
        cameraTexture?.latestPixelBuffer = pixelBuffer
        textureRegistry?.textureFrameAvailable(textureId)

        // Timestamp synchronization
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestampMs = Int(CMTimeGetSeconds(timestamp) * 1000)

        // FPS throttle: skip frame if too soon since last inference
        if minFrameIntervalMs > 0 && timestampMs - lastInferenceTimestampMs < minFrameIntervalMs {
            return
        }

        guard timestampMs > latestSubmittedTimestamp else { return }
        latestSubmittedTimestamp = timestampMs
        lastInferenceTimestampMs = timestampMs

        // Send to MediaPipe (NO UIImage conversion)
        do {
            let mpImage = try MPImage(pixelBuffer: pixelBuffer)
            try poseLandmarker?.detectAsync(image: mpImage, timestampInMilliseconds: timestampMs)
        } catch {
            print("[\(Self.TAG)] Inference error: \(error)")
        }
    }
}

// MARK: - PoseLandmarkerLiveStreamDelegate

extension NativeMotionEngine: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(
        _ poseLandmarker: PoseLandmarker,
        didFinishDetection result: PoseLandmarkerResult?,
        timestampInMilliseconds: Int,
        error: Error?
    ) {
        guard let result = result, error == nil else { return }
        guard !result.landmarks.isEmpty else { return }
        guard bufferPointer != nil else { return }

        let imageLandmarks = result.landmarks[0]
        let worldLandmarks = result.worldLandmarks[0]

        // Flatten into reusable arrays: [x, y, z, visibility] × 33
        for i in 0..<Self.NUM_LANDMARKS {
            let idx = i * 4
            let lm = imageLandmarks[i]
            poseLandmarkData[idx] = lm.x
            poseLandmarkData[idx + 1] = lm.y
            poseLandmarkData[idx + 2] = lm.z
            poseLandmarkData[idx + 3] = lm.visibility?.floatValue ?? 0

            let wlm = worldLandmarks[i]
            worldLandmarkData[idx] = wlm.x
            worldLandmarkData[idx + 1] = wlm.y
            worldLandmarkData[idx + 2] = wlm.z
            worldLandmarkData[idx + 3] = wlm.visibility?.floatValue ?? 0
        }

        // Write to C buffer via pose_buffer_write (frameId written LAST)
        frameId += 1
        let currentFrameId = frameId
        // Capture array snapshots — Swift value types are CoW, safe to capture
        let poseSnapshot = poseLandmarkData
        let worldSnapshot = worldLandmarkData
        bufferQueue.async { [weak self] in
            guard let self = self, let ptr = self.bufferPointer else { return }
            poseSnapshot.withUnsafeBufferPointer { posePtr in
                worldSnapshot.withUnsafeBufferPointer { worldPtr in
                    pose_buffer_write(ptr, currentFrameId, posePtr.baseAddress, worldPtr.baseAddress)
                }
            }
        }
    }
}

// MARK: - Flutter Texture Wrapper

/// Provides camera pixel buffers to the Flutter texture system.
/// Updates are decoupled from inference — rendering MUST NOT wait for pose detection.
class CameraFlutterTexture: NSObject, FlutterTexture {
    private let lock = NSLock()
    private var _latestPixelBuffer: CVPixelBuffer?

    var latestPixelBuffer: CVPixelBuffer? {
        get { lock.lock(); defer { lock.unlock() }; return _latestPixelBuffer }
        set { lock.lock(); _latestPixelBuffer = newValue; lock.unlock() }
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer = _latestPixelBuffer else { return nil }
        return Unmanaged.passRetained(buffer)
    }
}
