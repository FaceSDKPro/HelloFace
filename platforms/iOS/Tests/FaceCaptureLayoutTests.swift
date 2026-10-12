import Foundation

@main
struct FaceCaptureLayoutTests {
    static func main() {
        let phone = CGSize(width: 375, height: 812)
        let circle = FaceCaptureLayout.circleBounds(
            in: phone,
            statusHeight: 46,
            topInset: 47,
            bottomInset: 34
        )
        precondition(circle.width == 300)
        precondition(FaceCaptureLayout.previewShortSide(circle: circle, availableSize: phone) == 324)

        let largeTextCircle = FaceCaptureLayout.circleBounds(
            in: phone,
            statusHeight: 92,
            topInset: 47,
            bottomInset: 34
        )
        let largeTextPreview = FaceCaptureLayout.previewShortSide(
            circle: largeTextCircle,
            availableSize: phone
        )
        precondition(largeTextPreview > largeTextCircle.width)
        precondition(largeTextPreview <= phone.width)

        let landscape = CGSize(width: 812, height: 375)
        let landscapeCircle = FaceCaptureLayout.circleBounds(
            in: landscape,
            statusHeight: 46,
            topInset: 0,
            bottomInset: 21
        )
        let landscapePreview = FaceCaptureLayout.previewShortSide(
            circle: landscapeCircle,
            availableSize: landscape
        )
        precondition(landscapePreview > landscapeCircle.width)
        precondition(landscapePreview <= landscape.height)
        print("Face capture layout: guided preview stays 24pt wider than the guide when space allows")
    }
}
