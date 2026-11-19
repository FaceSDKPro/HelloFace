import Foundation
import CoreGraphics
import ImageIO
import SwiftUI

/// Confirmed Demo crops only. App sandbox, excluded from backup; no shared URLs or image history.
enum FacePhotoStore {
    enum Library: String, Sendable { case search, reference }
    // Serialize crop reads/writes/deletes off MainActor so a thumbnail sees a complete replacement.
    private static let queue = DispatchQueue(label: "HiFaceDemo.Photos", qos: .utility)

    private static func background<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    // Encode arbitrary UTF-8 IDs into safe path components and split keys exceeding the component limit.
    private static func file(_ faceID: String, library: Library, create: Bool) throws -> URL {
        guard !faceID.isEmpty, !faceID.contains("\0") else { throw CocoaError(.fileWriteInvalidFileName) }
        var root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                              appropriateFor: nil, create: create)
            .appendingPathComponent("face-photos-v1", isDirectory: true)
            .appendingPathComponent(library.rawValue, isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try root.setResourceValues(values)
        }
        var key = faceID.utf8.allSatisfy { (48...57).contains($0) } ? faceID
            : "~" + faceID.utf8.map { String(format: "%02x", $0) }.joined()
        while key.count > 120 {
            root.appendPathComponent(String(key.prefix(120)), isDirectory: true)
            key = String(key.dropFirst(120))
        }
        if create { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        return root.appendingPathComponent(key + ".jpg")
    }

    private static func write(_ image: CGImage?, faceID: String, library: Library) {
        do {
            let path = try file(faceID, library: library, create: true)
            guard let image, image.width <= 720, image.height <= 720 else {
                try? FileManager.default.removeItem(at: path)
                return
            }
            let data = NSMutableData()
            guard let encoder = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            CGImageDestinationAddImage(encoder, image,
                [kCGImageDestinationLossyCompressionQuality: 0.95] as CFDictionary)
            guard CGImageDestinationFinalize(encoder) else { throw CocoaError(.fileWriteUnknown) }
            #if os(iOS)
            try (data as Data).write(to: path, options: [.atomic, .completeFileProtection])
            #else
            try (data as Data).write(to: path, options: .atomic)
            #endif
        } catch {
            // Feature has already committed. A failed replacement must not display the old face.
            if let path = try? file(faceID, library: library, create: false) { try? FileManager.default.removeItem(at: path) }
        }
    }

    static func saveLater(image: CGImage?, faceID: String, library: Library = .search) {
        queue.async { write(image, faceID: faceID, library: library) }
    }

    static func save(image: CGImage?, faceID: String, library: Library = .search) async {
        await background { write(image, faceID: faceID, library: library) }
    }

    static func remove(faceID: String, library: Library = .search) async {
        await remove(faceIDs: [faceID], library: library)
    }

    static func remove(faceIDs: [String], library: Library = .search) async {
        await background {
            for faceID in faceIDs {
                if let path = try? file(faceID, library: library, create: false) { try? FileManager.default.removeItem(at: path) }
            }
        }
    }

    static func thumbnail(faceID: String, library: Library = .search) async -> CGImage? {
        await background {
            guard let path = try? file(faceID, library: library, create: false),
                  let info = try? path.resourceValues(forKeys: [.fileSizeKey]),
                  let count = info.fileSize, count > 0, count <= 1024 * 1024,
                  let data = try? Data(contentsOf: path), data.count <= 1024 * 1024,
                  let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }
            let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                           kCGImageSourceThumbnailMaxPixelSize: 96] as CFDictionary
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
        }
    }
}

struct FacePhotoThumbnail: View {
    let faceID: String
    let library: FacePhotoStore.Library
    // Include the revision in the async load key so overwriting an existing ID reloads its portrait.
    let revision: Int
    let diameter: CGFloat
    let circular: Bool
    @State private var photo: CGImage?
    private struct LoadKey: Hashable { let faceID: String; let library: FacePhotoStore.Library; let revision: Int }
    init(faceID: String, library: FacePhotoStore.Library = .search, revision: Int = 0, diameter: CGFloat = 42, circular: Bool = false) {
        self.faceID = faceID; self.library = library; self.revision = revision
        self.diameter = diameter; self.circular = circular
    }
    var body: some View {
        Group {
            if let photo { Image(decorative: photo, scale: 1).resizable().scaledToFill() }
            else if circular {
                Image(systemName: "person.fill").resizable().scaledToFit().padding(diameter / 4)
                    .foregroundStyle(DemoTheme.contentAccent)
            } else { Image(systemName: "person.fill").foregroundStyle(.white.opacity(0.65)) }
        }
        .frame(width: diameter, height: diameter)
        .background(circular ? DemoTheme.contentAccent.opacity(0.08) : .white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: circular ? diameter / 2 : 9))
        .task(id: LoadKey(faceID: faceID, library: library, revision: revision)) {
            photo = nil
            let loaded = await FacePhotoStore.thumbnail(faceID: faceID, library: library)
            guard !Task.isCancelled else { return }
            photo = loaded
        }
        .onDisappear { photo = nil }
        .accessibilityHidden(true)
    }
}
