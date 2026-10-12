import CoreGraphics
import SwiftUI

/// 检测和搜索 Overlay 共用的显示框规则，不修改 SDK 返回的原始人脸坐标。
enum FaceOverlayLayout {
    /// 与 Android Demo 一致：左右各增加原框宽度的 10%，总显示宽度为 1.2 倍。
    static let horizontalExpansion: CGFloat = 0.10

    static func expandedFaceRect(_ rect: CGRect) -> CGRect {
        rect.insetBy(dx: -rect.width * horizontalExpansion, dy: 0)
    }
}

/// SwiftUI Canvas 没有文字描边模式；围绕中心白字绘制紧邻深灰字形，得到稳定的圆角描边。
enum OutlinedOverlayText {
    private static let outlineColor = Color(
        red: 24.0 / 255.0,
        green: 24.0 / 255.0,
        blue: 24.0 / 255.0,
        opacity: 0.92
    )
    private static let outlineOffsets: [CGSize] = [
        CGSize(width: -1.25, height: 0),
        CGSize(width: 1.25, height: 0),
        CGSize(width: 0, height: -1.25),
        CGSize(width: 0, height: 1.25),
        CGSize(width: -0.9, height: -0.9),
        CGSize(width: 0.9, height: -0.9),
        CGSize(width: -0.9, height: 0.9),
        CGSize(width: 0.9, height: 0.9)
    ]

    static func draw(
        _ value: String,
        font: Font,
        context: inout GraphicsContext,
        at point: CGPoint,
        anchor: UnitPoint = .bottomLeading
    ) {
        guard !value.isEmpty else { return }
        // 每个标签只解析一次深色与白色字形；多个偏移复用结果，避免重复排版。
        let outline = context.resolve(Text(value).font(font).foregroundColor(outlineColor))
        let fill = context.resolve(Text(value).font(font).foregroundColor(.white))
        for offset in outlineOffsets {
            context.draw(
                outline,
                at: CGPoint(x: point.x + offset.width, y: point.y + offset.height),
                anchor: anchor
            )
        }
        context.draw(
            fill,
            at: point,
            anchor: anchor
        )
    }
}
