import Foundation

// 仅替换 UIKit/PhotosUI 边界，运行真实 Coordinator 的异步交付与取消逻辑。
@MainActor protocol UIViewControllerRepresentable {
    typealias Context = PhotoPickerContext
}
@MainActor extension UIViewControllerRepresentable {
    static func dismantleUIViewController(_ controller: PHPickerViewController,
                                         coordinator: FacePhotoPicker.Coordinator) {}
}
struct PhotoPickerContext { let coordinator: FacePhotoPicker.Coordinator }
struct HiFaceRGBAImage: Sendable {}
struct HiFaceError: Error {
    enum Code { case unsupportedFormat }
    let code: Code
    let message: String
}
enum UTType {
    struct Value: Sendable { let identifier: String }
    static let image = Value(identifier: "public.image")
}
struct PHPickerConfiguration {
    struct Library { static func shared() -> Library { Library() } }
    enum Filter { case images }
    enum Representation { case current }
    var filter: Filter?
    var selectionLimit = 0
    var preferredAssetRepresentationMode: Representation?
    init(photoLibrary: Library) {}
}
@MainActor protocol PHPickerViewControllerDelegate {}
@MainActor final class PHPickerViewController {
    var delegate: (any PHPickerViewControllerDelegate)?
    init(configuration: PHPickerConfiguration) {}
}
struct PHPickerResult { let itemProvider: PhotoProvider }
@MainActor final class PhotoProvider {
    let progress = Progress(totalUnitCount: 1)
    private var completion: (@Sendable (URL?, (any Error)?) -> Void)?
    func loadFileRepresentation(forTypeIdentifier: String,
                                completionHandler: @escaping @Sendable (URL?, (any Error)?) -> Void) -> Progress {
        completion = completionHandler
        return progress
    }
    func complete() { completion?(nil, nil) }
}
enum StaticPhotoDecoder {
    static func decode(fileURL: URL) -> Result<HiFaceRGBAImage, HiFaceError> { .success(HiFaceRGBAImage()) }
}

@main struct FacePhotoPickerLifecycleTests {
    @MainActor static func flush() async { for _ in 0..<100 { await Task.yield() } }

    @MainActor static func main() async {
        let controller = PHPickerViewController(configuration: PHPickerConfiguration(photoLibrary: .shared()))
        var delivered = 0
        let picker = FacePhotoPicker { _ in delivered += 1 }

        let cancelled = picker.makeCoordinator()
        let oldProvider = PhotoProvider()
        cancelled.picker(controller, didFinishPicking: [PHPickerResult(itemProvider: oldProvider)])
        FacePhotoPicker.dismantleUIViewController(controller, coordinator: cancelled)
        oldProvider.complete()
        await flush()
        precondition(delivered == 0, "Dismissed picker delivered a late decoding result")
        precondition(oldProvider.progress.isCancelled, "Dismissal did not cancel the provider request")

        let queued = picker.makeCoordinator()
        let queuedProvider = PhotoProvider()
        queued.picker(controller, didFinishPicking: [PHPickerResult(itemProvider: queuedProvider)])
        queuedProvider.complete()
        FacePhotoPicker.dismantleUIViewController(controller, coordinator: queued)
        await flush()
        precondition(delivered == 0, "Dismissal did not invalidate the queued MainActor delivery")

        let current = picker.makeCoordinator()
        let currentProvider = PhotoProvider()
        current.picker(controller, didFinishPicking: [PHPickerResult(itemProvider: currentProvider)])
        currentProvider.complete()
        await flush()
        precondition(delivered == 1, "Active picker failed to deliver its result")
        FacePhotoPicker.dismantleUIViewController(controller, coordinator: current)
        print("Photo picker lifecycle: late, queued and active deliveries passed")
    }
}
