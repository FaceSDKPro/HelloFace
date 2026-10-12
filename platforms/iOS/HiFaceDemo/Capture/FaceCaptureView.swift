import SwiftUI

/// 清晰正脸采集；用于 1:1 参考身份和搜索库录入。
struct FaceCaptureView: View {
    @ObservedObject var model: CameraDemoModel
    let onClose: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: InputField?
    private let capturedFacePreviewSize: CGFloat = 144 * 1.1

    private enum InputField: Hashable { case faceID, group }

    var body: some View {
        ZStack {
            FaceCaptureCameraView(model: model, onClose: onClose)
                // 键盘只调整确认框；底层相机始终保持全屏尺寸，避免重新拍摄时随键盘退场缩放。
                .ignoresSafeArea(.keyboard, edges: .bottom)
                .allowsHitTesting(model.pendingReferenceFeature == nil)
                .accessibilityHidden(model.pendingReferenceFeature != nil)
            if model.pendingReferenceFeature != nil { captureConfirmation }
        }
    }

    private var captureConfirmation: some View {
        CameraDialog {
            CameraDialogTitle(
                title: model.enrollsInSearchLibrary ? "确认录入信息" : "确认人脸照片",
                subtitle: model.enrollsInSearchLibrary
                    ? "请确认人脸清晰，设置唯一 Face ID"
                    : "请确认正脸清晰、无遮挡",
                symbol: "person.crop.square",
                symbolPlacement: .leading,
                symbolScale: 0.75,
                textScale: 0.9
            )
            if let image = model.alignedFace {
                Image(image, scale: 1, label: Text("本次采集的人脸预览"))
                    .resizable().scaledToFit()
                    .frame(width: capturedFacePreviewSize, height: capturedFacePreviewSize)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .scaleEffect(x: model.previewMirrored ? -1 : 1, y: 1)
            }
            TextField("输入唯一的人脸 ID", text: $model.enrollmentFaceID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Face ID")
                .focused($focusedField, equals: .faceID)
                .submitLabel(model.enrollsInSearchLibrary ? .next : .done)
                .onSubmit { focusedField = model.enrollsInSearchLibrary ? .group : nil }
            if model.enrollsInSearchLibrary {
                VStack(alignment: .leading, spacing: 6) {
                    Text("分组（选填）").font(.subheadline.weight(.medium))
                    TextField("输入分组名称", text: $model.enrollmentGroup)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("分组，选填")
                        .focused($focusedField, equals: .group)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                }
            }
            if let detail = model.detail, detail.hasPrefix("保存失败") || model.status == "保存失败" {
                Text(detail).font(.footnote).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            dialogActions
            .padding(.top, 8)
            .disabled(model.isSavingCapture)
        }
        .disabled(model.isSavingCapture)
        .onChange(of: model.enrollmentCompleted) { completed in
            if completed { onClose() }
        }
    }

    @ViewBuilder private var dialogActions: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                retryButton.frame(maxWidth: .infinity)
                saveButton.frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: 10) {
                retryButton
                saveButton
            }
        }
    }

    private var retryButton: some View {
        Button {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                focusedField = nil
                model.restartFlow()
            }
        } label: {
            Text(model.enrollsInSearchLibrary ? "重拍" : "重试").frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var saveButton: some View {
        Button {
            focusedField = nil
            if model.enrollsInSearchLibrary {
                model.saveSearchCapture()
            } else if model.saveCapturedReference() {
                onClose()
            }
        } label: {
            HStack(spacing: 7) {
                if model.isSavingCapture { ProgressView().controlSize(.small).tint(.white) }
                Text(model.isSavingCapture ? "正在保存…" : saveButtonTitle)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .foregroundStyle(.white)
        .controlSize(.large)
        .disabled(!model.canSaveCapturedReference)
    }

    private var saveButtonTitle: String {
        model.enrollsInSearchLibrary ? "保存" : "完成"
    }
}
