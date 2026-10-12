import Foundation

// 等形 SDK 桩只控制异步完成顺序，运行真实 Demo Model；不访问照片、模型或 Keychain。
typealias CGImage = String
struct HiFaceRGBAImage: Sendable {
    let name: String
    func makeCGImage() -> CGImage? { name }
}
struct FaceCaptureResult: Sendable {
    let feature: String
    let alignedFace: HiFaceRGBAImage?
}
struct HiFaceError: Error { let message: String }
enum DemoErrorPresentation { static func message(for error: HiFaceError) -> String { error.message } }

actor ComparisonWork {
    private var captures: [String: CheckedContinuation<Result<FaceCaptureResult, HiFaceError>, Never>] = [:]
    private var comparison: CheckedContinuation<Result<Float, HiFaceError>, Never>?

    func capture(_ image: HiFaceRGBAImage) async -> Result<FaceCaptureResult, HiFaceError> {
        await withCheckedContinuation { captures[image.name] = $0 }
    }
    func compare() async -> Result<Float, HiFaceError> {
        await withCheckedContinuation { comparison = $0 }
    }
    func hasCapture(_ name: String) -> Bool { captures[name] != nil }
    var hasComparison: Bool { comparison != nil }
    func completeCapture(_ name: String, feature: String) {
        guard let pending = captures.removeValue(forKey: name) else { preconditionFailure("Missing capture") }
        pending.resume(returning: .success(FaceCaptureResult(
            feature: feature, alignedFace: HiFaceRGBAImage(name: "aligned-\(name)"))))
    }
    func completeComparison(_ score: Float) {
        guard let pending = comparison else { preconditionFailure("Missing comparison") }
        comparison = nil
        pending.resume(returning: .success(score))
    }
}
final class HiFaceSDK: Sendable {
    let work = ComparisonWork()
    func capture(_ image: HiFaceRGBAImage) async -> Result<FaceCaptureResult, HiFaceError> {
        await work.capture(image)
    }
    func compare(feature: String, with other: String) async -> Result<Float, HiFaceError> {
        await work.compare()
    }
    func close() {}
}
@MainActor enum DemoEnvironment {
    static var latest = HiFaceSDK()
    static func makeSDK() -> HiFaceSDK { latest = HiFaceSDK(); return latest }
}

@main struct StaticFaceComparisonModelTests {
    @MainActor static func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<1000 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        preconditionFailure("Timed out waiting for comparison work")
    }
    @MainActor static func flush() async { for _ in 0..<100 { await Task.yield() } }

    @MainActor static func readyModel() async throws -> (StaticFaceComparisonModel, ComparisonWork) {
        let model = StaticFaceComparisonModel()
        let work = DemoEnvironment.latest.work
        model.load(HiFaceRGBAImage(name: "left"), into: .left)
        model.load(HiFaceRGBAImage(name: "right"), into: .right)
        try await waitUntil {
            let left = await work.hasCapture("left")
            let right = await work.hasCapture("right")
            return left && right
        }
        await work.completeCapture("left", feature: "L")
        await work.completeCapture("right", feature: "R")
        try await waitUntil { model.canCompare }
        return (model, work)
    }

    @MainActor static func main() async throws {
        try await replacingPhotoRejectsLateCapture()
        try await replacingPhotoRejectsLateComparison()
        try await pickerFailureKeepsReadyPhotos()
        try await backgroundKeepsCompletedResultAndRejectsPendingComparison()
        try await backgroundRejectsPendingPhoto()
        print("Static comparison model: 5 scenarios passed")
    }

    @MainActor static func replacingPhotoRejectsLateCapture() async throws {
        let model = StaticFaceComparisonModel()
        let work = DemoEnvironment.latest.work
        model.load(HiFaceRGBAImage(name: "old"), into: .left)
        try await waitUntil { await work.hasCapture("old") }
        model.load(HiFaceRGBAImage(name: "new"), into: .left)
        try await waitUntil { await work.hasCapture("new") }
        await work.completeCapture("new", feature: "NEW")
        try await waitUntil { model.left.feature == "NEW" }
        await work.completeCapture("old", feature: "OLD")
        await flush()
        precondition(model.left.feature == "NEW" && model.left.preview == "aligned-new")
        model.stop()
    }

    @MainActor static func replacingPhotoRejectsLateComparison() async throws {
        let (model, work) = try await readyModel()
        model.compare()
        try await waitUntil { await work.hasComparison }
        model.load(HiFaceRGBAImage(name: "replacement"), into: .left)
        try await waitUntil { await work.hasCapture("replacement") }
        await work.completeComparison(0.99)
        await flush()
        precondition(model.similarity == nil && !model.isComparing)
        await work.completeCapture("replacement", feature: "NEW")
        try await waitUntil { model.left.feature == "NEW" }
        model.stop()
    }

    @MainActor static func pickerFailureKeepsReadyPhotos() async throws {
        let (model, work) = try await readyModel()
        model.compare()
        try await waitUntil { await work.hasComparison }
        await work.completeComparison(0.9)
        try await waitUntil { model.similarity != nil }
        model.reportPickerError(HiFaceError(message: "Unreadable photo"), for: .left)
        precondition(model.left.feature == "L" && model.left.preview == "aligned-left")
        precondition(model.left.hasError && !model.left.isProcessing)
        precondition(model.canCompare && model.similarity == nil)
        model.stop()
    }

    @MainActor static func backgroundKeepsCompletedResultAndRejectsPendingComparison() async throws {
        let (model, work) = try await readyModel()
        model.compare()
        try await waitUntil { await work.hasComparison }
        await work.completeComparison(0.8)
        try await waitUntil { model.similarity != nil }
        model.stop()
        precondition(model.similarity == 0.8 && model.canCompare)
        model.compare()
        try await waitUntil { await work.hasComparison }
        model.stop()
        await work.completeComparison(0.1)
        await flush()
        precondition(model.similarity == nil && model.canCompare && !model.isComparing)
    }

    @MainActor static func backgroundRejectsPendingPhoto() async throws {
        let (model, work) = try await readyModel()
        model.load(HiFaceRGBAImage(name: "pending"), into: .left)
        try await waitUntil { await work.hasCapture("pending") }
        model.stop()
        await work.completeCapture("pending", feature: "LATE")
        await flush()
        precondition(model.left.feature == nil && model.left.preview == nil && !model.left.isProcessing)
        precondition(model.right.feature == "R")
    }
}
