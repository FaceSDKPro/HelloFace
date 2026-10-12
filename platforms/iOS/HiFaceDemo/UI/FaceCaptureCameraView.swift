import SwiftUI

/// 采集、活体和动态 1:1 共用相机底图、圆形引导与导航，页面只决定可用操作。
struct FaceCaptureCameraView: View {
    @ObservedObject var model: CameraDemoModel
    let onClose: () -> Void
    var showsCameraSwitch = false
    @ScaledMetric(relativeTo: .headline) private var statusFontSize = 19

    var body: some View {
        GeometryReader { geometry in
            let statusHeight = max(28, statusFontSize * 2.4)
            let circle = FaceCaptureLayout.circleBounds(
                in: geometry.size,
                statusHeight: statusHeight,
                topInset: geometry.safeAreaInsets.top,
                bottomInset: geometry.safeAreaInsets.bottom
            )
            let previewShortSide = FaceCaptureLayout.previewShortSide(
                circle: circle,
                availableSize: geometry.size
            )
            ZStack {
                // 引导页缩小预览的显示短边；底层帧、分辨率和 SDK 输入保持不变。
                CameraPreview(session: model.pipeline.captureSession, mirrored: model.previewMirrored)
                    .frame(width: previewShortSide, height: geometry.size.height)
                    .ignoresSafeArea()
                FaceCaptureOverlayView(
                    status: model.status,
                    countdownProgress: model.phase == .completed || model.phase == .failed
                        ? 0 : model.actionCountdownProgress,
                    topInset: geometry.safeAreaInsets.top,
                    bottomInset: geometry.safeAreaInsets.bottom
                )
                .ignoresSafeArea()
                VStack {
                    DemoCameraControls(model: model, onClose: onClose, onDark: false,
                                       showsResolution: false,
                                       onSwitchCamera: cameraSwitchAction)
                    Spacer()
                    VStack(spacing: 8) {
                        if let notice = model.cameraNotice {
                            Text(notice).font(.footnote).multilineTextAlignment(.center)
                        }
                        Text(model.cameraDisplayMetrics)
                            .font(.caption.monospacedDigit())
                            .accessibilityLabel("当前相机参数：\(model.cameraDisplayMetrics)")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }
            }
        }
        .background(.white)
    }

    private var cameraSwitchAction: (() -> Void)? {
        guard showsCameraSwitch else { return nil }
        return { model.switchCamera() }
    }
}
