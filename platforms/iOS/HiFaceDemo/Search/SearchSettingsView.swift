import HiFace
import SwiftUI

enum DemoFaceSearchConfiguration {
    /// 默认匹配成功后立即开始下一轮；仅影响成功后的下一轮搜索。
    static let successIntervalMilliseconds = 0
    static let recommended = (try? FaceSearchSessionConfiguration(
        searchIntervalMilliseconds: successIntervalMilliseconds
    )) ?? .default
}

struct SearchSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let onApply: (FaceSearchSessionConfiguration) -> Void

    @State private var mode: FaceSearchMode
    @State private var group: String
    @State private var tag: String
    @State private var needsLiveness: Bool
    @State private var threshold: Float
    @State private var intervalMilliseconds: Int
    @State private var timeoutMilliseconds: Int
    @State private var maxFaces: Int
    @State private var errorMessage: String?
    @FocusState private var focusedField: InputField?

    private enum InputField: String, Hashable { case group, tag }

    init(
        configuration: FaceSearchSessionConfiguration,
        onApply: @escaping (FaceSearchSessionConfiguration) -> Void
    ) {
        self.onApply = onApply
        _mode = State(initialValue: configuration.mode)
        _group = State(initialValue: configuration.group ?? "")
        _tag = State(initialValue: configuration.tag ?? "")
        _needsLiveness = State(initialValue: configuration.needsLiveness)
        _threshold = State(initialValue: configuration.threshold)
        _intervalMilliseconds = State(initialValue: configuration.searchIntervalMilliseconds)
        _timeoutMilliseconds = State(initialValue: configuration.searchTimeoutMilliseconds)
        _maxFaces = State(initialValue: configuration.maxFacesPerFrame)
    }

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        settingsSection(DemoL10n.text("搜索模式")) {
                            Picker(DemoL10n.text("模式"), selection: $mode) {
                                Text(DemoL10n.text("单人 1:N")).tag(FaceSearchMode.singleFace)
                                Text(DemoL10n.text("多人 M:N")).tag(FaceSearchMode.multipleFaces)
                            }
                            .pickerStyle(.segmented)
                            Toggle(DemoL10n.text("单帧静默活体"), isOn: $needsLiveness)
                                .disabled(mode == .multipleFaces)
                            if mode == .multipleFaces {
                                Stepper(DemoL10n.text("单帧最多处理 {0} 张脸", [String(describing: maxFaces)]), value: $maxFaces, in: 1...5)
                                Text(DemoL10n.text("多人模式不检测活体；仅处理选中人脸。"))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        settingsSection(DemoL10n.text("搜索范围")) {
                            TextField(DemoL10n.text("分组（留空表示不限）"), text: $group)
                                .demoTextInputStyle()
                                .focused($focusedField, equals: .group)
                                .submitLabel(.next)
                                .onSubmit { focusedField = .tag }
                                .id(InputField.group.rawValue)
                            TextField(DemoL10n.text("标签（留空表示不限）"), text: $tag)
                                .demoTextInputStyle()
                                .focused($focusedField, equals: .tag)
                                .submitLabel(.done)
                                .onSubmit { focusedField = nil }
                                .id(InputField.tag.rawValue)
                        }
                        settingsSection(DemoL10n.text("识别参数")) {
                            VStack(alignment: .leading) {
                                Text(String(format: DemoL10n.text("相似度阈值 %.2f"), threshold)).monospacedDigit()
                                Slider(value: $threshold, in: 0.75...0.85, step: 0.01)
                            }
                            Stepper(
                                DemoL10n.text("成功间隔 {0} ms", [String(describing: intervalMilliseconds)]),
                                value: $intervalMilliseconds,
                                in: 0...3_000,
                                step: 500
                            )
                            Text(DemoL10n.text("0–3000 ms，默认 0；匹配成功后等待，不控制帧率。"))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Stepper(
                                DemoL10n.text("单轮超时 {0} ms", [String(describing: timeoutMilliseconds)]),
                                value: $timeoutMilliseconds,
                                in: 1_000...3_000,
                                step: 500
                            )
                        }
                        if let errorMessage {
                            Text(errorMessage).font(.footnote).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button(DemoL10n.text("恢复默认参数"), action: reset)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 16)
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .onChange(of: focusedField) { field in
                    guard let field else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(field.rawValue, anchor: .center) }
                }
            }
            .navigationTitle(DemoL10n.text("人脸搜索设置"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DemoL10n.text("取消")) { focusedField = nil; dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(DemoL10n.text("应用"), action: apply)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(DemoL10n.text("完成")) { focusedField = nil }
                }
            }
            .onChange(of: mode) { next in
                needsLiveness = next == .singleFace
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.light)
        .environment(\.colorScheme, .light)
        .tint(DemoTheme.contentAccent)
    }

    private func settingsSection<Content: View>(
        _ title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 14, content: content)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func reset() {
        focusedField = nil
        let value = DemoFaceSearchConfiguration.recommended
        mode = value.mode
        group = value.group ?? ""
        tag = value.tag ?? ""
        needsLiveness = value.needsLiveness
        threshold = value.threshold
        intervalMilliseconds = value.searchIntervalMilliseconds
        timeoutMilliseconds = value.searchTimeoutMilliseconds
        maxFaces = value.maxFacesPerFrame
        errorMessage = nil
    }

    private func apply() {
        focusedField = nil
        do {
            let value = try FaceSearchSessionConfiguration(
                mode: mode,
                group: normalized(group),
                tag: normalized(tag),
                needsLiveness: needsLiveness,
                threshold: threshold,
                searchIntervalMilliseconds: intervalMilliseconds,
                searchTimeoutMilliseconds: timeoutMilliseconds,
                maxFacesPerFrame: maxFaces
            )
            onApply(value)
            dismiss()
        } catch {
            errorMessage = (error as? HiFaceError).map { DemoErrorPresentation.message(for: $0) }
                ?? DemoErrorPresentation.message(for: error)
        }
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
