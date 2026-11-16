import Foundation
import CoreGraphics

// Compile with the actual Demo FacePhotoStore.swift. Synthetic pixels and unique IDs only.
@main struct FacePhotoStoreTests {
    static func image(_ shade: UInt8) -> CGImage {
        var bytes = [UInt8](repeating: shade, count: 333 * 333 * 4)
        for index in stride(from: 3, to: bytes.count, by: 4) { bytes[index] = 255 }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(width: 333, height: 333, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: 333 * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    static func shade(_ image: CGImage) -> Int {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Int(bytes[0])
    }
    static func main() async throws {
        let id = "test-" + UUID().uuidString
        let missing = await FacePhotoStore.thumbnail(faceID: id)
        precondition(missing == nil)
        await FacePhotoStore.save(image: image(25), faceID: id)
        let first = await FacePhotoStore.thumbnail(faceID: id)!
        precondition(first.width <= 96 && abs(shade(first) - 25) <= 4)
        await FacePhotoStore.save(image: image(220), faceID: id)
        let second = await FacePhotoStore.thumbnail(faceID: id)!
        precondition(abs(shade(second) - 220) <= 4)
        await FacePhotoStore.save(image: image(25), faceID: id, library: .reference)
        let reference = await FacePhotoStore.thumbnail(faceID: id, library: .reference)!
        precondition(abs(shade(reference) - 25) <= 4)
        let search = await FacePhotoStore.thumbnail(faceID: id)!
        precondition(abs(shade(search) - 220) <= 4)
        let other = await FacePhotoStore.thumbnail(faceID: id + "missing")
        precondition(other == nil)
        await FacePhotoStore.save(image: nil, faceID: id)
        let replaced = await FacePhotoStore.thumbnail(faceID: id)
        precondition(replaced == nil)
        let retainedReference = await FacePhotoStore.thumbnail(faceID: id, library: .reference)!
        precondition(abs(shade(retainedReference) - 25) <= 4)
        await FacePhotoStore.remove(faceIDs: [id], library: .reference)
        let removedReference = await FacePhotoStore.thumbnail(faceID: id, library: .reference)
        precondition(removedReference == nil)
        await FacePhotoStore.save(image: image(25), faceID: id)
        await FacePhotoStore.remove(faceID: id)
        let removed = await FacePhotoStore.thumbnail(faceID: id)
        precondition(removed == nil)
        await FacePhotoStore.save(image: image(25), faceID: id)
        await FacePhotoStore.save(image: image(220), faceID: id + "-keep")
        await FacePhotoStore.remove(faceIDs: [id, id + "-missing"])
        let deletedBatch = await FacePhotoStore.thumbnail(faceID: id)
        let retained = await FacePhotoStore.thumbnail(faceID: id + "-keep")
        precondition(deletedBatch == nil && retained != nil && abs(shade(retained!) - 220) <= 4)
        await FacePhotoStore.remove(faceID: id + "-keep")
        print("FacePhotoStore: JPEG decode, same-ID replacement, missing-ID isolation and deletion passed")
    }
}
