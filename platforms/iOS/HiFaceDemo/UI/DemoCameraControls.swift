import SwiftUI

struct CameraSettingsLink: View {
    var body: some View {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            Link(DemoL10n.text("打开设置"), destination: url).buttonStyle(.borderedProminent)
        }
    }
}

struct DemoCameraControls: View {
    @ObservedObject var model: CameraDemoModel
    let onClose: () -> Void
    var onDark = true
    var showsResolution = true
    var onSwitchCamera: (() -> Void)?
    var onSearchSettings: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            DemoCameraButton(icon: "chevron.backward", label: DemoL10n.text("返回"), onDark: onDark, action: onClose)
            Spacer()
            if showsResolution {
                Text(model.cameraDisplayMetrics)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(onDark ? Color.white : Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(onDark ? Color.black.opacity(0.55) : Color.clear, in: Capsule())
                    .accessibilityLabel(DemoL10n.text("当前相机参数：{0}", [String(describing: model.cameraDisplayMetrics)]))
                Spacer()
            }
            if let onSearchSettings {
                DemoCameraButton(icon: "slider.horizontal.3", label: DemoL10n.text("搜索设置"), onDark: onDark,
                                 action: onSearchSettings)
                    .disabled(model.isSwitchingCamera)
            }
            if let onSwitchCamera {
                DemoCameraButton(icon: "camera.rotate", label: DemoL10n.text("切换摄像头"), onDark: onDark,
                                 action: onSwitchCamera)
                    .disabled(model.isSwitchingCamera || !model.cameraReady)
            }
        }
        .padding(12)
    }
}
