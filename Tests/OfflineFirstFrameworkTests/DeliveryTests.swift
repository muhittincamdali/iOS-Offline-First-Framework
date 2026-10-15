import Foundation
import Testing
@testable import OfflineFirstFramework

/// What happens when a push reaches the server but its answer does not reach the store.
@Suite("Offline store: lost answers")
struct DeliveryTests {
    let clock = TestClock()

    @Test func deleteAfterALostAnswerReachesTheServer() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = ScriptedTransport()
        let answerLost = OneShot()
        await transport.onPush { changes in
            let outcomes = try await server.push(changes)
            if await answerLost.fire() { throw URLError(.networkConnectionLost) }
            return outcomes
        }
        await transport.onPull { try await server.pull(since: $0) }
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock))
        try await store.save(Note(id: "a", text: "A"))
        await #expect(throws: URLError.self) { try await store.sync() }
        #expect(await server.record("a") != nil)

        try await store.delete("a")
        #expect(await store.pendingChanges().first?.isDelete == true)
        clock.advance(by: 120)
        try await store.sync()
        #expect(await store.records().isEmpty)
        #expect(await store.pendingChanges().isEmpty)
        #expect(await server.record("a") == nil)
    }

    @Test func deleteAfterTheAppEndedBeforeTheAnswerReachesTheServer() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let storage = InMemoryStorage()
        let neverAnswers = ScriptedTransport()
        await neverAnswers.onPush { changes in
            _ = try await server.push(changes)
            try await Task.sleep(for: .seconds(3_600))
            return [:]
        }
        let first = try OfflineStore<Note>(name: "notes", storage: storage, transport: neverAnswers,
                                           configuration: makeConfiguration(clock: clock))
        try await first.save(Note(id: "a", text: "A"))
        let hangingSync = Task { try await first.sync() }
        defer { hangingSync.cancel() }
        #expect(await eventually { await server.pushRequests == 1 })

        // The app ends here; a new process opens the same file.
        let reopened = try OfflineStore<Note>(name: "notes", storage: storage, transport: server,
                                              configuration: makeConfiguration(clock: clock))
        try await reopened.delete("a")
        #expect(await reopened.pendingChanges().first?.isDelete == true)
        try await reopened.sync()
        #expect(await reopened.records().isEmpty)
        #expect(await server.record("a") == nil)
    }

    @Test func aRecordThatWasNeverSentIsDeletedOnTheDeviceOnly() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: server,
                                           configuration: makeConfiguration(clock: clock))
        try await store.save(Note(id: "a", text: "draft"))
        try await store.delete("a")
        #expect(await store.pendingChanges().isEmpty)
        try await store.sync()
        #expect(await server.pushRequests == 0)
    }

    @Test func filesWithoutTheSentMarkStillOpen() throws {
        let json = #"{"id":"a","position":0,"record":{"id":"a","text":"A"},"timestamp":{"counter":0,"nodeID":"n","wallTime":1}}"#
        let entry = try JSONDecoder().decode(StoredEntry<Note>.self, from: Data(json.utf8))
        #expect(entry.wasSent == false)
        #expect(entry.record == Note(id: "a", text: "A"))
    }

    // MARK: - Changes in doubt

    private func store(_ name: String, _ transport: any SyncTransport<Note>, resolver: ConflictResolver<Note>) throws -> OfflineStore<Note> {
        try OfflineStore<Note>(name: name, storage: InMemoryStorage(), transport: transport,
                               configuration: makeConfiguration(clock: clock, resolver: resolver))
    }

    /// The server applied A's change but the answer was lost; B then wrote on top of it. A pull
    /// that meets A's waiting change must not resolve it again under a new change ID, or A
    /// would put its change back over B's (with `.clientWins`). The next push, under the same
    /// change ID, learns it was applied, and A takes B's version.
    @Test func aChangeWhoseAnswerWasLostIsNotPushedOverANewerWrite() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = ScriptedTransport()
        let answerLost = OneShot()
        await transport.onPush { changes in
            let outcomes = try await server.push(changes)
            if await answerLost.fire() { throw URLError(.networkConnectionLost) }
            return outcomes
        }
        await transport.onPull { try await server.pull(since: $0) }
        let deviceA = try store("a", transport, resolver: .clientWins)
        let deviceB = try store("b", server, resolver: .clientWins)
        try await deviceA.save(Note(id: "x", text: "A"))
        await #expect(throws: URLError.self) { try await deviceA.sync() }
        try await deviceB.sync()
        try await deviceB.save(Note(id: "x", text: "B, after seeing A"))
        try await deviceB.sync()

        // A pulls B's version while its own change waits for its retry date.
        try await deviceA.sync()
        #expect(await deviceA.pendingChanges().count == 1)
        clock.advance(by: 10)
        try await deviceA.sync()
        #expect(await server.record("x")?.text == "B, after seeing A")
        #expect(await deviceA.record("x")?.text == "B, after seeing A")
        #expect(await deviceA.pendingChanges().isEmpty)
    }

    /// The repeated push is answered from the server's memory with the conflict of its first
    /// push, which names the version current then; a version pulled since is newer and wins.
    @Test func aRememberedConflictAnswerDoesNotRollBackANewerVersion() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = ScriptedTransport()
        let answerLost = OneShot()
        await transport.onPush { changes in
            let outcomes = try await server.push(changes)
            if await answerLost.fire() { throw URLError(.networkConnectionLost) }
            return outcomes
        }
        await transport.onPull { try await server.pull(since: $0) }
        let store = try store("notes", transport, resolver: .serverWins)
        await server.write(Note(id: "x", text: "s1"))
        try await store.sync()
        await server.write(Note(id: "x", text: "s2"))
        try await store.save(Note(id: "x", text: "local"))
        await #expect(throws: URLError.self) { try await store.sync() }
        await server.write(Note(id: "x", text: "s3"))
        try await store.sync()
        clock.advance(by: 10)
        try await store.sync()
        #expect(await store.record("x")?.text == "s3")
        #expect(await store.pendingChanges().isEmpty)
    }

    /// A retry that never leaves the device (no connection) does not clear the doubt an earlier
    /// push with a lost answer left.
    @Test func aRetryThatNeverLeftTheDeviceKeepsTheChangeInDoubt() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let pushes = Counter()
        let transport = ScriptedTransport()
        await transport.onPush { changes in
            switch await pushes.next() {
            case 1:
                _ = try await server.push(changes)
                throw URLError(.networkConnectionLost)
            case 2:
                throw URLError(.notConnectedToInternet)
            default:
                return try await server.push(changes)
            }
        }
        await transport.onPull { try await server.pull(since: $0) }
        let deviceA = try store("a", transport, resolver: .clientWins)
        let deviceB = try store("b", server, resolver: .clientWins)
        try await deviceA.save(Note(id: "x", text: "A"))
        await #expect(throws: URLError.self) { try await deviceA.sync() }
        try await deviceB.sync()
        try await deviceB.save(Note(id: "x", text: "B, after seeing A"))
        try await deviceB.sync()

        clock.advance(by: 10)
        await #expect(throws: URLError.self) { try await deviceA.sync() }
        #expect(await deviceA.state.entries["x"]?.pending?.isInDoubt == true)
        try await deviceA.sync()
        clock.advance(by: 100)
        try await deviceA.sync()
        #expect(await server.record("x")?.text == "B, after seeing A")
        #expect(await deviceA.record("x")?.text == "B, after seeing A")
    }
}

/// Returns `true` the first time only.
actor OneShot {
    private var fired = false

    func fire() -> Bool {
        defer { fired = true }
        return !fired
    }
}
