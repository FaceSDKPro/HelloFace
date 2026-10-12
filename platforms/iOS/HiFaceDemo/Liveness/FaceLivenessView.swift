import SwiftUI

/// 与 Android 活体页共用采集引导样式，右上角保留镜头切换。
struct FaceLivenessView: View {
    @ObservedObject var model: CameraDemoModel
    let onClose: () -> Void

    var body: some View {
        FaceCaptureCameraView(model: model, onClose: onClose, showsCameraSwitch: true)
    }
}
