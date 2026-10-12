import Foundation
import HiFace

/// 对应 Android `FaceSearchStatusUi`：页面显示阶段引导，逐脸结果留在人脸框上。
enum FaceSearchPresentation {
    /// 与 Android 一致：仅恢复暂时失败的有效会话，启动拒绝需重新进入。
    static func canResumeSearch(_ error: HiFaceError) -> Bool {
        switch error.code {
        case .notReady, .processingFailed, .databaseError: true
        default: false
        }
    }

    static func options(for configuration: FaceSearchSessionConfiguration) -> String {
        if configuration.mode == .multipleFaces { return "M:N · 不检测姿态与活体" }
        return "1:N · " + (configuration.needsLiveness ? "活体已开启" : "活体未开启")
    }

    static func guidance(for progress: FaceSearchProgress) -> (title: String, hint: String) {
        switch progress.stage {
        case .waitingForFace: ("等待人脸入镜", "面向镜头，入镜后自动识别")
        case .faceTooSmall: ("请靠近一点", "人脸太小，请靠近一些")
        case .searching: ("正在搜索", "正在匹配人脸库")
        case .emptyGallery: ("当前范围内暂无已录入人脸", "请录入人脸或调整搜索设置")
        case .successInterval: ("等待下一次搜索", "间隔结束后自动继续")
        @unknown default: ("正在处理", "请稍候")
        }
    }

    static func configurationText(_ value: FaceSearchSessionConfiguration) -> String {
        var values = [
            value.mode == .singleFace ? "单人 1:N" : "多人 M:N",
            String(format: "门限 %.2f", value.threshold)
        ]
        if value.needsLiveness { values.append("单帧活体") }
        if let group = value.group { values.append("Group \(group)") }
        if let tag = value.tag { values.append("Tag \(tag)") }
        return values.joined(separator: " · ")
    }

}
