import SwiftUI

struct CameraSettingsView: View {
    // An empty value shows no selected tier and leaves the default to the current camera feature.
    @AppStorage(DemoCameraSettings.resolutionKey)
    private var resolution = ""
    // Extra overlay-coordinate correction is independent of the camera preview's mirroring.
    @AppStorage(DemoCameraSettings.mirrorCoordinatesKey)
    private var mirrorsOverlayCoordinates = false

    var body: some View {
        Form {
            Section {
                ForEach(CameraAnalysisResolution.allCases) { value in
                    resolutionRow(value)
                }
            } header: {
                Text(DemoL10n.text("摄像头分辨率"))
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(DemoL10n.text("根据你的业务场景，配置合适的摄像头支持的分辨率。"))
                    Text(DemoL10n.text("未选择档位时，实时人脸搜索使用高档，其他相机功能使用低档。"))
                }
            }

            Section {
                Toggle(DemoL10n.text("相机坐标镜像校正"), isOn: $mirrorsOverlayCoordinates)
            } header: {
                Text(DemoL10n.text("画面校正"))
            } footer: {
                Text(DemoL10n.text("默认关闭；标记与预览左右相反时开启，不改变画面。"))
            }

            Section {
                HStack {
                    Text(DemoL10n.text("目标倍率"))
                    Spacer()
                    Text("0.8×").foregroundStyle(.secondary)
                }
            } header: {
                Text(DemoL10n.text("镜头视野"))
            } footer: {
                Text(DemoL10n.text("优先使用 0.8×；普通广角可能最低为 1.0×。实际倍率见相机页。"))
            }

            Section {
                Label(DemoL10n.text("设置自动保存，重新进入相机页面后生效。"), systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
        .preferredColorScheme(.light)
        .navigationBarHidden(false)
        .tint(DemoTheme.contentAccent)
        .navigationTitle(DemoL10n.text("SDK参数设置"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resolutionRow(_ value: CameraAnalysisResolution) -> some View {
        let selected = resolution == value.rawValue
        return Button {
            resolution = value.rawValue
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(value.title).foregroundStyle(.primary)
                    Text(value.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(DemoTheme.contentAccent)
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value.title)，\(value.detail)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
