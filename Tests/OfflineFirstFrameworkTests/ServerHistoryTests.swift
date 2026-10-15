import Foundation
import Testing
@testable import OfflineFirstFramework

/// A server that restarts, loses its data or is replaced must not make the store lose a write
/// the server accepted, or keep an old version for good.
@Suite("Offline store: server history")
struct ServerHistoryTests {
    let clock = TestClock()

    private func makeStore(_ transport: any SyncTransport<Note>, storage: any StorageBackend = InMemoryStorage(),
                           name: String = "notes",
                           configure: (inout OfflineStore<Note>.Configuration) -> Void = { _ in }) throws -> OfflineStore<Note> {
        var configuration = makeConfiguration(clock: clock)
        configure(&configuration)
        return try OfflineStore<Note>(name: name, storage: storage, transport: transport, configuration: configuration)
    }

    @Test func aServerNeverHandsOutTheSameRevisionTwice() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let first = await server.write(Note(id: "a", text: "1"))
        await server.restart()
        let afterRestart = await server.write(Note(id: "a", text: "2"))
        let otherInstance = await InMemorySyncServer<Note>(now: { [clock] in clock.now }).write(Note(id: "a", text: "3"))
        #expect(Set([first, afterRestart, otherInstance]).count == 3)
    }

    /// A restarted server (new instance, data lost) counts from one again. Device A still holds
    /// the record's revision from before; its older offline edit must not replace B's newer
    /// write, which the new server accepted.
    @Test func anOfflineEditBasedOnARevisionFromBeforeARestartDoesNotReplaceANewerWrite() async throws {
        let storageA = InMemoryStorage()
        let before = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let deviceA = try makeStore(before, storage: storageA)
        try await deviceA.save(Note(id: "a", text: "A v1"))
        try await deviceA.sync()
        try await deviceA.save(Note(id: "a", text: "A older offline edit"))
        clock.advance(by: 10)

        let restarted = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let deviceB = try makeStore(restarted, name: "b")
        try await deviceB.save(Note(id: "a", text: "B newer write"))
        #expect(try await deviceB.sync().pushed == 1)

        let reopenedA = try makeStore(restarted, storage: storageA)
        let report = try await reopenedA.sync()
        #expect(report.conflicts == 1)
        #expect(await restarted.record("a")?.text == "B newer write")
        #expect(await reopenedA.record("a")?.text == "B newer write")
        #expect(await reopenedA.pendingChanges().isEmpty)
    }

    /// After the restart the record's new revision must not look like the echo of the old one.
    @Test func aRecordWrittenAgainAfterARestartIsPulled() async throws {
        let storage = InMemoryStorage()
        let before = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        await before.write(Note(id: "a", text: "old epoch"))
        try await makeStore(before, storage: storage).sync()

        clock.advance(by: 10)
        let restarted = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        await restarted.write(Note(id: "a", text: "new epoch"))
        let store = try makeStore(restarted, storage: storage)
        try await store.sync()
        #expect(await store.record("a")?.text == "new epoch")
        try await store.sync()
        #expect(await store.record("a")?.text == "new epoch")
    }

    /// The same with `.serverWins`: the newer server copy is pulled, and a local edit made on the
    /// old copy meets it as a conflict instead of replacing it.
    @Test func aLocalEditOnACopyFromBeforeARestartMeetsTheNewerServerCopy() async throws {
        let storage = InMemoryStorage()
        let before = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        await before.write(Note(id: "a", text: "v1"))
        try await makeStore(before, storage: storage) { $0.conflictResolver = .serverWins }.sync()

        let restarted = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        clock.advance(by: 10)
        await restarted.write(Note(id: "a", text: "newer server edit"))
        let store = try makeStore(restarted, storage: storage) { $0.conflictResolver = .serverWins }
        try await store.save(Note(id: "a", text: "local"))
        let report = try await store.sync()
        #expect(report.conflicts == 1)
        #expect(await restarted.record("a")?.text == "newer server edit")
        #expect(await store.record("a")?.text == "newer server edit")
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test func aRestartKeepsRecordsAndStartsTheNextPullFromTheBeginning() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try makeStore(server)
        try await store.save(Note(id: "a", text: "A"))
        try await store.sync()
        let revision = try #require(await server.revision(of: "a"))

        await server.restart()
        #expect(await server.revision(of: "a") == revision)
        #expect(try await server.pull(since: await store.state.token).changes.map(\.recordID) == ["a"])
        let report = try await store.sync()
        #expect(report.pulled == 0)
        #expect(await store.records() == [Note(id: "a", text: "A")])

        try await store.save(Note(id: "a", text: "after the restart"))
        #expect(try await store.sync().pushed == 1)
        #expect(await server.record("a")?.text == "after the restart")
    }
}
