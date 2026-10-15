import Foundation
import Testing
@testable import OfflineFirstFramework

/// Answers that break the protocol must not grow, corrupt or roll back the store.
@Suite("Offline store: misbehaving servers")
struct MisbehavingServerTests {
    let clock = TestClock()

    private func makeStore(_ transport: any SyncTransport<Note>, storage: any StorageBackend = InMemoryStorage()) throws -> OfflineStore<Note> {
        try OfflineStore<Note>(name: "notes", storage: storage, transport: transport, configuration: makeConfiguration(clock: clock))
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

    @Test func pagesOutOfOrderDoNotRollBackARecord() async throws {
        let newer = RemoteChange(recordID: "a", record: Note(id: "a", text: "new"), revision: "5",
                                 timestamp: HLCTimestamp(wallTime: 5_000, nodeID: "laptop"))
        let older = RemoteChange(recordID: "a", record: Note(id: "a", text: "old"), revision: "3",
                                 timestamp: HLCTimestamp(wallTime: 3_000, nodeID: "laptop"))
        let transport = ScriptedTransport(
            push: { changes in Dictionary(uniqueKeysWithValues: changes.map { ($0.id, .conflict(current: newer)) }) },
            pull: { token in
                switch token {
                case nil: PullResponse(changes: [newer], token: "p1", hasMore: true)
                case "p1": PullResponse(changes: [older], token: "p2", hasMore: false)
                default: PullResponse(changes: [], token: token, hasMore: false)
                }
            }
        )
        let store = try makeStore(transport)
        let report = try await store.sync()
        #expect(report.conflicts == 1)
        #expect(await store.record("a")?.text == "new")
        // The newer version is offered back on top of the older revision; the server's answer
        // shows it is current and settles the record.
        let offered = try #require(await store.pendingChanges().first)
        #expect(offered.record?.text == "new")
        try await store.sync()
        #expect(await store.pendingChanges().isEmpty)
        #expect(await store.record("a")?.text == "new")
        #expect(await store.state.entries["a"]?.revision == "5")
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

    @Test func tombstonesAreKeptUpToTheLimit() async throws {
        let total = OfflineStore<Note>.maximumTombstones + 5
        let tombstones = (0..<total).map { index in
            StoredEntry<Note>(id: "n\(index)", record: nil, timestamp: HLCTimestamp(wallTime: Int64(index), nodeID: "x"),
                              revision: "\(index)", position: UInt64(index), pending: nil)
        }
        let file = StoreFile<Note>(format: StoreFile<Note>.currentFormat, schemaVersion: 1, nodeID: "x", clock: nil, token: nil,
                                   lastSyncedAt: nil, nextSequence: UInt64(total), entries: tombstones)
        let storage = InMemoryStorage()
        try storage.write(StoreFileCoder.encode(file), to: "notes.store")
        let store = try makeStore(ScriptedTransport(), storage: storage)
        #expect(await store.state.entries.count == total)
        try await store.sync()
        let entries = await store.state.entries
        #expect(entries.count == OfflineStore<Note>.maximumTombstones)
        #expect(entries["n0"] == nil)
        #expect(entries["n\(total - 1)"] != nil)
    }
}
