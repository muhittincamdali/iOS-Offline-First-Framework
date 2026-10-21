import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// The file 2.0.0 wrote for the store "a" (its test clock at 1,700,000,000 s): "n" and "s"
/// accepted as v1 and v2 with the token "2", then an edit of "n" whose push the server applied
/// as v3 while its answer was lost (attempt 1, retry 10 seconds later), then a record "new"
/// that was never sent. Written by 2.0.0's `OfflineStore` through `InMemoryStorage`.
private let fileOf200 = #"""
{"clock":{"counter":3,"nodeID":"224CB6FB-A7AA-4C4C-B799-B162D73EB8C9","wallTime":1700000000000},"entries":[{"id":"n","pending":{"attempts":1,"changeID":"5778BE3B-406C-4C55-9058-9D3CD079411B","isParked":false,"lastError":"Error Domain=NSURLErrorDomain Code=-1005 \"(null)\"","nextAttemptAt":721692810,"sequence":4},"position":0,"record":{"id":"n","text":"A's edit"},"revision":"v1","timestamp":{"counter":2,"nodeID":"224CB6FB-A7AA-4C4C-B799-B162D73EB8C9","wallTime":1700000000000},"wasSent":true},{"id":"s","position":2,"record":{"id":"s","text":"synced"},"revision":"v2","timestamp":{"counter":1,"nodeID":"224CB6FB-A7AA-4C4C-B799-B162D73EB8C9","wallTime":1700000000000},"wasSent":true},{"id":"new","pending":{"attempts":0,"changeID":"5166E23A-96A0-4438-8EA8-FB11BE31C1AF","isParked":false,"sequence":6},"position":5,"record":{"id":"new","text":"never sent"},"timestamp":{"counter":3,"nodeID":"224CB6FB-A7AA-4C4C-B799-B162D73EB8C9","wallTime":1700000000000},"wasSent":false}],"format":1,"lastSyncedAt":721692800,"nextSequence":7,"nodeID":"224CB6FB-A7AA-4C4C-B799-B162D73EB8C9","schemaVersion":1,"token":"2"}
"""#

/// The change ID of the edit of "n" in ``fileOf200``.
private let lostEditID = UUID(uuidString: "5778BE3B-406C-4C55-9058-9D3CD079411B")!

/// The server the store of ``fileOf200`` synced with: revisions `v<position>`, tokens the last
/// position, sequences, change IDs, and the answers to change IDs it applied. It holds what the
/// file says, the edit whose answer was lost, and B's edit of "n" made on top of it.
private actor ServerOf200 {
    struct Version { var record: Note?; var revision: String; var position: Int; var changeID: UUID? }
    private var stored: [String: Version] = [:]
    private var answers: [UUID: PushOutcome<Note>] = [:]
    private var position = 0
    var epoch: String?

    /// v1 ("base") and v3 (the edit whose answer was lost) of "n" were replaced by B's v4.
    init(epoch: String?) {
        self.epoch = epoch
        stored = ["s": Version(record: Note(id: "s", text: "synced"), revision: "v2", position: 2, changeID: nil),
                  "n": Version(record: Note(id: "n", text: "B's edit"), revision: "v4", position: 4, changeID: UUID())]
        answers = [lostEditID: .accepted(revision: "v3")]
        position = 4
    }

    @discardableResult
    private func apply(_ record: Note, changeID: UUID?) -> String {
        position += 1
        stored[record.id] = Version(record: record, revision: "v\(position)", position: position, changeID: changeID)
        if let changeID { answers[changeID] = .accepted(revision: "v\(position)") }
        return "v\(position)"
    }

    func push(_ changes: [OutgoingChange<Note>]) -> [UUID: PushOutcome<Note>] {
        var outcomes: [UUID: PushOutcome<Note>] = [:]
        for change in changes {
            if let answer = answers[change.id] {
                outcomes[change.id] = answer
            } else if let current = stored[change.recordID], current.revision != change.baseRevision {
                outcomes[change.id] = .conflict(current: remote(change.recordID, current))
            } else {
                outcomes[change.id] = .accepted(revision: apply(change.record ?? Note(id: change.recordID, text: ""), changeID: change.id))
            }
        }
        return outcomes
    }

    func pull(_ token: String?) -> PullResponse<Note> {
        let after = token.flatMap { Int($0) } ?? 0
        let changed = stored.filter { $0.value.position > after }.sorted { $0.value.position < $1.value.position }
        return PullResponse(changes: changed.map { remote($0.key, $0.value) }, token: "\(changed.last?.value.position ?? after)",
                            hasMore: false, epoch: epoch)
    }

    func text(_ id: String) -> String? { stored[id]?.record?.text }

    private func remote(_ id: String, _ version: Version) -> RemoteChange<Note> {
        RemoteChange(recordID: id, record: version.record, revision: version.revision, timestamp: nil,
                     sequence: UInt64(version.position), changeID: version.changeID)
    }
}

/// A store file of 2.0.0. 2.0.0 kept none of the state that now protects accepted writes: epochs
/// and whether two requests reported them, changes in doubt, own writes. A missing epoch check
/// and missing own writes already read the safe way (the next sync checks the epoch with a
/// second request; the push answer decides instead of an own write). A missing in-doubt mark did
/// not: an edit whose push the server applied while its answer was lost counted as never sent,
/// so a pull before its retry met B's edit, made on top of it, as a conflict, and `.clientWins`
/// and the merge put the device's edit back over B's. A pending change of a file without the mark
/// now counts as in doubt when it may have gone out. A value the file holds but that cannot be
/// read fails the open instead of counting as missing.
@Suite("Offline store: store files of 2.0.0")
struct StoreFileVersionTests {
    private func storage(holding text: String) throws -> InMemoryStorage {
        let storage = InMemoryStorage()
        try storage.write(Data(text.utf8), to: "a.store")
        return storage
    }

    private func resolver(_ policy: ScenarioPolicy, asked: OSAllocatedUnfairLock<[String]>) -> ConflictResolver<Note> {
        ConflictResolver { conflict in
            asked.withLock { $0.append("\(conflict.recordID): \(conflict.local?.text ?? "-") / \(conflict.remote?.text ?? "-")") }
            switch policy {
            case .serverWins: return .keepRemote
            case .clientWins: return .keepLocal
            case .lastWriteWins: return ConflictResolver<Note>.lastWriteWins.resolve(conflict)
            case .merge:
                return .merged(Note(id: conflict.recordID, text: "\(conflict.local?.text ?? "") | \(conflict.remote?.text ?? "")"))
            }
        }
    }

    @Test func aFileOf200ReadsWhatItDoesNotSayTheSafeWay() async throws {
        let clock = TestClock()
        let storage = try storage(holding: fileOf200)
        let a = try OfflineStore<Note>(name: "a", storage: storage, configuration: makeConfiguration(clock: clock))
        let state = await a.state
        #expect(state.token == "2")
        #expect(state.serverEpoch == nil)
        #expect(!state.epochIsConfirmed)
        #expect(state.history == 0)
        #expect(state.retiredEpochs.isEmpty)
        #expect(state.entries["n"]?.pending?.isInDoubt == true)
        #expect(state.entries["n"]?.pending?.changeID == lostEditID)
        #expect(state.entries["new"]?.pending?.isInDoubt == false)
        #expect(state.entries["s"]?.pending == nil)
        #expect(state.entries.values.allSatisfy { $0.ownChangeIDs.isEmpty && $0.sequence == nil })

        // The next write records the mark, and the file opens with it.
        try await a.save(Note(id: "t", text: "after the upgrade"))
        let reopened = try OfflineStore<Note>(name: "a", storage: storage, configuration: makeConfiguration(clock: clock))
        #expect(await reopened.state.entries["n"]?.pending?.isInDoubt == true)
        #expect(await reopened.state.entries["new"]?.pending?.isInDoubt == false)
        #expect(await reopened.state.entries["t"]?.pending?.isInDoubt == false)
    }

    /// The edit of "n" was applied as v3, its answer lost, and B edited on top of it (v4). The
    /// first sync after the upgrade comes before the edit's retry: its pull brings B's edit.
    @Test(arguments: ScenarioPolicy.allCases, [false, true])
    func anEditOf200WhoseAnswerWasLostDoesNotGoBackOverALaterEdit(policy: ScenarioPolicy, reportsEpochs: Bool) async throws {
        let clock = TestClock()
        let server = ServerOf200(epoch: reportsEpochs ? "e1" : nil)
        let transport = ScriptedTransport(push: { await server.push($0) }, pull: { await server.pull($0) })
        let asked = OSAllocatedUnfairLock<[String]>(initialState: [])
        let a = try OfflineStore<Note>(name: "a", storage: try storage(holding: fileOf200), transport: transport,
                                       configuration: makeConfiguration(clock: clock, resolver: resolver(policy, asked: asked)))
        try await a.sync()
        for _ in 0..<4 {
            clock.advance(by: 120)
            try await a.sync()
        }
        #expect(asked.withLock { $0 }.isEmpty)
        #expect(await server.text("n") == "B's edit")
        #expect(await a.record("n")?.text == "B's edit")
        #expect(await a.record("s")?.text == "synced")
        #expect(await server.text("new") == "never sent")
        #expect(await a.pendingChanges().isEmpty)
        #expect(await a.failedChanges().isEmpty)
        #expect(await a.state.epochIsConfirmed)
    }

    /// A value of the sync state that the file holds but that cannot be read is not taken for a
    /// missing one: the open fails, and `.moveAsideAndStartEmpty` starts a new store, whose first
    /// page is checked by a second request.
    @Test(arguments: ["epochIsConfirmed", "retiredEpochs", "ownChangeIDs", "supersededChangeIDs", "isInDoubt"])
    func anUnreadableValueOfTheSyncStateFailsTheOpen(key: String) async throws {
        let clock = TestClock()
        let storage = InMemoryStorage()
        let store = try OfflineStore<Note>(name: "a", storage: storage, configuration: makeConfiguration(clock: clock))
        try await store.save(Note(id: "n", text: "pending"))
        let data = try #require(try storage.read("a.store"))
        guard case .object(var file) = try JSONDecoder().decode(JSONValue.self, from: data),
              case .array(var entries) = file["entries"] else { throw CancellationError() }
        switch key {
        case "ownChangeIDs": entries[0]["ownChangeIDs"] = "not a list"
        case "supersededChangeIDs": entries[0]["pending"]?["supersededChangeIDs"] = 7
        case "isInDoubt": entries[0]["pending"]?["isInDoubt"] = "not a value of its type"
        default: file[key] = "not a value of its type"
        }
        file["entries"] = .array(entries)
        try storage.write(JSONEncoder().encode(JSONValue.object(file)), to: "a.store")

        #expect {
            try OfflineStore<Note>(name: "a", storage: storage, configuration: makeConfiguration(clock: clock))
        } throws: { error in
            guard case .corruptStore = error as? OfflineFirstError else { return false }
            return true
        }
        var configuration = makeConfiguration(clock: clock)
        configuration.corruptionPolicy = .moveAsideAndStartEmpty
        let fresh = try OfflineStore<Note>(name: "a", storage: storage, configuration: configuration)
        #expect(await fresh.records().isEmpty)
        #expect(await !fresh.state.epochIsConfirmed)
        #expect(await fresh.state.token == nil)
    }

    enum Interruption: String, CaseIterable, Sendable, CustomStringConvertible {
        case none, dropAtFirstPull, dropAtSecondPull, dropAtThirdPull, onePage, twoPages
        var description: String { rawValue }
    }

    enum ServerChange: String, CaseIterable, Sendable, CustomStringConvertible {
        case none, restarted, moreWrites
        var description: String { rawValue }
    }

    /// The keys a store file of 2.0.0 holds, at the top, in an entry and in a pending change.
    private static let keysOf200: (file: Set<String>, entry: Set<String>, pending: Set<String>) = (
        ["clock", "entries", "format", "lastSyncedAt", "nextSequence", "nodeID", "schemaVersion", "token"],
        ["id", "pending", "position", "record", "revision", "timestamp", "wasSent"],
        ["attempts", "changeID", "isParked", "lastError", "nextAttemptAt", "sequence"]
    )

    /// Keeps only what 2.0.0 wrote.
    private static func asFileOf200(_ data: Data) throws -> Data {
        guard case .object(var file) = try JSONDecoder().decode(JSONValue.self, from: data),
              case .array(var entries) = file["entries"] else { throw CancellationError() }
        file = file.filter { keysOf200.file.contains($0.key) }
        for index in entries.indices {
            guard case .object(var entry) = entries[index] else { continue }
            entry = entry.filter { keysOf200.entry.contains($0.key) }
            if case .object(let pending)? = entry["pending"] {
                entry["pending"] = .object(pending.filter { keysOf200.pending.contains($0.key) })
            }
            entries[index] = .object(entry)
        }
        file["entries"] = .array(entries)
        return try JSONEncoder().encode(JSONValue.object(file))
    }

    /// 500 records a store of 2.0.0 synced, the app updated, and a first sync that ends early or
    /// not: the store keeps every record through it, also with a server that restarted (its
    /// token is no longer valid, so the pull starts over) or wrote more since.
    @Test(arguments: Interruption.allCases, ServerChange.allCases)
    func aFileOf200With500RecordsKeepsThemThroughTheFirstSync(interruption: Interruption, change: ServerChange) async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(pageSize: 100, now: { clock.now })
        for index in 0..<500 { await server.write(Note(id: "r\(index)", text: "record \(index)")) }
        let storage = InMemoryStorage()
        let pullsLeft = OSAllocatedUnfairLock(initialState: Int.max)
        let transport = ScriptedTransport(push: { try await server.push($0) }, pull: { token in
            guard pullsLeft.withLock({ left in defer { left -= 1 }; return left > 0 }) else {
                throw URLError(.networkConnectionLost)
            }
            return try await server.pull(since: token)
        })
        let before = try OfflineStore<Note>(name: "a", storage: storage, transport: transport,
                                            configuration: makeConfiguration(clock: clock))
        try await before.sync()
        #expect(await before.count == 500)
        try storage.write(try Self.asFileOf200(try #require(try storage.read("a.store"))), to: "a.store")

        switch change {
        case .none: break
        case .restarted: await server.restart()
        case .moreWrites: for index in 500..<650 { await server.write(Note(id: "r\(index)", text: "record \(index)")) }
        }
        var configuration = makeConfiguration(clock: clock)
        switch interruption {
        case .none: break
        case .dropAtFirstPull: pullsLeft.withLock { $0 = 0 }
        case .dropAtSecondPull: pullsLeft.withLock { $0 = 1 }
        case .dropAtThirdPull: pullsLeft.withLock { $0 = 2 }
        case .onePage: configuration.maximumPullPages = 1
        case .twoPages: configuration.maximumPullPages = 2
        }
        let upgraded = try OfflineStore<Note>(name: "a", storage: storage, transport: transport, configuration: configuration)
        #expect(await upgraded.count == 500)
        _ = try? await upgraded.sync()
        let kept = Set(await upgraded.records().map(\.id))
        #expect((0..<500).allSatisfy { kept.contains("r\($0)") })
        let reopened = try OfflineStore<Note>(name: "a", storage: storage, configuration: configuration)
        #expect(Set(await reopened.records().map(\.id)) == kept)

        // The connection comes back: the store ends with the server's records.
        pullsLeft.withLock { $0 = Int.max }
        let later = try OfflineStore<Note>(name: "a", storage: storage, transport: transport,
                                           configuration: makeConfiguration(clock: clock))
        for _ in 0..<3 { try await later.sync() }
        let expected = await server.records().sorted { $0.id < $1.id }
        #expect(await later.records().sorted { $0.id < $1.id } == expected)
        #expect(expected.count == (change == .moreWrites ? 650 : 500))
    }
}
