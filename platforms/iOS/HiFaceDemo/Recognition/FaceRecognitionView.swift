import SwiftUI
import UIKit
import HiFace

@MainActor
struct FaceRecognitionView: View {
    @Environment(\.dismiss) private var dismiss
    // Keep separate option drafts for verification and standalone liveness.
    @State private var verification = RecognitionOptions()
    @State private var liveness = RecognitionOptions()
    @State private var references: [String] = []
    // A request snapshots the options and reference ID for the next camera destination.
    @State private var request: RecognitionRequest?
    // Show this result inline after the camera screen returns.
    @State private var result: RecognitionInlineResult?
    @State private var deletingReference: ReferenceDeletion?
    @State private var pickingReference = false
    // The page cancels extraction on exit. The confirmation owns only the staged sample.
    @State private var albumExtraction: Task<Void, Never>?
    // Reuse the camera capture model only for its staged sample and confirmation/save behavior.
    @State private var albumConfirmation: CameraDemoModel?
    @State private var albumError: String?

    var body: some View {
        ScrollViewReader { scroll in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                recognitionCard {
                    Text(DemoL10n.text("1:1 人脸验证")).font(.headline)
                    Text(DemoL10n.text("选择已录入的人脸，与当前相机人脸进行比对")).font(.footnote).foregroundStyle(DemoTheme.contentSecondaryText)
                    RecognitionOptionsEditor(options: $verification, standalone: false)
                    Text(DemoL10n.text("已录入的人脸")).font(.subheadline.bold())
                    Text(DemoL10n.text(references.isEmpty ? "暂无已录入的人脸。" : "左右滑动，点击头像开始 1:1 验证，长按删除"))
                        .font(.caption).foregroundStyle(DemoTheme.contentSecondaryText)
                    if !references.isEmpty { referenceList }
                    HStack(spacing: 16) {
                        Button {
                            albumError = nil
                            pickingReference = true
                        } label: {
                            Text(DemoL10n.text("相册添加")).frame(maxWidth: .infinity, minHeight: 42).contentShape(Rectangle())
                        }
                        NavigationLink(destination: LazyDestination { CameraDemoView(mode: .capture) }) {
                            Text(DemoL10n.text("相机录入")).frame(maxWidth: .infinity, minHeight: 42).contentShape(Rectangle())
                        }
                    }
                    .buttonStyle(.plain).font(.subheadline.bold()).foregroundStyle(DemoTheme.homeBackground)
                    if albumExtraction != nil { ProgressView() }
                    if let albumError { Text(albumError).font(.footnote).foregroundStyle(.red) }
                }
                recognitionCard {
                    Text(DemoL10n.text("独立活体检测")).font(.headline)
                    Text(DemoL10n.text("不比对身份。静默活体始终开启，可叠加动作挑战。")).font(.footnote).foregroundStyle(DemoTheme.contentSecondaryText)
                    RecognitionOptionsEditor(options: $liveness, standalone: true)
                    Button {
                        startRecognition(liveness)
                    } label: {
                        Text(DemoL10n.text("开始活体检测"))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }.buttonStyle(.borderedProminent)
                }
                if let result {
                    recognitionCard {
                        Text(DemoL10n.text(result.passed ? "检测通过" : "检测未通过"))
                            .font(.caption.bold()).foregroundStyle(result.passed ? DemoTheme.contentAccent : .red)
                        Text(result.title).font(.headline)
                        if !result.detail.isEmpty { Text(result.detail).font(.subheadline).foregroundStyle(DemoTheme.contentSecondaryText) }
                    }
                    .id("recognition.result")
                    .accessibilityIdentifier("recognition.result")
                }
            }.padding(.horizontal, 12).padding(.vertical, 10)
        }
        .onChange(of: result?.id) { _ in
            if result != nil { scroll.scrollTo("recognition.result", anchor: .bottom) }
        }
        .onAppear {
            if result != nil { scroll.scrollTo("recognition.result", anchor: .bottom) }
        }
        }
        .disabled(albumExtraction != nil || albumConfirmation != nil)
        .accessibilityHidden(albumConfirmation != nil)
        .overlay {
            if let model = albumConfirmation {
                CaptureConfirmation(model: model, onRetry: {
                    albumConfirmation = nil
                    pickingReference = true
                }, onClose: {
                    albumConfirmation = nil
                    reloadReferences()
                })
                .accessibilityAddTraits(.isModal)
            }
        }
        .sheet(isPresented: $pickingReference) {
            FacePhotoPicker(maximumPixelSize: FacePhotoPicker.imageSearchMaximumPixelSize, onCompletion: pickedReference)
        }
        .background(DemoTheme.content.ignoresSafeArea())
        .foregroundStyle(Color.primary)
        .tint(DemoTheme.contentAccent)
        .navigationTitle(DemoL10n.text("人脸识别"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(DemoL10n.text("人脸识别"))
                    .font(.headline)
                    .foregroundStyle(Color.white)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    if albumConfirmation != nil { albumConfirmation = nil } else { dismiss() }
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Color.white)
                }
                .offset(x: -4)
                .accessibilityLabel(DemoL10n.text("返回"))
            }
        }
        .recognitionNavigationAppearance()
        .preferredColorScheme(.light)
        .onAppear(perform: reloadReferences)
        .onDisappear {
            albumExtraction?.cancel()
            albumExtraction = nil
            albumConfirmation = nil
        }
        .alert(item: $deletingReference) { reference in
            Alert(title: Text(DemoL10n.text("删除这条人脸？")),
                message: Text(DemoL10n.text("Face ID：{0}\n\n删除后需重新录入。", [reference.faceID])),
                primaryButton: .destructive(Text(DemoL10n.text("删除"))) {
                    deleteReference(reference.faceID)
                }, secondaryButton: .cancel(Text(DemoL10n.text("取消"))))
        }
        .background {
            NavigationLink(isActive: Binding(get: { request != nil }, set: { if !$0 { request = nil } })) {
                LazyDestination {
                    if let request {
                        CameraDemoView(mode: request.faceID == nil ? .liveness : .verification,
                            recognitionActions: request.options.actions, recognitionSilent: request.options.silent,
                            recognitionReferenceID: request.faceID, onRecognitionResult: returnedResult).id(request.id)
                    }
                }
            } label: { EmptyView() }
        }
    }

    private var referenceList: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            LazyHStack(alignment: .top, spacing: 14) {
                ForEach(references, id: \.self) { faceID in
                    Button {
                        startRecognition(verification, faceID: faceID)
                    } label: {
                        VStack(spacing: 8) {
                            FacePhotoThumbnail(faceID: faceID, library: .reference, diameter: 64, circular: true)
                            Text(faceID).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                        }
                        .frame(width: 80).padding(.vertical, 2).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { deletingReference = ReferenceDeletion(faceID: faceID) } label: {
                            Label(DemoL10n.text("删除"), systemImage: "trash")
                        }
                    }
                    .accessibilityLabel(DemoL10n.text("验证 {0}，长按删除", [faceID]))
                    .accessibilityAction(named: Text(DemoL10n.text("删除"))) {
                        deletingReference = ReferenceDeletion(faceID: faceID)
                    }
                }
            }
        }
    }

    // Re-read IDs after returning from enrollment; features remain in the private reference store.
    private func reloadReferences() {
        #if DEBUG
        if let ids = ProcessInfo.processInfo.environment["HIFACE_UI_TEST_REFERENCE_IDS"] {
            references = ids.components(separatedBy: ",")
            return
        }
        #endif
        do { references = try DemoFaceStore.faceIDs() }
        catch { result = RecognitionInlineResult(title: DemoL10n.text("读取参考人脸失败"), detail: error.localizedDescription, passed: false) }
    }

    // Build the shared confirmation from a photo without starting the camera.
    private func pickedReference(_ selection: Result<HiFaceRGBAImage, HiFaceError>?) {
        pickingReference = false
        guard let selection else { return }
        albumExtraction = Task {
            do {
                let image = try selection.get()
                let model = CameraDemoModel(mode: .capture)
                try await model.prepareAlbumReference(image)
                try Task.checkCancellation()
                albumConfirmation = model
            } catch {
                if !Task.isCancelled { albumError = DemoErrorPresentation.message(for: error) }
            }
            if !Task.isCancelled { albumExtraction = nil }
        }
    }

    // A Face ID selects 1:1 verification. An absent ID starts standalone liveness.
    private func startRecognition(_ options: RecognitionOptions, faceID: String? = nil) {
        guard options.valid else { return }
        result = nil
        request = RecognitionRequest(options: options, faceID: faceID)
    }

    private func returnedResult(_ title: String, _ detail: String, _ passed: Bool) {
        result = RecognitionInlineResult(title: title, detail: detail, passed: passed)
    }

    private func deleteReference(_ faceID: String) {
        do {
            try DemoFaceStore.delete(faceID: faceID)
            references.removeAll { $0 == faceID }
            Task { await FacePhotoStore.remove(faceID: faceID, library: .reference) }
        } catch {
            result = RecognitionInlineResult(title: DemoL10n.text("删除失败"),
                detail: error.localizedDescription, passed: false)
        }
    }

    private func recognitionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .foregroundStyle(DemoTheme.contentText)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08)).allowsHitTesting(false))
    }
}

private struct RecognitionInlineResult {
    let id = UUID()
    let title: String
    let detail: String
    let passed: Bool
}

private struct ReferenceDeletion: Identifiable {
    let faceID: String
    var id: String { faceID }
}

/// A value snapshot prevents UI edits from changing a running camera request.
private struct RecognitionRequest {
    let id = UUID()
    let options: RecognitionOptions
    let faceID: String?
}

private struct RecognitionOptions {
    var silent = true
    var enabled = true
    var selected = [true, false, false, true]
    static let order: [FaceAction] = [.blink, .openMouth, .shakeHead, .nodHead]
    var actions: [FaceAction] { enabled ? Self.order.enumerated().compactMap { selected[$0.offset] ? $0.element : nil } : [] }
    var valid: Bool { !enabled || selected.contains(true) }
}

private struct RecognitionOptionsEditor: View {
    @Binding var options: RecognitionOptions
    let standalone: Bool
    private let titles = ["眨眼", "张嘴", "摇头", "点头"]
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if !standalone {
                Toggle(isOn: $options.silent) {
                    VStack(alignment: .leading, spacing: 3.3) {
                        Text(DemoL10n.text("静默活体")).font(.subheadline.bold())
                        Text(DemoL10n.text("检测是否为真人，无需指定动作")).font(.caption).foregroundStyle(DemoTheme.contentSecondaryText)
                    }
                }
            }
            Toggle(isOn: $options.enabled) {
                VStack(alignment: .leading, spacing: 3.3) {
                    Text(DemoL10n.text("动作活体")).font(.subheadline.bold())
                    Text(DemoL10n.text("勾选需要完成的动作")).font(.caption).foregroundStyle(DemoTheme.contentSecondaryText)
                }
            }
            if options.enabled {
                Text(DemoL10n.text(options.valid ? "至少选择一个动作，按下方顺序执行" : "请至少勾选一个动作"))
                    .font(.caption).foregroundStyle(options.valid ? DemoTheme.contentSecondaryText : .red)
                HStack(spacing: 6) {
                    ForEach(titles.indices, id: \.self) { index in
                        Button { options.selected[index].toggle() } label: {
                            VStack(spacing: 3) {
                                Image(systemName: options.selected[index] ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(options.selected[index] ? DemoTheme.contentAccent : DemoTheme.contentSecondaryText)
                                Text(DemoL10n.text(titles[index]))
                                    .font(.caption2).lineLimit(1).minimumScaleFactor(0.65)
                                    .foregroundStyle(DemoTheme.contentText)
                            }
                            .frame(maxWidth: .infinity, minHeight: 40)
                        }.buttonStyle(.plain)
                        .accessibilityLabel(DemoL10n.text(titles[index]))
                        .accessibilityAddTraits(options.selected[index] ? .isSelected : [])
                    }
                }
            }
            Text(DemoL10n.text(options.enabled ? "按勾选顺序完成动作，再正对镜头完成检测。" : standalone || options.silent
                ? "正对镜头即可，无需做指定动作。" : "仅进行 1:1 人脸比对，不进行活体检测。"))
                .font(.caption).foregroundStyle(DemoTheme.contentSecondaryText).padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DemoTheme.contentAccent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private extension View {
    @ViewBuilder
    func recognitionNavigationAppearance() -> some View {
        if #available(iOS 16.0, *) {
            self
                .toolbarBackground(DemoTheme.homeBackground, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        } else {
            self
        }
    }
}
