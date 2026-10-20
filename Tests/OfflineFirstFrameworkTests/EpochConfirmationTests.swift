import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A cache in front of the server that answers the pull from the beginning, the same URL for
/// every device, with a page it keeps (a shared CDN entry with a long max-age). Every other
/// request reaches the server.
private actor SharedFirstPageCache: SyncTransport {
    let server: InMemorySyncServer<Note>
    /// Whether the first answer from the server is kept.
    private let keepsFirstAnswer: Bool
    private var cached: PullResponse<Note>?
    private(set) var originPulls = 0
    nonisolated var serverIdentity: String? { "https://cdn.example.com/sync/notes" }

    init(server: InMemorySyncServer<Note>, keepsFirstAnswer: Bool) {
        self.server = server
        self.keepsFirstAnswer = keepsFirstAnswer
    }

    func serve(_ page: PullResponse<Note>?) {
        cached = page
    }

    func push(_ changes: [OutgoingChange<Note>]) async throws -> [UUID: PushOutcome<Note>] {
        try await server.push(changes)
    }

    func pull(since token: String?) async throws -> PullResponse<Note> {
        if token == nil, let cached { return cached }
        originPulls += 1
        let page = try await server.pull(since: token)
        if token == nil, keepsFirstAnswer { cached = page }
        return page
    }
}

/// Another epoch than the store's is believed only when two requests of one sync report it,
/// and both belong to one step of the pull: a sync that may fetch one page still follows a
/// restart, and a cache that answers only the pull from the beginning makes the sync fail
/// instead of spending its pages or rolling the store back.
@Suite("Offline store: confirming a server epoch")
struct EpochConfirmationTests {
    let clock = TestClock()

    private func forwarding(to server: InMemorySyncServer<Note>) async -> ScriptedTransport {
        let transport = ScriptedTransport()
        await transport.onPush { try await server.push($0) }
        await transport.onPull { try await server.pull(since: $0) }
        return transport
    }

    private func onePagePerSync() -> OfflineStore<Note>.Configuration {
        var configuration = makeConfiguration(clock: clock)
        configuration.maximumPullPages = 1
        return configuration
    }

    @Test func aSyncThatFetchesOnePageFollowsAServerRestart() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: server, configuration: onePagePerSync())
        await server.write(Note(id: "a", text: "a1"))
        try await store.sync()

        await server.restart()
        await server.write(Note(id: "b", text: "written after the restart"))
        let report = try await store.sync()
        #expect(await store.record("b")?.text == "written after the restart")
        #expect(await store.record("a")?.text == "a1")
        #expect(!report.hasMoreChanges)
    }

    @Test func aSyncThatFetchesOnePageFollowsARestartAfterDiscardChange() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: server, configuration: onePagePerSync())
        await server.write(Note(id: "a", text: "a1"))
        try await store.sync()
        await server.setOnline(false)
        try await store.save(Note(id: "a", text: "local"))
        _ = try? await store.sync()
        try await store.discardChange(for: "a")
        await server.setOnline(true)
        await server.restart()
        await server.write(Note(id: "b", text: "after"))

        try await store.sync()
        #expect(await store.record("b")?.text == "after")
        #expect(await store.record("a")?.text == "a1")
    }

    /// After a restart, the pull with the token reaches the server (a later epoch) and the pull
    /// from the beginning gets the cached page of the store's own epoch. The sync fails after
    /// at most two requests to the server, stores nothing, and follows the server once the
    /// cache entry expires.
    @Test func aCachedFirstPageFromBeforeARestartFailsTheSyncInsteadOfSpendingItsPages() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        await server.write(Note(id: "a", text: "a"))
        let cache = SharedFirstPageCache(server: server, keepsFirstAnswer: true)
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: cache,
                                           configuration: makeConfiguration(clock: clock))
        try await store.sync()
        await server.write(Note(id: "b", text: "b"))
        try await store.sync()
        await server.restart()
        await server.write(Note(id: "c", text: "written after the restart"))

        let before = await cache.originPulls
        for _ in 0..<3 {
            await #expect(throws: OfflineFirstError.self) { try await store.sync() }
            guard case .failed = await store.status else {
                Issue.record("status \(await store.status)")
                return
            }
            clock.advance(by: 300)
        }
        #expect(await cache.originPulls - before <= 6)
        #expect(await store.record("c") == nil)
        #expect(await store.records().map(\.text) == ["a", "b"])

        await cache.serve(nil)
        try await store.sync()
        #expect(await store.record("c")?.text == "written after the restart")
    }

    /// The cached first page is from two restarts ago, earlier than the store's epoch, while
    /// the pull with the token reports a later one. The two never agree, so no sync counts a
    /// refusal of the cached epoch or takes it, however many syncs meet it.
    @Test func aCachedFirstPageOfAnEarlierEpochIsNeverTaken() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        await server.write(Note(id: "a", text: "a v1, two restarts ago"))
        let earliest = try await server.pull(since: nil)
        await server.restart()
        await server.write(Note(id: "a", text: "a v2"))
        let cache = SharedFirstPageCache(server: server, keepsFirstAnswer: false)
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: cache,
                                           configuration: makeConfiguration(clock: clock))
        try await store.sync()
        await cache.serve(earliest)
        await server.restart()
        await server.write(Note(id: "a", text: "a v3, current"))

        for _ in 0..<(2 * OfflineStore<Note>.maximumEpochRefusals) {
            await #expect(throws: OfflineFirstError.self) { try await store.sync() }
            #expect(await store.record("a")?.text == "a v2")
            clock.advance(by: 300)
        }
        #expect(await store.state.epochRefusal == nil)

        await cache.serve(nil)
        try await store.sync()
        #expect(await store.record("a")?.text == "a v3, current")
    }

    /// After resetChangeToken(), a lagging replica still in an earlier epoch answers the pull
    /// from the beginning; the pull after its token reaches the server, which names the store's
    /// epoch. The replica's versions are not taken: no record goes back, and a deleted record,
    /// whose deletion the server no longer lists, stays deleted.
    @Test func aResetDoesNotTakeAnEarlierEpochFromOnePage() async throws {
        func change(_ id: String, _ text: String?, _ revision: String, _ sequence: UInt64) -> RemoteChange<Note> {
            RemoteChange(recordID: id, record: text.map { Note(id: id, text: $0) }, revision: revision, timestamp: nil, sequence: sequence)
        }
        let e1 = "0000000000000001", e2 = "0000000000000002"
        let staleE1 = PullResponse<Note>(changes: [change("x", "x1", "\(e1).1", 1), change("z", "z1", "\(e1).2", 2)],
                                         token: "\(e1).2", hasMore: false, epoch: e1)
        let compactedE2 = PullResponse<Note>(changes: [change("x", "x2", "\(e2).4", 4)], token: "\(e2).4", hasMore: false, epoch: e2)
        let withDeletionE2 = PullResponse<Note>(changes: [change("x", "x2", "\(e2).4", 4), change("z", nil, "\(e2).3", 3)],
                                                token: "\(e2).4", hasMore: false, epoch: e2)
        let answers = OSAllocatedUnfairLock<[PullResponse<Note>]>(initialState: [withDeletionE2])
        let transport = ScriptedTransport(pull: { _ in answers.withLock { $0.count > 1 ? $0.removeFirst() : $0[0] } })
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock))
        try await store.sync()
        #expect(await store.record("z") == nil)

        try await store.resetChangeToken()
        answers.withLock { $0 = [staleE1, compactedE2] }
        try await store.sync()
        #expect(await store.record("x")?.text == "x2")
        #expect(await store.record("z") == nil)
        for _ in 0..<3 { try await store.sync() }
        #expect(await store.record("x")?.text == "x2")
        #expect(await store.record("z") == nil)
        #expect(await store.state.serverEpoch == e2)
    }
}
