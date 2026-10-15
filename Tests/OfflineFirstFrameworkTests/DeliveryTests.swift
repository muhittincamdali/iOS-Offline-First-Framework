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
}

/// Returns `true` the first time only.
actor OneShot {
    private var fired = false

    func fire() -> Bool {
        defer { fired = true }
        return !fired
    }
}
