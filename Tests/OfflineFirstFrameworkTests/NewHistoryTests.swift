import Foundation
import Testing
@testable import OfflineFirstFramework

/// The store's write is accepted while its entry belongs to the server history the next pull
/// leaves: the push runs before the pull that sees the new epoch, or the pull after the restart
/// stopped before the record's echo. A stale page of the new epoch (a shared cache, a lagging
/// replica) then brings the version the write replaced. It must not roll the write back, and an
/// edit made after it must not meet the device's own write as a conflict.
@Suite("Offline store: own writes in a new server history")
struct NewHistoryTests {
    let clock = TestClock()

    private func makeStore(_ transport: any SyncTransport<Note>, resolver: ConflictResolver<Note>) throws -> OfflineStore<Note> {
        try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                               configuration: makeConfiguration(clock: clock, resolver: resolver))
    }

    private func forwarding(to server: InMemorySyncServer<Note>) async -> ScriptedTransport {
        let transport = ScriptedTransport()
        await transport.onPush { try await server.push($0) }
        await transport.onPull { try await server.pull(since: $0) }
        return transport
    }

    /// `resolver`, recording the text of every server version it is asked about.
    private func recording(_ resolver: ConflictResolver<Note>, into seen: SeenTexts) -> ConflictResolver<Note> {
        ConflictResolver { conflict in
            seen.add(conflict.remote?.text)
            return resolver.resolve(conflict)
        }
    }

    /// The device pushes after a server restart, before its pull sees the new epoch. The pull
    /// from the beginning is answered by a cache with the page another device got right after
    /// the restart, which still has the version the write replaced.
    @Test(arguments: ConvergenceTests.Policy.allCases)
    func aStaleFirstPageOfTheNewEpochDoesNotRollBackTheOwnAcceptedWrite(policy: ConvergenceTests.Policy) async throws {
        let seen = SeenTexts()
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = await forwarding(to: server)
        let store = try makeStore(transport, resolver: recording(policy.resolver, into: seen))
        await server.write(Note(id: "x", text: "v1"))
        try await store.sync()
        await server.restart()
        let cachedFirstPage = try await server.pull(since: nil)
        clock.advance(by: 5)
        try await store.save(Note(id: "x", text: "v3"))
        let cached = OneShot()
        await transport.onPull { token in
            if token == nil, await cached.fire() { return cachedFirstPage }
            return try await server.pull(since: token)
        }
        try await store.sync()
        #expect(await server.record("x")?.text == "v3")
        #expect(await store.record("x")?.text == "v3", "\(policy)")

        clock.advance(by: 5)
        try await store.save(Note(id: "x", text: "v4"))
        try await store.sync()
        try await store.sync()
        #expect(!seen.values.contains("v3"), "\(policy): the resolver was asked about the device's own write")
        #expect(await server.record("x")?.text == "v4", "\(policy)")
        #expect(await store.record("x")?.text == "v4", "\(policy)")
    }

    /// The pull after the restart gets the first page of the new epoch and then the connection
    /// drops, so the record's entry stays in the old history. The write is accepted, and a
    /// lagging replica of the new epoch sends the version it replaced.
    @Test(arguments: ConvergenceTests.Policy.allCases)
    func anAcceptedWriteRightAfterAnEpochChangeIsNotRolledBack(policy: ConvergenceTests.Policy) async throws {
        let server = InMemorySyncServer<Note>(pageSize: 1, now: { [clock] in clock.now })
        let transport = await forwarding(to: server)
        let store = try makeStore(transport, resolver: policy.resolver)
        let lagging = try await interruptedPullAfterARestart(server, transport: transport, store: store)

        clock.advance(by: 10)
        try await store.save(Note(id: "a", text: "v2"))
        await answerNextPull(of: transport, with: lagging, from: server)
        try await store.sync()
        #expect(await server.record("a")?.text == "v2")
        #expect(await store.record("a")?.text == "v2", "\(policy): rolled back to the version the write replaced")
        try await store.sync()
        #expect(await store.record("a")?.text == "v2", "\(policy)")
        #expect(await store.pendingChanges().isEmpty)
    }

    /// The same, then the user edits before the next sync. The edit goes out on top of the
    /// device's own write; with server wins it would otherwise be dropped.
    @Test func anEditAfterAnAcceptedWriteInANewHistoryIsNotResolvedAgainstIt() async throws {
        let seen = SeenTexts()
        let server = InMemorySyncServer<Note>(pageSize: 1, now: { [clock] in clock.now })
        let transport = await forwarding(to: server)
        let store = try makeStore(transport, resolver: recording(.serverWins, into: seen))
        let lagging = try await interruptedPullAfterARestart(server, transport: transport, store: store)
        clock.advance(by: 10)
        try await store.save(Note(id: "a", text: "v2"))
        await answerNextPull(of: transport, with: lagging, from: server)
        try await store.sync()

        clock.advance(by: 10)
        try await store.save(Note(id: "a", text: "v3 newest edit"))
        try await store.sync()
        try await store.sync()
        #expect(seen.values.isEmpty)
        #expect(await server.record("a")?.text == "v3 newest edit")
        #expect(await store.record("a")?.text == "v3 newest edit")
    }

    /// Another device writes after the restart, and this device's edit meets that write as a
    /// conflict before its pull sees the new epoch. Whatever the policy keeps (the other
    /// device's version, or the device's write on top of it) is newer than the first page of
    /// the new epoch that a cache stored right after the restart.
    @Test(arguments: ConvergenceTests.Policy.allCases)
    func aStaleFirstPageOfTheNewEpochDoesNotRollBackWhatAConflictAnswerBrought(policy: ConvergenceTests.Policy) async throws {
        let seen = SeenTexts()
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = await forwarding(to: server)
        let store = try makeStore(transport, resolver: recording(policy.resolver, into: seen))
        await server.write(Note(id: "x", text: "v1"))
        try await store.sync()
        await server.restart()
        let cachedFirstPage = try await server.pull(since: nil)
        clock.advance(by: 5)
        await server.write(Note(id: "x", text: "v2 from another device"))
        clock.advance(by: 5)
        try await store.save(Note(id: "x", text: "v3"))
        let cached = OneShot()
        await transport.onPull { token in
            if token == nil, await cached.fire() { return cachedFirstPage }
            return try await server.pull(since: token)
        }
        try await store.sync()
        #expect(seen.values == ["v2 from another device"], "\(policy)")
        let kept = await server.record("x")?.text
        #expect(kept != "v1")
        #expect(await store.record("x")?.text == kept, "\(policy): rolled back to the first page of the new epoch")
        try await store.sync()
        #expect(await store.record("x")?.text == kept, "\(policy)")
        #expect(await store.pendingChanges().isEmpty)
    }

    /// A store opened with another server takes that server's versions, also of a record whose
    /// last push the old server answered: what the old server told about the order says nothing
    /// about the new one.
    @Test func anotherServerReplacesWhatTheOldServersPushAnswerTold() async throws {
        let storage = InMemoryStorage()
        let first = RemoteChange<Note>(recordID: "x", record: Note(id: "x", text: "v1"), revision: "a.1",
                                       timestamp: HLCTimestamp(wallTime: 1_000, nodeID: "other"), sequence: 1)
        let serverA = ScriptedTransport(identity: "https://a.example/sync/notes", push: { changes in
            Dictionary(uniqueKeysWithValues: changes.map { ($0.id, .accepted(revision: "a.9")) })
        }, pull: { token in
            PullResponse(changes: token == nil ? [first] : [], token: "a.1", hasMore: false)
        })
        let configuration = makeConfiguration(clock: clock, resolver: .lastWriteWins)
        let store = try OfflineStore<Note>(name: "notes", storage: storage, transport: serverA, configuration: configuration)
        try await store.sync()
        try await store.save(Note(id: "x", text: "v2"))
        try await store.sync()

        let other = RemoteChange<Note>(recordID: "x", record: Note(id: "x", text: "the other server's copy"), revision: "b.1",
                                       timestamp: HLCTimestamp(wallTime: 1_000, nodeID: "other"), sequence: 1)
        let serverB = ScriptedTransport(identity: "https://b.example/sync/notes", pull: { _ in
            PullResponse(changes: [other], token: "b.1", hasMore: false)
        })
        let reopened = try OfflineStore<Note>(name: "notes", storage: storage, transport: serverB, configuration: configuration)
        try await reopened.sync()
        #expect(await reopened.record("x")?.text == "the other server's copy")
    }

    /// After a restore that set the server's sequence back, the server's version has a lower
    /// sequence than the one the store's last push answer told. A pull cannot tell that version
    /// from a stale one and keeps the device's (a documented limit), but the conflict answer to
    /// the next edit comes from the server itself: the edit is resolved against it and goes out
    /// instead of waiting for good.
    @Test func aConflictAnswerAfterARestoreIsResolvedWhateverTheOldHistoryToldAboutTheOrder() async throws {
        let base = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "v1"), revision: "e1.1",
                                      timestamp: HLCTimestamp(wallTime: 1_000, nodeID: "other"), sequence: 1)
        let pages = ScriptedTransport(push: { changes in
            Dictionary(uniqueKeysWithValues: changes.map { ($0.id, .accepted(revision: "e1.2")) })
        }, pull: { token in
            token == nil ? PullResponse(changes: [base], token: "e1.1", hasMore: false, epoch: "e1")
                : PullResponse(changes: [], token: token, hasMore: false, epoch: "e1")
        })
        let store = try makeStore(pages, resolver: .lastWriteWins)
        try await store.sync()
        try await store.save(Note(id: "a", text: "v2, lost by the restore"))
        try await store.sync()

        let restored = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "written after the restore"), revision: "e2.1",
                                          timestamp: HLCTimestamp(wallTime: 2_000, nodeID: "other"), sequence: 1)
        await pages.onPull { _ in PullResponse(changes: [restored], token: "e2.1", hasMore: false, epoch: "e2") }
        await pages.onPush { changes in
            Dictionary(uniqueKeysWithValues: changes.map { change in
                (change.id, change.baseRevision == "e2.1" ? .accepted(revision: "e2.2") : .conflict(current: restored))
            })
        }
        try await store.sync()
        #expect(await store.record("a")?.text == "v2, lost by the restore")
        clock.advance(by: 10)
        try await store.save(Note(id: "a", text: "v3"))
        let report = try await store.sync()
        #expect(report.conflicts == 1)
        #expect(report.pushed == 1)
        #expect(await store.record("a")?.text == "v3")
        #expect(await store.pendingChanges().isEmpty)
    }

    /// After a restore from a backup, the server lost the device's accepted write and holds the
    /// version it replaced. A pull does not take that version over the write (the store cannot
    /// tell it from a stale page), but the conflict answer to the next edit comes from the
    /// server itself: the edit is resolved against it instead of waiting for good.
    @Test func aConflictWithTheVersionALostWriteReplacedIsResolved() async throws {
        let base = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "v1"), revision: "e1.1",
                                      timestamp: HLCTimestamp(wallTime: 1_000, nodeID: "other"), sequence: 1)
        let pages = ScriptedTransport(push: { changes in
            Dictionary(uniqueKeysWithValues: changes.map { ($0.id, .accepted(revision: "e1.2")) })
        }, pull: { token in
            token == nil ? PullResponse(changes: [base], token: "e1.1", hasMore: false, epoch: "e1")
                : PullResponse(changes: [], token: token, hasMore: false, epoch: "e1")
        })
        let store = try makeStore(pages, resolver: .lastWriteWins)
        try await store.sync()
        try await store.save(Note(id: "a", text: "v2, lost by the restore"))
        try await store.sync()

        await pages.onPull { _ in PullResponse(changes: [base], token: "e2.1", hasMore: false, epoch: "e2") }
        await pages.onPush { changes in
            Dictionary(uniqueKeysWithValues: changes.map { change in
                (change.id, change.baseRevision == "e1.1" ? .accepted(revision: "e2.2") : .conflict(current: base))
            })
        }
        try await store.sync()
        #expect(await store.record("a")?.text == "v2, lost by the restore")
        clock.advance(by: 10)
        try await store.save(Note(id: "a", text: "v3"))
        let report = try await store.sync()
        #expect(report.conflicts == 1)
        #expect(report.pushed == 1)
        #expect(await store.record("a")?.text == "v3")
        #expect(await store.pendingChanges().isEmpty)
    }

    /// Syncs once, restarts the server and lets the next sync get only the first page of the new
    /// epoch (record "b"); returns the page a lagging replica sends next: record "a" at the
    /// version from before the restart.
    private func interruptedPullAfterARestart(_ server: InMemorySyncServer<Note>, transport: ScriptedTransport,
                                              store: OfflineStore<Note>) async throws -> PullResponse<Note> {
        await server.write(Note(id: "b", text: "b"))
        await server.write(Note(id: "a", text: "v1"))
        try await store.sync()
        await server.restart()
        let pulls = Counter()
        await transport.onPull { token in
            if await pulls.next() > 2 { throw URLError(.networkConnectionLost) }
            return try await server.pull(since: token)
        }
        await #expect(throws: URLError.self) { try await store.sync() }
        let lagging = try await server.pull(since: await store.state.token)
        #expect(lagging.changes.map(\.record?.text) == ["v1"])
        return lagging
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
}

/// Texts a resolver was asked about, from any thread.
final class SeenTexts: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String?] = []

    func add(_ value: String?) {
        lock.lock()
        defer { lock.unlock() }
        stored.append(value)
    }

    var values: [String?] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
}
