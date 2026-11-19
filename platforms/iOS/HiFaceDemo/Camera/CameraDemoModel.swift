import Foundation
import AVFoundation
import HiFace
import SwiftUI

/// Demo screen state; FaceFlowOutcome and FaceSearchEndReason still represent SDK business outcomes.
/// Demo 页面状态；SDK 的业务终态仍由 `FaceFlowOutcome` 和 `FaceSearchEndReason` 表达。
enum CameraDemoPhase: Equatable {
    case preparing
    case selectingReference
    case running
    case completed
    case failed
    case needsReference

    /// Only these phases resume processing when the camera returns.
    var needsCameraFlow: Bool { self == .preparing || self == .running }
}

/// Camera-screen coordinator connecting AVFoundation, SDK requests, and SwiftUI state. UI and Search
/// groups own text mappings.
/// 相机能力页面的协调器：连接 AVFoundation、SDK 请求和 SwiftUI 展示状态。
/// 文案映射由 UI 与 Search 分组负责。
@MainActor
final class CameraDemoModel: ObservableObject {
    // Demo countdown duration for the final stable-capture prompt, expressed in milliseconds.
    private static let captureStableCountdownMilliseconds: Int64 = 700

    // MARK: - Published presentation state
    // 公开的展示状态。

    @Published var detection: FaceDetectionResult?
    // Preview mirroring and overlay coordinate correction are tracked separately.
    @Published var previewMirrored = true
    @Published var overlayMirrored = true
    @Published var cameraResolution = DemoL10n.text("等待相机画面")
    @Published var cameraZoom = DemoL10n.text("等待倍率")
    @Published var cameraNotice: String?
    @Published var status = DemoL10n.text("正在启动…")
    @Published var detail: String?
    @Published var alignedFace: CGImage?
    @Published var enrollmentFaceID = ""
    @Published var enrollmentGroup = ""
    // A duplicate search-library ID needs a second, explicit replacement confirmation.
    @Published var confirmsSearchOverwrite = false
    @Published private(set) var isSavingCapture = false
    @Published private(set) var enrollmentCompleted = false
    @Published private(set) var phase: CameraDemoPhase = .preparing
    @Published private(set) var cameraReady = false
    @Published private(set) var needsCameraSettings = false
    @Published private(set) var failureAllowsRetry = true
    @Published private(set) var isSwitchingCamera = false
    // Feature paired with alignedFace while the capture waits for confirmation.
    @Published private(set) var pendingReferenceFeature: String?
    @Published private(set) var referenceFaceIDs: [String] = []
    @Published private(set) var selectedReferenceID: String?
    // Fraction of the current countdown remaining, from 1 at start to 0 at expiry.
    @Published private(set) var actionCountdownProgress: Double = 1
    @Published private(set) var searchOverlay = FaceSearchOverlayState()
    @Published private(set) var searchDetectedCount = 0
    @Published private(set) var searchSelectedCount = 0
    @Published private(set) var searchConfiguration = DemoFaceSearchConfiguration.recommended

    var searchFrame: FaceSearchFrame? { searchOverlay.frame }

    #if DEBUG
    @Published private(set) var cameraTestFrameTimestamp: Double = 0
    #endif

    var cameraDisplayMetrics: String { "\(cameraResolution) · \(cameraZoom)" }

    // MARK: - SDK and lifecycle state
    // SDK 与生命周期状态。

    // This model creates and closes the SDK; the camera pipeline reuses the same instance.
    // 当前模型负责创建和关闭 SDK，相机管线复用同一实例。
    let sdk: HiFaceSDK
    let pipeline: CameraPipeline
    // nil uses the camera screen’s default challenge. An empty array explicitly requests no actions.
    private let recognitionActions: [FaceAction]?
    private let recognitionSilent: Bool
    private let recognitionReferenceID: String?
    @Published private(set) var completedPassed = false
    private let mode: CameraDemoMode
    let enrollsInSearchLibrary: Bool
    // Capture, liveness, and verification finish once. Search keeps its session across scene pauses.
    private var request: FaceRequest?
    private var searchSession: FaceSearchSession?
    private var lastSearchError: HiFaceError?
    private var actionCountdownTask: Task<Void, Never>?
    private var actionCountdown = FaceActionCountdown()
    private var actionStepCount = 0
    private var searchStaleTask: Task<Void, Never>?
    // Accumulate frame and terminal search callbacks here before publishing the visible overlay.
    private var searchDisplayState = FaceSearchOverlayState()
    private var searchExpirySchedule = FaceSearchOverlayExpirySchedule()
    // Owns the confirmed search-library save until it completes or the screen cancels it.
    private var enrollmentTask: Task<Void, Never>?
    // SDK action budget used by the visible countdown; the SDK decides the terminal outcome.
    private var actionTimeoutMilliseconds: Int64 = 0
    // The page remains started while suspended. Leaving the page closes its search session.
    private var started = false
    private var suspended = false

    init(mode: CameraDemoMode, enrollsInSearchLibrary: Bool = false,
         recognitionActions: [FaceAction]? = nil, recognitionSilent: Bool = true,
         recognitionReferenceID: String? = nil) {
        self.recognitionActions = recognitionActions
        self.recognitionSilent = recognitionSilent
        self.recognitionReferenceID = recognitionReferenceID
        self.mode = mode
        self.enrollsInSearchLibrary = enrollsInSearchLibrary
        sdk = HiFaceSDK()
        let detectionConfiguration = mode == .detection
            ? (try? FaceDetectionConfiguration(maxFaces: 10, includesDetailedLandmarks: true)) ?? .default
            : FaceDetectionConfiguration.default
        // Search defaults to 640x480; saved camera settings take precedence.
        // 搜索默认 640×480，已保存的相机设置优先。
        let cameraSettings = DemoCameraSettings.load(
            defaultAnalysisResolution: mode == .search ? .low : .medium
        )
        pipeline = CameraPipeline(
            sdk: sdk,
            detectionConfiguration: detectionConfiguration,
            settings: cameraSettings,
            // Search uses 15 FPS active and 10 FPS idle preview, with 5 FPS idle SDK analysis.
            // 搜索活跃 15 FPS、待机预览 10 FPS，待机 SDK 分析保持 5 FPS。
            sessionFramesPerSecond: mode == .search ? 15 : 30,
            minimumSessionFramesPerSecond: mode == .search ? 10 : nil,
            deliversDetectionResults: mode != .search
        )
        pipeline.onDetection = { [weak self] result, previewMirrored, overlayMirrored in
            guard let self, self.started else { return }
            detection = result
            self.previewMirrored = previewMirrored
            self.overlayMirrored = overlayMirrored
            if self.mode == .detection {
                phase = .running
                status = result.faces.isEmpty
                    ? DemoL10n.text("未检测到人脸")
                    : DemoL10n.text("检测到 {0} 张人脸", [String(describing: result.faces.count)])
                detail = result.faces.first.map(Self.detectionDetail)
            }
        }
        pipeline.onMirroringChanged = { [weak self] previewMirrored, overlayMirrored in
            guard let self, self.started else { return }
            self.previewMirrored = previewMirrored
            self.overlayMirrored = overlayMirrored
        }
        pipeline.onAnalysisResolutionChanged = { [weak self] width, height, fallback in
            guard let self, self.started else { return }
            cameraResolution = "\(width) × \(height)" + (fallback ? DemoL10n.text(" · 已适配") : "")
        }
        pipeline.onZoomFactorChanged = { [weak self] factor, constrained in
            guard let self, self.started else { return }
            let value = String(format: "%.1f×", factor)
            cameraZoom = constrained ? DemoL10n.text("{0} · 镜头限制", [String(describing: value)]) : value
        }
        pipeline.onNotice = { [weak self] message in
            guard let self, self.started else { return }
            cameraNotice = message
        }
        pipeline.onCameraAvailabilityChanged = { [weak self] available, message in
            self?.handleCameraAvailability(available: available, message: message)
        }
        pipeline.onError = { [weak self] message in self?.handleCameraError(message) }
        pipeline.onStarted = { [weak self] in self?.cameraDidStart() }
        #if DEBUG
        pipeline.onTestFrame = { [weak self] timestamp in self?.cameraTestFrameTimestamp = timestamp }
        #endif
    }

    func start() {
        if started {
            guard suspended else { return }
            suspended = false
            cameraReady = false
            pipeline.start(analysisEnabled: false)
            return
        }
        started = true
        suspended = false
        cameraReady = false
        if mode == .capture { enrollmentCompleted = false }
        // Resume after camera access is granted in Settings; reread references after enrollment.
        // 从系统设置允许相机访问后恢复；从录入页返回时重新读取参考身份。
        if needsCameraSettings, AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            needsCameraSettings = false
            phase = .preparing
        }
        if mode == .verification, phase == .needsReference || phase == .selectingReference {
            phase = .preparing
        }
        if mode == .capture, !enrollsInSearchLibrary { refreshReferenceFaces() }
        // Retain completed previews and reference selection across permission prompts, backgrounding, and
        // temporary navigation away.
        // 权限弹窗、切后台或临时离开页面后，保留已完成的预览和参考身份选择。
        pipeline.start(analysisEnabled: false)
    }

    // Start or resume SDK work only after the current camera configuration reports readiness.
    private func cameraDidStart() {
        guard started, !suspended, !isSwitchingCamera else { return }
        cameraReady = true
        if phase.needsCameraFlow {
            if mode == .search, let searchSession {
                searchSession.resume()
                phase = .running
                status = DemoL10n.text("正在准备")
                detail = DemoL10n.text("准备完成后自动开始")
            } else {
                startFlowIfNeeded()
            }
        }
        if phase == .running { pipeline.resumeAnalysis() }
    }

    // Leaving the page closes search and camera resources; the model retains its SDK until deinit.
    func stop() {
        guard started else { return }
        started = false
        suspended = false
        cancelPendingCameraWork()
        searchSession?.close()
        searchSession = nil
        pipeline.stop()
        lastSearchError = nil
    }

    /// Retain the search session in the background; start() resumes it on foreground return.
    /// 后台保留搜索会话，返回前台由 start() 恢复。
    func suspend() {
        guard started, !suspended else { return }
        suspended = true
        cancelPendingCameraWork()
        searchSession?.pause()
        if phase.needsCameraFlow {
            phase = .preparing
            status = DemoL10n.text("返回前台后恢复相机")
            detail = mode == .search
                ? FaceSearchPresentation.configurationText(searchConfiguration)
                : DemoL10n.text("当前流程将在相机恢复后重新开始")
        }
        pipeline.stop()
    }

    /// Stop and background pause share cleanup; callers choose whether to close or retain search.
    /// 停止和后台暂停共用收尾；搜索会话由调用方决定关闭或保留。
    private func cancelPendingCameraWork() {
        cameraReady = false
        isSwitchingCamera = false
        enrollmentTask?.cancel()
        enrollmentTask = nil
        isSavingCapture = false
        confirmsSearchOverwrite = false
        request?.cancel()
        request = nil
        resetActionProgress()
        clearSearchDisplay()
        detection = nil
    }

    /// Request 10 FPS preview and 5 FPS SDK analysis after ten continuous no-face seconds; hardware falls back within supported ranges
    /// while SDK input keeps target throttling.
    /// 连续无人脸 10 秒后请求 10 FPS 预览、5 FPS 分析；会话按支持范围回退，SDK 输入独立限流。
    func setSearchCameraIdle(_ idle: Bool) {
        guard mode == .search else { return }
        pipeline.setSessionFrameRate(idle ? 10 : 15, analysisFramesPerSecond: idle ? 5 : 15)
    }

    deinit {
        enrollmentTask?.cancel()
        actionCountdownTask?.cancel()
        searchStaleTask?.cancel()
        pipeline.stop()
        sdk.close()
    }

    func restartFlow() {
        guard started, !isSwitchingCamera else { return }
        request?.cancel()
        request = nil
        searchSession?.close()
        searchSession = nil
        clearPendingCapture()
        detection = nil
        clearSearchDisplay()
        resetActionProgress()
        failureAllowsRetry = true
        phase = .preparing
        // Recheck permissions and resume/rebuild the camera session; start() is safe while already running.
        // 重新检查权限并恢复/重建相机会话；已在运行时 `start()` 是安全的。
        pipeline.start(analysisEnabled: false)
    }

    // MARK: - Capture and enrollment
    // 采集与录入。

    // Save the confirmed 1:1 feature first, then queue its optional portrait.
    @discardableResult
    func saveCapturedReference() -> Bool {
        guard canSaveCapturedReference, let pendingReferenceFeature else { return false }
        do {
            let faceID = try DemoFaceStore.save(
                feature: pendingReferenceFeature,
                faceID: enrollmentFaceID
            )
            FacePhotoStore.saveLater(image: alignedFace, faceID: faceID, library: .reference)
            clearPendingCapture()
            enrollmentFaceID = faceID
            refreshReferenceFaces()
            status = DemoL10n.text("已保存 1:1 参考人脸")
            detail = DemoL10n.text("Face ID：{0}；同名录入会更新原样本", [String(describing: faceID)])
            return true
        } catch {
            status = DemoL10n.text("保存失败")
            detail = DemoErrorPresentation.message(for: error)
            return false
        }
    }

    /// Save search enrollment directly from the captured result, matching Android without passing through
    /// 1:1 reference storage.
    /// 搜索录入直接保存本次采集结果，与 Android 一样不经过 1:1 参考样本中转。
    func saveSearchCapture(replace: Bool = false) {
        guard started, enrollsInSearchLibrary, canSaveCapturedReference,
              !isSavingCapture, let feature = pendingReferenceFeature else { return }
        let faceID = enrollmentFaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = enrollmentGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        enrollmentFaceID = faceID
        enrollmentGroup = group
        confirmsSearchOverwrite = false
        isSavingCapture = true
        let photo = alignedFace
        enrollmentTask = Task { [weak self] in
            do {
                try await Self.persistSearchCapture(
                    faceID: faceID, feature: feature, group: group, replace: replace, photo: photo
                )
                guard let self, !Task.isCancelled, started else { return }
                isSavingCapture = false
                enrollmentTask = nil
                clearPendingCapture()
                status = DemoL10n.text("人脸已保存")
                detail = "Face ID：\(faceID)"
                enrollmentCompleted = true
            } catch {
                guard let self, !Task.isCancelled, started else { return }
                isSavingCapture = false
                enrollmentTask = nil
                if (error as? HiFaceError)?.code == .alreadyExists {
                    confirmsSearchOverwrite = true
                } else {
                    status = DemoL10n.text("保存失败")
                    detail = DemoL10n.text("保存失败：{0}", [String(describing: DemoErrorPresentation.message(for: error))])
                }
            }
        }
    }

    /// Open and query off the main thread; after cancellation, start no save but let submitted database
    /// work finish.
    /// 开库和查询在非主线程执行；取消后不再发起保存，已提交的数据库操作自然结束。
    private nonisolated static func persistSearchCapture(
        faceID: String, feature: String, group: String, replace: Bool, photo: CGImage?
    ) async throws {
        try Task.checkCancellation()
        let database = try HiFaceSDK.openSearchDatabase()
        do {
            try Task.checkCancellation()
            var tag = ""
            if replace {
                do {
                    tag = try await database.entry(faceID: faceID).tag
                } catch let error as HiFaceError where error.code == .notFound {
                    tag = ""
                }
            } else if try await database.contains(faceID: faceID) {
                throw HiFaceError(code: .alreadyExists, message: "Face ID already exists")
            }
            try Task.checkCancellation()
            try await database.saveFeature(faceID: faceID, feature: feature, tag: tag, group: group)
            await FacePhotoStore.save(image: photo, faceID: faceID)
            await database.close()
        } catch {
            await database.close()
            throw error
        }
    }

    // MARK: - Search
    // 搜索。

    var searchOptions: String {
        FaceSearchPresentation.options(for: searchConfiguration)
    }

    // MARK: - Verification
    // 验证。

    func selectReference(_ faceID: String) -> Bool {
        do {
            try DemoFaceStore.select(faceID: faceID)
            selectedReferenceID = faceID
            status = DemoL10n.text("已选择 {0}", [String(describing: faceID)])
            detail = DemoL10n.text("点击开始，完成动作、活体和 1:1 验证")
            return true
        } catch {
            status = DemoL10n.text("选择参考身份失败")
            detail = DemoErrorPresentation.message(for: error)
            return false
        }
    }

    func beginVerification() {
        guard started, cameraReady, !isSwitchingCamera, mode == .verification, request == nil,
              let faceID = selectedReferenceID else { return }
        do {
            guard let reference = try DemoFaceStore.feature(for: faceID) else {
                guard refreshReferenceFaces() else { return }
                pipeline.pauseAnalysis()
                phase = referenceFaceIDs.isEmpty ? .needsReference : .selectingReference
                status = DemoL10n.text("参考身份已不存在")
                detail = DemoL10n.text("Face ID：{0}；请重新录入或选择其他身份", [String(describing: faceID)])
                return
            }
            let actions = recognitionActions ?? FaceFlowPresentation.randomChallenge(count: 2)
            phase = .running
            resetActionProgress()
            pipeline.resumeAnalysis()
            status = DemoL10n.text("准备验证 {0}", [String(describing: faceID)])
            let configuration = try FaceVerificationConfiguration(
                referenceFeature: reference,
                requiresSilentLiveness: recognitionSilent,
                actions: actions,
                allowsMultipleFaces: true
            )
            actionTimeoutMilliseconds = configuration.actionTimeoutMilliseconds
            detail = String(
                format: DemoL10n.text("动作：%@；随后检测活体并验证（阈值 %.2f%%）"),
                FaceFlowPresentation.actionList(actions),
                configuration.threshold * 100
            )
            request = sdk.startCameraVerification(
                configuration: configuration,
                callbacks: flowCallbacks()
            )
        } catch {
            handleConfigurationError(error)
        }
    }

    // MARK: - Capture presentation
    // 采集展示。

    var canSaveCapturedReference: Bool {
        pendingReferenceFeature != nil
            && !enrollmentFaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Search controls
    // 搜索控制。

    func updateSearchConfiguration(_ configuration: FaceSearchSessionConfiguration) {
        guard mode == .search, !isSwitchingCamera else { return }
        searchConfiguration = configuration
        searchSession?.update(configuration: configuration)
        // Retain nonrecoverable errors; applying settings must not restart a rejected session.
        // 不可恢复错误保持原提示，应用设置不能让被拒绝的会话重新启动。
        if let lastSearchError, !FaceSearchPresentation.canResumeSearch(lastSearchError) { return }
        lastSearchError = nil
        prepareSearchPreview()
    }

    func resumeSearch() {
        guard started, !suspended, !isSwitchingCamera else { return }
        if let lastSearchError, !FaceSearchPresentation.canResumeSearch(lastSearchError) { return }
        lastSearchError = nil
        guard mode == .search, searchSession != nil else {
            restartFlow()
            return
        }
        prepareSearchPreview()
    }

    /// Camera startup rechecks permission. Only cameraDidStart may resume search and admit frames.
    private func prepareSearchPreview() {
        clearSearchDisplay()
        phase = .preparing
        status = DemoL10n.text("正在准备")
        detail = DemoL10n.text("准备完成后自动开始")
        if started && !suspended { pipeline.start(analysisEnabled: false) }
    }

    // MARK: - Camera controls
    // 相机控制。

    func switchCamera() {
        guard started, cameraReady, !isSwitchingCamera else { return }
        // Keep the same liveness challenge across a lens switch.
        let preservesLivenessRequest = mode == .liveness && phase == .running && request != nil
        let accepted = pipeline.switchCamera { [weak self] usable in
            guard let self, started else { return }
            isSwitchingCamera = false
            guard usable, cameraReady, phase.needsCameraFlow else { return }
            if preservesLivenessRequest, request != nil {
                pipeline.resumeAnalysis()
            } else if mode == .search, searchSession != nil {
                resumeSearch()
            } else {
                startFlowIfNeeded()
                if phase == .running { pipeline.resumeAnalysis() }
            }
        }
        // An interruption can reach the pipeline before its notification reaches this screen.
        guard accepted else { return }
        isSwitchingCamera = true
        cameraNotice = nil
        if !preservesLivenessRequest {
            request?.cancel()
            request = nil
            resetActionProgress()
        }
        searchSession?.pause()
        detection = nil
        clearSearchDisplay()
        if phase.needsCameraFlow && !preservesLivenessRequest {
            phase = .preparing
            status = DemoL10n.text("正在切换摄像头")
        }
    }

    // MARK: - SDK request creation
    // SDK 请求创建。

    private func startFlowIfNeeded() {
        failureAllowsRetry = true
        switch mode {
        case .detection:
            phase = .running
            status = DemoL10n.text("将人脸置于取景框内")
            detail = DemoL10n.text("显示最多 10 张脸、五点、468 点轮廓与头姿")
        case .capture:
            phase = .running
            status = DemoL10n.text("保持正脸稳定")
            detail = DemoL10n.text("保持正脸稳定，生成特征与预览")
            // Core requires 700 ms of stable frontal pose for capture; synchronize only the visual ring here,
            // without making business decisions.
            // Core 要求采集时正脸连续稳定 700 ms；这里只同步可视圆环，不参与业务判定。
            actionTimeoutMilliseconds = Self.captureStableCountdownMilliseconds
            request = sdk.startCameraCapture(callbacks: FaceCaptureCallbacks(
                onProgress: { [weak self] progress in self?.handle(progress) },
                onResult: { [weak self] result in self?.handleCapture(result) },
                onError: { [weak self] error in self?.handleFlowError(error) }
            ))
        case .liveness:
            do {
                phase = .running
                let actions = recognitionActions ?? FaceFlowPresentation.randomChallenge(count: 3)
                let configuration = try FaceLivenessConfiguration(
                    actions: actions,
                    allowsMultipleFaces: true
                )
                actionTimeoutMilliseconds = configuration.actionTimeoutMilliseconds
                status = DemoL10n.text("准备活体检测")
                detail = DemoL10n.text("动作：{0}；随后检测静默活体", [String(describing: FaceFlowPresentation.actionList(actions))])
                request = sdk.startCameraLiveness(
                    configuration: configuration,
                    callbacks: flowCallbacks()
                )
            } catch {
                handleConfigurationError(error)
            }
        case .verification:
            prepareReferenceSelection()
        case .search:
            phase = .running
            status = DemoL10n.text("正在准备")
            detail = DemoL10n.text("准备完成后自动开始")
            searchSession = sdk.startCameraSearch(
                configuration: searchConfiguration,
                callbacks: FaceSearchCallbacks(
                    onFrame: { [weak self] frame in self?.handle(frame) },
                    onProgress: { [weak self] progress in self?.handle(progress) },
                    onResult: { [weak self] result in self?.handle(result) },
                    onError: { [weak self] error in self?.handleSearchError(error) }
                )
            )
        }
    }

    // MARK: - SDK callbacks
    // SDK 回调。

    private func flowCallbacks() -> FaceFlowCallbacks {
        FaceFlowCallbacks(
            onProgress: { [weak self] progress in self?.handle(progress) },
            onResult: { [weak self] result in self?.handle(result) },
            onError: { [weak self] error in self?.handleFlowError(error) }
        )
    }

    private func handle(_ progress: FaceFlowProgress) {
        guard started else { return }
        status = FaceFlowPresentation.text(for: progress)
        if mode == .capture {
            if progress.stage == .holdStill {
                actionStepCount = 1
                startActionCountdownIfNeeded()
            } else {
                // Refill the ring when leaving frontal stability; restart the full 0.7-second timer on returning.
                // 离开正脸稳定阶段即重新蓄满；再次回正后按完整 0.7 秒重新计时。
                resetActionProgress()
            }
            return
        }
        if mode != .capture, progress.stage == .holdStill || progress.stage == .faceForward {
            status = DemoL10n.text("请正对镜头")
        }
        if progress.stage == .performAction, progress.stepCount > 0 {
            let nextStep = min(max(progress.stepNumber, 1), progress.stepCount)
            actionStepCount = progress.stepCount
            startActionCountdownIfNeeded()
            detail = DemoL10n.text("动作 {0}/{1}，完成后检测静默活体", [String(describing: nextStep), String(describing: actionStepCount)])
        } else if progress.action != nil,
                  progress.stage == .waitingForFace || progress.stage == .multipleFaces || progress.stage == .faceTooSmall {
            // Brief face loss or distance changes do not pause Core's total action deadline or reset the visual
            // ring.
            // 短暂丢脸或距离变化不会暂停 Core 的动作总时限，也不能重置显示圆环。
        } else {
            resetActionProgress()
        }
    }

    private func handleCapture(_ result: FaceCaptureResult) {
        guard started else { return }
        request = nil
        if case .failure(let error) = stageCapture(result) {
            handleFlowError(error)
            return
        }
        pipeline.pauseAnalysis()
        resetActionProgress()
        phase = .completed
    }

    // Discard the feature and its matching preview together when retaking or replacing a sample.
    func clearPendingCapture() {
        pendingReferenceFeature = nil
        alignedFace = nil
        detail = nil
    }

    // Extract an album candidate for the same confirmation UI used by guided capture.
    func prepareAlbumReference(_ image: HiFaceRGBAImage) async throws {
        let faces = try await sdk.captureFaces(image).get()
        try Task.checkCancellation()
        try stageAlbumReference(faces)
    }

    func stageAlbumReference(_ faces: [FaceImageCapture]) throws {
        clearPendingCapture()
        // A second detection counts even when its feature could not be extracted.
        guard faces.count == 1 else {
            throw ReferencePhotoError.requiresSingleFace
        }
        try stageCapture(faces[0].capture.get()).get()
        previewMirrored = false
    }

    // Camera and album sources share this validation step before exposing a saveable draft.
    private func stageCapture(_ result: FaceCaptureResult) -> Result<Void, HiFaceError> {
        guard DemoFaceStore.isValidFeature(result.feature),
              let preview = result.alignedFace?.makeCGImage() else {
            return .failure(HiFaceError(code: .processingFailed, message: "Invalid capture feature or aligned preview"))
        }
        pendingReferenceFeature = result.feature
        alignedFace = preview
        status = DemoL10n.text("人脸采集完成")
        detail = enrollsInSearchLibrary ? DemoL10n.text("请确认照片与录入信息") : DemoL10n.text("请确认照片，再保存为 1:1 验证样本")
        return .success(())
    }

    private func handle(_ result: FaceFlowResult) {
        guard started else { return }
        completedPassed = result.passed
        request = nil
        pipeline.pauseAnalysis()
        resetActionProgress()
        phase = .completed
        alignedFace = result.alignedFace?.makeCGImage()
        switch mode {
        case .liveness:
            let outcomeMessage = result.passed ? DemoL10n.text("活体检测通过") : FaceFlowPresentation.outcomeText(result.outcome)
            status = outcomeMessage
            // Passing or spoof-detected results contain a score; early timeout or face loss shows only the reason.
            // nil means no passive-liveness score, not zero; map preserves nil.
            // 通过或检测到非真人时已产生分数；动作超时、丢脸等提前结束时只展示结果原因。
            // nil 表示未产生静默活体分数，不能当作 0 分展示；map 在 nil 时保留 nil。
            let livenessScore = result.livenessScore
            detail = livenessScore.map { String(format: DemoL10n.text("活体分数 %.3f"), $0) }
        case .verification:
            let outcomeMessage = result.passed ? DemoL10n.text("1:1 验证通过") : FaceFlowPresentation.outcomeText(result.outcome)
            status = outcomeMessage
            var resultDetails: [String] = []
            if let selectedReferenceID { resultDetails.append("Face ID \(selectedReferenceID)") }
            // Omit similarity if identity comparison did not finish; do not display 0%.
            // 未完成身份比对时没有相似度，省略该项，不能当作 0% 展示。
            if let similarity = result.similarity {
                resultDetails.append(String(format: DemoL10n.text("相似度 %.2f%%"), similarity * 100))
            }
            // Display passive-liveness and similarity scores separately; never fill missing scores with zero.
            // 静默活体分数与相似度分别展示；未产生的分数不补零。
            if let livenessScore = result.livenessScore {
                resultDetails.append(String(format: DemoL10n.text("活体分数 %.3f"), livenessScore))
            }
            detail = resultDetails.isEmpty ? nil : resultDetails.joined(separator: " · ")
        default:
            status = result.passed ? DemoL10n.text("流程通过") : FaceFlowPresentation.outcomeText(result.outcome)
        }
    }

    private func handle(_ result: FaceSearchResult) {
        guard started else { return }
        if searchDisplayState.complete(result, now: ProcessInfo.processInfo.systemUptime) {
            searchOverlay = searchDisplayState
        }
        scheduleSearchOverlayExpiry()
    }

    private func handle(_ frame: FaceSearchFrame) {
        guard started else { return }
        // Private state still receives every frame ID; repeated empty frames do not republish the same empty
        // image and wake SwiftUI.
        // 私有状态仍接收每个帧号；连续空帧不发布同一空画面以重复唤醒 SwiftUI。
        if searchDisplayState.accept(frame, now: ProcessInfo.processInfo.systemUptime) {
            searchOverlay = searchDisplayState
        }
        scheduleSearchOverlayExpiry()
    }

    private func scheduleSearchOverlayExpiry() {
        let deadline = searchDisplayState.expiresAt
        guard searchExpirySchedule.update(to: deadline) else { return }
        searchStaleTask?.cancel()
        guard let deadline else {
            searchStaleTask = nil
            return
        }
        let delay = max(0.001, deadline - ProcessInfo.processInfo.systemUptime)
        searchStaleTask = Task { [weak self] in
            try? await Task<Never, Never>.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            searchExpirySchedule.reset()
            searchStaleTask = nil
            if searchDisplayState.expire(now: ProcessInfo.processInfo.systemUptime) {
                searchOverlay = searchDisplayState
            }
            scheduleSearchOverlayExpiry()
        }
    }

    private func handle(_ progress: FaceSearchProgress) {
        guard started else { return }
        if searchDetectedCount != progress.detectedCount { searchDetectedCount = progress.detectedCount }
        if searchSelectedCount != progress.selectedCount { searchSelectedCount = progress.selectedCount }
        var changed = searchDisplayState.setAssociationEnabled(
            searchConfiguration.mode == .multipleFaces || progress.detectedCount <= 1
        )
        if progress.stage == .emptyGallery, let newest = searchDisplayState.newestFrameID {
            changed = searchDisplayState.rejectScores(through: newest) || changed
        }
        if changed { searchOverlay = searchDisplayState }
        let guidance = FaceSearchPresentation.guidance(for: progress)
        if status != guidance.title { status = guidance.title }
        if detail != guidance.hint { detail = guidance.hint }
        scheduleSearchOverlayExpiry()
    }

    private func handleFlowError(_ error: HiFaceError) {
        guard started else { return }
        request = nil
        if mode == .capture, !enrollsInSearchLibrary, cameraReady, !suspended,
           DemoErrorPresentation.shouldRestartCapture(error) {
            resetActionProgress()
            phase = .preparing
            startFlowIfNeeded()
            detail = DemoL10n.text("上一帧处理失败，已自动继续")
            pipeline.resumeAnalysis()
            return
        }
        searchSession?.close()
        searchSession = nil
        pipeline.pauseAnalysis()
        resetActionProgress()
        failureAllowsRetry = DemoErrorPresentation.isRetryable(error)
        phase = .failed
        status = DemoL10n.text("处理失败")
        detail = DemoErrorPresentation.message(for: error)
    }

    private func handleSearchError(_ error: HiFaceError) {
        guard started else { return }
        lastSearchError = error
        pipeline.pauseAnalysis()
        clearSearchDisplay()
        failureAllowsRetry = FaceSearchPresentation.canResumeSearch(error)
        phase = .failed
        status = DemoL10n.text("人脸搜索已暂停")
        detail = "\(DemoErrorPresentation.message(for: error)) (\(error.code.rawValue))"
    }

    private func handleCameraError(_ message: String) {
        guard started else { return }
        cameraReady = false
        needsCameraSettings = AVCaptureDevice.authorizationStatus(for: .video) == .denied
        request?.cancel()
        request = nil
        searchSession?.pause()
        pipeline.pauseAnalysis()
        clearSearchDisplay()
        resetActionProgress()
        failureAllowsRetry = true
        phase = .failed
        status = DemoL10n.text("相机或帧处理失败")
        detail = message
    }

    private func handleCameraAvailability(available: Bool, message: String) {
        guard started else { return }
        cameraReady = available
        cameraNotice = message
        guard phase.needsCameraFlow else { return }
        if available {
            // On recovery notification, invalidate the interrupted flow; CameraPipeline then calls cameraDidStart
            // to rebuild it.
            // 恢复通知到达时作废中断前的流程；CameraPipeline 随后调用 cameraDidStart 重建流程。
            request?.cancel()
            request = nil
            searchSession?.pause()
            detection = nil
            clearSearchDisplay()
            resetActionProgress()
            phase = .preparing
            status = DemoL10n.text("正在恢复相机流程")
            detail = DemoL10n.text("系统相机恢复后重新开始本轮检测")
        } else {
            status = DemoL10n.text("相机暂时不可用")
            detail = DemoL10n.text("当前流程已暂停，系统释放相机后会自动重新开始")
        }
    }

    private func handleConfigurationError(_ error: Error) {
        failureAllowsRetry = false
        phase = .failed
        status = DemoL10n.text("配置无效")
        detail = DemoErrorPresentation.message(for: error)
        pipeline.pauseAnalysis()
        resetActionProgress()
    }

    // MARK: - Reference storage
    // 参考基准存储。

    private func prepareReferenceSelection() {
        if let recognitionReferenceID {
            if selectReference(recognitionReferenceID) { beginVerification() }
            else { phase = .failed }
            return
        }
        pipeline.pauseAnalysis()
        guard refreshReferenceFaces() else { return }
        guard !referenceFaceIDs.isEmpty, let selectedReferenceID else {
            phase = .needsReference
            status = DemoL10n.text("请先录入参考人脸")
            detail = DemoL10n.text("1:1 验证需要一份已确认的 Face ID 与 HF1 特征")
            return
        }
        phase = .selectingReference
        status = DemoL10n.text("选择要验证的身份")
        detail = DemoL10n.text("当前选择：{0}", [String(describing: selectedReferenceID)])
    }

    @discardableResult
    private func refreshReferenceFaces() -> Bool {
        do {
            let faceIDs = try DemoFaceStore.faceIDs()
            let selected = try DemoFaceStore.selectedFaceID(among: faceIDs)
            referenceFaceIDs = faceIDs
            selectedReferenceID = selected
            return true
        } catch {
            referenceFaceIDs = []
            selectedReferenceID = nil
            phase = .failed
            status = DemoL10n.text("读取参考人脸失败")
            detail = DemoErrorPresentation.message(for: error)
            return false
        }
    }

    // MARK: - Transient presentation state
    // 临时展示状态。

    private func resetActionProgress() {
        actionCountdownTask?.cancel()
        actionCountdownTask = nil
        actionStepCount = 0
        actionCountdown.reset()
        actionCountdownProgress = 1
    }

    private func clearSearchDisplay() {
        searchStaleTask?.cancel()
        searchStaleTask = nil
        searchExpirySchedule.reset()
        searchDisplayState.clear()
        searchOverlay = searchDisplayState
        searchDetectedCount = 0
        searchSelectedCount = 0
    }

    private func startActionCountdownIfNeeded() {
        guard actionCountdown.deadline == nil else { return }
        actionCountdown.startIfNeeded(actionTimeoutMilliseconds: actionTimeoutMilliseconds,
                                      stepCount: actionStepCount, now: ProcessInfo.processInfo.systemUptime)
        guard actionCountdown.deadline != nil else { return }
        actionCountdownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task<Never, Never>.sleep(nanoseconds: 100_000_000)
                guard !Task.isCancelled, let self else { return }
                let progress = actionCountdown.progress(at: ProcessInfo.processInfo.systemUptime)
                if actionCountdownProgress != progress { actionCountdownProgress = progress }
                if progress == 0 { return }
            }
        }
    }

    // MARK: - Detection presentation
    // 检测展示。

    private static func detectionDetail(_ face: DetectedFace) -> String {
        var values = [String(format: DemoL10n.text("置信度 %.1f%%"), face.confidence * 100)]
        if let pose = face.headPose {
            values.append(String(
                format: "Pitch %.1f° · Yaw %.1f° · Roll %.1f°",
                pose.pitch,
                pose.yaw,
                pose.roll
            ))
        }
        return values.joined(separator: " · ")
    }
}

enum ReferencePhotoError: LocalizedError {
    case requiresSingleFace
    var errorDescription: String? { DemoL10n.text("请选择只有一张人脸的照片。") }
}
