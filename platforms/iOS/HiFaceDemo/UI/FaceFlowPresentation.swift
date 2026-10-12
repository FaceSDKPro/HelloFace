import Foundation
import HiFace

/// 对应 Android `FaceFlowUi`：统一采集、活体和动态 1:1 的阶段、动作及终态文案。
enum FaceFlowPresentation {
    static func text(for progress: FaceFlowProgress) -> String {
        switch progress.stage {
        case .waitingForFace: return "请将人脸移入圆框"
        case .multipleFaces: return "请确保画面中只有一人"
        case .faceTooSmall: return "请靠近一点"
        case .faceNotFrontal, .faceForward: return "请正对镜头"
        case .holdStill: return "保持不动"
        case .faceUnstable: return "请保持人脸稳定"
        case .performAction:
            let suffix = progress.stepCount > 0
                ? "（\(progress.stepNumber)/\(progress.stepCount)）"
                : ""
            switch progress.action {
            case .shakeHead: return "请摇头\(suffix)"
            case .nodHead: return "请点头\(suffix)"
            case .blink: return "请眨眼\(suffix)"
            case .openMouth: return "请张嘴\(suffix)"
            case nil: return "请完成动作\(suffix)"
            @unknown default: return "请完成动作\(suffix)"
            }
        @unknown default: return "正在处理，请稍候"
        }
    }

    static func outcomeText(_ outcome: FaceFlowOutcome) -> String {
        switch outcome {
        case .passed: "通过"
        case .notMatched: "人脸不匹配"
        case .spoofDetected: "活体检测未通过"
        case .noFaceTimeout: "等待人脸超时"
        case .faceLost: "人脸离开画面时间过长"
        case .multipleFaces: "画面中存在多张人脸"
        case .actionTimeout: "动作挑战超时"
        case .finalCaptureTimeout: "最终采样超时"
        @unknown default: "未知流程结果"
        }
    }

    /// Demo 每轮生成互不重复的动作；生产业务可以替换为服务端挑战策略。
    static func randomChallenge(count: Int) -> [FaceAction] {
        Array(FaceAction.allCases.shuffled().prefix(count))
    }

    static func actionList(_ actions: [FaceAction]) -> String {
        actions.map {
            switch $0 {
            case .shakeHead: "摇头"
            case .nodHead: "点头"
            case .blink: "眨眼"
            case .openMouth: "张嘴"
            @unknown default: "其他动作"
            }
        }.joined(separator: "、")
    }
}
