import CoreGraphics

@main
struct FaceOverlayLayoutTests {
    static func main() {
        let source = CGRect(x: 40, y: 25, width: 100, height: 160)
        let expanded = FaceOverlayLayout.expandedFaceRect(source)
        precondition(expanded == CGRect(x: 30, y: 25, width: 120, height: 160))
        precondition(expanded.midX == source.midX)
        precondition(expanded.minY == source.minY && expanded.height == source.height)

        let empty = FaceOverlayLayout.expandedFaceRect(.zero)
        precondition(empty == .zero)
        print("Face overlay layout: horizontal display width expands to 1.2x")
    }
}
