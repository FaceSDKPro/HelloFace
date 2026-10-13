import SwiftUI

struct StaticFaceComparisonView: View {
    @StateObject private var model = StaticFaceComparisonModel()
    @State private var pickingSide: ComparisonSide?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                guideCard

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 16) { photoCards }
                } else {
                    HStack(alignment: .top, spacing: 12) { photoCards }
                }

                if let similarity = model.similarity {
                    resultCard(similarity: similarity)
                } else if let error = model.comparisonError {
                    errorCard(error)
                }
            }
            .frame(maxWidth: 592)
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { navigationHeader }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                Button(action: model.compare) {
                    HStack(spacing: 10) {
                        if model.isComparing { ProgressView().tint(.white) }
                        Text(model.isComparing ? DemoL10n.text("正在比对…") : DemoL10n.text("开始比对"))
                            .font(.body.weight(.semibold))
                    }
                    .foregroundStyle(model.canCompare ? Color.white : Color(uiColor: .secondaryLabel))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(model.canCompare ? DemoTheme.contentAccent : Color(uiColor: .systemGray5))
                    }
                }
                .buttonStyle(.plain)
                .disabled(!model.canCompare)
                .frame(maxWidth: 592)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemBackground))
        }
        .tint(DemoTheme.contentAccent)
        // 主页使用深色品牌外观；比对页单独恢复浅色语义色，避免灰字落在深灰卡片上。
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        .navigationBarHidden(true)
        .sheet(item: $pickingSide) { side in
            FacePhotoPicker { result in
                pickingSide = nil
                switch result {
                case .success(let image):
                    model.load(image, into: side)
                case .failure(let error):
                    model.reportPickerError(error, for: side)
                case nil:
                    break
                }
            }
        }
        .onDisappear(perform: model.stop)
    }

    @ViewBuilder private var photoCards: some View {
        photoCard(side: .left, state: model.left)
        photoCard(side: .right, state: model.right)
    }

    private var navigationHeader: some View {
        ZStack {
            Text(DemoL10n.text("静态人脸比对"))
                .font(.headline)
                .foregroundStyle(.white)
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                        Text(DemoL10n.text("返回"))
                    }
                    .foregroundStyle(.white)
                    .frame(minWidth: 60, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DemoL10n.text("返回"))
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(DemoTheme.home.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Divider().overlay(.white.opacity(0.16)) }
    }

    private var guideCard: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: "person.crop.rectangle")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(DemoTheme.contentAccent)
                .frame(width: 42, height: 42)
                .background(DemoTheme.contentAccent.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(DemoL10n.text("选择两张清晰正脸照片"))
                    .font(.headline)
                    .foregroundStyle(Color(uiColor: .label))
                Text(DemoL10n.text("多人照片会自动选取画面中最大的人脸。"))
                    .font(.subheadline)
                    .foregroundStyle(Color(uiColor: .label).opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color(uiColor: .separator).opacity(0.42), lineWidth: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    private func photoCard(side: ComparisonSide, state: ComparisonPhotoState) -> some View {
        Button { pickingSide = side } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack(spacing: 8) {
                    Text(side.title)
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .label))
                    Spacer(minLength: 0)
                    stateBadge(state)
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemGroupedBackground))
                    if let preview = state.preview {
                        Image(decorative: preview, scale: 1)
                            .resizable()
                            .scaledToFill()
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.46)],
                            startPoint: .center,
                            endPoint: .bottom
                        )
                        Text(DemoL10n.text("轻点更换"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.34), in: Capsule())
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            .padding(10)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 26, weight: .medium))
                                .frame(width: 52, height: 52)
                                .background(DemoTheme.contentAccent.opacity(0.11), in: Circle())
                            Text(DemoL10n.text("选择照片"))
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(DemoTheme.contentAccent)
                    }
                    if state.isProcessing {
                        Color.white.opacity(0.82)
                        VStack(spacing: 10) {
                            ProgressView().tint(DemoTheme.contentAccent)
                            Text(DemoL10n.text("正在处理"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color(uiColor: .label))
                        }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(photoBorderColor(state), lineWidth: state.hasError ? 1.5 : 1)
                }
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: statusIcon(state))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(state))
                        .padding(.top, 1)
                    Text(statusText(state))
                        .font(.footnote)
                        .foregroundStyle(state.hasError ? Color.red : Color(uiColor: .label).opacity(0.7))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color(uiColor: .separator).opacity(0.42), lineWidth: 0.5)
            }
        }
        .buttonStyle(ComparisonPhotoButtonStyle())
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(side.title)，\(state.status)")
        .accessibilityHint(DemoL10n.text("打开系统照片选择器"))
    }

    private func stateBadge(_ state: ComparisonPhotoState) -> some View {
        Text(stateBadgeText(state))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(statusColor(state))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor(state).opacity(0.1), in: Capsule())
    }

    private func resultCard(similarity: Float) -> some View {
        VStack(spacing: 8) {
            Label(DemoL10n.text("比对完成"), systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DemoTheme.contentAccent)
            Text(String(format: "%.2f%%", similarity * 100))
                .font(.system(.largeTitle, design: .rounded).monospacedDigit().bold())
                .foregroundStyle(Color(uiColor: .label))
            Text(DemoL10n.text("人脸相似度"))
                .font(.caption)
                .foregroundStyle(Color(uiColor: .secondaryLabel))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(DemoTheme.contentAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(DemoTheme.contentAccent.opacity(0.22), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DemoL10n.text("人脸相似度 {0} 百分比", [String(describing: similarity * 100)]))
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(uiColor: .label))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.red.opacity(0.18), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private func stateBadgeText(_ state: ComparisonPhotoState) -> String {
        if state.hasError { return DemoL10n.text("需重选") }
        if state.isProcessing { return DemoL10n.text("处理中") }
        if state.feature != nil { return DemoL10n.text("已就绪") }
        return DemoL10n.text("待选择")
    }

    private func statusText(_ state: ComparisonPhotoState) -> String {
        if state.preview == nil && !state.isProcessing && !state.hasError {
            return DemoL10n.text("点击卡片选择照片")
        }
        return state.status
    }

    private func statusIcon(_ state: ComparisonPhotoState) -> String {
        if state.hasError { return "exclamationmark.circle.fill" }
        if state.isProcessing { return "clock.fill" }
        if state.feature != nil { return "checkmark.circle.fill" }
        return "info.circle.fill"
    }

    private func statusColor(_ state: ComparisonPhotoState) -> Color {
        state.hasError ? .red : (state.feature != nil ? DemoTheme.contentAccent : Color(uiColor: .secondaryLabel))
    }

    private func photoBorderColor(_ state: ComparisonPhotoState) -> Color {
        if state.hasError { return .red.opacity(0.72) }
        if state.feature != nil { return DemoTheme.contentAccent.opacity(0.58) }
        return Color(uiColor: .separator).opacity(0.55)
    }
}

private struct ComparisonPhotoButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
