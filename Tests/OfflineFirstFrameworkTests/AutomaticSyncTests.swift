import Foundation
import Testing
@testable import OfflineFirstFramework

/// Polls `condition` until it holds or two seconds pass.
func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<200 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return await condition()
}

@Suite("Automatic sync")
struct AutomaticSyncTests {
    let clock = TestClock()

    private func makeStore(_ server: InMemorySyncServer<Note>) throws -> OfflineStore<Note> {
        try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: server, configuration: makeConfiguration(clock: clock))
    }

    @Test func simulatedConnectivityReportsChanges() async {
        let connectivity = SimulatedConnectivity(isOnline: false)
        var updates = connectivity.updates().makeAsyncIterator()
        #expect(await updates.next() == false)
        connectivity.setOnline(true)
        connectivity.setOnline(true)
        #expect(await updates.next() == true)
        connectivity.setOnline(false)
        #expect(await updates.next() == false)
        #expect(!connectivity.isOnline)
    }

    @Test func syncsWhenTheDeviceComesOnline() async throws {
        let server = InMemorySyncServer<Note>()
        let store = try makeStore(server)
        let connectivity = SimulatedConnectivity(isOnline: false)
        try await store.save(Note(id: "a", text: "Written offline"))
        await store.startAutomaticSync(monitor: connectivity, interval: nil, debounce: .milliseconds(20))
        #expect(await eventually { await store.status == .offline })
        #expect(await server.pushRequests == 0)

        connectivity.setOnline(true)
        #expect(await eventually { await server.record("a") != nil })
        #expect(await eventually { await store.pendingChanges().isEmpty })
        await store.stopAutomaticSync()
    }

    @Test func pushesLocalChangesAfterTheDebounce() async throws {
        let server = InMemorySyncServer<Note>()
        let store = try makeStore(server)
        let connectivity = SimulatedConnectivity(isOnline: true)
        await store.startAutomaticSync(monitor: connectivity, interval: nil, debounce: .milliseconds(300))
        #expect(await eventually { await server.pullRequests == 1 })

        for index in 0..<5 {
            try await store.save(Note(id: "n\(index)", text: "Edit \(index)"))
        }
        #expect(await eventually { await server.records().count == 5 })
        // The burst of five saves went out together.
        #expect(await server.pushRequests == 1)
        await store.stopAutomaticSync()
        #expect(await !store.isAutomaticSyncEnabled)
    }

    @Test func stoppedAutomaticSyncDoesNothing() async throws {
        let server = InMemorySyncServer<Note>()
        let store = try makeStore(server)
        let connectivity = SimulatedConnectivity(isOnline: false)
        await store.startAutomaticSync(monitor: connectivity, interval: nil, debounce: .zero)
        await store.stopAutomaticSync()
        connectivity.setOnline(true)
        try await store.save(Note(id: "a", text: "A"))
        try await Task.sleep(for: .milliseconds(100))
        #expect(await server.pushRequests == 0)
        #expect(await server.pullRequests == 0)
    }

    @Test func periodicSyncPullsRemoteChanges() async throws {
        let server = InMemorySyncServer<Note>()
        let store = try makeStore(server)
        await store.startAutomaticSync(monitor: SimulatedConnectivity(isOnline: true), interval: .seconds(1), debounce: .zero)
        #expect(await eventually { await server.pullRequests >= 1 })
        await server.write(Note(id: "remote", text: "From another device"))
        // The interval is at least one second; wait for the second run.
        var found = false
        for _ in 0..<30 where !found {
            try await Task.sleep(for: .milliseconds(100))
            found = await store.record("remote") != nil
        }
        #expect(found)
        await store.stopAutomaticSync()
    }

    @Test func aRetryDateFarInTheFutureFromADamagedFileDoesNotStopTheApp() async throws {
        let storage = InMemoryStorage()
        let failing = ScriptedTransport(push: { _ in [:] })
        let first = try OfflineStore<Note>(name: "notes", storage: storage, transport: failing, configuration: makeConfiguration(clock: clock))
        try await first.save(Note(id: "a", text: "A"))
        _ = try? await first.sync()
        let file = String(decoding: try #require(try storage.read("notes.store")), as: UTF8.self)
        let damaged = file.replacing(/"nextAttemptAt":[-0-9.eE+]+/, with: #""nextAttemptAt":1e300"#)
        #expect(damaged != file)
        try storage.write(Data(damaged.utf8), to: "notes.store")

        let server = InMemorySyncServer<Note>()
        let store = try OfflineStore<Note>(name: "notes", storage: storage, transport: server, configuration: makeConfiguration(clock: clock))
        await store.startAutomaticSync(monitor: SimulatedConnectivity(isOnline: true), interval: .seconds(300), debounce: .zero)
        #expect(await eventually { await server.pullRequests == 1 })
        // The next run is scheduled after the sync; computing its wait used to trap. No wait of
        // the retry policy is that long, so the change counts as due and goes out.
        try await Task.sleep(for: .milliseconds(100))
        #expect(await store.isAutomaticSyncEnabled)
        #expect(await server.record("a")?.text == "A")
        #expect(await store.pendingChanges().isEmpty)
        await store.stopAutomaticSync()
    }
}
