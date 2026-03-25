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

    // MediaPipe
    private var poseLandmarker: PoseLandmarker?

    // C buffer (allocated once, never reallocated)
    private var bufferPointer: UnsafeMutablePointer<PoseBuffer>?

    // Timestamp synchronization
    private var latestSubmittedTimestamp: Int = 0
    private var frameId: Int32 = 0

    // Reusable arrays (no per-frame allocation)
    private var poseLandmarkData = [Float](repeating: 0, count: NativeMotionEngine.NUM_LANDMARKS * 4)
    private var worldLandmarkData = [Float](repeating: 0, count: NativeMotionEngine.NUM_LANDMARKS * 4)

    // Runtime config
    private var minPoseDetectionConfidence: Float = 0.5
    private var minTrackingConfidence: Float = 0.5
    private var minPosePresenceConfidence: Float = 0.5
    private var numPoses: Int = 1

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
        minPoseDetectionConfidence = (config["minPoseDetectionConfidence"] as? NSNumber)?.floatValue ?? 0.5
        minTrackingConfidence = (config["minTrackingConfidence"] as? NSNumber)?.floatValue ?? 0.5
        minPosePresenceConfidence = (config["minPosePresenceConfidence"] as? NSNumber)?.floatValue ?? 0.5
        numPoses = config["numPoses"] as? Int ?? 1
    }

    private func initializePoseLandmarker() {
        guard let modelPath = getModelPath() else {
            print("[\(Self.TAG)] ERROR: pose_landmarker_lite.task not found")
            return
        }

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

    private func getModelPath() -> String? {
        let podBundle = Bundle(for: type(of: self))

        // Try resource bundle (CocoaPods resource_bundles)
        if let resourceBundlePath = podBundle.path(forResource: "flutter_pose_detection", ofType: "bundle"),
           let resourceBundle = Bundle(path: resourceBundlePath),
           let path = resourceBundle.path(forResource: "pose_landmarker_lite", ofType: "task") {
            return path
        }

        // Try plugin bundle directly
        if let path = podBundle.path(forResource: "pose_landmarker_lite", ofType: "task") {
            return path
        }

        // Try main bundle
        if let path = Bundle.main.path(forResource: "pose_landmarker_lite", ofType: "task") {
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

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
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
    func updateConfig(_ config: [String: Any]) {
        applyConfig(config)

        poseLandmarker = nil
        frameId = 0
        latestSubmittedTimestamp = 0

        initializePoseLandmarker()
        print("[\(Self.TAG)] PoseLandmarker reinitialized with new config")
    }

    // MARK: - Dispose

    func dispose() {
        // Stop landmarker first — prevents new callbacks
        poseLandmarker = nil

        // Drain inferenceQueue to ensure no in-flight callbacks
        inferenceQueue.sync {}

        // Now safe to stop camera
        sessionQueue.sync {
            captureSession?.stopRunning()
            captureSession = nil
        }

        if let texId = cameraTexture != nil ? textureId : nil {
            textureRegistry?.unregisterTexture(texId)
        }
        cameraTexture = nil
        textureId = -1

        if let ptr = bufferPointer {
            pose_buffer_free(ptr)
            bufferPointer = nil
        }

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

        guard timestampMs > latestSubmittedTimestamp else { return }
        latestSubmittedTimestamp = timestampMs

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
        poseLandmarkData.withUnsafeBufferPointer { posePtr in
            worldLandmarkData.withUnsafeBufferPointer { worldPtr in
                pose_buffer_write(bufferPointer, frameId, posePtr.baseAddress, worldPtr.baseAddress)
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
