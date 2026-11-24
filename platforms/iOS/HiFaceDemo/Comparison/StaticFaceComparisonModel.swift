import Foundation
import HiFace
import SwiftUI
@preconcurrency import UIKit

enum ComparisonSide: String, Identifiable {
    case left
    case right

    var id: String { rawValue }
    var title: String { self == .left ? DemoL10n.text("照片 1") : DemoL10n.text("照片 2") }
}

struct ComparisonPhotoState {
    var preview: CGImage?
    // Only a successful extraction makes a slot eligible for feature-to-feature comparison.
    var feature: String?
    var status = DemoL10n.text("选择照片")
    var isProcessing = false
    var hasError = false
}

/// Asynchronous static-image screen model; versioning discards old task results after photo
/// reselection.
/// 静态图片页的异步状态模型；版本号用于丢弃用户重新选图后返回的旧任务结果。
@MainActor
final class StaticFaceComparisonModel: ObservableObject {
    @Published private(set) var left = ComparisonPhotoState()
    @Published private(set) var right = ComparisonPhotoState()
    @Published private(set) var similarity: Float?
    @Published private(set) var comparisonError: String?
    @Published private(set) var isComparing = false

    // Keep one SDK per model; image versions reject stale results, and deinit closes the SDK.
    // 每个模型持有一个 SDK；图片版本号用于丢弃旧结果，模型销毁时关闭 SDK。
    private let sdk: HiFaceSDK
    // Each slot advances independently, so replacing one photo leaves the other extraction running.
    private var versions: [ComparisonSide: Int] = [.left: 0, .right: 0]
    private var photoTasks: [ComparisonSide: Task<Void, Never>] = [:]
    private var comparisonTask: Task<Void, Never>?
    // A comparison has its own lifetime because replacing either slot invalidates its result.
    private var comparisonVersion = 0

    init() {
        sdk = HiFaceSDK()
    }

    var canCompare: Bool {
        left.feature != nil && right.feature != nil && !isComparing
    }

    // Replace one slot and invalidate the old pair score while extraction runs asynchronously.
    func load(_ image: HiFaceRGBAImage, into side: ComparisonSide) {
        photoTasks[side]?.cancel()
        cancelComparison()

        let version = (versions[side] ?? 0) + 1
        versions[side] = version
        update(side) {
            $0.preview = image.makeCGImage()
            $0.feature = nil
            $0.status = DemoL10n.text("正在提取人脸…")
            $0.isProcessing = true
            $0.hasError = false
        }

        photoTasks[side] = Task { [weak self, sdk] in
            let capture = await sdk.capture(image)
            guard let self, !Task.isCancelled, versions[side] == version else { return }
            defer {
                if versions[side] == version { photoTasks[side] = nil }
            }
            switch capture {
            case .failure(let error):
                finish(side, version: version, error: error)
            case .success(let result):
                let alignedPreview = result.alignedFace?.makeCGImage()
                update(side) {
                    // Reuse the displayed source if the SDK has no aligned preview.
                    $0.preview = alignedPreview ?? $0.preview
                    $0.feature = result.feature
                    $0.status = DemoL10n.text("已就绪，点击可更换")
                    $0.isProcessing = false
                    $0.hasError = false
                }
            }
        }
    }

    /// Retain the previous usable image and feature if selection or decoding fails, matching Android Demo.
    /// 选图或解码失败时保留上一次可用图片和特征，与 Android Demo 行为一致。
    func reportPickerError(_ error: HiFaceError, for side: ComparisonSide) {
        photoTasks[side]?.cancel()
        photoTasks[side] = nil
        versions[side, default: 0] += 1
        cancelComparison()
        update(side) {
            $0.status = DemoErrorPresentation.message(for: error)
            $0.isProcessing = false
            $0.hasError = true
        }
    }

    func compare() {
        guard let leftFeature = left.feature, let rightFeature = right.feature else { return }
        cancelComparison()
        let version = comparisonVersion
        isComparing = true
        comparisonTask = Task { [weak self, sdk] in
            let result = await sdk.compare(feature: leftFeature, with: rightFeature)
            guard let self, !Task.isCancelled, comparisonVersion == version else { return }
            defer {
                if comparisonVersion == version { comparisonTask = nil }
            }
            isComparing = false
            switch result {
            case .success(let score): similarity = score
            case .failure(let error): comparisonError = DemoErrorPresentation.message(for: error)
            }
        }
    }

    func stop() {
        photoTasks.values.forEach { $0.cancel() }
        photoTasks.removeAll()
        cancelComparison(keepingResult: true)
        for side in [ComparisonSide.left, .right] {
            versions[side, default: 0] += 1
            update(side) {
                if $0.isProcessing { $0 = ComparisonPhotoState() }
            }
        }
    }

    deinit { sdk.close() }

    /// Clear old scores on image change/recomparison; temporary navigation cancels in-flight work but
    /// retains completed results.
    /// 换图/重新比较清掉旧分数；暂时离开页面只取消在途工作，保留已经完成的结果。
    private func cancelComparison(keepingResult: Bool = false) {
        comparisonTask?.cancel()
        comparisonTask = nil
        comparisonVersion += 1
        isComparing = false
        if !keepingResult {
            similarity = nil
            comparisonError = nil
        }
    }

    private func finish(_ side: ComparisonSide, version: Int, error: HiFaceError) {
        guard versions[side] == version else { return }
        update(side) {
            $0.feature = nil
            $0.status = DemoErrorPresentation.message(for: error)
            $0.isProcessing = false
            $0.hasError = true
        }
    }

    private func update(_ side: ComparisonSide, body: (inout ComparisonPhotoState) -> Void) {
        switch side {
        case .left: body(&left)
        case .right: body(&right)
        }
    }

}
