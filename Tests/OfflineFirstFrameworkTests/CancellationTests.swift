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

    @Test func aCallAfterEveryCallerWasCancelledStartsANewSync() async throws {
        let gate = Gate()
        let transport = ScriptedTransport(push: { changes in
            // Answers only when the test opens the gate, even after the sync was cancelled.
            await gate.wait()
            return Dictionary(uniqueKeysWithValues: changes.map { ($0.id, .accepted(revision: "1")) })
        })
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock))
        try await store.save(Note(id: "a", text: "A"))
        let first = Task { try await store.sync() }
        #expect(await eventually { await transport.pushed.count == 1 })
        first.cancel()
        // The cancelled sync is still waiting for its push when the second call arrives.
        let second = Task { try await store.sync() }
        try await Task.sleep(for: .milliseconds(50))
        await gate.open()

        await #expect(throws: CancellationError.self) { try await first.value }
        let report = try await second.value
        #expect(report.skipped == false)
        #expect(await transport.pulls == 1)
        #expect(await transport.pushed.count == 1)
        #expect(await store.pendingChanges().isEmpty)
        #expect(await store.status == .idle)
    }
}

/// Suspends callers until ``open()``, whether or not their task was cancelled.
private actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}
