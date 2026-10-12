import SwiftUI

/// 与 Android 采集确认框一致的白色卡片；不使用会透出相机暗色的毛玻璃材质。
/// 内容过高时在安全区内滚动，短内容保持自适应高度。
struct CameraDialog<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(reduceTransparency ? 0.48 : 0.32).ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16, content: content)
                        .padding(24)
                        .frame(maxWidth: .infinity)
                        .background(GeometryReader { contentGeometry in
                            Color.clear.preference(key: CameraDialogHeightKey.self, value: contentGeometry.size.height)
                        })
                }
                // Preference 首帧还是 0；先保留最小高度，避免弹框从一条细线跳变为完整卡片。
                .frame(height: min(max(120, contentHeight), max(120, geometry.size.height - 48)))
                .onPreferenceChange(CameraDialogHeightKey.self) { contentHeight = $0 }
                .background(dialogShape.fill(.white))
                .clipShape(dialogShape)
                .shadow(color: .black.opacity(0.14), radius: 24, y: 10)
                .frame(maxWidth: horizontalSizeClass == .regular ? 420 : 360)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Color.primary)
        .tint(DemoTheme.contentAccent)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        // 只覆盖卡片内容，避免深色相机页把输入框、次要文字和键盘变成深色。
        .environment(\.colorScheme, .light)
        .accessibilityAddTraits(.isModal)
    }

    private var dialogShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }
}

enum CameraDialogSymbolPlacement {
    case top
    case leading
}

struct CameraDialogTitle: View {
    let title: String
    let subtitle: String
    let symbol: String
    var symbolPlacement: CameraDialogSymbolPlacement = .top
    var symbolScale: CGFloat = 1
    var textScale: CGFloat = 1
    @ScaledMetric(relativeTo: .title2) private var symbolFontSize: CGFloat = 22
    @ScaledMetric(relativeTo: .title3) private var titleFontSize: CGFloat = 20
    @ScaledMetric(relativeTo: .subheadline) private var subtitleFontSize: CGFloat = 15

    var body: some View {
        Group {
            if symbolPlacement == .leading {
                HStack(alignment: .center, spacing: 12) {
                    symbolView
                    titleText(alignment: .leading)
                }
            } else {
                VStack(spacing: 10) {
                    symbolView
                    titleText(alignment: .center)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
    }

    private var symbolView: some View {
        Image(systemName: symbol)
            .font(.system(size: symbolFontSize * symbolScale, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(DemoTheme.contentAccent)
            .padding(14 * symbolScale)
            .background(DemoTheme.contentAccent.opacity(0.08), in: Circle())
            .accessibilityHidden(true)
    }

    private func titleText(alignment: TextAlignment) -> some View {
        VStack(alignment: alignment == .leading ? .leading : .center, spacing: 5) {
            Text(title)
                .font(.system(size: titleFontSize * textScale, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.system(size: subtitleFontSize * textScale))
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .multilineTextAlignment(alignment)
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }
}

private struct CameraDialogHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 应用内提示统一用不透明白色卡片，窗口仍可保留深色预览和可读的状态栏。
/// 模态层阻止底层操作和 VoiceOver 穿透；关闭动作由调用处显式更新状态。
extension View {
    func demoDialog<Content: View>(
        isPresented: Bool,
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        self
            .allowsHitTesting(!isPresented)
            .accessibilityHidden(isPresented)
            .overlay {
                if isPresented {
                    CameraDialog(content: content)
                        .buttonStyle(DemoDialogButtonStyle())
                        .accessibilityAction(.escape, onDismiss)
                }
            }
    }
}

/// 普通操作以品牌绿突出，取消使用浅底，删除等破坏性操作保留系统红色语义。
private struct DemoDialogButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let isCancel = configuration.role == .cancel
        let accent = configuration.role == .destructive ? Color.red : DemoTheme.contentAccent
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 24)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .foregroundStyle(isCancel ? Color.primary : Color.white)
            .background(isCancel ? Color(uiColor: .secondarySystemBackground) : accent,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
    }
}
