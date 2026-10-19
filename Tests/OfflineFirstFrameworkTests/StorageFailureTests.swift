import Foundation
import Testing
@testable import OfflineFirstFramework

/// The store file cannot be written (a full disk, file protection, another instance) while a
/// change is in doubt. Marking the change as sent writes nothing, so the push leaves, and the
/// answer cannot be stored: without a wait of its own, every sync would send it again.
@Suite("Offline store: a file that cannot be written")
struct StorageFailureTests {
    let clock = TestClock()

    /// A store with a change in doubt: its first push was applied, the answer was lost.
    private func storeWithAChangeInDoubt(_ server: InMemorySyncServer<Note>, storage: FailingStorage) async throws -> OfflineStore<Note> {
        let transport = ScriptedTransport()
        let answerLost = OneShot()
        await transport.onPush { changes in
            let outcomes = try await server.push(changes)
            if await answerLost.fire() { throw URLError(.networkConnectionLost) }
            return outcomes
        }
        await transport.onPull { try await server.pull(since: $0) }
        let store = try OfflineStore<Note>(name: "notes", storage: storage, transport: transport, configuration: makeConfiguration(clock: clock))
        try await store.save(Note(id: "a", text: "A"))
        await #expect(throws: URLError.self) { try await store.sync() }
        clock.advance(by: 20)
        return store
    }

    @Test func syncsWaitWithBackoffWhileTheFileCannotBeWritten() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let storage = FailingStorage()
        let store = try await storeWithAChangeInDoubt(server, storage: storage)
        storage.setFailing(true)
        let before = await server.pushRequests
        for _ in 0..<10 {
            await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        }
        #expect(await server.pushRequests - before == 1)
        #expect(await server.pullRequests == 0)

        // The wait grows: 10 seconds after the first failure, 20 after the second.
        clock.advance(by: 11)
        _ = try? await store.sync()
        clock.advance(by: 11)
        _ = try? await store.sync()
        #expect(await server.pushRequests - before == 2)

        // A write that succeeds ends the wait.
        storage.setFailing(false)
        try await store.save(Note(id: "b", text: "B"))
        try await store.sync()
        #expect(await store.pendingChanges().isEmpty)
        #expect(await server.record("a")?.text == "A")
        #expect(await server.record("b")?.text == "B")
    }

    @Test func automaticSyncWaitsWhileTheFileCannotBeWritten() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let storage = FailingStorage()
        let store = try await storeWithAChangeInDoubt(server, storage: storage)
        storage.setFailing(true)
        let before = await server.pushRequests
        await store.startAutomaticSync(monitor: SimulatedConnectivity(isOnline: true), interval: .seconds(300), debounce: .seconds(2))
        try await Task.sleep(for: .seconds(3))
        await store.stopAutomaticSync()
        #expect(await server.pushRequests - before == 1)
    }
}
