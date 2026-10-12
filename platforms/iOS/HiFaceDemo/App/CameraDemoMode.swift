import Foundation

enum CameraDemoMode: String, CaseIterable, Identifiable {
    case detection = "实时人脸检测"
    case capture = "人脸采集"
    case verification = "1:1 人脸验证"
    case liveness = "活体检测"
    case search = "人脸搜索识别"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .detection: "实时展示人脸框、五点、轮廓和头姿"
        case .capture: "采集清晰正脸，并保存人脸特征"
        case .verification: "选择 Face ID，完成动作活体后进行动态 1:1 验证"
        case .liveness: "随机动作挑战与双模型静默检测"
        case .search: "从人脸库中检索匹配结果"
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
