import Foundation
import HiFace

/// Counterpart of Android FaceFlowUi: shared stage, action, and outcome text for capture, liveness, and
/// dynamic 1:1.
/// 对应 Android `FaceFlowUi`：统一采集、活体和动态 1:1 的阶段、动作及终态文案。
enum FaceFlowPresentation {
    static func guidance(for progress: FaceFlowProgress, capture: Bool) -> (title: String, speech: String?) {
        let title: String
        switch progress.stage {
        case .waitingForFace: title = DemoL10n.text("请将人脸移入圆框")
        case .multipleFaces: title = DemoL10n.text("请确保画面中只有一人")
        case .faceTooSmall: title = DemoL10n.text("请靠近一点")
        case .faceNotFrontal, .faceForward: title = DemoL10n.text("请正对镜头")
        case .holdStill: title = capture ? DemoL10n.text("保持不动") : DemoL10n.text("请正对镜头")
        case .faceUnstable: return (DemoL10n.text("请保持人脸稳定"), nil)
        case .performAction:
            let labels = progress.action.map(actionLabels)
            let suffix = progress.stepCount > 0 ? "（\(progress.stepNumber)/\(progress.stepCount)）" : ""
            let actionTitle = DemoL10n.text(labels?.title ?? "请完成动作{0}", [suffix])
            return (actionTitle, capture ? nil : labels.map { DemoL10n.text($0.name) })
        @unknown default: return (DemoL10n.text("正在处理，请稍候"), nil)
        }
        return (title, capture ? nil : title)
    }

    static func outcomeText(_ outcome: FaceFlowOutcome) -> String {
        switch outcome {
        case .passed: DemoL10n.text("通过")
        case .notMatched: DemoL10n.text("人脸不匹配")
        case .spoofDetected: DemoL10n.text("活体检测未通过")
        case .noFaceTimeout: DemoL10n.text("等待人脸超时")
        case .faceLost: DemoL10n.text("人脸离开画面时间过长")
        case .multipleFaces: DemoL10n.text("画面中存在多张人脸")
        case .actionTimeout: DemoL10n.text("动作挑战超时")
        case .finalCaptureTimeout: DemoL10n.text("最终采样超时")
        @unknown default: DemoL10n.text("未知流程结果")
        }
    }

    /// Generate distinct actions each Demo round; production applications may replace this with server-
    /// issued challenges.
    /// Demo 每轮生成互不重复的动作；生产业务可以替换为服务端挑战策略。
    static func randomChallenge(count: Int) -> [FaceAction] {
        Array(FaceAction.allCases.shuffled().prefix(count))
    }

    static func actionList(_ actions: [FaceAction]) -> String {
        actions.map { DemoL10n.text(actionLabels($0).name) }.joined(separator: "、")
    }

    private static func actionLabels(_ action: FaceAction) -> (name: String, title: String) {
        switch action {
        case .shakeHead: ("摇头", "请摇头{0}")
        case .nodHead: ("点头", "请点头{0}")
        case .blink: ("眨眼", "请眨眼{0}")
        case .openMouth: ("张嘴", "请张嘴{0}")
        @unknown default: ("其他动作", "请完成动作{0}")
        }
    }
}
