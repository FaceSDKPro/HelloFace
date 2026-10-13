import Foundation
import HiFace

/// 对应 Android `FaceFlowUi`：统一采集、活体和动态 1:1 的阶段、动作及终态文案。
enum FaceFlowPresentation {
    static func text(for progress: FaceFlowProgress) -> String {
        switch progress.stage {
        case .waitingForFace: return DemoL10n.text("请将人脸移入圆框")
        case .multipleFaces: return DemoL10n.text("请确保画面中只有一人")
        case .faceTooSmall: return DemoL10n.text("请靠近一点")
        case .faceNotFrontal, .faceForward: return DemoL10n.text("请正对镜头")
        case .holdStill: return DemoL10n.text("保持不动")
        case .faceUnstable: return DemoL10n.text("请保持人脸稳定")
        case .performAction:
            let suffix = progress.stepCount > 0
                ? "（\(progress.stepNumber)/\(progress.stepCount)）"
                : ""
            switch progress.action {
            case .shakeHead: return DemoL10n.text("请摇头{0}", [String(describing: suffix)])
            case .nodHead: return DemoL10n.text("请点头{0}", [String(describing: suffix)])
            case .blink: return DemoL10n.text("请眨眼{0}", [String(describing: suffix)])
            case .openMouth: return DemoL10n.text("请张嘴{0}", [String(describing: suffix)])
            case nil: return DemoL10n.text("请完成动作{0}", [String(describing: suffix)])
            @unknown default: return DemoL10n.text("请完成动作{0}", [String(describing: suffix)])
            }
        @unknown default: return DemoL10n.text("正在处理，请稍候")
        }
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

    /// Demo 每轮生成互不重复的动作；生产业务可以替换为服务端挑战策略。
    static func randomChallenge(count: Int) -> [FaceAction] {
        Array(FaceAction.allCases.shuffled().prefix(count))
    }

    static func actionList(_ actions: [FaceAction]) -> String {
        actions.map {
            switch $0 {
            case .shakeHead: DemoL10n.text("摇头")
            case .nodHead: DemoL10n.text("点头")
            case .blink: DemoL10n.text("眨眼")
            case .openMouth: DemoL10n.text("张嘴")
            @unknown default: DemoL10n.text("其他动作")
            }
        }.joined(separator: "、")
    }
}
