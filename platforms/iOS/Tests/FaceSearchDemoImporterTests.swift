import Foundation

struct HiFaceError: Error {
    enum Code { case invalidArgument, processingFailed }
    let code: Code
    let message: String
}
enum FaceFeatureFormat { static let featureSpaceID = "test-space" }
struct FaceSearchFeatureEntry: Sendable {
    let faceID: String
    init(faceID: String, feature: String, updateTimeMilliseconds: Int64, tag: String, group: String) throws {
        self.faceID = faceID
        EntryStop.shared.onEntry(faceID)
    }
}
final class EntryStop: @unchecked Sendable {
    static let shared = EntryStop()
    private let lock = NSLock()
    private var target = ""
    private var control: FaceSearchImportControl?
    func configure(_ control: FaceSearchImportControl?, target: String = "") {
        lock.withLock { self.control = control; self.target = target }
    }
    func onEntry(_ id: String) {
        let stopping = lock.withLock { id == target ? control : nil }
        stopping?.stop()
    }
}
actor FaceSearchDatabase {
    private(set) var writes: [[String]] = []
    let failAt: Int?
    init(failAt: Int? = nil) { self.failAt = failAt }
    func saveFeatures(_ batch: [FaceSearchFeatureEntry]) throws {
        if writes.count == failAt { throw HiFaceError(code: .processingFailed, message: "disk full") }
        writes.append(batch.map(\.faceID))
    }
}
final class HiFaceSDK: Sendable {
    let extract: @Sendable () async -> Result<String, HiFaceError>
    init(extract: @escaping @Sendable () async -> Result<String, HiFaceError>) { self.extract = extract }
    func extractFeature(from image: Int) async -> Result<String, HiFaceError> { await extract() }
}
enum StaticPhotoDecoder {
    static func decode(data: Data) -> Result<Int, HiFaceError> { .success(0) }
}
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.withLock { value += 1; return value } }
    var count: Int { lock.withLock { value } }
}
@main struct FaceSearchDemoImporterTests {
    @MainActor static func main() async throws {
        try prepareResources()
        try await stoppedExtractionSavesTail()
        try await stoppedDownloadIsNotFailure()
        try await stoppedBatchCommitIsNotDuplicated()
        try await tailFailureKeepsCommittedCount()
        try await stoppedFeatureImportKeepsSavedBatches()
        try await fullImport()
        print("Face search importer: stop during download/extraction/write, tail failure, features and full import passed")
    }
    static func prepareResources() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let images = (0..<1000).map { ["faceId": "\($0)", "imageUrl": "https://example.test/\($0)", "group": "image", "tag": "", "updateTimeMillis": 0] as [String: Any] }
        let features = (0..<10_000).map { ["faceId": "\($0)", "feature": "HF1:test", "group": "A", "tag": "", "updateTimeMillis": 0] as [String: Any] }
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "imageFormat": "url", "entryCount": 1000, "entries": images]).write(to: folder.appendingPathComponent("images_1000.json"))
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "featureFormat": "HF1", "featureSpaceId": "test-space", "entryCount": 10_000, "entries": features]).write(to: folder.appendingPathComponent("features_10000.json"))
    }
    @MainActor static func stoppedExtractionSavesTail() async throws {
        let control = FaceSearchImportControl(), count = Counter()
        let database = FaceSearchDatabase()
        let sdk = HiFaceSDK {
            if count.next() == 37 { control.stop() }
            return .success("HF1:test")
        }
        var saved = 0
        let summary = try await FaceSearchDemoImporter.importImages(sdk: sdk, database: database, control: control,
            downloadImage: { _ in Data([1]) }, progress: { saved = $0.imported })
        let writes = await database.writes
        precondition(summary.stopped && summary.imported == 37 && summary.failed == 0)
        precondition(saved == 37 && writes.map(\.count) == [37] && count.count == 37)
    }
    @MainActor static func stoppedDownloadIsNotFailure() async throws {
        let control = FaceSearchImportControl(), started = Counter(), extracts = Counter()
        let sdk = HiFaceSDK { _ = extracts.next(); return .success("HF1:test") }
        let operation = Task {
            try await FaceSearchDemoImporter.importImages(sdk: sdk, database: FaceSearchDatabase(), control: control,
                downloadImage: { _ in
                    _ = started.next()
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                    return Data([1])
                }, progress: { _ in })
        }
        while started.count < 5 { await Task.yield() }
        control.stop()
        let summary = try await operation.value
        precondition(summary.stopped && summary.imported == 0 && summary.failed == 0)
        precondition(extracts.count == 0 && started.count == 5)
    }
    @MainActor static func stoppedBatchCommitIsNotDuplicated() async throws {
        let control = FaceSearchImportControl()
        let database = FaceSearchDatabase()
        let sdk = HiFaceSDK { .success("HF1:test") }
        let summary = try await FaceSearchDemoImporter.importImages(sdk: sdk, database: database, control: control,
            downloadImage: { _ in Data([1]) }, progress: { if $0.imported == 100 { control.stop() } })
        let writes = await database.writes
        precondition(summary.stopped && summary.imported == 100 && writes.map(\.count) == [100])
    }
    @MainActor static func tailFailureKeepsCommittedCount() async throws {
        let control = FaceSearchImportControl(), count = Counter()
        let database = FaceSearchDatabase(failAt: 1)
        let sdk = HiFaceSDK {
            if count.next() == 137 { control.stop() }
            return .success("HF1:test")
        }
        var saved = 0
        do {
            _ = try await FaceSearchDemoImporter.importImages(sdk: sdk, database: database, control: control,
                downloadImage: { _ in Data([1]) }, progress: { saved = $0.imported })
            preconditionFailure("A failed tail must surface its database error")
        } catch {
            let writes = await database.writes
            precondition(saved == 100 && writes.map(\.count) == [100])
        }
    }
    @MainActor static func stoppedFeatureImportKeepsSavedBatches() async throws {
        let control = FaceSearchImportControl()
        let database = FaceSearchDatabase()
        EntryStop.shared.configure(control, target: "136")
        defer { EntryStop.shared.configure(nil) }
        let summary = try await FaceSearchDemoImporter.importFeatures(database: database, control: control,
            progress: { _ in })
        let writes = await database.writes
        precondition(summary.stopped && summary.imported == 137 && writes.map(\.count) == [137])
    }
    @MainActor static func fullImport() async throws {
        let database = FaceSearchDatabase()
        let summary = try await FaceSearchDemoImporter.importImages(sdk: HiFaceSDK { .success("HF1:test") },
            database: database, control: FaceSearchImportControl(), downloadImage: { _ in Data([1]) }, progress: { _ in })
        let writes = await database.writes
        precondition(!summary.stopped && summary.imported == 1000 && summary.failed == 0)
        precondition(writes.map(\.count) == Array(repeating: 100, count: 10))
    }
}
