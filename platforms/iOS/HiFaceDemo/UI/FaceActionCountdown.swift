import Foundation

/// 与 Android 一致：整个动作序列共用一条倒计时，换动作或短暂丢脸不会重置。
struct FaceActionCountdown {
    private(set) var deadline: TimeInterval?
    private(set) var duration: TimeInterval = 0

    mutating func startIfNeeded(actionTimeoutMilliseconds: Int64, stepCount: Int, now: TimeInterval) {
        guard deadline == nil, actionTimeoutMilliseconds > 0, stepCount > 0 else { return }
        duration = Double(actionTimeoutMilliseconds) / 1_000 * Double(stepCount)
        deadline = now + duration
    }

    func progress(at now: TimeInterval) -> Double {
        guard let deadline, duration > 0 else { return 1 }
        return min(1, max(0, (deadline - now) / duration))
    }

    mutating func reset() {
        deadline = nil
        duration = 0
    }
}
