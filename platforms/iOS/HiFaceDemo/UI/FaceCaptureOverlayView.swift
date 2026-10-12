import SwiftUI

/// 采集、验证和活体共用的引导布局。预览短边只比圆圈直径多一圈安全余量。
enum FaceCaptureLayout {
    static let previewMargin: CGFloat = 24

    static func circleBounds(
        in size: CGSize,
        statusHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> CGRect {
        let portrait = size.height >= size.width
        let desiredDiameter = min(size.width, size.height) * (portrait ? 0.8 : 0.7)
        let top = topInset + 72 + statusHeight + 12
        let bottom = max(top, size.height - bottomInset - 60)
        let diameter = min(desiredDiameter, max(0, bottom - top))
        let radius = diameter / 2
        let centerY = min(max(size.height * (portrait ? 0.43 : 0.5), top + radius), bottom - radius)
        return CGRect(x: (size.width - diameter) / 2, y: centerY - radius,
                      width: diameter, height: diameter)
    }

    static func previewShortSide(circle: CGRect, availableSize: CGSize) -> CGFloat {
        min(min(availableSize.width, availableSize.height), circle.width + previewMargin)
    }
}

/// 对应 Android ui/FaceCaptureOverlayView：白色圆孔遮罩、上方状态和剩余倒计时圆环。
/// 只绘制引导层，不复制、裁剪或缩放送入 SDK 的相机帧。
struct FaceCaptureOverlayView: View {
    let status: String
    var countdownProgress: Double = 1
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    @ScaledMetric(relativeTo: .headline) private var statusFontSize = 19

    var body: some View {
        GeometryReader { geometry in
            let statusHeight = max(28, statusFontSize * 2.4)
            let circle = FaceCaptureLayout.circleBounds(
                in: geometry.size,
                statusHeight: statusHeight,
                topInset: topInset,
                bottomInset: bottomInset
            )
            let progress = countdownProgress.isFinite ? min(1, max(0, countdownProgress)) : 0
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    path.addEllipse(in: circle)
                }
                .fill(.white, style: FillStyle(eoFill: true))
                Circle()
                    .stroke(.white.opacity(0.4), lineWidth: 1.95)
                    .frame(width: max(0, circle.width - 6), height: max(0, circle.height - 6))
                    .position(x: circle.midX, y: circle.midY)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color(white: 0.97), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: max(0, circle.width - 6), height: max(0, circle.height - 6))
                    .position(x: circle.midX, y: circle.midY)
                Text(status)
                    .font(.system(size: statusFontSize, weight: .bold))
                    .foregroundStyle(DemoTheme.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .frame(width: max(0, geometry.size.width - 48), height: statusHeight, alignment: .bottom)
                    .position(x: circle.midX, y: circle.minY - 12 - statusHeight / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status)
        .accessibilityAddTraits(.updatesFrequently)
    }

}
