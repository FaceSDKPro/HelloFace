import SwiftUI

/// 实时检测接入示例：预览和 Overlay 完整等比显示同一帧坐标系。
struct FaceDetectionView: View {
    @ObservedObject var model: CameraDemoModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            CameraPreview(session: model.pipeline.captureSession, mirrored: model.previewMirrored)
                .ignoresSafeArea()
            FaceDetectionOverlayView(result: model.detection, mirrored: model.overlayMirrored)
                .ignoresSafeArea()
            VStack {
                DemoCameraControls(model: model, onClose: onClose, onSwitchCamera: model.switchCamera)
                Spacer()
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
                            Button("重试") { model.restartFlow() }
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
        .background(.black)
    }
}
