import Foundation

// 使用等形 SDK 桩运行真实 Demo Model，主动控制开库和导入的完成顺序。
struct FaceSearchMetadata: Sendable {
    let faceID: String
    var group = ""
    var tag = ""
}
struct FaceSearchEntry: Sendable {
    let faceID: String
    var group = ""
    var tag = ""
    var metadata: FaceSearchMetadata {
        FaceSearchMetadata(faceID: faceID, group: group, tag: tag)
    }
}
struct HiFaceError: Error {
    enum Code { case notFound, internalError, databaseError }
    let code: Code
    let message: String
}
actor FaceSearchDatabase {
    private(set) var closes = 0
    private var entries: [FaceSearchEntry]
    private(set) var offsets: [Int] = []
    init(entries: [FaceSearchEntry] = []) { self.entries = entries }
    func count() throws -> UInt64 { UInt64(entries.count) }
    func recentEntries(offset: Int, limit: Int) throws -> [FaceSearchMetadata] {
        offsets.append(offset)
        return entries.dropFirst(offset).prefix(limit).map(\.metadata)
    }
    func entry(faceID: String) throws -> FaceSearchEntry {
        throw HiFaceError(code: .notFound, message: "missing")
    }
    func delete(faceID: String) throws -> Bool { true }
    func close() { closes += 1 }
}

final class DatabaseOpener: @unchecked Sendable {
    private let lock = NSLock()
    private var factories: [@Sendable () throws -> FaceSearchDatabase] = []
    private var opened = 0
    private var completed = 0

    func configure(_ factories: [@Sendable () throws -> FaceSearchDatabase]) {
        lock.withLock { self.factories = factories; opened = 0; completed = 0 }
    }
    var opens: Int { lock.withLock { opened } }
    var completions: Int { lock.withLock { completed } }
    func open() throws -> FaceSearchDatabase {
        let factory = lock.withLock {
            opened += 1
            return factories.removeFirst()
        }
        defer { lock.withLock { completed += 1 } }
        return try factory()
    }
}

final class HiFaceSDK: @unchecked Sendable {
    static let opener = DatabaseOpener()
    private let lock = NSLock()
    private var closed = false
    var isClosed: Bool { lock.withLock { closed } }
    static func openSearchDatabase() throws -> FaceSearchDatabase { try opener.open() }
    func close() { lock.withLock { closed = true } }
}
@MainActor enum DemoEnvironment {
    static var instances: [HiFaceSDK] = []
    static func makeSDK() -> HiFaceSDK {
        let sdk = HiFaceSDK()
        instances.append(sdk)
        return sdk
    }
}
enum DemoErrorPresentation { static func message(for error: HiFaceError) -> String { error.message } }
enum FaceSearchDemoImportKind { case features, images; var title: String { "import" } }
struct FaceSearchDemoImportSummary { let imported: Int; let failed: Int }
@MainActor enum FaceSearchDemoImporter {
    static var pending: [CheckedContinuation<FaceSearchDemoImportSummary, Error>] = []
    static var finished = 0
    static func importFeatures(database: FaceSearchDatabase,
        progress: @escaping @MainActor @Sendable (Int, Int) -> Void) async throws -> FaceSearchDemoImportSummary {
        FaceSearchDemoImportSummary(imported: 0, failed: 0)
    }
    static func importImages(sdk: HiFaceSDK, database: FaceSearchDatabase,
        progress: @escaping @MainActor @Sendable (Int, Int) -> Void) async throws -> FaceSearchDemoImportSummary {
        defer { finished += 1 }
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
}

@main struct SearchLibraryModelTests {
    @MainActor static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        fatalError("Timed out waiting for asynchronous model work")
    }

    @MainActor static func flush() async {
        for _ in 0..<100 { await Task.yield() }
    }

    @MainActor static func main() async throws {
        try await retriesFailedOpen()
        try await staleOpeningCannotClearNewConnection()
        try await staleImportCannotClearNewSDK()
        try await paginationUsesTailIdentitiesAndReusesConnection()
        try await stopClearsConfirmations()
        print("SearchLibraryModelTests passed (5 lifecycle/pagination regressions)")
    }

    @MainActor static func paginationUsesTailIdentitiesAndReusesConnection() async throws {
        let database = FaceSearchDatabase(entries: (0..<101).map { FaceSearchEntry(faceID: "ID-\($0)") })
        HiFaceSDK.opener.configure([{ database }])
        let model = SearchLibraryModel()
        model.refresh()
        try await waitUntil { !model.isWorking }
        precondition(model.people.count == 100)
        model.loadMoreIfNeeded(current: model.people[89])
        precondition(!model.isWorking)
        let initialOffsets = await database.offsets
        precondition(initialOffsets == [0])
        // 行的旧展示值可以有旧元数据；是否在预加载区由 Face ID 决定，而非整行值相等。
        var staleEntry = FaceSearchEntry(faceID: model.people[90].id)
        staleEntry.tag = "previous metadata"
        model.loadMoreIfNeeded(current: SearchLibraryPerson(staleEntry))
        try await waitUntil { !model.isWorking }
        precondition(model.people.count == 101 && model.people.last?.id == "ID-100")
        precondition(model.status == "共 101 条人脸记录")
        let loadedOffsets = await database.offsets
        precondition(loadedOffsets == [0, 100])
        precondition(HiFaceSDK.opener.opens == 1)
        model.loadMoreIfNeeded(current: model.people[100])
        precondition(!model.isWorking)
        model.stop()
        await flush()
        let closes = await database.closes
        precondition(closes == 1)
    }

    @MainActor static func retriesFailedOpen() async throws {
        let database = FaceSearchDatabase()
        HiFaceSDK.opener.configure([
            { throw HiFaceError(code: .databaseError, message: "temporary error") },
            { database }
        ])
        let model = SearchLibraryModel()
        model.refresh()
        try await waitUntil { !model.isWorking }
        assert(model.hasError)
        model.refresh()
        try await waitUntil { !model.isWorking }
        assert(!model.hasError && HiFaceSDK.opener.opens == 2)
        model.stop()
    }

    @MainActor static func staleOpeningCannotClearNewConnection() async throws {
        let gate = DispatchSemaphore(value: 0)
        let database = FaceSearchDatabase()
        HiFaceSDK.opener.configure([
            {
                gate.wait()
                throw HiFaceError(code: .databaseError, message: "old page failed")
            },
            { database },
            { fatalError("Old opening cleared the new cached connection") }
        ])
        let model = SearchLibraryModel()
        model.refresh()
        try await waitUntil { HiFaceSDK.opener.opens == 1 }
        model.stop()
        model.refresh()
        try await waitUntil { !model.isWorking }
        gate.signal()
        try await waitUntil { HiFaceSDK.opener.completions == 2 }
        await flush()
        model.query = "missing"
        model.lookup()
        try await waitUntil { !model.isWorking }
        assert(model.isLookup && !model.hasError && HiFaceSDK.opener.opens == 2)
        model.stop()
    }

    @MainActor static func staleImportCannotClearNewSDK() async throws {
        HiFaceSDK.opener.configure([{ FaceSearchDatabase() }, { FaceSearchDatabase() }])
        DemoEnvironment.instances = []
        FaceSearchDemoImporter.pending = []
        FaceSearchDemoImporter.finished = 0
        let model = SearchLibraryModel()
        model.requestImport(.images)
        model.confirmImport()
        try await waitUntil { FaceSearchDemoImporter.pending.count == 1 }
        model.stop()
        model.requestImport(.images)
        model.confirmImport()
        try await waitUntil { FaceSearchDemoImporter.pending.count == 2 }
        assert(DemoEnvironment.instances[0].isClosed)
        assert(!DemoEnvironment.instances[1].isClosed)
        FaceSearchDemoImporter.pending[0].resume(throwing: CancellationError())
        try await waitUntil { FaceSearchDemoImporter.finished == 1 }
        await flush()
        assert(model.isWorking, "Old completion changed the new import status")
        model.stop()
        assert(DemoEnvironment.instances[1].isClosed, "New SDK was lost before page cleanup")
        FaceSearchDemoImporter.pending[1].resume(throwing: CancellationError())
        try await waitUntil { FaceSearchDemoImporter.finished == 2 }
        await flush()
    }

    @MainActor static func stopClearsConfirmations() async throws {
        let model = SearchLibraryModel()
        model.requestDelete(faceID: "face.png")
        model.stop()
        assert(model.pendingDeleteFaceID == nil)
        model.requestImport(.features)
        model.stop()
        assert(model.pendingImport == nil)
    }
}
