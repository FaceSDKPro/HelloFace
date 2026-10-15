import SwiftUI
import UIKit

/// 与 Android 采集确认框一致的白色卡片；不使用会透出相机暗色的毛玻璃材质。
/// 内容过高时在安全区内滚动，短内容保持自适应高度。
struct CameraDialog<Content: View, Actions: View>: View {
    @ViewBuilder let content: () -> Content
    @ViewBuilder let actions: () -> Actions
    let horizontalMargin: CGFloat
    let scrollTarget: String?
    let hasActions: Bool
    @State private var contentHeight: CGFloat = 0
    @State private var actionsHeight: CGFloat = 0
    @State private var scrollRequest = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    init(horizontalMargin: CGFloat = 12, scrollTarget: String? = nil, @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.content = content
        self.actions = actions
        self.scrollTarget = scrollTarget
        self.horizontalMargin = horizontalMargin
        hasActions = true
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(reduceTransparency ? 0.48 : 0.32).ignoresSafeArea()
                VStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 14, content: content)
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                                .padding(.bottom, scrollTarget == nil ? 20 : 48)
                                .frame(maxWidth: .infinity)
                                .background(GeometryReader { contentGeometry in
                                    Color.clear.preference(key: CameraDialogHeightKey.self, value: contentGeometry.size.height)
                                })
                        }
                        .frame(height: min(max(120, contentHeight), max(0, geometry.size.height - actionsHeight - 24)))
                        .onChange(of: scrollTarget) { _ in revealInput(using: proxy) }
                        .onChange(of: geometry.size.height) { _ in revealInput(using: proxy) }
                        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                            revealInput(using: proxy)
                        }
                    }
                    if hasActions {
                        VStack(spacing: 0) {
                            Divider()
                            actions().padding(16)
                        }
                        .background(GeometryReader { actionGeometry in
                            Color.clear.preference(key: CameraDialogActionsHeightKey.self, value: actionGeometry.size.height)
                        })
                    }
                }
                .onPreferenceChange(CameraDialogHeightKey.self) { contentHeight = $0 }
                .onPreferenceChange(CameraDialogActionsHeightKey.self) { actionsHeight = $0 }
                .background(dialogShape.fill(.white))
                .clipShape(dialogShape)
                .shadow(color: .black.opacity(0.14), radius: 24, y: 10)
                .frame(maxWidth: horizontalSizeClass == .regular ? 560 : 480)
                .padding(.horizontal, horizontalMargin)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Color.primary)
        .tint(DemoTheme.contentAccent)
        .buttonBorderShape(.roundedRectangle(radius: 12))
        // 只覆盖卡片内容，避免深色相机页把输入框、次要文字和键盘变成深色。
        .environment(\.colorScheme, .light)
        .accessibilityAddTraits(.isModal)
        .onDisappear { scrollRequest += 1 }
    }

    private var dialogShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
    }

    private func revealInput(using proxy: ScrollViewProxy) {
        scrollRequest += 1
        let request = scrollRequest
        guard let scrollTarget else { return }
        // 等键盘和系统的光标滚动完成，再把包含标签与内边距的整块输入区移入视口。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            guard scrollRequest == request else { return }
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(scrollTarget, anchor: .center) }
        }
    }
}

extension CameraDialog where Actions == EmptyView {
    init(horizontalMargin: CGFloat = 12, scrollTarget: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.content = content
        actions = { EmptyView() }
        self.scrollTarget = scrollTarget
        self.horizontalMargin = horizontalMargin
        hasActions = false
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
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: subtitleFontSize * textScale))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
            }
        }
        .multilineTextAlignment(alignment)
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
    }
}

private struct CameraDialogHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct CameraDialogActionsHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// 应用内提示统一用不透明白色卡片，窗口仍可保留深色预览和可读的状态栏。
/// 模态层阻止底层操作和 VoiceOver 穿透；关闭动作由调用处显式更新状态。
extension View {
    func demoTextInputStyle() -> some View {
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .textFieldStyle(.plain)
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

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
