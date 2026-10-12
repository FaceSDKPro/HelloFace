import HiFace
import SwiftUI

struct FaceDetectionOverlayView: View {
    private static let meshContours = [
        [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365,
         379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234,
         127, 162, 21, 54, 103, 67, 109, 10],
        [33, 7, 163, 144, 145, 153, 154, 155, 133, 173, 157, 158, 159, 160, 161,
         246, 33],
        [362, 382, 381, 380, 374, 373, 390, 249, 263, 466, 388, 387, 386, 385,
         384, 398, 362],
        [61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291, 409, 270, 269, 267,
         0, 37, 39, 40, 185, 61],
        [168, 6, 197, 195, 5, 4, 1, 19, 94, 2]
    ]

    let result: FaceDetectionResult?
    let mirrored: Bool

    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                guard let result, result.imageWidth > 0, result.imageHeight > 0 else { return }
                let imageWidth = CGFloat(result.imageWidth)
                let imageHeight = CGFloat(result.imageHeight)
                // 与预览层的 resizeAspect 一致：完整显示画面，并计入居中留边。
                let scale = CameraPreviewLayout.scale(
                    view: size, image: CGSize(width: imageWidth, height: imageHeight)
                )
                let offsetX = (size.width - imageWidth * scale) / 2
                let offsetY = (size.height - imageHeight * scale) / 2

                func mapped(_ point: HiFacePoint) -> CGPoint {
                    var x = CGFloat(point.x) * scale + offsetX
                    if mirrored { x = size.width - x }
                    return CGPoint(x: x, y: CGFloat(point.y) * scale + offsetY)
                }

                for (index, face) in result.faces.enumerated() {
                    var x = CGFloat(face.bounds.x) * scale + offsetX
                    let width = CGFloat(face.bounds.width) * scale
                    if mirrored { x = size.width - x - width }
                    // 与 Android 一致，仅把显示框左右各扩大 10%；关键点和 SDK 坐标保持原值。
                    let rect = FaceOverlayLayout.expandedFaceRect(CGRect(
                        x: x,
                        y: CGFloat(face.bounds.y) * scale + offsetY,
                        width: width,
                        height: CGFloat(face.bounds.height) * scale
                    ))
                    let faceColor = index == 0 ? Color.green : Color.cyan
                    context.stroke(
                        Path(roundedRect: rect, cornerRadius: 10),
                        with: .color(faceColor),
                        lineWidth: index == 0 ? 3 : 2
                    )

                    var label = String(format: "%.1f%%", face.confidence * 100)
                    if let pose = face.headPose {
                        label += String(
                            format: "  P %.0f°  Y %.0f°  R %.0f°",
                            pose.pitch,
                            pose.yaw,
                            pose.roll
                        )
                    }
                    OutlinedOverlayText.draw(
                        label,
                        font: .caption2.monospacedDigit().bold(),
                        context: &context,
                        at: CGPoint(x: rect.minX, y: max(14, rect.minY - 6)),
                        anchor: .bottomLeading
                    )

                    for point in face.landmarks {
                        let position = mapped(point)
                        let dot = CGRect(
                            x: position.x - 2.5,
                            y: position.y - 2.5,
                            width: 5,
                            height: 5
                        )
                        context.fill(Path(ellipseIn: dot), with: .color(.yellow))
                    }

                    if let mesh = face.mesh {
                        for contour in Self.meshContours {
                            let points = contour.compactMap { mesh.points.indices.contains($0)
                                ? mapped(mesh.points[$0])
                                : nil
                            }
                            guard let first = points.first, points.count > 1 else { continue }
                            var path = Path()
                            path.move(to: first)
                            points.dropFirst().forEach { path.addLine(to: $0) }
                            context.stroke(
                                path,
                                with: .color(Color.purple.opacity(0.9)),
                                lineWidth: 2
                            )
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
