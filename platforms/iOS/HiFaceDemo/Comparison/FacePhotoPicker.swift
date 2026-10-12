import Foundation
import HiFace
import ImageIO
@preconcurrency import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct FacePhotoPicker: UIViewControllerRepresentable {
    let onCompletion: @MainActor (Result<HiFaceRGBAImage, HiFaceError>?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    static func dismantleUIViewController(_ uiViewController: PHPickerViewController, coordinator: Coordinator) {
        coordinator.cancel()
    }

    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let parent: FacePhotoPicker
        private var decoding: Progress?
        private var invalidated = false

        init(parent: FacePhotoPicker) { self.parent = parent }

        func cancel() {
            invalidated = true
            decoding?.cancel()
            decoding = nil
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !invalidated else { return }
            guard let provider = results.first?.itemProvider else {
                parent.onCompletion(nil)
                return
            }
            // 文件表示避免先把大尺寸 HEIF/JPEG 整体复制进 Data；回调内同步完成缩略解码，
            // 不让系统临时 URL 逃出其有效生命周期。
            decoding = provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
                let result: Result<HiFaceRGBAImage, HiFaceError>
                if let url {
                    result = StaticPhotoDecoder.decode(fileURL: url)
                } else {
                    result = .failure(HiFaceError(
                        code: .unsupportedFormat,
                        message: "Unable to read selected image: \(error?.localizedDescription ?? "missing file")"
                    ))
                }
                Task { @MainActor [weak self] in
                    // 解码或 MainActor 交付可能晚于选择器销毁，不能覆盖后续选择或已退出的页面。
                    guard let self, !invalidated else { return }
                    decoding = nil
                    parent.onCompletion(result)
                }
            }
        }
    }
}

/// 相册和人脸库图片导入共用的限尺寸解码器。
enum StaticPhotoDecoder {
    private static let maximumPixelSize = 1_080

    /// ImageIO 直接从临时文件降采样并应用 EXIF 方向，避免解码完整原图。
    static func decode(fileURL: URL) -> Result<HiFaceRGBAImage, HiFaceError> {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions as CFDictionary) else {
            return .failure(HiFaceError(code: .unsupportedFormat, message: "Unable to decode selected image"))
        }
        return decode(source: source)
    }

    /// 网络导入只在 20 MB 上限检查后进入这里，同样降采样并应用 EXIF 方向。
    static func decode(data: Data) -> Result<HiFaceRGBAImage, HiFaceError> {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return .failure(HiFaceError(code: .unsupportedFormat, message: "Unable to decode selected image"))
        }
        return decode(source: source)
    }

    private static func decode(source: CGImageSource) -> Result<HiFaceRGBAImage, HiFaceError> {
        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            thumbnailOptions as CFDictionary
        ) else {
            return .failure(HiFaceError(code: .unsupportedFormat, message: "Unable to render selected image"))
        }
        do {
            return .success(try HiFaceRGBAImage(cgImage: image))
        } catch let error as HiFaceError {
            return .failure(error)
        } catch {
            return .failure(HiFaceError(code: .invalidArgument, message: "Invalid selected image: \(error)"))
        }
    }
}
