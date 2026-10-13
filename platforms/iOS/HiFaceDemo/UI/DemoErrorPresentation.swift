import Foundation
import HiFace

/// 对应 Android `DemoErrorUi`：页面只依赖稳定错误码，避免直接展示可能变化的底层英文信息。
enum DemoErrorPresentation {
    static func message(for error: Error) -> String {
        if let sdkError = error as? HiFaceError { return message(for: sdkError) }
        return error.localizedDescription
    }

    static func message(for error: HiFaceError) -> String {
        switch error.code {
        case .notReady: DemoL10n.text("SDK 尚未准备完成，请稍后重试")
        case .closed: DemoL10n.text("SDK 已关闭，请重新进入页面")
        case .invalidArgument: DemoL10n.text("调用参数无效，请检查 Demo 配置")
        case .unsupportedFormat: DemoL10n.text("不支持的图片或相机帧格式")
        case .modelLoadFailed: DemoL10n.text("模型加载失败，请检查模型资源")
        case .imageNoFace: DemoL10n.text("未检测到人脸")
        case .imageFaceTooSmall: DemoL10n.text("人脸尺寸过小，请靠近后重试")
        case .busy: DemoL10n.text("SDK 正在处理上一帧，请稍后重试")
        case .processingFailed: DemoL10n.text("人脸处理失败，请重试")
        case .notFound: DemoL10n.text("未找到指定的人脸记录")
        case .databaseError: DemoL10n.text("人脸库操作失败")
        case .resourceExhausted: DemoL10n.text("设备资源不足，请关闭其他任务后重试")
        case .alreadyExists: DemoL10n.text("Face ID 已存在")
        case .internalError: DemoL10n.text("SDK 内部错误")
        @unknown default: DemoL10n.text("SDK 返回未知错误，请更新 Demo")
        }
    }

    /// 配置、模型、数据库和生命周期错误需要先修复原因，重复执行同一请求没有意义。
    static func isRetryable(_ error: HiFaceError) -> Bool {
        switch error.code {
        case .notReady, .imageNoFace, .imageFaceTooSmall, .busy, .processingFailed:
            true
        default:
            false
        }
    }

    /// 与 Android 一致：普通引导录入只对偶发帧处理失败自动创建下一次请求。
    static func shouldRestartCapture(_ error: HiFaceError) -> Bool {
        error.code == .processingFailed
    }
}
