import SwiftUI

struct DemoHomeView: View {
    @State private var showsAbout = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("HiFace SDK").font(.title2.weight(.bold))
                            Text("离线｜数据安全｜高效")
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
                        .accessibilityLabel("关于 HiFace SDK Demo")
                    }
                    Text("选择一项能力开始体验")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.top, 22)
                        .padding(.bottom, 12)
                    VStack(spacing: 11) {
                        ForEach(CameraDemoMode.allCases) { mode in
                            NavigationLink(destination: LazyDestination { CameraDemoView(mode: mode) }) {
                                DemoCard(title: mode.rawValue, subtitle: mode.subtitle, icon: mode.icon)
                            }
                        }
                        NavigationLink(destination: LazyDestination { StaticFaceComparisonView() }) {
                            DemoCard(title: "静态人脸 1:1 对比", subtitle: "比较两张静态图片中的人脸", icon: "photo.on.rectangle.angled")
                        }
                        NavigationLink(destination: LazyDestination { CameraSettingsView() }) {
                            DemoCard(title: "摄像头参数设置", subtitle: "设置分析分辨率与坐标镜像", icon: "slider.horizontal.3")
                        }
                    }
                    .buttonStyle(HomeFeatureButtonStyle())
                    Button("关于 HiFace SDK Demo") { showsAbout = true }
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
                    title: "关于 HiFace SDK Demo",
                    subtitle: "更新以及更多说明：https://github.com/FaceSDKPro/",
                    symbol: "info.circle"
                )
                Button("知道了") { showsAbout = false }
            }
            .preferredColorScheme(.dark)
        }
        .navigationViewStyle(.stack)
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
