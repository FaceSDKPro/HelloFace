import SwiftUI

/// 1:N/M:N 搜索接入示例：页面持有会话状态，送帧和相机生命周期由共享协调器负责。
struct FaceSearchView: View {
    @ObservedObject var model: CameraDemoModel
    let onClose: () -> Void
    @State private var showsSearchSettings = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                CameraPreview(session: model.pipeline.captureSession, mirrored: model.previewMirrored)
                FaceSearchOverlayView(overlay: model.searchOverlay, mirrored: model.overlayMirrored)
                VStack {
                    DemoCameraControls(model: model, onClose: onClose,
                                       onSwitchCamera: model.switchCamera,
                                       onSearchSettings: { showsSearchSettings = true })
                    Spacer()
                    if model.searchDetectedCount > 1 {
                        Text(model.searchConfiguration.mode == .singleFace
                             ? "检测到 \(model.searchDetectedCount) 人 · 优先识别最大脸"
                             : "检测到 \(model.searchDetectedCount) 人 · 本次处理 \(model.searchSelectedCount) 人")
                            .font(.caption2)
                            .padding(10)
                            .background(DemoTheme.searchSurface.opacity(0.85), in: Capsule())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            Text(model.searchOptions)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.75))
                .padding(.vertical, 6)
            VStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 7) {
                        Circle().fill(model.phase == .failed ? Color.red : DemoTheme.searchAccent)
                            .frame(width: 6, height: 6)
                        Text(model.status).font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                    }
                    Text(model.cameraNotice ?? model.detail ?? "面向镜头，入镜后自动识别")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if model.phase == .failed {
                        if model.needsCameraSettings {
                            CameraSettingsLink()
                        } else if model.failureAllowsRetry {
                            Button("重试") { model.resumeSearch() }
                                .foregroundStyle(DemoTheme.searchAccent)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DemoTheme.searchSurface, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.updatesFrequently)
                HStack(spacing: 10) {
                    NavigationLink(destination: LazyDestination {
                        CameraDemoView(mode: .capture, enrollsInSearchLibrary: true)
                    }) {
                        Label("录入人脸", systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(DemoTheme.search)
                            .background(DemoTheme.searchAccent, in: RoundedRectangle(cornerRadius: 10))
                    }
                    NavigationLink(destination: LazyDestination { SearchLibraryView() }) {
                        Label("人脸库", systemImage: "person.3")
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(DemoTheme.searchAccent)
                            .background(DemoTheme.searchSurface, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 12)
        }
        .foregroundStyle(.white)
        .background(DemoTheme.search.ignoresSafeArea())
        .sheet(isPresented: $showsSearchSettings) {
            SearchSettingsView(configuration: model.searchConfiguration) {
                model.updateSearchConfiguration($0)
            }
        }
    }

}
