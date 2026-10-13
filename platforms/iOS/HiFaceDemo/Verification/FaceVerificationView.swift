import SwiftUI

/// 先选择参考 Face ID，再完成动作、静默活体和 1:1 比对。
struct FaceVerificationView: View {
    @ObservedObject var model: CameraDemoModel
    let onClose: () -> Void

    var body: some View {
        ZStack {
            FaceCaptureCameraView(model: model, onClose: onClose)
                .allowsHitTesting(model.phase != .selectingReference)
                .accessibilityHidden(model.phase == .selectingReference)
            if model.phase == .selectingReference { referenceSelection }
        }
    }

    private var referenceSelection: some View {
        CameraDialog {
            CameraDialogTitle(
                title: DemoL10n.text("选择参考人脸"),
                subtitle: DemoL10n.text("选择已录入的 Face ID，开始身份验证。"),
                symbol: "person.crop.circle"
            )
            ForEach(model.referenceFaceIDs, id: \.self) { faceID in
                Button {
                    if model.selectReference(faceID) { model.beginVerification() }
                } label: {
                    HStack {
                        Text(faceID)
                            .font(.body.weight(.medium))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DemoL10n.text("验证 {0}", [String(describing: faceID)]))
            }
            if model.status == DemoL10n.text("选择参考身份失败") {
                Text(model.detail ?? model.status).font(.footnote).foregroundStyle(.red)
            }
            Button(DemoL10n.text("取消"), role: .cancel) { onClose() }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
