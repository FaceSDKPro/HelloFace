import SwiftUI

struct CameraSettingsView: View {
    @AppStorage(DemoCameraSettings.resolutionKey)
    private var resolution = CameraAnalysisResolution.medium.rawValue
    @AppStorage(DemoCameraSettings.mirrorCoordinatesKey)
    private var mirrorsOverlayCoordinates = false

    var body: some View {
        Form {
            Section {
                ForEach(CameraAnalysisResolution.allCases) { value in
                    resolutionRow(value)
                }
            } header: {
                Text("摄像头分辨率")
            } footer: {
                Text("根据当前镜头自动选择支持的分辨率，实际尺寸在相机页显示。低档适合近距离使用，中档适合日常检测与活体。")
            }

            Section {
                Toggle("相机坐标镜像校正", isOn: $mirrorsOverlayCoordinates)
            } header: {
                Text("画面校正")
            } footer: {
                Text("默认关闭。仅在人脸框、关键点与画面的左右位置相反时开启，不影响拍摄画面。")
            }

            Section {
                HStack {
                    Text("目标倍率")
                    Spacer()
                    Text("0.8×").foregroundStyle(.secondary)
                }
            } header: {
                Text("镜头视野")
            } footer: {
                Text("所有相机功能统一尝试 0.8×。仅支持普通广角的镜头最低为 1.0×，相机页会显示实际倍率。")
            }

            Section {
                Label("设置自动保存，重新进入相机页面后生效。", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
        .preferredColorScheme(.light)
        .navigationBarHidden(false)
        .tint(DemoTheme.contentAccent)
        .navigationTitle("摄像头参数设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            resolution = CameraAnalysisResolution(storedValue: resolution).rawValue
        }
    }

    private func resolutionRow(_ value: CameraAnalysisResolution) -> some View {
        let selected = resolution == value.rawValue
        return Button {
            resolution = value.rawValue
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(value.title).foregroundStyle(.primary)
                        if value == .medium {
                            Text("推荐")
                                .font(.caption)
                                .foregroundStyle(DemoTheme.contentAccent)
                        }
                    }
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
