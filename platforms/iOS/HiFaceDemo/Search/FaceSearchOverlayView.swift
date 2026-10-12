import Foundation
import HiFace
import SwiftUI

/// 搜索专用 Overlay；框上只显示当前有效评分，文字与框色遵循 Android Demo 的规则。
struct FaceSearchOverlayView: View {
    let overlay: FaceSearchOverlayState
    let mirrored: Bool

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                guard let frame = overlay.frame, !frame.faces.isEmpty,
                      frame.imageWidth > 0, frame.imageHeight > 0 else { return }
                let imageWidth = CGFloat(frame.imageWidth)
                let imageHeight = CGFloat(frame.imageHeight)
                let scale = CameraPreviewLayout.scale(
                    view: size, image: CGSize(width: imageWidth, height: imageHeight)
                )
                let offsetX = (size.width - imageWidth * scale) / 2
                let offsetY = (size.height - imageHeight * scale) / 2

                for (index, face) in frame.faces.enumerated() {
                    var x = CGFloat(face.bounds.x) * scale + offsetX
                    let width = CGFloat(face.bounds.width) * scale
                    if mirrored { x = size.width - x - width }
                    // 只扩大绘制框，不参与跨帧匹配；关联逻辑始终使用 SDK 原始 bounds。
                    let rect = FaceOverlayLayout.expandedFaceRect(CGRect(
                        x: x,
                        y: CGFloat(face.bounds.y) * scale + offsetY,
                        width: width,
                        height: CGFloat(face.bounds.height) * scale
                    ))
                    let box = overlay.box(at: index)
                    let color = Self.color(box.color)
                    context.stroke(
                        Path(rect),
                        with: .color(color),
                        lineWidth: 2
                    )
                    guard !box.title.isEmpty else { continue }
                    let font: Font = .system(size: 14, weight: .semibold, design: .monospaced)
                    let title = Self.fitted(box.title, font: font, width: size.width - 12,
                                            context: context)
                    let details = Self.fitted(box.details, font: font, width: size.width - 12,
                                              context: context)
                    let labelWidth = max(Self.width(title, font: font, context: context),
                                         Self.width(details, font: font, context: context))
                    let labelX = max(6, min(rect.minX, size.width - labelWidth - 6))
                    let labelY = max(details.isEmpty ? 16 : 34, min(rect.minY - 6, size.height - 6))
                    OutlinedOverlayText.draw(
                        title,
                        font: font,
                        context: &context,
                        at: CGPoint(x: labelX, y: labelY - (details.isEmpty ? 0 : 18)),
                        anchor: .bottomLeading
                    )
                    if !details.isEmpty {
                        OutlinedOverlayText.draw(
                            details,
                            font: font,
                            context: &context,
                            at: CGPoint(x: labelX, y: labelY),
                            anchor: .bottomLeading
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private static func color(_ value: FaceSearchOverlayState.BoxColor) -> Color {
        switch value {
        case .pending: Color(red: 164 / 255, green: 180 / 255, blue: 201 / 255)
        case .unmatched: Color(red: 1, green: 60 / 255, blue: 60 / 255)
        case .matched: Color(red: 40 / 255, green: 220 / 255, blue: 100 / 255)
        }
    }

    private static func width(_ value: String, font: Font, context: GraphicsContext) -> CGFloat {
        context.resolve(Text(value).font(font)).measure(in: CGSize(width: 10_000, height: 100)).width
    }

    private static func fitted(_ value: String, font: Font, width available: CGFloat,
                               context: GraphicsContext) -> String {
        guard !value.isEmpty, available > 0 else { return "" }
        if width(value, font: font, context: context) <= available { return value }
        let characters = Array(value)
        var lower = 0
        var upper = characters.count
        while lower < upper {
            let middle = (lower + upper + 1) / 2
            let candidate = String(characters.prefix(middle)) + "…"
            if width(candidate, font: font, context: context) <= available {
                lower = middle
            } else {
                upper = middle - 1
            }
        }
        return String(characters.prefix(lower)) + "…"
    }
}
