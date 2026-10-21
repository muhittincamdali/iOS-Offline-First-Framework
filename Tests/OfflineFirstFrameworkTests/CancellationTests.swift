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
        // One sync: its pull, and the second request that checks the server's first epoch.
        #expect(await server.pullRequests == 2)
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
        // The pull, and the second request that checks that the server reports no epoch.
        #expect(await transport.pulls == 2)
        #expect(await transport.pushed.count == 1)
        #expect(await store.pendingChanges().isEmpty)
        #expect(await store.status == .idle)
    }

    private func storeWithDeadline(_ transport: ScriptedTransport) throws -> OfflineStore<Note> {
        var configuration = makeConfiguration(clock: clock)
        configuration.syncTimeout = .seconds(1)
        return try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport, configuration: configuration)
    }

    /// A server that never answers ends each sync at the deadline instead of keeping every
    /// caller, and automatic sync, waiting.
    @Test func aPullThatNeverAnswersEndsAtTheDeadline() async throws {
        let transport = ScriptedTransport(pull: { _ in
            try await Task.sleep(for: .seconds(3_600))
            return PullResponse(changes: [], token: nil, hasMore: false)
        })
        let store = try storeWithDeadline(transport)
        let start = ContinuousClock.now
        await #expect(throws: URLError(.timedOut)) { try await store.sync() }
        #expect(ContinuousClock.now - start < .seconds(30))
        #expect(await store.status == .offline)
        await #expect(throws: URLError(.timedOut)) { try await store.sync() }
        #expect(await transport.pulls == 2)
    }

    @Test func aPushThatNeverAnswersCountsAFailedAttempt() async throws {
        let transport = ScriptedTransport(push: { _ in
            try await Task.sleep(for: .seconds(3_600))
            return [:]
        })
        let store = try storeWithDeadline(transport)
        try await store.save(Note(id: "a", text: "A"))
        await #expect(throws: URLError(.timedOut)) { try await store.sync() }
        let pending = try #require(await store.pendingChanges().first)
        #expect(pending.attempts == 1)
        #expect(pending.nextAttemptAt == clock.now.addingTimeInterval(10))
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
