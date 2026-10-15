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
}
