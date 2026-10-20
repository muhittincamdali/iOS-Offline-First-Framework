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

    /// Every restart and every new instance reports a later epoch of the same length, so its
    /// text order is the order of the restarts.
    @Test func everyRestartOfTheInMemoryServerReportsALaterEpoch() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        var epochs: [String] = []
        for _ in 0..<20 {
            epochs.append(try #require(try await server.pull(since: nil).epoch))
            await server.restart()
        }
        epochs.append(try #require(try await InMemorySyncServer<Note>().pull(since: nil).epoch))
        #expect(epochs.allSatisfy { $0.utf8.count == 16 })
        #expect(zip(epochs, epochs.dropFirst()).allSatisfy { $0 < $1 })
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

    // MARK: - Epochs and server identity

    @Test func aStoreOpenedWithAnotherServerPullsFromTheStart() async throws {
        let storage = InMemoryStorage()
        let serverA = ScriptedTransport(identity: "https://a.example/sync/notes", pull: { _ in
            PullResponse(changes: [], token: "serverA-cursor-42", hasMore: false)
        })
        try await makeStore(serverA, storage: storage).sync()
        let tokens = TokenLog()
        let serverB = ScriptedTransport(identity: "https://b.example/sync/notes", pull: { token in
            await tokens.add(token)
            return PullResponse(changes: [], token: "b1", hasMore: false)
        })
        try await makeStore(serverB, storage: storage).sync()
        try await makeStore(serverB, storage: storage).sync()
        #expect(await tokens.all == [nil, "b1"])
    }

    @Test func aNewEpochStartsThePullAgainAndKeepsPendingChanges() async throws {
        let a = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "A"), revision: "e1.1", timestamp: nil)
        let b = RemoteChange<Note>(recordID: "b", record: Note(id: "b", text: "B"), revision: "e1.2", timestamp: nil)
        let transport = ScriptedTransport(push: { _ in throw URLError(.notConnectedToInternet) }, pull: { token in
            token == nil ? PullResponse(changes: [a, b], token: "e1.2", hasMore: false, epoch: "e1")
                : PullResponse(changes: [], token: token, hasMore: false, epoch: "e1")
        })
        let store = try makeStore(transport)
        try await store.sync()
        try await store.save(Note(id: "draft", text: "written offline"))
        await #expect(throws: URLError.self) { try await store.sync() }

        // The server restarted from a backup: it kept "a", lost "b" and got "c" since.
        let c = RemoteChange<Note>(recordID: "c", record: Note(id: "c", text: "C"), revision: "e2.3", timestamp: nil)
        let tokens = TokenLog()
        await transport.onPull { token in
            await tokens.add(token)
            return PullResponse(changes: [a, c], token: "e2.3", hasMore: false, epoch: "e2")
        }
        let report = try await store.sync()
        #expect(await tokens.all == ["e1.2", nil])
        #expect(report.pulled == 1)
        #expect(await store.state.token == "e2.3")
        #expect(await store.state.serverEpoch == "e2")
        #expect(await store.record("c") == Note(id: "c", text: "C"))
        #expect(await store.pendingChanges().map(\.recordID) == ["draft"])

        await transport.onPush { changes in Dictionary(uniqueKeysWithValues: changes.map { ($0.id, .accepted(revision: "e2.4")) }) }
        clock.advance(by: 60)
        #expect(try await store.sync().pushed == 1)
    }

    @Test func anEpochThatChangesTwiceInOneSyncFailsTheSync() async throws {
        let pulls = Counter()
        let transport = ScriptedTransport(pull: { _ in
            let number = await pulls.next()
            return PullResponse(changes: [], token: "t\(number)", hasMore: false, epoch: "e\(number)")
        })
        let store = try makeStore(transport)
        try await store.sync()
        await #expect(throws: OfflineFirstError.invalidServerResponse(
            "Two pulls of one sync named the server epochs “e2” and “e3”, as a cache or another deployment that answers some requests would.")) {
            try await store.sync()
        }
        #expect(await transport.pulls == 3)
        #expect(await store.state.serverEpoch == "e1")
    }

    @Test func theFirstEpochAServerReportsKeepsTheToken() async throws {
        let transport = ScriptedTransport(pull: { token in
            token == nil ? PullResponse(changes: [], token: "t1", hasMore: false)
                : PullResponse(changes: [], token: "t2", hasMore: false, epoch: "e1")
        })
        let store = try makeStore(transport)
        try await store.sync()
        try await store.sync()
        #expect(await transport.pulls == 2)
        #expect(await store.state.token == "t2")
        #expect(await store.state.serverEpoch == "e1")
    }

    /// After a restore from a backup the server's copy is older than the one the store holds;
    /// it is the server's current version, so it replaces the store's, without a conflict.
    @Test func aVersionFromAnEarlierHistoryIsReplacedWhateverItsTimestamp() async throws {
        let newer = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "lost by the server"), revision: "e1.7",
                                       timestamp: HLCTimestamp(wallTime: 5_000, nodeID: "laptop"))
        let restored = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "restored"), revision: "e1.3",
                                          timestamp: HLCTimestamp(wallTime: 3_000, nodeID: "laptop"))
        let transport = ScriptedTransport(pull: { _ in PullResponse(changes: [newer], token: "e1.7", hasMore: false, epoch: "e1") })
        let store = try makeStore(transport)
        try await store.sync()
        await transport.onPull { _ in PullResponse(changes: [restored], token: "e2.3", hasMore: false, epoch: "e2") }
        let report = try await store.sync()
        #expect(report.conflicts == 0)
        #expect(await store.record("a")?.text == "restored")
        #expect(await store.pendingChanges().isEmpty)
    }
}

private actor TokenLog {
    private(set) var all: [String?] = []

    func add(_ token: String?) {
        all.append(token)
    }
}
