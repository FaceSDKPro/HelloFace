import Foundation
import HiFace

/// Map stable SDK error codes to localized guidance instead of displaying low-level message text.
/// 根据稳定 SDK 错误码显示本地化提示，不直接展示底层错误文案。
enum DemoErrorPresentation {
    static func message(for error: Error) -> String {
        if let sdkError = error as? HiFaceError { return message(for: sdkError) }
        return error.localizedDescription
    }

    static func message(for error: HiFaceError) -> String {
        switch error.code {
        case .notReady: DemoL10n.text("引擎未就绪，请稍后重试")
        case .closed: DemoL10n.text("会话已关闭，请重新进入")
        case .invalidArgument: DemoL10n.text("输入无效")
        case .unsupportedFormat: DemoL10n.text("图片或视频帧格式不支持")
        case .modelLoadFailed: DemoL10n.text("人脸模型加载失败")
        case .imageNoFace: DemoL10n.text("未检测到人脸")
        case .imageFaceTooSmall: DemoL10n.text("人脸过小")
        case .busy: DemoL10n.text("引擎正忙，请稍后重试")
        case .processingFailed: DemoL10n.text("处理失败，请重试")
        case .notFound: DemoL10n.text("未找到人脸记录")
        case .databaseError: DemoL10n.text("无法访问人脸库")
        case .resourceExhausted: DemoL10n.text("内存或存储空间不足")
        case .alreadyExists: DemoL10n.text("人脸记录已存在")
        case .internalError: DemoL10n.text("SDK 内部错误")
        default: accessMessage(for: error.code) ?? DemoL10n.text("SDK 返回未知错误，请更新 Demo")
        }
    }

    static func isAccessError(_ code: HiFaceErrorCode) -> Bool {
        switch code {
        case .licenseMissing, .licenseInvalid, .licenseNotYetValid, .licenseExpired,
             .licenseFeatureDenied, .licenseClockInvalid: true
        default: false
        }
    }

    static func accessMessage(for code: HiFaceErrorCode) -> String? {
        isAccessError(code) ? DemoL10n.text("功能不可用（错误码 {0}）", [String(code.rawValue)]) : nil
    }

    /// Configuration, model, database, and lifecycle errors require fixing the cause; repeating the same
    /// request is ineffective.
    /// 配置、模型、数据库和生命周期错误需要先修复原因，重复执行同一请求没有意义。
    static func isRetryable(_ error: HiFaceError) -> Bool {
        switch error.code {
        case .notReady, .imageNoFace, .imageFaceTooSmall, .busy, .processingFailed:
            true
        default:
            false
        }
    }

    /// Restart guided capture automatically only after a transient frame-processing failure.
    /// 仅在偶发帧处理失败后自动重启引导采集。
    static func shouldRestartCapture(_ error: HiFaceError) -> Bool {
        error.code == .processingFailed
    }
}
