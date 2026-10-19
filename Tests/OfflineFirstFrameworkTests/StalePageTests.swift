import Foundation
import Testing
@testable import OfflineFirstFramework

/// A pull answered by a replica that lags behind, right after the server accepted the store's
/// own write. The answer to a push carries only the revision, so until the write's echo
/// arrives the store has to know from elsewhere that an older page is older.
@Suite("Offline store: stale pages after the store's own write")
struct StalePageTests {
    let clock = TestClock()

    private func makeStore(_ transport: any SyncTransport<Note>, storage: any StorageBackend = InMemoryStorage(),
                           resolver: ConflictResolver<Note> = .lastWriteWins) throws -> OfflineStore<Note> {
        try OfflineStore<Note>(name: "notes", storage: storage, transport: transport,
                               configuration: makeConfiguration(clock: clock, resolver: resolver))
    }

    private func forwarding(to server: InMemorySyncServer<Note>) async -> ScriptedTransport {
        let transport = ScriptedTransport()
        await transport.onPush { try await server.push($0) }
        await transport.onPull { try await server.pull(since: $0) }
        return transport
    }

    /// The next pull gets `page`, every later one the server's answer.
    private func answerNextPull(of transport: ScriptedTransport, with page: PullResponse<Note>,
                                from server: InMemorySyncServer<Note>) async {
        let stale = OneShot()
        await transport.onPull { token in
            if await stale.fire() { return page }
            return try await server.pull(since: token)
        }
    }

    @Test(arguments: ConvergenceTests.Policy.allCases)
    func anAcceptedWriteIsNotRolledBackByAStalePage(policy: ConvergenceTests.Policy) async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = await forwarding(to: server)
        let store = try makeStore(transport, resolver: policy.resolver)
        try await store.save(Note(id: "a", text: "milk"))
        try await store.sync()
        let beforeEdit = try await server.pull(since: nil)

        clock.advance(by: 10)
        try await store.save(Note(id: "a", text: "milk, eggs"))
        await answerNextPull(of: transport, with: beforeEdit, from: server)
        #expect(try await store.sync().pushed == 1)
        #expect(await server.record("a")?.text == "milk, eggs")
        #expect(await store.record("a")?.text == "milk, eggs", "\(policy)")
        try await store.sync()
        #expect(await store.record("a")?.text == "milk, eggs", "\(policy)")
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test(arguments: ConvergenceTests.Policy.allCases)
    func anAcceptedDeleteIsNotUndoneByAStalePage(policy: ConvergenceTests.Policy) async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = await forwarding(to: server)
        let store = try makeStore(transport, resolver: policy.resolver)
        try await store.save(Note(id: "a", text: "A"))
        try await store.sync()
        let beforeDelete = try await server.pull(since: nil)

        clock.advance(by: 10)
        try await store.delete("a")
        await answerNextPull(of: transport, with: beforeDelete, from: server)
        try await store.sync()
        #expect(await server.record("a") == nil)
        #expect(await store.record("a") == nil, "\(policy)")
        try await store.sync()
        #expect(await store.record("a") == nil, "\(policy)")
    }

    /// The user edits what the store shows after the stale page. Had the page rolled the record
    /// back, the edit would replace the acknowledged "eggs" on the server.
    @Test func anEditAfterAStalePageKeepsTheAcknowledgedWrite() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = await forwarding(to: server)
        let store = try makeStore(transport)
        try await store.save(Note(id: "a", text: "milk"))
        try await store.sync()
        let beforeEdit = try await server.pull(since: nil)
        clock.advance(by: 10)
        try await store.save(Note(id: "a", text: "milk, eggs"))
        await answerNextPull(of: transport, with: beforeEdit, from: server)
        try await store.sync()

        clock.advance(by: 10)
        let shown = try #require(await store.record("a"))
        try await store.save(Note(id: "a", text: shown.text + " today"))
        try await store.sync()
        try await store.sync()
        #expect(await server.record("a")?.text == "milk, eggs today")
    }

    /// A replica that honours the token but has not seen the store's write yet: it sends the
    /// other device's version, which the store's newer edit replaced through last write wins.
    @Test func aLaggingReplicaAfterAConflictDoesNotRollBackTheWinner() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = await forwarding(to: server)
        let store = try makeStore(transport)
        try await store.save(Note(id: "a", text: "v1"))
        try await store.sync()
        let token = await store.state.token
        clock.advance(by: 5)
        await server.write(Note(id: "a", text: "other device"))
        clock.advance(by: 5)
        try await store.save(Note(id: "a", text: "mine, newer"))
        let replica = try await server.pull(since: token)
        await answerNextPull(of: transport, with: replica, from: server)
        try await store.sync()
        #expect(await server.record("a")?.text == "mine, newer")
        #expect(await store.record("a")?.text == "mine, newer")
    }

    /// The same after the app ended between the push and the pull: what the store knows about
    /// the order of its accepted write is in the file.
    @Test func aLaggingReplicaAfterARestartDoesNotRollBackTheWinner() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = await forwarding(to: server)
        let storage = InMemoryStorage()
        var store = try makeStore(transport, storage: storage)
        try await store.save(Note(id: "a", text: "v1"))
        try await store.sync()
        let token = await store.state.token
        clock.advance(by: 5)
        await server.write(Note(id: "a", text: "other device"))
        clock.advance(by: 5)
        try await store.save(Note(id: "a", text: "mine, newer"))
        let replica = try await server.pull(since: token)
        await transport.onPull { _ in throw URLError(.timedOut) }
        await #expect(throws: URLError.self) { try await store.sync() }
        #expect(await server.record("a")?.text == "mine, newer")

        store = try makeStore(transport, storage: storage)
        await answerNextPull(of: transport, with: replica, from: server)
        try await store.sync()
        #expect(await store.record("a")?.text == "mine, newer")
    }

    /// A replica or cache that still answers from before a server restart: its page names the
    /// epoch the store left, and its versions would roll every record back. The store refuses
    /// it, also after the app restarted.
    @Test func aPageFromAnEpochTheStoreLeftIsRefused() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = await forwarding(to: server)
        let storage = InMemoryStorage()
        var store = try makeStore(transport, storage: storage)
        try await store.save(Note(id: "a", text: "v1"))
        try await store.sync()
        let beforeRestart = try await server.pull(since: nil)

        await server.restart()
        clock.advance(by: 10)
        try await store.save(Note(id: "a", text: "v2"))
        try await store.sync()
        #expect(await server.record("a")?.text == "v2")

        store = try makeStore(transport, storage: storage)
        try await store.resetChangeToken()
        await answerNextPull(of: transport, with: beforeRestart, from: server)
        await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        #expect(await store.record("a")?.text == "v2")
        try await store.sync()
        #expect(await store.record("a")?.text == "v2")
        #expect(await store.pendingChanges().isEmpty)
    }

    /// Two accepted writes without an echo in between: the replica has the first, not the
    /// second. The first is the store's own earlier write, so it is older.
    @Test func aStalePageWithTheStoresEarlierWriteDoesNotRollBackItsLaterOne() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = await forwarding(to: server)
        let store = try makeStore(transport)
        try await store.save(Note(id: "a", text: "v1"))
        try await store.sync()
        clock.advance(by: 5)
        try await store.save(Note(id: "a", text: "v2"))
        let token = await store.state.token
        await answerNextPull(of: transport, with: PullResponse(changes: [], token: token, hasMore: false), from: server)
        try await store.sync()
        let replica = try await server.pull(since: token)
        #expect(replica.changes.map(\.record?.text) == ["v2"])

        clock.advance(by: 5)
        try await store.save(Note(id: "a", text: "v3"))
        await answerNextPull(of: transport, with: replica, from: server)
        try await store.sync()
        #expect(await server.record("a")?.text == "v3")
        #expect(await store.record("a")?.text == "v3")
    }
}
