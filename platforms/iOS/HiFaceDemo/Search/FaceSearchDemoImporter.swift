import Foundation
import HiFace

enum FaceSearchDemoImportKind: String, Identifiable, Sendable {
    case features
    case images

    var id: String { rawValue }
    var title: String {
        self == .features
            ? String(localized: "search_import_features")
            : String(localized: "search_import_images")
    }
}

struct FaceSearchDemoImportSummary: Sendable {
    let imported: Int
    let failed: Int
}

/// Demo Resources 专用批量导入器；数据不属于 SDK。特征按 1000 条写库，图片有界预下载、串行提取。
/// images_1000.json 仅供演示；业务接入时替换为已获授权的人脸测试图片 URL，并使用 CDN 加速。
enum FaceSearchDemoImporter {
    private static let featureCount = 10_000
    private static let imageCount = 1000
    private static let featureBatchSize = 1_000
    private static let imageBatchSize = 100
    private static let imagePrefetchCount = 5
    private static let maximumImageBytes = 20 * 1_024 * 1_024

    static func importFeatures(
        database: FaceSearchDatabase,
        progress: @escaping @MainActor @Sendable (Int, Int) -> Void
    ) async throws -> FaceSearchDemoImportSummary {
        let manifest: FeatureManifest = try decodeResource(named: "features_10000")
        guard manifest.schemaVersion == 1,
              manifest.featureFormat == "HF1",
              manifest.featureSpaceId == FaceFeatureFormat.featureSpaceID,
              manifest.entryCount == featureCount,
              manifest.entries.count == featureCount else {
            throw invalidManifest("Feature JSON header or entry count is invalid")
        }
        var imported = 0
        for start in stride(from: 0, to: manifest.entries.count, by: featureBatchSize) {
            try Task.checkCancellation()
            let end = min(start + featureBatchSize, manifest.entries.count)
            let batch = try manifest.entries[start..<end].map { value in
                try FaceSearchFeatureEntry(
                    faceID: value.faceID,
                    feature: value.feature,
                    updateTimeMilliseconds: value.updateTimeMillis,
                    tag: value.tag,
                    group: value.group
                )
            }
            try await database.saveFeatures(batch)
            imported += batch.count
            await progress(imported, featureCount)
        }
        return FaceSearchDemoImportSummary(imported: imported, failed: 0)
    }

    static func importImages(
        sdk: HiFaceSDK,
        database: FaceSearchDatabase,
        progress: @escaping @MainActor @Sendable (Int, Int) -> Void
    ) async throws -> FaceSearchDemoImportSummary {
        let manifest: ImageManifest = try decodeResource(named: "images_1000")
        guard manifest.schemaVersion == 1,
              manifest.imageFormat == "url",
              manifest.entryCount == imageCount,
              manifest.entries.count == imageCount else {
            throw invalidManifest("Image JSON header or entry count is invalid")
        }
        var processed = 0
        var imported = 0
        var failed = 0
        var batch: [FaceSearchFeatureEntry] = []
        var nextToStart = 0
        try await withThrowingTaskGroup(of: DownloadedImage.self) { downloads in
            while nextToStart < min(imagePrefetchCount, manifest.entries.count) {
                let value = manifest.entries[nextToStart]
                downloads.addTask {
                    DownloadedImage(entry: value, data: try? await download(value.imageURL))
                }
                nextToStart += 1
            }

            while let downloaded = try await downloads.next() {
                try Task.checkCancellation()
                // 按完成顺序消费，并在解码前补位，避免慢请求阻塞后续图片。
                if nextToStart < manifest.entries.count {
                    let value = manifest.entries[nextToStart]
                    downloads.addTask {
                        DownloadedImage(entry: value, data: try? await download(value.imageURL))
                    }
                    nextToStart += 1
                }
                guard let data = downloaded.data else {
                    failed += 1
                    processed += 1
                    // 每张结束立即更新；最后一张在尾批写库完成后报告，避免重复终值。
                    if processed < imageCount { await progress(processed, imageCount) }
                    continue
                }

                try Task.checkCancellation()
                do {
                    let image = try StaticPhotoDecoder.decode(data: data).get()
                    switch await sdk.extractFeature(from: image) {
                    case .success(let feature):
                        try Task.checkCancellation()
                        let value = downloaded.entry
                        batch.append(try FaceSearchFeatureEntry(
                            faceID: value.faceID,
                            feature: feature,
                            updateTimeMilliseconds: value.updateTimeMillis,
                            tag: value.tag,
                            group: value.group
                        ))
                    case .failure:
                        failed += 1
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failed += 1
                }
                processed += 1
                if batch.count >= imageBatchSize {
                    try Task.checkCancellation()
                    try await database.saveFeatures(batch)
                    imported += batch.count
                    batch.removeAll(keepingCapacity: true)
                }
                if processed < imageCount { await progress(processed, imageCount) }
            }
        }
        if !batch.isEmpty {
            try Task.checkCancellation()
            try await database.saveFeatures(batch)
            imported += batch.count
        }
        await progress(processed, imageCount)
        return FaceSearchDemoImportSummary(imported: imported, failed: failed)
    }

    private static func download(_ address: String) async throws -> Data {
        guard let url = URL(string: address), url.scheme == "https" else {
            throw HiFaceError(code: .invalidArgument, message: "Demo image URL must use HTTPS")
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (fileURL, response) = try await URLSession.shared.download(for: request)
        defer { try? FileManager.default.removeItem(at: fileURL) }
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              response.expectedContentLength <= Int64(maximumImageBytes) else {
            throw HiFaceError(code: .processingFailed, message: "Unable to download demo image")
        }
        try Task.checkCancellation()
        let fileSize = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard fileSize > 0, fileSize <= maximumImageBytes else {
            throw HiFaceError(code: .processingFailed, message: "Unable to download demo image")
        }
        return try Data(contentsOf: fileURL, options: .mappedIfSafe)
    }

    private static func decodeResource<Value: Decodable>(named name: String) throws -> Value {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw invalidManifest("Bundled \(name).json is missing")
        }
        do { return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url)) }
        catch { throw invalidManifest("Invalid bundled \(name).json: \(error.localizedDescription)") }
    }

    private static func invalidManifest(_ message: String) -> HiFaceError {
        HiFaceError(code: .invalidArgument, message: message)
    }
}

private struct FeatureManifest: Decodable, Sendable {
    let schemaVersion: Int
    let featureFormat: String
    let featureSpaceId: String
    let entryCount: Int
    let entries: [FeatureManifestEntry]
}

private struct FeatureManifestEntry: Decodable, Sendable {
    let faceID: String
    let feature: String
    let group: String
    let tag: String
    let updateTimeMillis: Int64

    private enum CodingKeys: String, CodingKey {
        case faceID = "faceId", feature, group, tag, updateTimeMillis
    }
}

private struct ImageManifest: Decodable, Sendable {
    let schemaVersion: Int
    let imageFormat: String
    let entryCount: Int
    let entries: [ImageManifestEntry]
}

private struct ImageManifestEntry: Decodable, Sendable {
    let faceID: String
    let imageURL: String
    let group: String
    let tag: String
    let updateTimeMillis: Int64

    private enum CodingKeys: String, CodingKey {
        case faceID = "faceId", imageURL = "imageUrl", group, tag, updateTimeMillis
    }
}

private struct DownloadedImage: Sendable {
    let entry: ImageManifestEntry
    let data: Data?
}
