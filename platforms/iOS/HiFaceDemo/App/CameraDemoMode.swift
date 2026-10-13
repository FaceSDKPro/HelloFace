import Foundation

enum CameraDemoMode: String, CaseIterable, Identifiable {
    case detection = "实时人脸检测"
    case capture = "人脸采集"
    case verification = "1:1 人脸验证"
    case liveness = "活体检测"
    case search = "人脸搜索识别"

    var id: String { rawValue }
    var title: String { DemoL10n.text(rawValue) }

    var subtitle: String {
        switch self {
        case .detection: DemoL10n.text("查看人脸框、关键点、轮廓和头姿")
        case .capture: DemoL10n.text("采集正脸并保存特征")
        case .verification: DemoL10n.text("选择 Face ID，活体通过后验证")
        case .liveness: DemoL10n.text("随机动作挑战与双模型静默检测")
        case .search: DemoL10n.text("识别人脸库中的身份")
        }
    }

    var icon: String {
        switch self {
        case .detection: "faceid"
        case .capture: "person.crop.square"
        case .verification: "checkmark.shield"
        case .liveness: "eye"
        case .search: "person.3.fill"
        }
    }
}
