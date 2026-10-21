import Foundation
import Testing
@testable import OfflineFirstFramework

/// Answers that break the protocol must not grow, corrupt or roll back the store.
@Suite("Offline store: misbehaving servers")
struct MisbehavingServerTests {
    let clock = TestClock()

    private func makeStore(_ transport: any SyncTransport<Note>, storage: any StorageBackend = InMemoryStorage(),
                           resolver: ConflictResolver<Note> = .lastWriteWins) throws -> OfflineStore<Note> {
        try OfflineStore<Note>(name: "notes", storage: storage, transport: transport,
                               configuration: makeConfiguration(clock: clock, resolver: resolver))
    }

    @Test func anAcceptedRevisionOverTheLimitIsNotStored() async throws {
        let long = String(repeating: "r", count: 200_000)
        let transport = ScriptedTransport(push: { changes in
            Dictionary(uniqueKeysWithValues: changes.map { ($0.id, .accepted(revision: long)) })
        })
        let storage = InMemoryStorage()
        let store = try makeStore(transport, storage: storage)
        try await store.save(Note(id: "a", text: "A"))
        let report = try await store.sync()
        #expect(report.pushed == 0)
        let pending = try #require(await store.pendingChanges().first)
        #expect(pending.attempts == 1)
        #expect(pending.lastError?.contains("revision") == true)
        let file = try #require(try storage.read("notes.store"))
        #expect(file.count < 10_000)
    }

    /// The server's sequences tell the older version; without them the store cannot tell (see
    /// ServerOrderTests).
    @Test func pagesOutOfOrderDoNotRollBackARecord() async throws {
        let newer = RemoteChange(recordID: "a", record: Note(id: "a", text: "new"), revision: "5",
                                 timestamp: HLCTimestamp(wallTime: 5_000, nodeID: "laptop"), sequence: 5)
        let older = RemoteChange(recordID: "a", record: Note(id: "a", text: "old"), revision: "3",
                                 timestamp: HLCTimestamp(wallTime: 3_000, nodeID: "laptop"), sequence: 3)
        let transport = ScriptedTransport(pull: { token in
            switch token {
            case nil: PullResponse(changes: [newer], token: "p1", hasMore: true)
            case "p1": PullResponse(changes: [older], token: "p2", hasMore: false)
            default: PullResponse(changes: [], token: token, hasMore: false)
            }
        })
        let store = try makeStore(transport)
        let report = try await store.sync()
        // The older version is skipped: no conflict, and nothing goes back to the server.
        #expect(report.conflicts == 0)
        #expect(report.pulled == 1)
        #expect(await store.record("a")?.text == "new")
        #expect(await store.pendingChanges().isEmpty)
        #expect(await store.state.entries["a"]?.revision == "5")
        try await store.sync()
        #expect(await transport.pushed.isEmpty)
    }

    /// The same pages with `.serverWins`: a policy that takes every server version must not take
    /// an older one either.
    @Test func pagesOutOfOrderDoNotRollBackARecordWithServerWins() async throws {
        let newer = RemoteChange(recordID: "a", record: Note(id: "a", text: "new"), revision: "5",
                                 timestamp: HLCTimestamp(wallTime: 5_000, nodeID: "laptop"), sequence: 5)
        let older = RemoteChange(recordID: "a", record: Note(id: "a", text: "old"), revision: "3",
                                 timestamp: HLCTimestamp(wallTime: 3_000, nodeID: "laptop"), sequence: 3)
        let transport = ScriptedTransport(pull: { token in
            switch token {
            case nil: PullResponse(changes: [newer], token: "p1", hasMore: true)
            case "p1": PullResponse(changes: [older], token: "p2", hasMore: false)
            default: PullResponse(changes: [], token: token, hasMore: false)
            }
        })
        let store = try makeStore(transport, resolver: .serverWins)
        try await store.sync()
        try await store.sync()
        #expect(await store.record("a")?.text == "new")
    }

    /// The store first sees the deletion of a record it never held, then an older live version.
    @Test func aDeletionOfARecordTheStoreNeverHeldIsKept() async throws {
        let deleted = RemoteChange<Note>(recordID: "a", record: nil, revision: "5",
                                         timestamp: HLCTimestamp(wallTime: 5_000, nodeID: "laptop"), sequence: 5)
        let older = RemoteChange(recordID: "a", record: Note(id: "a", text: "old"), revision: "3",
                                 timestamp: HLCTimestamp(wallTime: 3_000, nodeID: "laptop"), sequence: 3)
        let transport = ScriptedTransport(pull: { token in
            switch token {
            case nil: PullResponse(changes: [deleted], token: "p1", hasMore: true)
            case "p1": PullResponse(changes: [older], token: "p2", hasMore: false)
            default: PullResponse(changes: [], token: token, hasMore: false)
            }
        })
        let store = try makeStore(transport)
        try await store.sync()
        try await store.sync()
        #expect(await store.record("a") == nil)
        #expect(await store.state.entries["a"]?.revision == "5")
    }

    /// Without timestamps the server's sequence tells which version is older.
    @Test func aStalePageWithoutTimestampsIsRecognisedBySequence() async throws {
        let transport = ScriptedTransport(pull: { token in
            switch token {
            case nil: PullResponse(changes: [RemoteChange(recordID: "a", record: Note(id: "a", text: "A"), revision: "1", timestamp: nil, sequence: 1)],
                                   token: "t1", hasMore: false)
            case "t1": PullResponse(changes: [RemoteChange(recordID: "a", record: nil, revision: "3", timestamp: nil, sequence: 3)],
                                    token: "t3", hasMore: true)
            case "t3": PullResponse(changes: [RemoteChange(recordID: "a", record: Note(id: "a", text: "A"), revision: "2", timestamp: nil, sequence: 2)],
                                    token: "t4", hasMore: false)
            default: PullResponse(changes: [], token: token, hasMore: false)
            }
        })
        let store = try makeStore(transport)
        try await store.sync()
        #expect(await store.record("a") != nil)
        try await store.sync()
        try await store.sync()
        #expect(await store.record("a") == nil)
    }

    /// aStalePullDoesNotBringBackADeletedRecord with `.serverWins`.
    @Test func aStalePullDoesNotBringBackADeletedRecordWithServerWins() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = ScriptedTransport()
        await transport.onPush { try await server.push($0) }
        await transport.onPull { try await server.pull(since: $0) }
        let store = try makeStore(transport, resolver: .serverWins)
        try await store.save(Note(id: "a", text: "A"))
        try await store.sync()
        let beforeDelete = try await server.pull(since: nil)
        clock.advance(by: 1)
        try await store.delete("a")
        try await store.sync()
        #expect(await server.record("a") == nil)

        let replicaAnswered = OneShot()
        await transport.onPull { token in
            if await replicaAnswered.fire() { return beforeDelete }
            return try await server.pull(since: token)
        }
        try await store.sync()
        #expect(await store.records().isEmpty)
        try await store.sync()
        #expect(await store.records().isEmpty)
        #expect(await server.record("a") == nil)
    }

    /// A stale page that meets a pending local edit is not a conflict either: with `.serverWins`
    /// the edit would otherwise be dropped for a version the server no longer has.
    @Test func aStalePageDoesNotDropAPendingEdit() async throws {
        let current = RemoteChange(recordID: "a", record: Note(id: "a", text: "current"), revision: "5",
                                   timestamp: HLCTimestamp(wallTime: 5_000, nodeID: "laptop"), sequence: 5)
        let older = RemoteChange(recordID: "a", record: Note(id: "a", text: "old"), revision: "3",
                                 timestamp: HLCTimestamp(wallTime: 3_000, nodeID: "laptop"), sequence: 3)
        let transport = ScriptedTransport(push: { _ in throw URLError(.notConnectedToInternet) }, pull: { token in
            token == nil ? PullResponse(changes: [current], token: "p5", hasMore: false)
                : PullResponse(changes: [older], token: "p3", hasMore: false)
        })
        let store = try makeStore(transport, resolver: .serverWins)
        try await store.sync()
        try await store.save(Note(id: "a", text: "local edit"))
        await #expect(throws: URLError.self) { try await store.sync() }
        // The push waits for its retry date; the pull meets the older version.
        try await store.sync()
        #expect(await store.record("a")?.text == "local edit")
        #expect(await store.pendingChanges().count == 1)
    }

    /// A conflict answer that names the version the change is based on, or an older one, is
    /// not resolved; the change is tried again later.
    @Test func aConflictAnswerWithAnOlderVersionIsAFailedAttempt() async throws {
        let current = RemoteChange(recordID: "a", record: Note(id: "a", text: "current"), revision: "5", timestamp: nil, sequence: 5)
        let older = RemoteChange(recordID: "a", record: Note(id: "a", text: "old"), revision: "3", timestamp: nil, sequence: 3)
        let transport = ScriptedTransport(
            push: { changes in Dictionary(uniqueKeysWithValues: changes.map { ($0.id, .conflict(current: older)) }) },
            pull: { token in PullResponse(changes: token == nil ? [current] : [], token: "p5", hasMore: false) }
        )
        let store = try makeStore(transport, resolver: .serverWins)
        try await store.sync()
        try await store.save(Note(id: "a", text: "local edit"))
        let report = try await store.sync()
        #expect(report.conflicts == 1)
        let pending = try #require(await store.pendingChanges().first)
        #expect(pending.record?.text == "local edit")
        #expect(pending.attempts == 1)
        #expect(pending.lastError?.contains("older version") == true)
    }

    @Test func aStalePullDoesNotBringBackADeletedRecord() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = ScriptedTransport()
        await transport.onPush { try await server.push($0) }
        await transport.onPull { try await server.pull(since: $0) }
        let store = try makeStore(transport)
        try await store.save(Note(id: "a", text: "A"))
        try await store.sync()
        let beforeDelete = try await server.pull(since: nil)

        clock.advance(by: 1)
        try await store.delete("a")
        try await store.sync()
        #expect(await server.record("a") == nil)

        // A lagging replica answers the next pull with the record as it was before the delete.
        let replicaAnswered = OneShot()
        await transport.onPull { token in
            if await replicaAnswered.fire() { return beforeDelete }
            return try await server.pull(since: token)
        }
        try await store.sync()
        #expect(await store.records().isEmpty)
        try await store.sync()
        #expect(await store.records().isEmpty)
        #expect(await store.pendingChanges().isEmpty)
        #expect(await server.record("a") == nil)
    }

    /// Tokens that go round in a circle (A, B, A, ...) with "more follow" stop the pull at the
    /// first repeat instead of costing a hundred requests and file writes on every sync.
    @Test func changeTokensThatGoRoundInACircleStopThePull() async throws {
        let storage = WriteCountingStorage()
        let transport = ScriptedTransport(pull: { token in
            PullResponse(changes: [RemoteChange(recordID: "a", record: Note(id: "a", text: "a"), revision: "1", timestamp: nil)],
                         token: token == "A" ? "B" : "A", hasMore: true)
        })
        let store = try makeStore(transport, storage: storage)
        await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        #expect(await transport.pulls == 3)
        #expect(storage.writes <= 3)
        #expect(await store.state.token == "B")
    }

    /// A page that says more changes follow without moving the token is refused before any of
    /// it is stored.
    @Test func aPageThatDoesNotMoveTheTokenIsNotStored() async throws {
        let transport = ScriptedTransport(pull: { token in
            PullResponse(changes: [RemoteChange(recordID: "a", record: Note(id: "a", text: "A"), revision: "1", timestamp: nil)],
                         token: token, hasMore: true)
        })
        let store = try makeStore(transport)
        await #expect(throws: OfflineFirstError.pullTokenDidNotAdvance(token: nil)) { try await store.sync() }
        #expect(await store.records().isEmpty)
    }

    @Test func tombstonesAreKeptUpToTheLimit() async throws {
        #expect(OfflineStore<Note>.Configuration().maximumTombstones == 10_000)
        let limit = 50
        let total = limit + 5
        let tombstones = (0..<total).map { index in
            StoredEntry<Note>(id: "n\(index)", record: nil, timestamp: HLCTimestamp(wallTime: Int64(index), nodeID: "x"),
                              revision: "\(index)", position: UInt64(index), pending: nil)
        }
        let file = StoreFile<Note>(format: StoreFile<Note>.currentFormat, schemaVersion: 1, nodeID: "x", clock: nil, token: nil,
                                   lastSyncedAt: nil, nextSequence: UInt64(total), entries: tombstones)
        let storage = InMemoryStorage()
        try storage.write(StoreFileCoder.encode(file), to: "notes.store")
        var configuration = makeConfiguration(clock: clock)
        configuration.maximumTombstones = limit
        let store = try OfflineStore<Note>(name: "notes", storage: storage, transport: ScriptedTransport(), configuration: configuration)
        #expect(await store.state.entries.count == total)
        try await store.sync()
        let entries = await store.state.entries
        #expect(entries.count == limit)
        #expect(entries["n0"] == nil)
        #expect(entries["n\(total - 1)"] != nil)
    }

    @Test func aRestartedServerSendsEverythingAgain() async throws {
        let storage = InMemoryStorage()
        let before = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        for id in ["a", "b", "c"] {
            await before.write(Note(id: id, text: id))
        }
        let first = try makeStore(before, storage: storage)
        try await first.sync()
        #expect(try await first.sync().pulled == 0)

        // A new instance starts at revision 0 again; the saved token belongs to the old one.
        // It gets past the old token's revision 3, so only the epoch tells the two apart:
        // reading the old token as a revision here would skip the first three writes.
        let restarted = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let written = ["w", "x", "y", "z"]
        for id in written {
            await restarted.write(Note(id: id, text: "written after the restart"))
        }
        let store = try makeStore(restarted, storage: storage)
        let report = try await store.sync()
        #expect(report.pulled == written.count)
        for id in written {
            #expect(await store.record(id) != nil)
        }
        #expect(try await store.sync().pulled == 0)
    }
}
