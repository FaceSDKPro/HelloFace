import SwiftUI
import UIKit
import Darwin
import os

struct DemoHomeView: View {
    @State private var showsAbout = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("HiFace SDK").font(.title2.weight(.bold))
                            Text(DemoL10n.text("离线｜数据安全｜高效"))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        Spacer()
                        Button { showsAbout = true } label: {
                            Image(systemName: "info.circle")
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .background(.white.opacity(0.15), in: Circle())
                        }
                        .accessibilityLabel(DemoL10n.text("关于 HiFace SDK Demo"))
                    }
                    Text(DemoDeviceInfo.copyText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
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
                        ForEach(CameraDemoMode.allCases) { mode in
                            NavigationLink(destination: LazyDestination { CameraDemoView(mode: mode) }) {
                                DemoCard(title: mode.title, subtitle: mode.subtitle, icon: mode.icon)
                                    .accessibilityIdentifier("demo.feature.\(mode.id)")
                            }
                        }
                        NavigationLink(destination: LazyDestination { StaticFaceComparisonView() }) {
                            DemoCard(title: DemoL10n.text("静态人脸 1:1 对比"), subtitle: DemoL10n.text("比对两张图片中的人脸"), icon: "photo.on.rectangle.angled")
                        }
                        NavigationLink(destination: LazyDestination { CameraSettingsView() }) {
                            DemoCard(title: DemoL10n.text("摄像头参数设置"), subtitle: DemoL10n.text("设置分析分辨率与坐标镜像"), icon: "slider.horizontal.3")
                        }
                    }
                    .buttonStyle(HomeFeatureButtonStyle())
                    Button(DemoL10n.text("关于 HiFace SDK Demo")) { showsAbout = true }
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.top, 14)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }
            .background(DemoTheme.home.ignoresSafeArea())
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .navigationBarHidden(true)
            .demoDialog(isPresented: showsAbout, onDismiss: { showsAbout = false }) {
                CameraDialogTitle(
                    title: DemoL10n.text("关于 HiFace SDK Demo"),
                    subtitle: DemoL10n.text("更新以及更多说明：https://github.com/FaceSDKPro/"),
                    symbol: "info.circle"
                )
                Button(DemoL10n.text("知道了")) { showsAbout = false }
            }
            .preferredColorScheme(.dark)
        }
        .navigationViewStyle(.stack)
    }

    private func copyDeviceInfo() {
        let value = DemoDeviceInfo.copyText
        DemoDeviceInfo.logger.info("\(value, privacy: .public)")
        UIPasteboard.general.string = value
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

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

/// 避免 iOS 15 提前构造目标页面时创建相机或 Native Session。
struct LazyDestination<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View { content() }
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
                .symbolRenderingMode(.hierarchical)
                .frame(width: iconSize, height: iconSize)
                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.75))
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(minHeight: 68)
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.24)))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

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
