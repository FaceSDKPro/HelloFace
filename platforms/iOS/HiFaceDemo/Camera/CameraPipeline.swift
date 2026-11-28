@preconcurrency import AVFoundation
import HiFace

/// AVFoundation counterpart of Android CameraPreviewFragment. Manage permissions, session, lenses,
/// preview, and synchronous frames only; the SDK owns face flows, model threads, and business outcomes.
/// The camera must produce clear images; for face search, a camera with a wide dynamic range above
/// 105 dB is recommended.
/// @unchecked Sendable relies on isolation by sessionQueue, frameQueue, and controlLock.
/// 对应 Android `CameraPreviewFragment` 的 AVFoundation 适配层。
///
/// 这里只管理权限、会话、镜头、预览和同步送帧；人脸流程、模型线程与业务终态由 SDK 负责。
/// 摄像头需成像清晰，人脸搜索建议相机宽动态大于105DB。
/// `@unchecked Sendable` 依赖 `sessionQueue`、`frameQueue` 和 `controlLock` 的隔离约束。
final class CameraPipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    // A coalesced UI result carries the frame generation that produced its coordinates.
    private struct PendingDetection {
        let result: FaceDetectionResult
        let previewMirrored: Bool
        let generation: Int
    }

    // MARK: - Session and synchronized state
    // 会话与同步状态。

    let captureSession = AVCaptureSession()
    private let sdk: HiFaceSDK
    private let detectionConfiguration: FaceDetectionConfiguration
    private let settings: DemoCameraSettings
    private let mode: CameraDemoMode
    // Session configuration and device changes run here. SDK frame submission uses frameQueue.
    private let sessionQueue = DispatchQueue(
        label: "com.hiface.demo.camera.session",
        autoreleaseFrequency: .workItem
    )
    private let frameQueue = DispatchQueue(
        label: "com.hiface.demo.camera.frames",
        qos: .userInteractive,
        autoreleaseFrequency: .workItem
    )
    // Protect cross-queue control flags and pending deliveries; configure AVFoundation on sessionQueue.
    private let controlLock = NSLock()
    private var position: AVCaptureDevice.Position
    private var configured = false
    // Requested session state. analysisEnabled separately gates SDK delivery while preview can continue.
    private var wantsRunning = false
    private var analysisEnabled = true
    // Drop frame submissions while a lens change is in progress.
    private var inputTransitioning = false
    private var sessionUnavailable = false
    // Start/stop invalidates session callbacks. A pause or lens change also invalidates earlier frames.
    private var lifecycleGeneration = 0
    private var frameGeneration = 0
    // At most one main-actor delivery is queued. It takes the newest result under controlLock.
    private var pendingDetection: PendingDetection?
    private var detectionDeliveryScheduled = false
    // Suppress repeated frame errors with the same SDK code until useful output resumes.
    private var lastReportedError: HiFaceErrorCode?
    private var resolutionAdjusted = false
    private var reportedFrameWidth = 0
    private var reportedFrameHeight = 0
    // Protected by controlLock; update the app gate first, then serialize AVCaptureDevice changes on
    // sessionQueue.
    // 受 controlLock 保护；先更新应用侧门禁，再由 sessionQueue 串行修改 AVCaptureDevice。
    private var targetSessionFramesPerSecond: Int32
    // Throttle SDK submission on frameQueue even if the device delivers preview frames faster.
    private var applicationFrameIntervalSeconds: Double
    // Timestamp of the last SDK submission, in sample-buffer seconds on frameQueue.
    private var lastAcceptedFrameSeconds: Double?

    // MARK: - Main actor callbacks
    // 主 actor 回调。

    var onDetection: (@MainActor @Sendable (FaceDetectionResult, Bool, Bool) -> Void)?
    var onError: (@MainActor @Sendable (_ message: String, _ needsCameraSettings: Bool) -> Void)?
    var onMirroringChanged: (@MainActor @Sendable (Bool, Bool) -> Void)?
    var onAnalysisResolutionChanged: (@MainActor @Sendable (Int, Int, Bool) -> Void)?
    var onZoomFactorChanged: (@MainActor @Sendable (CGFloat, Bool) -> Void)?
    var onNotice: (@MainActor @Sendable (String) -> Void)?
    var onCameraAvailabilityChanged: (@MainActor @Sendable (Bool, String) -> Void)?
    var onStarted: (@MainActor @Sendable () -> Void)?

    #if DEBUG
    // Only UI-regression processes observe raw camera frames, independent of paused SDK analysis or an
    // empty library.
    // 仅 UI 回归进程观察原始相机帧，不依赖 SDK 是否暂停分析或人脸库是否为空。
    private let observesTestFrames = ProcessInfo.processInfo.arguments.contains("--camera-lifecycle-test")
    private var lastTestFrameTimestamp: Double = -.infinity // frameQueue only / 仅限 frameQueue
    var onTestFrame: (@MainActor @Sendable (Double) -> Void)?
    #endif

    init(
        sdk: HiFaceSDK,
        detectionConfiguration: FaceDetectionConfiguration = .default,
        settings: DemoCameraSettings = .load(),
        mode: CameraDemoMode
    ) {
        self.sdk = sdk
        self.detectionConfiguration = detectionConfiguration
        self.settings = settings
        position = settings.prefersBackCamera ? .back : .front
        self.mode = mode
        targetSessionFramesPerSecond = mode == .search ? CameraFrameRatePolicy.searchActive.preview : 30
        applicationFrameIntervalSeconds = Self.frameInterval(for: mode == .search ? CameraFrameRatePolicy.searchActive.analysis : 30)
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
    // 生命周期。

    @objc private func sessionInterrupted(_ notification: Notification) {
        if let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber,
           reason.intValue == AVCaptureSession.InterruptionReason.videoDeviceNotAvailableInBackground.rawValue {
            return // scenePhase 负责 inactive/background 暂停，不能把正常切换变成失败。 / scenePhase handles inactive/background pauses; ordinary transitions must not become failures.
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
            // A new start supersedes queued lens switches; do not carry an old switch lock into a new lifecycle.
            // 新一轮启动会取代仍在排队的镜头切换，不能把旧切换锁带入新生命周期。
            inputTransitioning = false
            sessionUnavailable = false
            lifecycleGeneration += 1
            invalidatePendingFrames()
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
            invalidatePendingFrames()
        }
        // The OS may suspend the process before queued background cleanup runs, while foreground start()
        // advances the lifecycle generation. Never cancel queued stop by generation; the shared serial queue
        // guarantees stop-before-start.
        // 退后台后进程可能在队列执行前被系统挂起；此时回前台的 start() 会推进生命周期代次。
        // 已排队的停止任务不能按代次取消；停止和启动共用串行队列，确保始终先停后启。
        sessionQueue.async { [captureSession] in
            if captureSession.isRunning { captureSession.stopRunning() }
        }
    }

    /// Pause analysis but retain preview while showing capture, liveness, or verification outcomes.
    /// 暂停分析但保留预览，用于展示采集、活体和验证终态。
    func pauseAnalysis() {
        withControlLock {
            analysisEnabled = false
            invalidatePendingFrames()
        }
    }

    func resumeAnalysis() {
        withControlLock {
            analysisEnabled = true
            invalidatePendingFrames()
            lastAcceptedFrameSeconds = nil
        }
        frameQueue.async { [weak self] in self?.lastReportedError = nil }
    }

    /// Update analysis throttling immediately and request device rate asynchronously; actual preview rate
    /// depends on hardware.
    /// 立即更新分析门禁，异步请求设备帧率；实际预览帧率取决于硬件支持。
    func setSearchIdle(_ idle: Bool) {
        guard mode == .search else { return }
        let rates = idle ? CameraFrameRatePolicy.searchIdle : CameraFrameRatePolicy.searchActive
        let changed = withControlLock { () -> Bool in
            guard targetSessionFramesPerSecond != rates.preview else { return false }
            targetSessionFramesPerSecond = rates.preview
            applicationFrameIntervalSeconds = Self.frameInterval(for: rates.analysis)
            lastAcceptedFrameSeconds = nil
            return true
        }
        guard changed else { return }
        sessionQueue.async { [weak self] in
            guard let self,
                  withControlLock({ targetSessionFramesPerSecond == rates.preview }) else { return }
            applyDeviceFrameRate(rates.preview)
        }
    }

    /// Returns true once the switch is reserved and SDK input is paused. Completion runs on the
    /// main actor after frames from the previous lens drain, if this session is still current.
    @MainActor
    func switchCamera(completion: @escaping @MainActor @Sendable (Bool) -> Void) -> Bool {
        let generation = withControlLock { () -> Int? in
            guard wantsRunning, !inputTransitioning, !sessionUnavailable else { return nil }
            inputTransitioning = true
            analysisEnabled = false
            invalidatePendingFrames()
            return lifecycleGeneration
        }
        guard let generation else { return false }
        sessionQueue.async { [weak self] in
            guard let self, isCurrentLifecycle(generation) else { return }
            let target = withControlLock {
                position == .front ? AVCaptureDevice.Position.back : .front
            }
            let usable = reconfigureInput(to: target)
            // Drain old-camera queued frames before allowing SDK flow recovery.
            // 排空旧镜头已入队的帧，再允许调用方恢复 SDK 流程。
            frameQueue.async { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrentLifecycle(generation) else { return }
                    let available = self.withControlLock {
                        self.inputTransitioning = false
                        return !self.sessionUnavailable
                    }
                    completion(usable && available)
                }
            }
        }
        return true
    }

    // MARK: - Session configuration
    // 会话配置。

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
        guard let actualPosition = installInput(preferredPosition: currentPosition) else {
            reportError(DemoL10n.text("无法打开所选相机"), generation: generation)
            return false
        }
        withControlLock { position = actualPosition }
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

    private func installInput(preferredPosition: AVCaptureDevice.Position) -> AVCaptureDevice.Position? {
        let alternate: AVCaptureDevice.Position = preferredPosition == .front ? .back : .front
        for candidate in [preferredPosition, alternate] {
            guard let device = Self.preferredDevice(position: candidate),
                  let input = try? AVCaptureDeviceInput(device: device),
                  captureSession.canAddInput(input) else {
                continue
            }
            captureSession.addInput(input)
            return candidate
        }
        return nil
    }

    private func applyResolutionFormat() -> Bool {
        guard let device = (captureSession.inputs.first as? AVCaptureDeviceInput)?.device,
              let format = Self.captureFormat(from: Self.captureFormats(for: device), tier: settings.analysisResolution,
                  frameRates: mode == .search ? CameraFrameRatePolicy.searchPreviewRates : [30]) else {
            return false
        }
        do {
            try device.lockForConfiguration()
        } catch {
            return false
        }
        defer { device.unlockForConfiguration() }
        // Setting activeFormat puts iOS into inputPriority automatically, preventing a quality preset from
        // overriding the selected format.
        // iOS 在设置 activeFormat 后自动进入 inputPriority，避免质量 preset 再覆盖所选格式。
        device.activeFormat = format
        let targetFramesPerSecond = withControlLock { targetSessionFramesPerSecond }
        // Lower hardware capture where possible even without exact target support; never assign durations outside the
        // format's advertised range.
        // 不支持精确目标时也尽量降低硬件采集；不能写入格式未声明的时长。
        if let duration = Self.frameDuration(for: device.activeFormat, target: targetFramesPerSecond) {
            Self.setFrameDuration(duration, on: device)
        }
        withControlLock { lastAcceptedFrameSeconds = nil }
        let displayMultiplier = Self.displayZoomMultiplier(for: device)
        let requestedZoom = CameraZoomPolicy.deviceFactor(
            displayMultiplier: displayMultiplier,
            minimum: device.minAvailableVideoZoomFactor,
            maximum: device.maxAvailableVideoZoomFactor,
            requestedDisplayFactor: settings.zoomRatio
        )
        device.videoZoomFactor = requestedZoom
        let actualDisplayZoom = CameraZoomPolicy.displayFactor(
            deviceFactor: device.videoZoomFactor,
            displayMultiplier: displayMultiplier
        )
        reportZoomFactor(
            actualDisplayZoom,
            constrained: abs(actualDisplayZoom - settings.zoomRatio) > 0.01
        )
        let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let actual = CameraFrameSize(width: Int(dimensions.width), height: Int(dimensions.height))
        let preferred = settings.analysisResolution.preferredSize
        withControlLock {
            resolutionAdjusted = actual.longSide != preferred.longSide || actual.shortSide != preferred.shortSide
            reportedFrameWidth = 0
            reportedFrameHeight = 0
        }
        return true
    }

    private struct CaptureFormats {
        var formats: [AVCaptureDevice.Format] = []
        var options: [CameraFormatOption] = []
    }

    private static func captureFormats(for device: AVCaptureDevice) -> CaptureFormats {
        var candidates = CaptureFormats()
        // Evaluate NV12 capabilities once per camera for both regular and search settings.
        for format in device.formats {
            let pixelFormat = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            guard (pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                   || pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
                  !format.unsupportedCaptureOutputClasses.contains(where: { $0 == AVCaptureVideoDataOutput.self })
            else { continue }
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            candidates.formats.append(format)
            candidates.options.append(CameraFormatOption(
                size: CameraFrameSize(width: Int(dimensions.width), height: Int(dimensions.height)),
                fieldOfView: format.videoFieldOfView,
                frameRateRanges: Self.frameRateRanges(for: format)
            ))
        }
        return candidates
    }

    private static func captureFormat(from candidates: CaptureFormats, tier: CameraAnalysisResolution,
                                      frameRates: [Double]) -> AVCaptureDevice.Format? {
        let index = CameraResolutionPolicy.selectIndex(
            from: candidates.options,
            tier: tier,
            sdkLimit: CameraFrameSize(width: HiFaceCameraFrame.maximumLongSidePixels,
                                      height: HiFaceCameraFrame.maximumShortSidePixels),
            preferredFrameRates: frameRates
        )
        return index.map { candidates.formats[$0] }
    }

    /// Request frame rate for the current format without rebuilding the session; app throttling still
    /// controls analysis on hardware fallback or setting failure.
    /// 按当前格式请求设备帧率，不重建会话；硬件回退或设置失败时仍由应用门禁控制分析频率。
    private func applyDeviceFrameRate(_ framesPerSecond: Int32) {
        guard configured,
              let device = (captureSession.inputs.first as? AVCaptureDeviceInput)?.device,
              let duration = Self.frameDuration(for: device.activeFormat, target: framesPerSecond) else { return }
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }
            Self.setFrameDuration(duration, on: device)
        } catch {
            // Lock contention or system policy may reject changes; captureOutput still drops frames early at the
            // same target rate.
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
    // 镜头切换。

    private func reconfigureInput(to target: AVCaptureDevice.Position) -> Bool {
        guard configured else {
            let generation = withControlLock {
                position = target
                invalidatePendingFrames()
                return lifecycleGeneration
            }
            reportMirroring(generation: generation)
            return true
        }
        guard let device = Self.preferredDevice(position: target),
              let replacement = try? AVCaptureDeviceInput(device: device) else {
            reportCurrentNotice(DemoL10n.text("当前设备没有可切换的摄像头"))
            return true
        }
        let previous = captureSession.inputs.first
        captureSession.beginConfiguration()
        if let previous { captureSession.removeInput(previous) }
        // Use the new camera's supported format first, then reselect by user preset after adding it; never
        // reuse the old camera's resolution.
        // 新镜头先使用自身支持的格式，加入后重新按用户档位选择，不能沿用旧镜头的分辨率。
        if captureSession.canSetSessionPreset(.inputPriority) {
            captureSession.sessionPreset = .inputPriority
        }
        let installed = installConfiguredInput(replacement)
        let restored = installed || installConfiguredInput(previous)
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
        }
        reportMirroring(generation: withControlLock { lifecycleGeneration })
        return true
    }

    private func installConfiguredInput(_ input: AVCaptureInput?) -> Bool {
        guard let input, captureSession.canAddInput(input) else { return false }
        captureSession.addInput(input)
        if applyResolutionFormat() { return true }
        captureSession.removeInput(input)
        return false
    }

    private static func preferredDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        // iOS 18 can convert virtual ultrawide internal zoomFactor to system-display 0.8x. Older systems and
        // front cameras use ordinary wide cameras with a safe minimum of 1.0x.
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

    private static func displayZoomMultiplier(for device: AVCaptureDevice) -> CGFloat {
        if #available(iOS 18.0, *) {
            let multiplier = device.displayVideoZoomFactorMultiplier
            if multiplier.isFinite && multiplier > 0 { return multiplier }
        }
        return 1
    }


    // MARK: - Frame delivery
    // 帧交付。

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
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let (generation, previewMirrored) = withControlLock({ () -> (Int, Bool)? in
            guard wantsRunning, analysisEnabled, !inputTransitioning, !sessionUnavailable else { return nil }
            if applicationFrameIntervalSeconds > 0, timestamp.isFinite,
               let previous = lastAcceptedFrameSeconds,
               timestamp >= previous,
               timestamp - previous < applicationFrameIntervalSeconds {
                return nil
            }
            if timestamp.isFinite { lastAcceptedFrameSeconds = timestamp }
            return (frameGeneration, position == .front)
        }) else { return }
        do {
            let frame = try HiFaceCameraFrame(
                pixelBuffer: pixelBuffer,
                rotation: .degrees0,
                isMirrored: previewMirrored
            )
            guard acceptFrame(width: frame.width, height: frame.height, generation: generation) else { return }
            switch sdk.processFrame(frame, configuration: detectionConfiguration) {
            case .success(let result):
                lastReportedError = nil
                // Only the detection screen draws this result. The other screens receive SDK flow callbacks.
                guard mode == .detection else { return }
                enqueueDetection(
                    result,
                    previewMirrored: previewMirrored,
                    generation: generation
                )
            case .failure(let error) where error.code == .notReady || error.code == .busy
                    || error.code == .processingFailed:
                // The flow coordinator already sends processingFailed to capture/liveness/verification callbacks; the
                // camera must not promote the same transient error into session failure. Without an active flow, drop
                // only that frame, matching Android.
                // 流程协调器已经把 processingFailed 交给录入/活体/验证回调；相机层不能再把
                // 同一个瞬时错误升级成会话故障。无活动流程时也与 Android 一样只丢弃该帧。
                break
            case .failure(let error):
                throw error
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
        generation: Int
    ) {
        let shouldSchedule = withControlLock { () -> Bool in
            guard wantsRunning, analysisEnabled, frameGeneration == generation else { return false }
            pendingDetection = PendingDetection(
                result: result,
                previewMirrored: previewMirrored,
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
            let latest = pendingDetection
            pendingDetection = nil
            guard wantsRunning, analysisEnabled, latest?.generation == frameGeneration else { return nil }
            return latest
        }
        guard let pending else { return }
        onDetection?(pending.result, pending.previewMirrored,
                     pending.previewMirrored != settings.mirrorsOverlayCoordinates)
    }

    // MARK: - Callback delivery
    // 回调交付。

    // The generation can change while the camera buffer is being wrapped.
    private func acceptFrame(width: Int, height: Int, generation: Int) -> Bool {
        let (current, fallback) = withControlLock { () -> (Bool, Bool?) in
            guard wantsRunning, analysisEnabled, frameGeneration == generation else { return (false, nil) }
            guard reportedFrameWidth != width || reportedFrameHeight != height else { return (true, nil) }
            reportedFrameWidth = width
            reportedFrameHeight = height
            return (true, resolutionAdjusted)
        }
        if let fallback {
            Task { @MainActor [weak self] in
                guard let self,
                      withControlLock({ wantsRunning && frameGeneration == generation }) else { return }
                onAnalysisResolutionChanged?(width, height, fallback)
            }
        }
        return current
    }

    private func reportFrameError(_ message: String, generation: Int) {
        Task { @MainActor [weak self] in
            guard let self,
                  withControlLock({ wantsRunning && frameGeneration == generation }) else { return }
            onError?(message, false)
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

    /// Retain session configuration during AVFoundation interruptions while preventing old frames from
    /// entering the SDK.
    /// AVFoundation 中断期间继续保留会话配置，但阻止旧帧进入 SDK。
    private func suspendForSessionRecovery() -> (lifecycle: Int, frame: Int)? {
        withControlLock {
            guard wantsRunning else { return nil }
            if !sessionUnavailable {
                sessionUnavailable = true
                invalidatePendingFrames()
            }
            return (lifecycleGeneration, frameGeneration)
        }
    }

    /// Resume on the camera-session queue after interruptions or media-service resets, avoiding main-thread
    /// blocking.
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
                // Let the screen invalidate the old SDK flow before admitting new frames, preventing state from
                // spanning an interruption.
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
        // Reuse exact device CMTime endpoints to avoid rounding outside fractional rates such as 7.5 FPS.
        // 端点直接复用设备给出的精确 CMTime，避免 7.5 等分数帧率的舍入越界。
        if selected.framesPerSecond == range.minFrameRate { return range.maxFrameDuration }
        if selected.framesPerSecond == range.maxFrameRate { return range.minFrameDuration }
        guard selected.framesPerSecond <= Double(Int32.max) else { return nil }
        return CMTime(value: 1, timescale: Int32(selected.framesPerSecond))
    }

    private static func setFrameDuration(_ duration: CMTime, on device: AVCaptureDevice) {
        // Manual durations raise an Objective-C exception while automatic frame rate is enabled.
        if #available(iOS 18.0, *), device.isAutoVideoFrameRateEnabled { return }
        if CMTimeCompare(device.activeVideoMinFrameDuration, duration) == 0,
           CMTimeCompare(device.activeVideoMaxFrameDuration, duration) == 0 { return }
        // Expand the allowed interval first so min <= max throughout the rate change.
        // 先扩展允许区间再收紧另一端，切换帧率时也保持 min <= max。
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
            onError?(message, AVCaptureDevice.authorizationStatus(for: .video) == .denied)
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
    // 同步。

    /// Call under controlLock. A queued main-actor delivery may still pick up a newer result.
    private func invalidatePendingFrames() {
        frameGeneration += 1
        pendingDetection = nil
    }

    private func withControlLock<T>(_ body: () -> T) -> T {
        controlLock.lock()
        defer { controlLock.unlock() }
        return body()
    }
}
