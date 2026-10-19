import Foundation
import Testing
@testable import OfflineFirstFramework

/// A store file restored from a backup onto a second device, or moved with a migration while
/// the first device stays in use: both stores then stamp their writes with the same node ID.
/// The other device's writes must still count as another device's, both when the store orders
/// versions and when it decides whether a version is a conflict.
@Suite("Offline store: a store file copied to another device")
struct CopiedStoreTests {
    let clock = TestClock()

    private func makeStore(_ transport: any SyncTransport<Note>, storage: InMemoryStorage,
                           resolver: ConflictResolver<Note>) throws -> OfflineStore<Note> {
        try OfflineStore<Note>(name: "notes", storage: storage, transport: transport,
                               configuration: makeConfiguration(clock: clock, resolver: resolver))
    }

    /// The first device's store, synced once with `server`, and a copy of its file.
    private func storeAndCopy(_ server: InMemorySyncServer<Note>, transport: any SyncTransport<Note>,
                              resolver: ConflictResolver<Note>) async throws -> (OfflineStore<Note>, InMemoryStorage) {
        let storage = InMemoryStorage()
        let store = try makeStore(transport, storage: storage, resolver: resolver)
        try await store.save(Note(id: "a", text: "v1"))
        try await store.sync()
        let copy = InMemoryStorage()
        try copy.write(try #require(try storage.read("notes.store")), to: "notes.store")
        return (store, copy)
    }

    /// The copy keeps its older edit through client wins; the first device, which still waits
    /// for the echo of its own accepted edit, must take the copy's version as the newer one.
    @Test func theCopysWriteIsNotTakenForAnEarlierOwnWrite() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = ScriptedTransport()
        await transport.onPush { try await server.push($0) }
        await transport.onPull { try await server.pull(since: $0) }
        let (first, storage) = try await storeAndCopy(server, transport: transport, resolver: .clientWins)
        let copy = try makeStore(server, storage: storage, resolver: .clientWins)
        #expect(copy.nodeID == first.nodeID)

        clock.advance(by: 5)
        try await copy.save(Note(id: "a", text: "copy's edit"))
        clock.advance(by: 5)
        try await first.save(Note(id: "a", text: "first device's edit"))
        let token = await first.state.token
        let noEcho = OneShot()
        await transport.onPull { since in
            if await noEcho.fire() { return PullResponse(changes: [], token: token, hasMore: false) }
            return try await server.pull(since: since)
        }
        try await first.sync()
        try await copy.sync()
        #expect(await server.record("a")?.text == "copy's edit")

        try await first.sync()
        #expect(await first.record("a")?.text == "copy's edit")
    }

    /// With server wins, an edit on the first device that meets the copy's newer write on the
    /// server is a conflict, and the server's version stays.
    @Test func theCopysWriteIsAConflictForTheFirstDevice() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let (first, storage) = try await storeAndCopy(server, transport: server, resolver: .serverWins)
        let copy = try makeStore(server, storage: storage, resolver: .serverWins)

        clock.advance(by: 5)
        try await copy.save(Note(id: "a", text: "copy's edit"))
        try await copy.sync()
        clock.advance(by: 5)
        try await first.save(Note(id: "a", text: "first device's edit"))
        let report = try await first.sync()
        #expect(report.conflicts == 1)
        #expect(await server.record("a")?.text == "copy's edit")
        #expect(await first.record("a")?.text == "copy's edit")
    }
}
