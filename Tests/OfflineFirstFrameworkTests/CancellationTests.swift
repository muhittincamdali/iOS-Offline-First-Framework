import Foundation
import Testing
@testable import OfflineFirstFramework

@Suite("Offline store: cancellation")
struct CancellationTests {
    let clock = TestClock()

    private func makeStore(_ server: InMemorySyncServer<Note>) throws -> OfflineStore<Note> {
        try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: server, configuration: makeConfiguration(clock: clock))
    }

    @Test func cancellingTheOnlyCallerStopsTheSync() async throws {
        let server = InMemorySyncServer<Note>(latency: .milliseconds(200), now: { [clock] in clock.now })
        let store = try makeStore(server)
        try await store.save(Note(id: "a", text: "A"))
        let caller = Task { try await store.sync() }
        #expect(await eventually { await server.pushRequests == 1 })
        caller.cancel()
        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(await server.pullRequests == 0)
        #expect(await store.pendingChanges().count == 1)
        #expect(await store.status == .idle)
    }

    @Test func cancellingOneCallerKeepsTheSyncForTheOthers() async throws {
        let server = InMemorySyncServer<Note>(latency: .milliseconds(200), now: { [clock] in clock.now })
        let store = try makeStore(server)
        try await store.save(Note(id: "a", text: "A"))
        let first = Task { try await store.sync() }
        #expect(await eventually { await server.pushRequests == 1 })
        let second = Task { try await store.sync() }
        // Give the second call time to join the running sync.
        try await Task.sleep(for: .milliseconds(50))
        first.cancel()

        let report = try await second.value
        #expect(report.pushed == 1)
        #expect(try await first.value == report)
        #expect(await server.pullRequests == 1)
        #expect(await server.record("a") == Note(id: "a", text: "A"))
        #expect(await store.pendingChanges().isEmpty)
    }
}
