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
            Form {
                Section("搜索模式") {
                    Picker("模式", selection: $mode) {
                        Text("单人 1:N").tag(FaceSearchMode.singleFace)
                        Text("多人 M:N").tag(FaceSearchMode.multipleFaces)
                    }
                    .pickerStyle(.segmented)
                    Toggle("单帧静默活体", isOn: $needsLiveness)
                        .disabled(mode == .multipleFaces)
                    if mode == .multipleFaces {
                        Stepper("单帧最多处理 \(maxFaces) 张脸", value: $maxFaces, in: 1...5)
                        Text("多人模式不执行活体；检测数可能大于实际选中处理数。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("搜索范围") {
                    TextField("分组（留空表示不限）", text: $group)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    TextField("标签（留空表示不限）", text: $tag)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
                Section("识别参数") {
                    VStack(alignment: .leading) {
                        Text(String(format: "相似度阈值 %.2f", threshold)).monospacedDigit()
                        Slider(value: $threshold, in: 0.75...0.85, step: 0.01)
                    }
                    Stepper(
                        "成功间隔 \(intervalMilliseconds) ms",
                        value: $intervalMilliseconds,
                        in: 0...3_000,
                        step: 500
                    )
                    Text("范围 0–3000 ms，默认 0；0 表示匹配成功后立即继续。该值不控制相机帧率。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Stepper(
                        "单轮超时 \(timeoutMilliseconds) ms",
                        value: $timeoutMilliseconds,
                        in: 1_000...3_000,
                        step: 500
                    )
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button("恢复默认参数", action: reset)
                }
            }
            .navigationTitle("人脸搜索设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用", action: apply)
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

    private func reset() {
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
                ?? error.localizedDescription
        }
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
