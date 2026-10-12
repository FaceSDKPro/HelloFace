import Foundation
import AVFoundation
import HiFace
import SwiftUI

/// Demo 页面状态；SDK 的业务终态仍由 `FaceFlowOutcome` 和 `FaceSearchEndReason` 表达。
enum CameraDemoPhase: Equatable {
    case preparing
    case selectingReference
    case running
    case completed
    case failed
    case needsReference
}

/// 相机能力页面的协调器：连接 AVFoundation、SDK 请求和 SwiftUI 展示状态。
/// 文案映射由 UI 与 Search 分组负责。
@MainActor
final class CameraDemoModel: ObservableObject {
    private static let captureStableCountdownMilliseconds: Int64 = 700

    // MARK: - Published presentation state

    @Published var detection: FaceDetectionResult?
    @Published var previewMirrored = true
    @Published var overlayMirrored = true
    @Published var cameraResolution = "等待相机画面"
    @Published var cameraZoom = "等待倍率"
    @Published var cameraNotice: String?
    @Published var status = "正在启动…"
    @Published var detail: String?
    @Published var alignedFace: CGImage?
    @Published var enrollmentFaceID = ""
    @Published var enrollmentGroup = ""
    @Published var confirmsSearchOverwrite = false
    @Published private(set) var isSavingCapture = false
    @Published private(set) var enrollmentCompleted = false
    @Published private(set) var phase: CameraDemoPhase = .preparing
    @Published private(set) var cameraReady = false
    @Published private(set) var needsCameraSettings = false
    @Published private(set) var failureAllowsRetry = true
    @Published private(set) var isSwitchingCamera = false
    @Published private(set) var pendingReferenceFeature: String?
    @Published private(set) var referenceFaceIDs: [String] = []
    @Published private(set) var selectedReferenceID: String?
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

    let sdk: HiFaceSDK
    let pipeline: CameraPipeline
    private let mode: CameraDemoMode
    let enrollsInSearchLibrary: Bool
    private var request: FaceRequest?
    private var searchSession: FaceSearchSession?
    private var lastSearchError: HiFaceError?
    private var actionCountdownTask: Task<Void, Never>?
    private var actionCountdown = FaceActionCountdown()
    private var actionStepCount = 0
    private var searchStaleTask: Task<Void, Never>?
    private var searchDisplayState = FaceSearchOverlayState()
    private var searchExpirySchedule = FaceSearchOverlayExpirySchedule()
    private var enrollmentTask: Task<Void, Never>?
    private var actionTimeoutMilliseconds: Int64 = 0
    private var started = false
    private var suspended = false

    init(mode: CameraDemoMode, enrollsInSearchLibrary: Bool = false) {
        self.mode = mode
        self.enrollsInSearchLibrary = enrollsInSearchLibrary
        sdk = DemoEnvironment.makeSDK()
        let detectionConfiguration = mode == .detection
            ? (try? FaceDetectionConfiguration(maxFaces: 10, includesDetailedLandmarks: true)) ?? .default
            : FaceDetectionConfiguration.default
        // 搜索默认 640×480，已保存的相机设置优先。
        let cameraSettings = DemoCameraSettings.load(
            defaultAnalysisResolution: mode == .search ? .low : .medium
        )
        pipeline = CameraPipeline(
            sdk: sdk,
            detectionConfiguration: detectionConfiguration,
            settings: cameraSettings,
            // 搜索活跃 15 FPS、待机 5 FPS；其他页面固定帧率。
            sessionFramesPerSecond: mode == .search ? 15 : 30,
            minimumSessionFramesPerSecond: mode == .search ? 5 : nil,
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
                    ? "未检测到人脸"
                    : "检测到 \(result.faces.count) 张人脸"
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
            cameraResolution = "\(width) × \(height)" + (fallback ? " · 已适配" : "")
        }
        pipeline.onZoomFactorChanged = { [weak self] factor, constrained in
            guard let self, self.started else { return }
            let value = String(format: "%.1f×", factor)
            cameraZoom = constrained ? "\(value) · 镜头限制" : value
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
        // 从系统设置授权后恢复；从录入页返回时重新读取参考身份。
        if needsCameraSettings, AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
            needsCameraSettings = false
            phase = .preparing
        }
        if mode == .verification, phase == .needsReference || phase == .selectingReference {
            phase = .preparing
        }
        if mode == .capture, !enrollsInSearchLibrary { refreshReferenceFaces() }
        // 权限弹窗、切后台或临时离开页面后，保留已完成的预览和参考身份选择。
        pipeline.start(analysisEnabled: false)
    }

    private func cameraDidStart() {
        guard started, !suspended, !isSwitchingCamera else { return }
        cameraReady = true
        if phase == .preparing || phase == .running {
            if mode == .search, let searchSession {
                searchSession.resume()
                phase = .running
                status = "正在准备"
                detail = "准备完成后自动开始"
            } else {
                startFlowIfNeeded()
            }
        }
        if phase == .running { pipeline.resumeAnalysis() }
    }

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

    /// 后台保留搜索会话，返回前台由 start() 恢复。
    func suspend() {
        guard started, !suspended else { return }
        suspended = true
        let shouldRestart = phase == .preparing || phase == .running
        cancelPendingCameraWork()
        searchSession?.pause()
        if shouldRestart {
            phase = .preparing
            status = "返回前台后恢复相机"
            detail = mode == .search
                ? FaceSearchPresentation.configurationText(searchConfiguration)
                : "当前流程将在相机恢复后重新开始"
        }
        pipeline.stop()
    }

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

    /// 连续无人脸 10 秒后请求 5 FPS，会话按支持范围回退，SDK 输入保持目标门禁。
    func setSearchCameraIdle(_ idle: Bool) {
        guard mode == .search else { return }
        pipeline.setSessionFrameRate(idle ? 5 : 15)
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
        pendingReferenceFeature = nil
        alignedFace = nil
        detection = nil
        detail = nil
        clearSearchDisplay()
        resetActionProgress()
        failureAllowsRetry = true
        phase = .preparing
        // 重新检查权限并恢复/重建相机会话；已在运行时 `start()` 是安全的。
        pipeline.start(analysisEnabled: false)
    }

    // MARK: - Capture and enrollment

    @discardableResult
    func saveCapturedReference() -> Bool {
        guard canSaveCapturedReference, let pendingReferenceFeature else { return false }
        do {
            let faceID = try DemoFaceStore.save(
                feature: pendingReferenceFeature,
                faceID: enrollmentFaceID
            )
            self.pendingReferenceFeature = nil
            enrollmentFaceID = faceID
            refreshReferenceFaces()
            status = "已保存 1:1 参考人脸"
            detail = "Face ID：\(faceID)；同名录入会安全更新原样本"
            return true
        } catch {
            status = "保存失败"
            detail = error.localizedDescription
            return false
        }
    }

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
        enrollmentTask = Task { [weak self] in
            do {
                try await Self.persistSearchCapture(
                    faceID: faceID, feature: feature, group: group, replace: replace
                )
                guard let self, !Task.isCancelled, started else { return }
                isSavingCapture = false
                enrollmentTask = nil
                pendingReferenceFeature = nil
                alignedFace = nil
                status = "人脸已保存"
                detail = "Face ID：\(faceID)"
                enrollmentCompleted = true
            } catch {
                guard let self, !Task.isCancelled, started else { return }
                isSavingCapture = false
                enrollmentTask = nil
                if (error as? HiFaceError)?.code == .alreadyExists {
                    confirmsSearchOverwrite = true
                } else {
                    status = "保存失败"
                    detail = "保存失败：\(error.localizedDescription)"
                }
            }
        }
    }

    /// 开库和查询在非主线程执行；取消后不再发起保存，已提交的数据库操作自然结束。
    private nonisolated static func persistSearchCapture(
        faceID: String, feature: String, group: String, replace: Bool
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
            await database.close()
        } catch {
            await database.close()
            throw error
        }
    }

    // MARK: - Search

    var searchOptions: String {
        FaceSearchPresentation.options(for: searchConfiguration)
    }

    // MARK: - Verification

    func selectReference(_ faceID: String) -> Bool {
        do {
            try DemoFaceStore.select(faceID: faceID)
            selectedReferenceID = faceID
            status = "已选择 \(faceID)"
            detail = "点击开始后执行动作挑战、静默活体和动态 1:1 比对"
            return true
        } catch {
            status = "选择参考身份失败"
            detail = error.localizedDescription
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
                status = "参考身份已不存在"
                detail = "Face ID：\(faceID)；请重新录入或选择其他身份"
                return
            }
            let actions = FaceFlowPresentation.randomChallenge(count: 2)
            phase = .running
            resetActionProgress()
            pipeline.resumeAnalysis()
            status = "准备验证 \(faceID)"
            let configuration = try FaceVerificationConfiguration(
                referenceFeature: reference,
                requiresSilentLiveness: true,
                actions: actions,
                allowsMultipleFaces: true
            )
            actionTimeoutMilliseconds = configuration.actionTimeoutMilliseconds
            detail = String(
                format: "动作挑战：%@；随后进行七帧静默活体与 1:1 比对（门限 %.2f%%）",
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

    var canSaveCapturedReference: Bool {
        pendingReferenceFeature != nil
            && !enrollmentFaceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Search controls

    func updateSearchConfiguration(_ configuration: FaceSearchSessionConfiguration) {
        guard mode == .search, !isSwitchingCamera else { return }
        searchConfiguration = configuration
        searchSession?.update(configuration: configuration)
        // 不可恢复错误保持原提示，应用设置不能让被拒绝的会话重新启动。
        if let lastSearchError, !FaceSearchPresentation.canResumeSearch(lastSearchError) { return }
        lastSearchError = nil
        clearSearchDisplay()
        phase = .preparing
        status = "正在准备"
        detail = "准备完成后自动开始"
        guard started else { return }
        pipeline.start(analysisEnabled: false)
    }

    func resumeSearch() {
        guard started, !isSwitchingCamera else { return }
        if let lastSearchError, !FaceSearchPresentation.canResumeSearch(lastSearchError) { return }
        lastSearchError = nil
        guard mode == .search, searchSession != nil else {
            restartFlow()
            return
        }
        clearSearchDisplay()
        phase = .preparing
        status = "正在准备"
        detail = "准备完成后自动开始"
        // 恢复时重新检查相机权限。
        pipeline.start(analysisEnabled: false)
    }

    // MARK: - Camera controls

    func switchCamera() {
        guard started, cameraReady, !isSwitchingCamera else { return }
        let wasRunning = phase == .running || phase == .preparing
        // 与 Android 一致：活体切摄保留当前安全挑战，避免切摄重新随机“换题”。
        let preservesLivenessRequest = mode == .liveness && phase == .running && request != nil
        isSwitchingCamera = true
        cameraNotice = nil
        pipeline.pauseAnalysis()
        if !preservesLivenessRequest {
            request?.cancel()
            request = nil
        }
        searchSession?.pause()
        detection = nil
        clearSearchDisplay()
        if !preservesLivenessRequest { resetActionProgress() }
        if wasRunning && !preservesLivenessRequest {
            phase = .preparing
            status = "正在切换摄像头"
        }
        pipeline.switchCamera { [weak self] usable in
            guard let self, started else { return }
            isSwitchingCamera = false
            guard usable else { return }
            if wasRunning {
                if preservesLivenessRequest {
                    pipeline.resumeAnalysis()
                } else if mode == .search, searchSession != nil {
                    resumeSearch()
                } else {
                    startFlowIfNeeded()
                    if phase == .running { pipeline.resumeAnalysis() }
                }
            }
        }
    }

    // MARK: - SDK request creation

    private func startFlowIfNeeded() {
        failureAllowsRetry = true
        switch mode {
        case .detection:
            phase = .running
            status = "将人脸置于取景框内"
            detail = "显示最多 10 张脸、五点、468 点轮廓与头姿"
        case .capture:
            phase = .running
            status = "保持正脸稳定"
            detail = "正脸稳定后生成 HF1 特征与对齐预览"
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
                let actions = FaceFlowPresentation.randomChallenge(count: 3)
                let configuration = try FaceLivenessConfiguration(
                    actions: actions,
                    allowsMultipleFaces: true
                )
                actionTimeoutMilliseconds = configuration.actionTimeoutMilliseconds
                status = "准备活体检测"
                detail = "动作挑战：\(FaceFlowPresentation.actionList(actions))；随后进行七帧静默活体"
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
            status = "正在准备"
            detail = "准备完成后自动开始"
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
                // 离开正脸稳定阶段即重新蓄满；再次回正后按完整 0.7 秒重新计时。
                resetActionProgress()
            }
            return
        }
        if mode != .capture, progress.stage == .holdStill || progress.stage == .faceForward {
            status = "请正对镜头"
        }
        if progress.stage == .performAction, progress.stepCount > 0 {
            let nextStep = min(max(progress.stepNumber, 1), progress.stepCount)
            actionStepCount = progress.stepCount
            startActionCountdownIfNeeded()
            detail = "动作挑战 \(nextStep)/\(actionStepCount)；完成后自动进行静默活体"
        } else if progress.action != nil,
                  progress.stage == .waitingForFace || progress.stage == .multipleFaces || progress.stage == .faceTooSmall {
            // 短暂丢脸或距离变化不会暂停 Core 的动作总时限，也不能重置显示圆环。
        } else {
            resetActionProgress()
        }
    }

    private func handleCapture(_ result: FaceCaptureResult) {
        guard started else { return }
        request = nil
        guard DemoFaceStore.isValidFeature(result.feature),
              let alignedFace = result.alignedFace?.makeCGImage() else {
            handleFlowError(HiFaceError(
                code: .processingFailed,
                message: "Camera capture completed without a valid HF1 feature or aligned preview"
            ))
            return
        }
        pipeline.pauseAnalysis()
        resetActionProgress()
        phase = .completed
        pendingReferenceFeature = result.feature
        self.alignedFace = alignedFace
        status = "人脸采集完成"
        detail = enrollsInSearchLibrary ? "请确认照片与录入信息" : "请确认照片，再保存为 1:1 验证样本"
    }

    private func handle(_ result: FaceFlowResult) {
        guard started else { return }
        request = nil
        pipeline.pauseAnalysis()
        resetActionProgress()
        phase = .completed
        alignedFace = result.alignedFace?.makeCGImage()
        switch mode {
        case .liveness:
            let outcomeMessage = result.passed ? "活体检测通过" : FaceFlowPresentation.outcomeText(result.outcome)
            status = outcomeMessage
            // 通过或检测到非真人时已产生分数；动作超时、丢脸等提前结束时只展示结果原因。
            // nil 表示未产生静默活体分数，不能当作 0 分展示；map 在 nil 时保留 nil。
            let livenessScore = result.livenessScore
            detail = livenessScore.map { String(format: "活体分数 %.3f", $0) }
        case .verification:
            let outcomeMessage = result.passed ? "1:1 验证通过" : FaceFlowPresentation.outcomeText(result.outcome)
            status = outcomeMessage
            var resultDetails: [String] = []
            if let selectedReferenceID { resultDetails.append("Face ID \(selectedReferenceID)") }
            // 未完成身份比对时没有相似度，省略该项，不能当作 0% 展示。
            if let similarity = result.similarity {
                resultDetails.append(String(format: "相似度 %.2f%%", similarity * 100))
            }
            // 静默活体分数与相似度分别展示；未产生的分数不补零。
            if let livenessScore = result.livenessScore {
                resultDetails.append(String(format: "活体分数 %.3f", livenessScore))
            }
            detail = resultDetails.isEmpty ? nil : resultDetails.joined(separator: " · ")
        default:
            status = result.passed ? "流程通过" : FaceFlowPresentation.outcomeText(result.outcome)
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
            detail = "上一帧处理失败，已自动继续"
            pipeline.resumeAnalysis()
            return
        }
        searchSession?.close()
        searchSession = nil
        pipeline.pauseAnalysis()
        resetActionProgress()
        failureAllowsRetry = DemoErrorPresentation.isRetryable(error)
        phase = .failed
        status = "处理失败"
        detail = DemoErrorPresentation.message(for: error)
    }

    private func handleSearchError(_ error: HiFaceError) {
        guard started else { return }
        lastSearchError = error
        pipeline.pauseAnalysis()
        clearSearchDisplay()
        failureAllowsRetry = FaceSearchPresentation.canResumeSearch(error)
        phase = .failed
        status = "人脸搜索已暂停"
        detail = failureAllowsRetry ? DemoErrorPresentation.message(for: error)
            : "搜索无法恢复，请检查任务占用、配置或模型状态，解决后返回并重新进入。"
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
        status = "相机或帧处理失败"
        detail = message
    }

    private func handleCameraAvailability(available: Bool, message: String) {
        guard started else { return }
        cameraReady = available
        cameraNotice = message
        guard !available else {
            // 恢复通知到达时作废中断前的流程；CameraPipeline 随后调用 cameraDidStart 重建流程。
            guard phase == .running || phase == .preparing else { return }
            request?.cancel()
            request = nil
            searchSession?.pause()
            detection = nil
            clearSearchDisplay()
            resetActionProgress()
            phase = .preparing
            status = "正在恢复相机流程"
            detail = "系统相机恢复后重新开始本轮检测"
            return
        }
        if phase == .running || phase == .preparing {
            status = "相机暂时不可用"
            detail = "当前流程已暂停，系统释放相机后会自动重新开始"
        }
    }

    private func handleConfigurationError(_ error: Error) {
        failureAllowsRetry = false
        phase = .failed
        status = "配置无效"
        detail = (error as? HiFaceError).map { DemoErrorPresentation.message(for: $0) }
            ?? error.localizedDescription
        pipeline.pauseAnalysis()
        resetActionProgress()
    }

    // MARK: - Reference storage

    private func prepareReferenceSelection() {
        pipeline.pauseAnalysis()
        guard refreshReferenceFaces() else { return }
        guard !referenceFaceIDs.isEmpty, let selectedReferenceID else {
            phase = .needsReference
            status = "请先录入参考人脸"
            detail = "1:1 验证需要一份已确认的 Face ID 与 HF1 特征"
            return
        }
        phase = .selectingReference
        status = "选择要验证的身份"
        detail = "当前选择：\(selectedReferenceID)"
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
            status = "读取参考人脸失败"
            detail = error.localizedDescription
            return false
        }
    }

    // MARK: - Transient presentation state

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

    private static func detectionDetail(_ face: DetectedFace) -> String {
        var values = [String(format: "置信度 %.1f%%", face.confidence * 100)]
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
