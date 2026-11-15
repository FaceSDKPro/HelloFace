import SwiftUI
import UIKit
import HiFace
import Darwin
import os

@MainActor
struct DemoHomeView: View {
    @Environment(\.openURL) private var openURL
    @State private var websiteToast: UUID?
    private let website = URL(string: "https://helloface.pages.dev/")!

    private var aboutTitle: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return DemoL10n.text("关于 HelloFace SDK {0}", [version])
    }

    private var websiteMessage: String {
        DemoL10n.text("更多：{0}", [website.absoluteString])
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("HiFace SDK").font(.title2.weight(.bold))
                            Text(DemoL10n.text("离线｜数据安全｜高效"))
                                .font(.caption)
                                .foregroundStyle(DemoTheme.homeSecondaryText)
                        }
                        Spacer()
                        Button { openWebsite() } label: {
                            Image(systemName: "info.circle")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(DemoTheme.homeSurface, in: Circle())
                        }
                        .accessibilityLabel(aboutTitle)
                    }
                    Text(DemoDeviceInfo.copyText)
                        .font(.caption)
                        .foregroundStyle(DemoTheme.homeSecondaryText)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, 4)
                        .padding(.top, 11)
                        .padding(.bottom, 12)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.5) { copyDeviceInfo() }
                        .accessibilityAction(named: Text(DemoL10n.text("复制设备信息"))) {
                            copyDeviceInfo()
                        }
                    VStack(spacing: 11) {
                        NavigationLink(destination: LazyDestination { CameraDemoView(mode: .detection) }) {
                            DemoCard(title: CameraDemoMode.detection.title, subtitle: CameraDemoMode.detection.subtitle, icon: CameraDemoMode.detection.icon)
                                .accessibilityIdentifier("demo.feature.\(CameraDemoMode.detection.id)")
                        }
                        NavigationLink(destination: FaceRecognitionMenuView()) {
                            DemoCard(title: DemoL10n.text("人脸识别"), subtitle: DemoL10n.text("通过相机进行 1:1 人脸识别与活体检测"), icon: "checkmark.shield")
                                .accessibilityIdentifier("demo.feature.recognition")
                        }
                        NavigationLink(destination: LazyDestination { CameraDemoView(mode: .search) }) {
                            DemoCard(title: CameraDemoMode.search.title, subtitle: CameraDemoMode.search.subtitle, icon: CameraDemoMode.search.icon)
                                .accessibilityIdentifier("demo.feature.\(CameraDemoMode.search.id)")
                        }
                        NavigationLink(destination: LazyDestination { StaticFaceComparisonView() }) {
                            DemoCard(title: DemoL10n.text("静态人脸 1:1 对比"), subtitle: DemoL10n.text("比对两张图片中的人脸"), icon: "photo.on.rectangle.angled")
                        }
                        NavigationLink(destination: LazyDestination { FaceImageSearchView() }) {
                            DemoCard(title: DemoL10n.text("图片人脸搜索识别"), subtitle: DemoL10n.text("检测图片中的多个人脸并搜索人脸库"), icon: "person.crop.rectangle.stack")
                        }
                        NavigationLink(destination: LazyDestination { CameraSettingsView() }) {
                            DemoCard(title: DemoL10n.text("SDK参数设置"), subtitle: DemoL10n.text("设置分析分辨率与坐标镜像"), icon: "slider.horizontal.3")
                        }
                    }
                    .buttonStyle(HomeFeatureButtonStyle())
                    Button(aboutTitle) { openWebsite() }
                        .font(.caption)
                        .foregroundStyle(DemoTheme.homeSecondaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .background(DemoTheme.homeBackground.ignoresSafeArea())
            .foregroundStyle(DemoTheme.homeText)
            .buttonStyle(.plain)
            .navigationBarHidden(true)
            .overlay(alignment: .bottom) {
                if websiteToast != nil {
                    Text(websiteMessage)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(16)
                        .allowsHitTesting(false)
                }
            }
            .task(id: websiteToast) {
                guard websiteToast != nil else { return }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled { websiteToast = nil }
            }
            .preferredColorScheme(.dark)
        }
        .navigationViewStyle(.stack)
    }

    private func openWebsite() {
        websiteToast = nil
        openURL(website) { accepted in
            if !accepted {
                websiteToast = UUID()
            }
        }
    }

    private func copyDeviceInfo() {
        let value = DemoDeviceInfo.copyText
        DemoDeviceInfo.logger.info("\(value, privacy: .public)")
        UIPasteboard.general.string = value
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

/// Device diagnostics are for the Demo home screen only; hardware model approximates Android's Board
/// field.
/// 设备诊断信息仅用于 Demo 主页；硬件型号是 Android Board 的近似字段。
@MainActor
private enum DemoDeviceInfo {
    static let values: [String] = {
        #if targetEnvironment(simulator)
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]
            ?? hardwareValue("hw.machine", fallback: UIDevice.current.model)
        #else
        let model = hardwareValue("hw.machine", fallback: UIDevice.current.model)
        #endif
        return [
            UIDevice.current.systemVersion, model, hardwareValue("hw.model", fallback: "-")
        ]
    }()
    static let copyText = values.joined(separator: "/")
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.hiface.demo", category: "DeviceInfo")

    private static func hardwareValue(_ name: String, fallback: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return fallback }
        var buffer = [CChar](repeating: 0, count: size)
        let result = buffer.withUnsafeMutableBufferPointer {
            sysctlbyname(name, $0.baseAddress, &size, nil, 0)
        }
        guard result == 0, let end = buffer.firstIndex(of: 0) else { return fallback }
        let value = String(decoding: buffer[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return value.isEmpty ? fallback : value
    }
}

/// Avoid creating cameras or Native Sessions when iOS 15 constructs destination screens early.
/// 避免 iOS 15 提前构造目标页面时创建相机或 Native Session。
struct LazyDestination<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View { content() }
}

@MainActor
private struct FaceRecognitionMenuView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var verification = RecognitionOptions()
    @State private var liveness = RecognitionOptions()
    @State private var references: [String] = []
    @State private var request: RecognitionRequest?
    @State private var result: RecognitionInlineResult?
    @State private var deletingReference: ReferenceDeletion?

    var body: some View {
        ScrollViewReader { scroll in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                recognitionCard {
                    Text(DemoL10n.text("1:1 人脸验证")).font(.headline)
                    Text(DemoL10n.text("选择已录入的人脸，与当前相机人脸进行比对")).font(.footnote).foregroundStyle(DemoTheme.contentSecondaryText)
                    RecognitionOptionsEditor(options: $verification, standalone: false)
                    HStack {
                        Text(DemoL10n.text("已录入的人脸")).font(.subheadline.bold())
                        Spacer()
                        NavigationLink(destination: LazyDestination { CameraDemoView(mode: .capture) }) {
                            Text(DemoL10n.text("＋ 采集人脸")).font(.subheadline)
                        }
                    }.padding(.top, 2)
                    Text(DemoL10n.text(references.isEmpty ? "暂无参考人脸，请先采集并保存 Face ID。" : "左右滑动，点击头像开始 1:1 验证，长按删除"))
                        .font(.caption).foregroundStyle(DemoTheme.contentSecondaryText)
                    ScrollView(.horizontal, showsIndicators: true) {
                        LazyHStack(alignment: .top, spacing: 14) {
                            ForEach(references, id: \.self) { faceID in
                                VStack(spacing: 8) {
                                    FacePhotoThumbnail(faceID: faceID, diameter: 64, circular: true)
                                    Text(faceID).font(.caption).lineLimit(2).multilineTextAlignment(.center)
                                }
                                .frame(width: 80).padding(.vertical, 2)
                                .contentShape(Rectangle())
                                // Moving beyond the tap tolerance yields to the horizontal ScrollView.
                                .gesture(LongPressGesture(minimumDuration: 0.5, maximumDistance: 12)
                                    .exclusively(before: TapGesture())
                                    .onEnded { gesture in
                                        switch gesture {
                                        case .first(true): deletingReference = ReferenceDeletion(faceID: faceID)
                                        case .second: startRecognition(verification, faceID: faceID)
                                        default: break
                                        }
                                    })
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(DemoL10n.text("验证 {0}，长按删除", [faceID]))
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { startRecognition(verification, faceID: faceID) }
                                .accessibilityAction(named: Text(DemoL10n.text("删除"))) {
                                    deletingReference = ReferenceDeletion(faceID: faceID)
                                }
                            }
                        }
                    }
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
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(Color.white)
                }
                .offset(x: -4)
                .accessibilityLabel(DemoL10n.text("返回"))
            }
        }
        .recognitionNavigationAppearance()
        .preferredColorScheme(.light)
        .onAppear {
            do { references = try DemoFaceStore.faceIDs() }
            catch { result = RecognitionInlineResult(title: DemoL10n.text("读取参考人脸失败"), detail: error.localizedDescription, passed: false) }
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
            Task { await FacePhotoStore.remove(faceID: faceID) }
        } catch {
            result = RecognitionInlineResult(title: DemoL10n.text("删除失败"),
                detail: error.localizedDescription, passed: false)
        }
    }

    private func recognitionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .foregroundStyle(DemoTheme.contentText)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08)))
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
    var enabled = false
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
        VStack(alignment: .leading, spacing: 10) {
            if !standalone {
                Toggle(isOn: $options.silent) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(DemoL10n.text("静默活体")).font(.subheadline.bold())
                        Text(DemoL10n.text("检测是否为真人，无需指定动作")).font(.caption).foregroundStyle(DemoTheme.contentSecondaryText)
                    }
                }
            }
            Toggle(isOn: $options.enabled) {
                VStack(alignment: .leading, spacing: 3) {
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
                .font(.caption).foregroundStyle(DemoTheme.contentAccent).padding(10)
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

private struct DemoCard: View {
    let title: String
    let subtitle: String
    let icon: String
    @ScaledMetric(relativeTo: .body) private var iconSize = 36

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.title3.weight(.medium))
                .symbolRenderingMode(.monochrome)
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(DemoTheme.homeText)
                .background(DemoTheme.homeSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(DemoTheme.homeBorder))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(DemoTheme.homeSecondaryText)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DemoTheme.homeArrow)
                .frame(width: 28, height: 28)
                .background(DemoTheme.homeArrowSurface, in: Circle())
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(minHeight: 68)
        .background(DemoTheme.homeSurface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(DemoTheme.homeBorder))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

/// Preserve NavigationLink system navigation and accessibility actions; add only lightweight press
/// feedback.
/// 保留 NavigationLink 的系统导航与辅助操作，仅补充轻量按下反馈。
private struct HomeFeatureButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
