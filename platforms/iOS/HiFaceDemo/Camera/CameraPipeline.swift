@preconcurrency import AVFoundation
import HiFace

/// 对应 Android `CameraPreviewFragment` 的 AVFoundation 适配层。
///
/// 这里只管理权限、会话、镜头、预览和同步送帧；人脸流程、模型线程与业务终态由 SDK 负责。
/// `@unchecked Sendable` 依赖 `sessionQueue`、`frameQueue` 和 `controlLock` 的隔离约束。
final class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private struct PendingDetection {
        let result: FaceDetectionResult
        let previewMirrored: Bool
        let overlayMirrored: Bool
        let generation: Int
    }

    // MARK: - Session and synchronized state

    let captureSession = AVCaptureSession()
    private let sdk: HiFaceSDK
    private let detectionConfiguration: FaceDetectionConfiguration
    private let settings: DemoCameraSettings
    private let deliversDetectionResults: Bool
    // 活跃帧率也是该页面允许设置的上限；搜索页另允许降到 5 FPS。
    private let sessionFramesPerSecond: Int32
    private let minimumSessionFramesPerSecond: Int32
    private let sessionQueue = DispatchQueue(
        label: "com.hiface.demo.camera.session",
        autoreleaseFrequency: .workItem
    )
    private let frameQueue = DispatchQueue(
        label: "com.hiface.demo.camera.frames",
        qos: .userInteractive,
        autoreleaseFrequency: .workItem
    )
    private let controlLock = NSLock()
    private var position: AVCaptureDevice.Position = .front
    private var configured = false
    private var wantsRunning = false
    private var analysisEnabled = true
    private var inputTransitioning = false
    private var sessionUnavailable = false
    private var lifecycleGeneration = 0
    private var frameGeneration = 0
    private var pendingDetection: PendingDetection?
    private var detectionDeliveryScheduled = false
    private var lastReportedError: HiFaceErrorCode?
    private var resolutionAdjusted = false
    private var reportedFrameWidth = 0
    private var reportedFrameHeight = 0
    // 受 controlLock 保护；先更新应用侧门禁，再由 sessionQueue 串行修改 AVCaptureDevice。
    private var targetSessionFramesPerSecond: Int32
    private var applicationFrameIntervalSeconds: Double = 0
    private var lastAcceptedFrameSeconds: Double?

    // MARK: - Main actor callbacks

    var onDetection: (@MainActor @Sendable (FaceDetectionResult, Bool, Bool) -> Void)?
    var onError: (@MainActor @Sendable (String) -> Void)?
    var onMirroringChanged: (@MainActor @Sendable (Bool, Bool) -> Void)?
    var onAnalysisResolutionChanged: (@MainActor @Sendable (Int, Int, Bool) -> Void)?
    var onZoomFactorChanged: (@MainActor @Sendable (CGFloat, Bool) -> Void)?
    var onNotice: (@MainActor @Sendable (String) -> Void)?
    var onCameraAvailabilityChanged: (@MainActor @Sendable (Bool, String) -> Void)?
    var onStarted: (@MainActor @Sendable () -> Void)?

    #if DEBUG
    // 仅 UI 回归进程观察原始相机帧，不依赖 SDK 是否暂停分析或人脸库是否为空。
    private let observesTestFrames = ProcessInfo.processInfo.arguments.contains("--camera-lifecycle-test")
    private var lastTestFrameTimestamp: Double = -.infinity // frameQueue only
    var onTestFrame: (@MainActor @Sendable (Double) -> Void)?
    #endif

    init(
        sdk: HiFaceSDK,
        detectionConfiguration: FaceDetectionConfiguration = .default,
        settings: DemoCameraSettings = .load(),
        sessionFramesPerSecond: Int32 = 30,
        minimumSessionFramesPerSecond: Int32? = nil,
        deliversDetectionResults: Bool = true
    ) {
        let minimumFramesPerSecond = minimumSessionFramesPerSecond ?? sessionFramesPerSecond
        precondition(minimumFramesPerSecond > 0 && minimumFramesPerSecond <= sessionFramesPerSecond)
        self.sdk = sdk
        self.detectionConfiguration = detectionConfiguration
        self.settings = settings
        self.deliversDetectionResults = deliversDetectionResults
        self.sessionFramesPerSecond = sessionFramesPerSecond
        self.minimumSessionFramesPerSecond = minimumFramesPerSecond
        targetSessionFramesPerSecond = sessionFramesPerSecond
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterrupted(_:)),
            name: AVCaptureSession.wasInterruptedNotification,
            object: captureSession
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionFailed(_:)),
            name: AVCaptureSession.runtimeErrorNotification,
            object: captureSession
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded(_:)),
            name: AVCaptureSession.interruptionEndedNotification,
            object: captureSession
        )
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Lifecycle

    @objc private func sessionInterrupted(_ notification: Notification) {
        if let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber,
           reason.intValue == AVCaptureSession.InterruptionReason.videoDeviceNotAvailableInBackground.rawValue {
            return // scenePhase 负责 inactive/background 暂停，不能把正常切换变成失败。
        }
        guard let token = suspendForSessionRecovery() else { return }
        reportCameraAvailability(
            false,
            message: DemoL10n.text("相机暂被占用，可用后自动继续"),
            token: token
        )
    }

    @objc private func sessionInterruptionEnded(_ notification: Notification) {
        _ = notification
        recoverSession(message: DemoL10n.text("相机已恢复"))
    }

    @objc private func sessionFailed(_ notification: Notification) {
        let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
        if error?.domain == AVFoundationErrorDomain,
           error?.code == AVError.Code.mediaServicesWereReset.rawValue,
           let token = suspendForSessionRecovery() {
            reportCameraAvailability(
                false,
                message: DemoL10n.text("相机服务已重置，正在自动恢复"),
                token: token
            )
            recoverSession(message: DemoL10n.text("相机服务已恢复"))
            return
        }
        reportCurrentError(error?.localizedDescription ?? DemoL10n.text("相机运行失败，请重试"))
    }

    func start(analysisEnabled: Bool = true) {
        let generation = withControlLock {
            wantsRunning = true
            self.analysisEnabled = analysisEnabled
            // 新一轮启动会取代仍在排队的镜头切换，不能把旧切换锁带入新生命周期。
            inputTransitioning = false
            sessionUnavailable = false
            lifecycleGeneration += 1
            frameGeneration += 1
            return lifecycleGeneration
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startAuthorized(generation: generation)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted {
                    startAuthorized(generation: generation)
                } else {
                    reportError(DemoL10n.text("未获得相机权限，请在系统设置中允许访问"), generation: generation)
                }
            }
        case .restricted:
            reportError(DemoL10n.text("相机访问受限，请检查屏幕使用时间或联系管理员"), generation: generation)
        default:
            reportError(DemoL10n.text("未获得相机权限，请在系统设置中允许访问"), generation: generation)
        }
    }

    func stop() {
        withControlLock {
            wantsRunning = false
            analysisEnabled = false
            inputTransitioning = false
            sessionUnavailable = false
            lifecycleGeneration += 1
            frameGeneration += 1
            pendingDetection = nil
        }
        // 退后台后进程可能在队列执行前被系统挂起；此时回前台的 start() 会推进生命周期代次。
        // 已排队的停止任务不能按代次取消；停止和启动共用串行队列，确保始终先停后启。
        sessionQueue.async { [captureSession] in
            if captureSession.isRunning { captureSession.stopRunning() }
        }
    }

    /// 暂停分析但保留预览，用于展示采集、活体和验证终态。
    func pauseAnalysis() {
        withControlLock {
            analysisEnabled = false
            frameGeneration += 1
            pendingDetection = nil
        }
    }

    func resumeAnalysis() {
        withControlLock {
            analysisEnabled = true
            frameGeneration += 1
            lastAcceptedFrameSeconds = nil
        }
        frameQueue.async { [weak self] in self?.lastReportedError = nil }
    }

    /// 立即更新分析门禁，异步请求设备帧率；实际预览帧率取决于硬件支持。
    func setSessionFrameRate(_ framesPerSecond: Int32) {
        precondition(framesPerSecond >= minimumSessionFramesPerSecond
            && framesPerSecond <= sessionFramesPerSecond)
        let changed = withControlLock { () -> Bool in
            guard targetSessionFramesPerSecond != framesPerSecond else { return false }
            targetSessionFramesPerSecond = framesPerSecond
            applicationFrameIntervalSeconds = Self.frameInterval(for: framesPerSecond)
            lastAcceptedFrameSeconds = nil
            return true
        }
        guard changed else { return }
        sessionQueue.async { [weak self] in
            guard let self,
                  withControlLock({ targetSessionFramesPerSecond == framesPerSecond }) else { return }
            applyDeviceFrameRate(framesPerSecond)
        }
    }

    func switchCamera(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        let generation = withControlLock { () -> Int? in
            guard wantsRunning, !inputTransitioning, !sessionUnavailable else { return nil }
            inputTransitioning = true
            frameGeneration += 1
            pendingDetection = nil
            return lifecycleGeneration
        }
        guard let generation else { return }
        sessionQueue.async { [weak self] in
            guard let self, isCurrentLifecycle(generation) else { return }
            let target = withControlLock {
                position == .front ? AVCaptureDevice.Position.back : .front
            }
            let usable = reconfigureInput(to: target)
            // 排空旧镜头已入队的帧，再允许调用方恢复 SDK 流程。
            frameQueue.async { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentLifecycle(generation) else { return }
                    self.withControlLock { self.inputTransitioning = false }
                    completion(usable)
                }
            }
        }
    }

    // MARK: - Session configuration

    private func startAuthorized(generation: Int) {
        sessionQueue.async { [weak self] in
            guard let self, isCurrentLifecycle(generation) else { return }
            guard configureIfNeeded(generation: generation), isCurrentLifecycle(generation) else { return }
            if !captureSession.isRunning { captureSession.startRunning() }
            guard captureSession.isRunning else {
                reportError(DemoL10n.text("相机启动失败，请重试"), generation: generation)
                return
            }
            withControlLock { sessionUnavailable = false }
            reportMirroring(generation: generation)
            Task { @MainActor [weak self] in
                guard let self, isCurrentLifecycle(generation) else { return }
                onStarted?()
            }
        }
    }

    private func configureIfNeeded(generation: Int) -> Bool {
        guard !configured else { return true }
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }
        captureSession.inputs.forEach(captureSession.removeInput)
        captureSession.outputs.forEach(captureSession.removeOutput)
        let currentPosition = withControlLock { position }
        guard installInput(position: currentPosition) else {
            reportError(DemoL10n.text("无法打开所选相机"), generation: generation)
            return false
        }
        guard applyResolutionFormat() else {
            reportError(DemoL10n.text("当前相机不支持可用的分析分辨率"), generation: generation)
            return false
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.automaticallyConfiguresOutputBufferDimensions = false
        output.deliversPreviewSizedOutputBuffers = false
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String:
                kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        ]
        output.setSampleBufferDelegate(self, queue: frameQueue)
        guard captureSession.canAddOutput(output) else {
            reportError(DemoL10n.text("相机不支持 NV12 分析输出"), generation: generation)
            return false
        }
        captureSession.addOutput(output)
        configureOutputConnections()
        configured = true
        return true
    }

    private func installInput(position: AVCaptureDevice.Position) -> Bool {
        guard let device = preferredDevice(position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              captureSession.canAddInput(input) else {
            return false
        }
        captureSession.addInput(input)
        return true
    }

    private func applyResolutionFormat() -> Bool {
        guard let device = (captureSession.inputs.first as? AVCaptureDeviceInput)?.device else {
            return false
        }
        // 尺寸与 NV12 是 SDK 输入约束；15/5 FPS 是分析目标，不能排除固定帧率的 Mac 摄像头。
        let formats = device.formats.filter { format in
            let pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            return (pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                    || pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
                && !format.unsupportedCaptureOutputClasses.contains { $0 == AVCaptureVideoDataOutput.self }
        }
        let options = formats.map { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            return CameraFormatOption(
                size: CameraFrameSize(width: Int(dimensions.width), height: Int(dimensions.height)),
                fieldOfView: format.videoFieldOfView,
                frameRateRanges: Self.frameRateRanges(for: format)
            )
        }
        guard let index = CameraResolutionPolicy.selectIndex(
            from: options,
            tier: settings.analysisResolution,
            sdkLimit: CameraFrameSize(
                width: HiFaceCameraFrame.maximumLongSidePixels,
                height: HiFaceCameraFrame.maximumShortSidePixels
            ),
            preferredFrameRates: [Double(sessionFramesPerSecond), Double(minimumSessionFramesPerSecond)]
        ) else { return false }
        do {
            try device.lockForConfiguration()
        } catch {
            return false
        }
        defer { device.unlockForConfiguration() }
        // iOS 在设置 activeFormat 后自动进入 inputPriority，避免质量 preset 再覆盖所选格式。
        device.activeFormat = formats[index]
        let targetFramesPerSecond = withControlLock { targetSessionFramesPerSecond }
        // 不支持 5 FPS 时也尽量降低硬件采集；不能写入格式未声明的时长。
        if let duration = Self.frameDuration(for: device.activeFormat, target: targetFramesPerSecond) {
            Self.setFrameDuration(duration, on: device)
        }
        withControlLock {
            applicationFrameIntervalSeconds = Self.frameInterval(for: targetSessionFramesPerSecond)
            lastAcceptedFrameSeconds = nil
        }
        let displayMultiplier: CGFloat
        if #available(iOS 18.0, *) {
            displayMultiplier = max(device.displayVideoZoomFactorMultiplier, .leastNonzeroMagnitude)
        } else {
            // iOS 15–17 没有系统显示倍率换算，使用普通广角的真实 1.0x，不能冒险写入 0.8。
            displayMultiplier = 1
        }
        let requestedZoom = CameraZoomPolicy.deviceFactor(
            displayMultiplier: displayMultiplier,
            minimum: device.minAvailableVideoZoomFactor,
            maximum: device.maxAvailableVideoZoomFactor
        )
        device.videoZoomFactor = requestedZoom
        let actualDisplayZoom = CameraZoomPolicy.displayFactor(
            deviceFactor: device.videoZoomFactor,
            displayMultiplier: displayMultiplier
        )
        reportZoomFactor(
            actualDisplayZoom,
            constrained: abs(actualDisplayZoom - CameraZoomPolicy.preferredDisplayFactor) > 0.01
        )
        let actual = options[index].size
        let preferred = settings.analysisResolution.preferredSize
        withControlLock {
            resolutionAdjusted = actual.longSide != preferred.longSide || actual.shortSide != preferred.shortSide
            reportedFrameWidth = 0
            reportedFrameHeight = 0
        }
        return true
    }

    /// 按当前格式请求设备帧率，不重建会话；硬件回退或设置失败时仍由应用门禁控制分析频率。
    private func applyDeviceFrameRate(_ framesPerSecond: Int32) {
        guard configured,
              let device = (captureSession.inputs.first as? AVCaptureDeviceInput)?.device,
              let duration = Self.frameDuration(for: device.activeFormat, target: framesPerSecond) else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            // 系统启用自动帧率时手工写时长会抛 Objective-C 异常，不能依赖 Swift catch。
            if #available(iOS 18.0, *), device.isAutoVideoFrameRateEnabled { return }
            Self.setFrameDuration(duration, on: device)
        } catch {
            // 锁竞争或系统策略可能拒绝动态修改；captureOutput 仍按相同目标帧率提前丢帧。
        }
    }

    private func configureOutputConnections() {
        for output in captureSession.outputs {
            guard let connection = output.connection(with: .video) else { continue }
            if connection.isVideoOrientationSupported { connection.videoOrientation = .portrait }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }

    // MARK: - Camera switching

    private func reconfigureInput(to target: AVCaptureDevice.Position) -> Bool {
        guard configured else {
            let generation = withControlLock {
                position = target
                frameGeneration += 1
                pendingDetection = nil
                return lifecycleGeneration
            }
            reportMirroring(generation: generation)
            return true
        }
        guard let device = preferredDevice(position: target),
              let replacement = try? AVCaptureDeviceInput(device: device) else {
            reportCurrentNotice(DemoL10n.text("当前设备没有可切换的摄像头"))
            return true
        }
        let previousInputs = captureSession.inputs
        captureSession.beginConfiguration()
        previousInputs.forEach(captureSession.removeInput)
        // 新镜头先使用自身支持的格式，加入后重新按用户档位选择，不能沿用旧镜头的分辨率。
        if captureSession.canSetSessionPreset(.inputPriority) {
            captureSession.sessionPreset = .inputPriority
        }
        var installed = false
        var restored = true
        if captureSession.canAddInput(replacement) {
            captureSession.addInput(replacement)
            installed = applyResolutionFormat()
            if !installed {
                captureSession.removeInput(replacement)
                restored = restore(inputs: previousInputs)
            }
        } else {
            restored = restore(inputs: previousInputs)
        }
        configureOutputConnections()
        captureSession.commitConfiguration()
        guard installed else {
            if restored {
                reportCurrentNotice(DemoL10n.text("无法切换摄像头，已保留原摄像头"))
            } else {
                configured = false
                reportCurrentError(DemoL10n.text("切换摄像头失败，且无法恢复原摄像头"))
            }
            return restored
        }
        withControlLock {
            position = target
            pendingDetection = nil
            reportedFrameWidth = 0
            reportedFrameHeight = 0
        }
        reportMirroring(generation: withControlLock { lifecycleGeneration })
        return true
    }

    private func restore(inputs: [AVCaptureInput]) -> Bool {
        var allRestored = true
        for input in inputs {
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
            } else {
                allRestored = false
            }
        }
        return allRestored && applyResolutionFormat()
    }

    private func preferredDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // iOS 18 可把虚拟超广角镜头的内部 zoomFactor 换算成系统 UI 使用的 0.8x。
        // 较早系统或前摄使用普通广角，最低安全值为 1.0x。
        if position == .back {
            if #available(iOS 18.0, *) {
                for type in [AVCaptureDevice.DeviceType.builtInTripleCamera, .builtInDualWideCamera] {
                    if let device = AVCaptureDevice.default(type, for: .video, position: position) {
                        return device
                    }
                }
            }
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    // MARK: - Frame delivery

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        #if DEBUG
        if observesTestFrames, timestamp.isFinite, timestamp - lastTestFrameTimestamp >= 0.25 {
            lastTestFrameTimestamp = timestamp
            let token = withControlLock { wantsRunning ? lifecycleGeneration : nil }
            if let token {
                Task { @MainActor [weak self] in
                    guard let self, isCurrentLifecycle(token) else { return }
                    onTestFrame?(timestamp)
                }
            }
        }
        #endif
        guard let generation = withControlLock({ () -> Int? in
            guard wantsRunning, analysisEnabled, !inputTransitioning, !sessionUnavailable else { return nil }
            if applicationFrameIntervalSeconds > 0, timestamp.isFinite,
               let previous = lastAcceptedFrameSeconds,
               timestamp >= previous,
               timestamp - previous < applicationFrameIntervalSeconds {
                return nil
            }
            if timestamp.isFinite { lastAcceptedFrameSeconds = timestamp }
            return frameGeneration
        }) else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        do {
            let mirroring = withControlLock { () -> (preview: Bool, overlay: Bool) in
                let preview = position == .front
                return (preview, preview != settings.mirrorsOverlayCoordinates)
            }
            let frame = try HiFaceCameraFrame(
                pixelBuffer: pixelBuffer,
                rotation: .degrees0,
                isMirrored: mirroring.preview
            )
            reportResolutionIfNeeded(width: frame.width, height: frame.height, generation: generation)
            switch sdk.processFrame(frame, configuration: detectionConfiguration) {
            case .success(let result):
                lastReportedError = nil
                // 搜索已有完整 onFrame 回调；不再另发检测结果使主线程和 SwiftUI 更新两遍。
                guard deliversDetectionResults else { return }
                enqueueDetection(
                    result,
                    previewMirrored: mirroring.preview,
                    overlayMirrored: mirroring.overlay,
                    generation: generation
                )
            case .failure(let error) where error.code == .notReady || error.code == .busy
                    || error.code == .processingFailed:
                // 流程协调器已经把 processingFailed 交给录入/活体/验证回调；相机层不能再把
                // 同一个瞬时错误升级成会话故障。无活动流程时也与 Android 一样只丢弃该帧。
                break
            case .failure(let error):
                guard lastReportedError != error.code else { return }
                lastReportedError = error.code
                reportFrameError(DemoErrorPresentation.message(for: error), generation: generation)
            }
        } catch let error as HiFaceError {
            guard lastReportedError != error.code else { return }
            lastReportedError = error.code
            reportFrameError(DemoErrorPresentation.message(for: error), generation: generation)
        } catch {
            reportFrameError(error.localizedDescription, generation: generation)
        }
    }

    private func enqueueDetection(
        _ result: FaceDetectionResult,
        previewMirrored: Bool,
        overlayMirrored: Bool,
        generation: Int
    ) {
        let shouldSchedule = withControlLock { () -> Bool in
            guard wantsRunning, analysisEnabled, frameGeneration == generation else { return false }
            pendingDetection = PendingDetection(
                result: result,
                previewMirrored: previewMirrored,
                overlayMirrored: overlayMirrored,
                generation: generation
            )
            guard !detectionDeliveryScheduled else { return false }
            detectionDeliveryScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        Task { @MainActor [weak self] in self?.deliverLatestDetection() }
    }

    @MainActor
    private func deliverLatestDetection() {
        let pending = withControlLock { () -> PendingDetection? in
            detectionDeliveryScheduled = false
            guard wantsRunning, analysisEnabled,
                  let pendingDetection,
                  pendingDetection.generation == frameGeneration else {
                self.pendingDetection = nil
                return nil
            }
            self.pendingDetection = nil
            return pendingDetection
        }
        guard let pending else { return }
        onDetection?(pending.result, pending.previewMirrored, pending.overlayMirrored)
    }

    // MARK: - Callback delivery

    private func reportResolutionIfNeeded(width: Int, height: Int, generation: Int) {
        let fallback = withControlLock { () -> Bool? in
            guard wantsRunning, analysisEnabled, frameGeneration == generation,
                  reportedFrameWidth != width || reportedFrameHeight != height else { return nil }
            reportedFrameWidth = width
            reportedFrameHeight = height
            return resolutionAdjusted
        }
        guard let fallback else { return }
        Task { @MainActor [weak self] in
            guard let self,
                  withControlLock({ wantsRunning && frameGeneration == generation }) else { return }
            onAnalysisResolutionChanged?(width, height, fallback)
        }
    }

    private func reportFrameError(_ message: String, generation: Int) {
        Task { @MainActor [weak self] in
            guard let self,
                  withControlLock({ wantsRunning && frameGeneration == generation }) else { return }
            onError?(message)
        }
    }

    private func reportZoomFactor(_ factor: CGFloat, constrained: Bool) {
        let generation = withControlLock { lifecycleGeneration }
        Task { @MainActor [weak self] in
            guard let self, isCurrentLifecycle(generation) else { return }
            onZoomFactorChanged?(factor, constrained)
        }
    }

    private func reportCurrentNotice(_ message: String) {
        let generation = withControlLock { lifecycleGeneration }
        Task { @MainActor [weak self] in
            guard let self, isCurrentLifecycle(generation) else { return }
            onNotice?(message)
        }
    }

    private func reportCurrentError(_ message: String) {
        reportError(message, generation: withControlLock { lifecycleGeneration })
    }

    /// AVFoundation 中断期间继续保留会话配置，但阻止旧帧进入 SDK。
    private func suspendForSessionRecovery() -> (lifecycle: Int, frame: Int)? {
        withControlLock {
            guard wantsRunning else { return nil }
            if !sessionUnavailable {
                sessionUnavailable = true
                frameGeneration += 1
                pendingDetection = nil
            }
            return (lifecycleGeneration, frameGeneration)
        }
    }

    /// 中断结束或媒体服务重置后在相机会话队列恢复，避免阻塞主线程。
    private func recoverSession(message: String) {
        guard let token = withControlLock({ () -> (lifecycle: Int, frame: Int)? in
            guard wantsRunning, sessionUnavailable else { return nil }
            return (lifecycleGeneration, frameGeneration)
        }) else { return }
        sessionQueue.async { [weak self] in
            guard let self, isCurrentRecovery(token) else { return }
            if !captureSession.isRunning { captureSession.startRunning() }
            guard captureSession.isRunning else {
                reportError(DemoL10n.text("相机恢复失败，请重试"), generation: token.lifecycle)
                return
            }
            Task { @MainActor [weak self] in
                guard let self, isCurrentRecovery(token) else { return }
                // 先让页面作废旧 SDK 流程，再开放新帧，避免中断前后的流程状态串联。
                onCameraAvailabilityChanged?(true, message)
                let resumed = withControlLock { () -> Bool in
                    guard wantsRunning,
                          lifecycleGeneration == token.lifecycle,
                          frameGeneration == token.frame,
                          sessionUnavailable else { return false }
                    sessionUnavailable = false
                    return true
                }
                guard resumed else { return }
                reportMirroring(generation: token.lifecycle)
                onStarted?()
            }
        }
    }

    private func reportCameraAvailability(
        _ available: Bool,
        message: String,
        token: (lifecycle: Int, frame: Int)
    ) {
        Task { @MainActor [weak self] in
            guard let self, isCurrentRecovery(token) else { return }
            onCameraAvailabilityChanged?(available, message)
        }
    }

    private func isCurrentRecovery(_ token: (lifecycle: Int, frame: Int)) -> Bool {
        withControlLock {
            wantsRunning
                && lifecycleGeneration == token.lifecycle
                && frameGeneration == token.frame
                && sessionUnavailable
        }
    }

    private static func frameDuration(for format: AVCaptureDevice.Format, target: Int32) -> CMTime? {
        let ranges = format.videoSupportedFrameRateRanges
        guard let selected = CameraFrameRatePolicy.select(
            target: Double(target), ranges: frameRateRanges(for: format)
        ) else { return nil }
        let range = ranges[selected.rangeIndex]
        // 端点直接复用设备给出的精确 CMTime，避免 7.5 等分数帧率的舍入越界。
        if selected.framesPerSecond == range.minFrameRate { return range.maxFrameDuration }
        if selected.framesPerSecond == range.maxFrameRate { return range.minFrameDuration }
        guard selected.framesPerSecond <= Double(Int32.max) else { return nil }
        return CMTime(value: 1, timescale: Int32(selected.framesPerSecond))
    }

    private static func setFrameDuration(_ duration: CMTime, on device: AVCaptureDevice) {
        if CMTimeCompare(device.activeVideoMinFrameDuration, duration) == 0,
           CMTimeCompare(device.activeVideoMaxFrameDuration, duration) == 0 { return }
        // 先扩展允许区间再收紧另一端，15/5 FPS 切换过程中也保持 min <= max。
        if CMTimeCompare(duration, device.activeVideoMinFrameDuration) >= 0 {
            device.activeVideoMaxFrameDuration = duration
            device.activeVideoMinFrameDuration = duration
        } else {
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
        }
    }

    private static func frameRateRanges(for format: AVCaptureDevice.Format) -> [CameraFrameRateRange] {
        format.videoSupportedFrameRateRanges.map {
            CameraFrameRateRange(minimum: $0.minFrameRate, maximum: $0.maxFrameRate)
        }
    }

    private static func frameInterval(for framesPerSecond: Int32) -> Double {
        max(0, 1 / Double(framesPerSecond) - 0.002)
    }

    private func reportError(_ message: String, generation: Int) {
        Task { @MainActor [weak self] in
            guard let self, isCurrentLifecycle(generation) else { return }
            onError?(message)
        }
    }

    private func reportMirroring(generation: Int) {
        let mirroring = withControlLock { () -> (preview: Bool, overlay: Bool) in
            let preview = position == .front
            return (preview, preview != settings.mirrorsOverlayCoordinates)
        }
        Task { @MainActor [weak self] in
            guard let self, isCurrentLifecycle(generation) else { return }
            onMirroringChanged?(mirroring.preview, mirroring.overlay)
        }
    }

    private func isCurrentLifecycle(_ generation: Int) -> Bool {
        withControlLock { wantsRunning && lifecycleGeneration == generation }
    }

    // MARK: - Synchronization

    private func withControlLock<T>(_ body: () -> T) -> T {
        controlLock.lock()
        defer { controlLock.unlock() }
        return body()
    }
}
