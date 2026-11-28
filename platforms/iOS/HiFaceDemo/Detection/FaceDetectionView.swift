import SwiftUI

/// Real-time detection example: preview and overlay aspect-fit the same frame coordinate space.
/// 实时检测接入示例：预览和 Overlay 完整等比显示同一帧坐标系。
struct FaceDetectionView: View {
    @ObservedObject var model: CameraDemoModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DemoCameraControls(model: model, onClose: onClose, onSwitchCamera: model.switchCamera)
            LiveCameraViewfinder(session: model.pipeline.captureSession, mirrored: model.previewMirrored,
                                 frameSize: model.previewFrameSize) {
                FaceDetectionOverlayView(result: model.detection, mirrored: model.overlayMirrored)
            }
            VStack {
                if let notice = model.cameraNotice {
                    Text(notice).font(.caption).multilineTextAlignment(.center).padding(16)
                }
                if model.phase == .failed {
                    VStack(spacing: 10) {
                        Text(model.status).font(.headline)
                        Text(model.detail ?? "").font(.caption)
                        if model.needsCameraSettings {
                            CameraSettingsLink()
                        } else {
                            Button(DemoL10n.text("重试")) { model.restartFlow() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(20)
                    .background(DemoTheme.searchSurface, in: RoundedRectangle(cornerRadius: 14))
                    .padding()
                }
            }
        }
        .foregroundStyle(.white)
        .background(DemoTheme.search.ignoresSafeArea())
    }
}
