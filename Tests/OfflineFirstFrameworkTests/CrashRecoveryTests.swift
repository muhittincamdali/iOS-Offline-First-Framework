import Foundation
import Testing
@testable import OfflineFirstFramework

/// Crashes between sending and storing, answers delivered twice, edits during a pull and
/// concurrent syncs: the scenarios of the 2.0.0 audit that already held, kept as regression
/// tests for the guarantees the documentation states.
@Suite("Offline store: crashes and repeated deliveries")
struct CrashRecoveryTests {
    let clock = TestClock()

    private func makeStore(_ transport: any SyncTransport<Note>, storage: any StorageBackend = InMemoryStorage()) throws -> OfflineStore<Note> {
        try OfflineStore<Note>(name: "notes", storage: storage, transport: transport, configuration: makeConfiguration(clock: clock))
    }

    private func forwarding(to server: InMemorySyncServer<Note>) async -> ScriptedTransport {
        let transport = ScriptedTransport()
        await transport.onPush { try await server.push($0) }
        await transport.onPull { try await server.pull(since: $0) }
        return transport
    }

    /// The sequences of the server's writes, one per write it applied.
    private func appliedWrites(on server: InMemorySyncServer<Note>) async throws -> [UInt64] {
        try await server.pull(since: nil).changes.compactMap(\.sequence).sorted()
    }

    @Test func aCrashBetweenSendAndAnswerReplaysTheSameChangeOnce() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let storage = InMemoryStorage()
        let diskAtCrash = InMemoryStorage()
        let first = ScriptedTransport()
        await first.onPush { changes in
            _ = try await server.push(changes)
            // The process dies here: the server applied the push, the answer is never stored.
            if let data = try storage.read("notes.store") { try diskAtCrash.write(data, to: "notes.store") }
            throw URLError(.networkConnectionLost)
        }
        let store = try makeStore(first, storage: storage)
        try await store.save(Note(id: "a", text: "A"))
        _ = try? await store.sync()
        let sentID = try #require(await first.pushed.first?.first?.id)

        let second = await forwarding(to: server)
        let restarted = try makeStore(second, storage: diskAtCrash)
        #expect(await restarted.pendingChanges().map(\.id) == [sentID])
        try await restarted.sync()
        #expect(await second.pushed.first?.first?.id == sentID)
        #expect(try await appliedWrites(on: server) == [1])
        #expect(await restarted.pendingChanges().isEmpty)
        #expect(await restarted.record("a") == Note(id: "a", text: "A"))
    }

    @Test func aCrashWhileStoringPageTwoKeepsPageOneAndResumes() async throws {
        let server = InMemorySyncServer<Note>(pageSize: 1, now: { [clock] in clock.now })
        let storage = FailingStorage()
        let transport = ScriptedTransport()
        let pulls = Counter()
        await transport.onPull { token in
            // The first sync checks the empty server's epoch with two requests; page one is the
            // third pull, page two the fourth.
            if await pulls.next() == 4 { storage.setFailing(true) }
            return try await server.pull(since: token)
        }
        let store = try makeStore(transport, storage: storage)
        try await store.sync()
        for id in ["a", "b", "c"] { await server.write(Note(id: id, text: id)) }
        await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        let reopened = try makeStore(server, storage: storage.inner)
        #expect(await reopened.records().map(\.id) == ["a"])
        #expect(await reopened.state.token != nil)
        #expect(try await reopened.sync().pulled == 2)
        #expect(await reopened.records().map(\.id) == ["a", "b", "c"])
    }

    @Test func aCrashWhileStoringPushAnswersReplaysOnce() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let storage = FailingStorage()
        let transport = ScriptedTransport()
        await transport.onPush { changes in
            let outcomes = try await server.push(changes)
            storage.setFailing(true)
            return outcomes
        }
        let store = try makeStore(transport, storage: storage)
        try await store.save(Note(id: "a", text: "A"))
        await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        let reopened = try makeStore(server, storage: storage.inner)
        #expect(await reopened.pendingChanges().count == 1)
        try await reopened.sync()
        #expect(try await appliedWrites(on: server) == [1])
        #expect(await reopened.pendingChanges().isEmpty)
    }

    @Test func aPushDeliveredTwiceIsAppliedOnce() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = ScriptedTransport()
        await transport.onPush { changes in
            _ = try await server.push(changes)
            return try await server.push(changes)
        }
        await transport.onPull { try await server.pull(since: $0) }
        let store = try makeStore(transport)
        try await store.save(contentsOf: [Note(id: "a", text: "A"), Note(id: "b", text: "B")])
        try await store.sync()
        #expect(try await appliedWrites(on: server) == [1, 2])
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test func aDeleteMadeWhileAPullRunsIsNotUndoneByAnOlderServerEdit() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = await forwarding(to: server)
        let store = try makeStore(transport)
        try await store.save(Note(id: "a", text: "v1"))
        try await store.sync()
        await server.write(Note(id: "a", text: "older server edit"))
        clock.advance(by: 10)
        let once = OneShot()
        await transport.onPull { token in
            if await once.fire() { try await store.delete("a") }
            return try await server.pull(since: token)
        }
        try await store.sync()
        #expect(await store.record("a") == nil)
        try await store.sync()
        #expect(await server.record("a") == nil)
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test(arguments: [true, false])
    func aLocalUpdateThatMeetsAServerDeleteFollowsLastWriteWins(updateIsNewer: Bool) async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try makeStore(server)
        try await store.save(Note(id: "a", text: "v1"))
        try await store.sync()
        if updateIsNewer {
            await server.delete("a")
            clock.advance(by: 10)
            try await store.save(Note(id: "a", text: "local edit"))
        } else {
            try await store.save(Note(id: "a", text: "local edit"))
            clock.advance(by: 10)
            await server.delete("a")
        }
        try await store.sync()
        try await store.sync()
        let expected: Note? = updateIsNewer ? Note(id: "a", text: "local edit") : nil
        #expect(await store.record("a") == expected)
        #expect(await server.record("a") == expected)
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test func concurrentSyncCallsNeverOverlap() async throws {
        let server = InMemorySyncServer<Note>(latency: .milliseconds(20), now: { [clock] in clock.now })
        let probe = ConcurrencyProbe()
        let transport = ScriptedTransport()
        await transport.onPush { changes in try await probe.measure { try await server.push(changes) } }
        await transport.onPull { token in try await probe.measure { try await server.pull(since: token) } }
        let store = try makeStore(transport)
        try await store.save(contentsOf: (0..<5).map { Note(id: "n\($0)", text: "\($0)") })
        try await withThrowingTaskGroup(of: SyncReport.self) { group in
            for _ in 0..<8 { group.addTask { try await store.sync() } }
            for try await _ in group {}
        }
        #expect(await probe.maximum == 1)
        #expect(await server.pushRequests == 1)
        #expect(await store.pendingChanges().isEmpty)
        #expect(await server.records().count == 5)
    }
}

/// Measures how many requests run at the same time.
private actor ConcurrencyProbe {
    private var current = 0
    private(set) var maximum = 0

    func enter() {
        current += 1
        maximum = max(maximum, current)
    }

    func leave() {
        current -= 1
    }

    nonisolated func measure<T: Sendable>(_ body: @Sendable () async throws -> T) async throws -> T {
        await enter()
        do {
            let value = try await body()
            await leave()
            return value
        } catch {
            await leave()
            throw error
        }
    }
}
