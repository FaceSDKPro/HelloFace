import Foundation
import HiFace
import SwiftUI

struct SearchLibraryPerson: Identifiable, Sendable, Equatable {
    let id: String
    let group: String
    let tag: String

    init(_ entry: FaceSearchEntry) {
        self.init(entry.metadata)
    }

    init(_ entry: FaceSearchMetadata) {
        id = entry.faceID
        group = entry.group
        tag = entry.tag
    }
}

/// 人脸库管理：精确查询、滚动加载、删除和两种批量导入；连接与任务由页面生命周期管理。
@MainActor
final class SearchLibraryModel: ObservableObject {
    @Published var status = "读取中…"
    @Published var query = ""
    @Published private(set) var people: [SearchLibraryPerson] = []
    @Published private(set) var isLookup = false
    @Published private(set) var isWorking = false
    @Published private(set) var hasError = false
    @Published private(set) var pendingDeleteFaceID: String?
    @Published private(set) var pendingImport: FaceSearchDemoImportKind?

    private static let loadSize = 100
    private static let prefetchRemaining = 10
    private var imageImportSDK: HiFaceSDK?
    private var databaseTask: Task<FaceSearchDatabase, Error>?
    private var databaseGeneration = 0
    private var operationTask: Task<Void, Never>?
    private var operationGeneration = 0
    private var nextOffset = 0
    private var canLoadMore = false

    private struct ListSnapshot: Sendable {
        let count: UInt64
        let people: [SearchLibraryPerson]
    }

    func refresh() {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? loadFirstPage() : lookup()
    }

    func lookup() {
        let faceID = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !faceID.isEmpty else {
            loadFirstPage()
            return
        }
        let generation = beginOperation(status: "正在查询…")
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let database = try await database()
                let total = try await database.count()
                let snapshot: ListSnapshot
                do {
                    snapshot = ListSnapshot(
                        count: total,
                        people: [SearchLibraryPerson(try await database.entry(faceID: faceID))]
                    )
                } catch let error as HiFaceError where error.code == .notFound {
                    snapshot = ListSnapshot(count: total, people: [])
                }
                guard isCurrent(generation) else { return }
                apply(snapshot, lookup: true)
                status = snapshot.people.isEmpty ? "未找到 Face ID：\(faceID)" : "找到 1 条记录"
                finish(generation)
            } catch {
                finish(error, generation: generation)
            }
        }
    }

    func clearLookup() {
        query = ""
        loadFirstPage()
    }

    /// 最后 10 条记录进入可见范围时预加载下一批，只检查这个小窗口。
    func loadMoreIfNeeded(current person: SearchLibraryPerson) {
        guard !isWorking, !isLookup, pendingDeleteFaceID == nil, pendingImport == nil, canLoadMore,
              people.suffix(Self.prefetchRemaining).contains(where: { $0.id == person.id }) else { return }
        let offset = nextOffset
        let generation = beginOperation(status: "正在加载更多…")
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let database = try await database()
                let total = try await database.count()
                let loaded = try await database.recentEntries(offset: offset, limit: Self.loadSize)
                    .map(SearchLibraryPerson.init)
                guard isCurrent(generation) else { return }
                nextOffset = offset + loaded.count
                canLoadMore = !loaded.isEmpty && nextOffset < Int(clamping: total)
                people = Self.merge(people, with: loaded)
                status = "共 \(total) 条人脸记录"
                finish(generation)
            } catch {
                finish(error, generation: generation)
            }
        }
    }

    func requestDelete(faceID: String) {
        guard !isWorking, pendingImport == nil else { return }
        pendingDeleteFaceID = faceID
    }

    func confirmDelete() {
        guard let faceID = pendingDeleteFaceID else { return }
        pendingDeleteFaceID = nil
        let lookup = isLookup
        let generation = beginOperation(status: "正在删除 \(faceID)…")
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let database = try await database()
                _ = try await database.delete(faceID: faceID)
                let snapshot: ListSnapshot
                if lookup {
                    snapshot = ListSnapshot(count: try await database.count(), people: [])
                } else {
                    snapshot = try await Self.firstPage(database: database)
                }
                guard isCurrent(generation) else { return }
                if !lookup { query = "" }
                apply(snapshot, lookup: lookup)
                status = "已删除 \(faceID)"
                finish(generation)
            } catch {
                finish(error, generation: generation)
            }
        }
    }

    func cancelDelete() { pendingDeleteFaceID = nil }

    func requestImport(_ kind: FaceSearchDemoImportKind) {
        guard !isWorking, pendingDeleteFaceID == nil else { return }
        pendingImport = kind
    }
    func cancelImport() { pendingImport = nil }

    func confirmImport() {
        guard let kind = pendingImport else { return }
        pendingImport = nil
        let generation = beginOperation(status: "准备\(kind.title)…")
        let sdk: HiFaceSDK? = kind == .images ? {
            // 每次导入独立持有 SDK；旧导入仍在退出时不能复用其即将关闭的实例。
            let value = DemoEnvironment.makeSDK()
            imageImportSDK = value
            return value
        }() : nil
        operationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if kind == .images {
                    sdk?.close()
                    if imageImportSDK === sdk { imageImportSDK = nil }
                }
            }
            do {
                let progress: @MainActor @Sendable (Int, Int) -> Void = { [weak self] done, total in
                    guard let self, isCurrent(generation) else { return }
                    status = "\(kind.title)：\(done) / \(total)"
                }
                let database = try await database()
                let summary: FaceSearchDemoImportSummary
                switch kind {
                case .features:
                    summary = try await FaceSearchDemoImporter.importFeatures(
                        database: database,
                        progress: progress
                    )
                case .images:
                    guard let sdk else {
                        throw HiFaceError(code: .internalError, message: "Image importer SDK is unavailable")
                    }
                    summary = try await FaceSearchDemoImporter.importImages(
                        sdk: sdk,
                        database: database,
                        progress: progress
                    )
                }
                let snapshot = try await Self.firstPage(database: database)
                guard isCurrent(generation) else { return }
                query = ""
                apply(snapshot)
                status = summary.failed == 0
                    ? "已导入 \(summary.imported) 条"
                    : "已导入 \(summary.imported) 条，跳过 \(summary.failed) 条"
                finish(generation)
            } catch is CancellationError {
                finish(generation)
            } catch {
                finish(error, generation: generation)
            }
        }
    }

    func stop() {
        operationGeneration &+= 1
        operationTask?.cancel()
        operationTask = nil
        imageImportSDK?.close()
        imageImportSDK = nil
        let opening = databaseTask
        databaseGeneration &+= 1
        databaseTask = nil
        if let opening {
            Task {
                guard let database = try? await opening.value else { return }
                await database.close()
            }
        }
        isWorking = false
        canLoadMore = false
        pendingDeleteFaceID = nil
        pendingImport = nil
    }

    deinit { imageImportSDK?.close() }

    private func loadFirstPage() {
        let generation = beginOperation(status: "读取中…")
        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let database = try await database()
                let snapshot = try await Self.firstPage(database: database)
                guard isCurrent(generation) else { return }
                apply(snapshot)
                status = "共 \(snapshot.count) 条人脸记录"
                finish(generation)
            } catch {
                finish(error, generation: generation)
            }
        }
    }

    private func beginOperation(status: String) -> Int {
        operationTask?.cancel()
        operationGeneration &+= 1
        isWorking = true
        hasError = false
        self.status = status
        return operationGeneration
    }

    /// 查询、删除、导入和刷新共用首批状态更新，避免总数、偏移和列表模式不一致。
    private func apply(_ snapshot: ListSnapshot, lookup: Bool = false) {
        people = snapshot.people
        isLookup = lookup
        nextOffset = lookup ? 0 : snapshot.people.count
        canLoadMore = !lookup && !snapshot.people.isEmpty && nextOffset < Int(clamping: snapshot.count)
    }

    private func isCurrent(_ generation: Int) -> Bool {
        !Task.isCancelled && operationGeneration == generation
    }

    private func finish(_ generation: Int) {
        guard operationGeneration == generation else { return }
        isWorking = false
        operationTask = nil
    }

    private func finish(_ error: Error, generation: Int) {
        guard isCurrent(generation) else { return }
        status = (error as? HiFaceError).map(DemoErrorPresentation.message(for:))
            ?? error.localizedDescription
        hasError = true
        canLoadMore = false
        finish(generation)
    }

    private nonisolated static func firstPage(database: FaceSearchDatabase) async throws -> ListSnapshot {
        let total = try await database.count()
        let entries = total == 0 ? [] : try await database.recentEntries(offset: 0, limit: loadSize)
        return ListSnapshot(count: total, people: entries.map(SearchLibraryPerson.init))
    }

    /// 数据更新会改变 recent 排序；按 ID 合并分页结果，刷新已展示的元数据并避免重复行。
    private nonisolated static func merge(
        _ current: [SearchLibraryPerson],
        with page: [SearchLibraryPerson]
    ) -> [SearchLibraryPerson] {
        var merged = current
        var indexes: [String: Int] = [:]
        for (index, person) in current.enumerated() { indexes[person.id] = index }
        for person in page {
            if let index = indexes[person.id] {
                merged[index] = person
            } else {
                indexes[person.id] = merged.count
                merged.append(person)
            }
        }
        return merged
    }

    /// 页面生命周期内复用同一连接，避免每加载 100 条就重复打开 SQLite 和重建连接缓存。
    private func database() async throws -> FaceSearchDatabase {
        let opening = databaseTask ?? Task.detached { try HiFaceSDK.openSearchDatabase() }
        databaseTask = opening
        let generation = databaseGeneration
        do {
            let database = try await opening.value
            try Task.checkCancellation()
            return database
        } catch {
            // 打开失败允许重试；旧页面任务结束时不能清空新页面已建立的连接。
            if generation == databaseGeneration, !(error is CancellationError) {
                databaseGeneration &+= 1
                databaseTask = nil
            }
            throw error
        }
    }
}
