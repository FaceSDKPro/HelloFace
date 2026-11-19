import Foundation

/// Stop new input and cancel network waits; let current extraction and the final save batch finish.
/// 停止新输入并取消网络等待，当前特征提取和尾批写库自然完成。
final class FaceSearchImportControl: @unchecked Sendable {
    private let lock = NSLock()
    private var stopping = false
    // Each active download registers one cancellation closure under its own ID.
    private var downloads: [UUID: @Sendable () -> Void] = [:]

    var isStopped: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopping
    }

    func stop() {
        lock.lock()
        stopping = true
        let cancellations = Array(downloads.values)
        downloads.removeAll()
        lock.unlock()
        // Invoke client code after unlocking so cancellation cannot reenter the lock.
        cancellations.forEach { $0() }
    }

    func register(_ cancel: @escaping @Sendable () -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        let stopped = stopping
        if !stopped { downloads[id] = cancel }
        lock.unlock()
        if stopped { cancel() }
        return id
    }

    func unregister(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        downloads.removeValue(forKey: id)
    }
}
