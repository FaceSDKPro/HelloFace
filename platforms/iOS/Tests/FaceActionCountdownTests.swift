import Foundation

@main
struct FaceActionCountdownTests {
    static func main() {
        var timer = FaceActionCountdown()
        precondition(timer.progress(at: 100) == 1)
        timer.startIfNeeded(actionTimeoutMilliseconds: 10_000, stepCount: 3, now: 100)
        precondition(timer.deadline == 130)
        precondition(timer.duration == 30 && timer.progress(at: 100) == 1)
        precondition(timer.progress(at: 115) == 0.5)
        // 第二个动作开始和短暂丢脸期间不重开倒计时。
        timer.startIfNeeded(actionTimeoutMilliseconds: 10_000, stepCount: 3, now: 115)
        precondition(timer.deadline == 130)
        precondition(abs(timer.progress(at: 119.1) - 10.9 / 30) < 0.000_001)
        precondition(timer.progress(at: 140) == 0)
        precondition(timer.progress(at: 130) == 0)
        // 回正、重试或切镜头后清空；下一轮按新的动作数重新开始。
        timer.reset()
        precondition(timer.deadline == nil && timer.progress(at: 150) == 1)
        timer.startIfNeeded(actionTimeoutMilliseconds: 10_000, stepCount: 2, now: 200)
        precondition(timer.deadline == 220)
        precondition(timer.progress(at: 199) == 1)
        timer.reset()
        timer.startIfNeeded(actionTimeoutMilliseconds: 0, stepCount: 3, now: 200)
        timer.startIfNeeded(actionTimeoutMilliseconds: 10_000, stepCount: 0, now: 200)
        precondition(timer.deadline == nil)
        // 人脸录入的 holdStill 复用同一计时器，但只显示一个 0.7 秒稳定窗口。
        timer.startIfNeeded(actionTimeoutMilliseconds: 700, stepCount: 1, now: 300)
        precondition(abs((timer.deadline ?? 0) - 300.7) < 0.000_001)
        precondition(abs(timer.progress(at: 300.35) - 0.5) < 0.000_001)
        precondition(timer.progress(at: 300.7) == 0)
        precondition(timer.progress(at: 301) == 0)
        timer.reset()
        precondition(timer.duration == 0 && timer.progress(at: 301) == 1)
        print("Face action/capture countdown checks passed")
    }
}
