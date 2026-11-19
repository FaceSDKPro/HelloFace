import Foundation
import HiFace
import ImageIO
@preconcurrency import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct FacePhotoPicker: UIViewControllerRepresentable {
    static let imageSearchMaximumPixelSize = 4_096
    let maximumPixelSize: Int
    // nil means user cancellation; a non-nil result carries decoded pixels or a decoding error.
    let onCompletion: @MainActor (Result<HiFaceRGBAImage, HiFaceError>?) -> Void

    init(maximumPixelSize: Int = 1_080,
         onCompletion: @escaping @MainActor (Result<HiFaceRGBAImage, HiFaceError>?) -> Void) {
        self.maximumPixelSize = maximumPixelSize
        self.onCompletion = onCompletion
    }

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
        // Dismantling the picker invalidates deliveries already queued for MainActor.
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
            // File representation avoids copying an entire large HEIF/JPEG into Data. Decode thumbnails
            // synchronously inside the callback so temporary system URLs never escape their lifetime.
            // 文件表示避免先把大尺寸 HEIF/JPEG 整体复制进 Data；回调内同步完成缩略解码，
            // 不让系统临时 URL 逃出其有效生命周期。
            let maximumPixelSize = parent.maximumPixelSize
            decoding = provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
                let result: Result<HiFaceRGBAImage, HiFaceError>
                if let url {
                    result = StaticPhotoDecoder.decode(fileURL: url, maximumPixelSize: maximumPixelSize)
                } else {
                    result = .failure(HiFaceError(
                        code: .unsupportedFormat,
                        message: "Unable to read selected image: \(error?.localizedDescription ?? "missing file")"
                    ))
                }
                Task { @MainActor [weak self] in
                    // Decoding or MainActor delivery may finish after picker destruction; never overwrite a newer
                    // selection or an exited screen.
                    // 解码或 MainActor 交付可能晚于选择器销毁，不能覆盖后续选择或已退出的页面。
                    guard let self, !self.invalidated else { return }
                    self.decoding = nil
                    self.parent.onCompletion(result)
                }
            }
        }
    }
}

/// Size-limited decoder shared by gallery selection and face-library image import.
/// 相册和人脸库图片导入共用的限尺寸解码器。
enum StaticPhotoDecoder {
    /// Preserve original resolution within the limit; downsample only oversized images and apply EXIF
    /// orientation.
    /// 原图在指定上限内保持分辨率，仅超限时降采样，并应用 EXIF 方向。
    static func decode(fileURL: URL, maximumPixelSize: Int = 1_080) -> Result<HiFaceRGBAImage, HiFaceError> {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, sourceOptions as CFDictionary) else {
            return .failure(HiFaceError(code: .unsupportedFormat, message: "Unable to decode selected image"))
        }
        return decode(source: source, maximumPixelSize: maximumPixelSize)
    }

    /// Network import enters here only after enforcing the 20 MB limit; also downsample and apply EXIF
    /// orientation.
    /// 网络导入只在 20 MB 上限检查后进入这里，同样降采样并应用 EXIF 方向。
    static func decode(data: Data) -> Result<HiFaceRGBAImage, HiFaceError> {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return .failure(HiFaceError(code: .unsupportedFormat, message: "Unable to decode selected image"))
        }
        return decode(source: source, maximumPixelSize: 1_080)
    }

    private static func decode(source: CGImageSource, maximumPixelSize: Int) -> Result<HiFaceRGBAImage, HiFaceError> {
        guard (2...4_096).contains(maximumPixelSize) else {
            return .failure(HiFaceError(code: .invalidArgument, message: "Image limit must be within 2...4096"))
        }
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
