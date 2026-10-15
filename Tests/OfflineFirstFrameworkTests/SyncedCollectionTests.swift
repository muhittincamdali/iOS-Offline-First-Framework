import Foundation
import Testing
@testable import OfflineFirstFramework

@MainActor
@Suite("Synced collection")
struct SyncedCollectionTests {
    let clock = TestClock()

    @Test func followsTheStoreAndItsSyncs() async throws {
        let server = InMemorySyncServer<Note>()
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: server,
                                           configuration: makeConfiguration(clock: clock))
        let collection = SyncedCollection(store: store)
        #expect(await eventually { @MainActor in collection.isLoaded })

        await collection.save(Note(id: "a", text: "From the view"))
        #expect(await eventually { @MainActor in collection.records == [Note(id: "a", text: "From the view")] })
        #expect(collection.pendingCount == 1)

        try await store.save(Note(id: "b", text: "From the store"))
        #expect(await eventually { @MainActor in collection.records.count == 2 })

        await collection.sync()
        #expect(await eventually { @MainActor in collection.pendingCount == 0 && collection.lastSyncedAt != nil })
        #expect(collection.status == .idle)
        #expect(collection.lastError == nil)

        await collection.delete("a")
        #expect(await eventually { @MainActor in collection.records.map(\.id) == ["b"] })
    }

    @Test func keepsErrorsForTheView() async throws {
        let server = InMemorySyncServer<Note>()
        var configuration = makeConfiguration(clock: clock)
        configuration.maximumPendingChanges = 1
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: server, configuration: configuration)
        let collection = SyncedCollection(store: store)
        await collection.save(Note(id: "a", text: "A"))
        await collection.save(Note(id: "b", text: "B"))
        #expect(collection.lastError == OfflineFirstError.outboxFull(limit: 1).errorDescription)

        await server.setOnline(false)
        await collection.sync()
        #expect(collection.lastError != nil)
        #expect(await eventually { @MainActor in collection.status == .offline })

        await server.setOnline(true)
        await collection.sync()
        #expect(collection.lastError == nil)
    }
}
