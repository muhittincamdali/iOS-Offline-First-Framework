import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A feed server with an epoch and positions for tokens, sequences optional: a token of
/// another deployment makes it answer with nothing.
actor EpochFeedServer {
    struct Stored { var record: Note?; var revision: String; var position: Int; var changeID: UUID? }
    let epoch: String
    let sendsSequences: Bool
    private var stored: [String: Stored] = [:]
    private var position = 0

    init(epoch: String, sendsSequences: Bool) {
        self.epoch = epoch
        self.sendsSequences = sendsSequences
    }

    func push(_ changes: [OutgoingChange<Note>]) -> [UUID: PushOutcome<Note>] {
        var outcomes: [UUID: PushOutcome<Note>] = [:]
        for change in changes {
            if let current = stored[change.recordID], current.revision != change.baseRevision {
                outcomes[change.id] = .conflict(current: remote(change.recordID, current))
                continue
            }
            position += 1
            stored[change.recordID] = Stored(record: change.record, revision: "\(epoch).v\(position)", position: position, changeID: change.id)
            outcomes[change.id] = .accepted(revision: "\(epoch).v\(position)")
        }
        return outcomes
    }

    func pull(_ token: String?) -> PullResponse<Note> {
        let after = token.flatMap { Int($0) } ?? 0
        let changed = stored.filter { $0.value.position > after }.sorted { $0.value.position < $1.value.position }
        return PullResponse(changes: changed.map { remote($0.key, $0.value) }, token: "\(changed.last?.value.position ?? after)",
                            hasMore: false, epoch: epoch)
    }

    func text(_ id: String) -> String? { stored[id]?.record?.text }

    private func remote(_ id: String, _ version: Stored) -> RemoteChange<Note> {
        RemoteChange(recordID: id, record: version.record, revision: version.revision, timestamp: nil,
                     sequence: sendsSequences ? UInt64(version.position) : nil, changeID: version.changeID)
    }
}

/// A page without an epoch once the store holds one: another deployment behind the same URL, or
/// a proxy that answers for the server. It was taken from a single request, with its revision,
/// sequence and token: the record went back to that copy, and the forged sequence made every
/// later conflict answer of the real server look older, so each edit of the record was parked,
/// also after `retryFailedChanges()` and `resetChangeToken()`. A store holds the epoch two
/// requests of its first sync reported, so one sync before the forged page is enough.
@Suite("Offline store: a page without an epoch")
struct MissingEpochTests {
    private static let forgedPage = PullResponse(
        changes: [RemoteChange(recordID: "n", record: Note(id: "n", text: "old copy"), revision: "legacy.99999",
                               timestamp: nil, sequence: 99_999)],
        token: "legacy.99999", hasMore: false, epoch: nil)

    /// Answers every pull with the forged page while `forged` is set, otherwise as `server`.
    private func transport(_ server: InMemorySyncServer<Note>, forged: OSAllocatedUnfairLock<Bool>) -> ScriptedTransport {
        ScriptedTransport(push: { try await server.push($0) }, pull: { token in
            if forged.withLock({ $0 }) { return Self.forgedPage }
            return try await server.pull(since: token)
        })
    }

    @Test func aPageWithoutAnEpochIsRefusedOnceTheStoreHoldsOne() async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        let forged = OSAllocatedUnfairLock(initialState: false)
        let transport = transport(server, forged: forged)
        let store = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock))
        await server.write(Note(id: "n", text: "real 1"))
        try await store.sync()
        let token = await store.state.token
        let epoch = await store.state.serverEpoch
        #expect(epoch != nil)
        #expect(await store.state.epochIsConfirmed)

        // Both requests of the check are answered without an epoch: refused, nothing changes.
        forged.withLock { $0 = true }
        let pullsBefore = await transport.pulls
        await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        #expect(await transport.pulls - pullsBefore == 2)
        #expect(await store.record("n")?.text == "real 1")
        #expect(await store.state.token == token)
        #expect(await store.state.serverEpoch == epoch)
        #expect(await store.state.entries["n"]?.sequence != 99_999)

        forged.withLock { $0 = false }
        await server.write(Note(id: "n", text: "real 2"))
        try await store.sync()
        #expect(await store.record("n")?.text == "real 2")
    }

    @Test func aSinglePageWithoutAnEpochIsDropped() async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        let forgedPulls = OSAllocatedUnfairLock(initialState: 0)
        let transport = ScriptedTransport(push: { try await server.push($0) }, pull: { token in
            let forged = forgedPulls.withLock { count in
                guard count > 0 else { return false }
                count -= 1
                return true
            }
            return forged ? Self.forgedPage : try await server.pull(since: token)
        })
        let store = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock))
        await server.write(Note(id: "n", text: "real 1"))
        try await store.sync()
        await server.write(Note(id: "n", text: "real 2"))

        // Only the first request goes elsewhere; the check asks the server, and the sync goes on.
        forgedPulls.withLock { $0 = 1 }
        try await store.sync()
        #expect(await store.record("n")?.text == "real 2")
        #expect(await store.state.entries["n"]?.revision?.hasPrefix("legacy") == false)
    }

    /// The edit made after the forged sync reaches the server, and nothing is parked.
    @Test func anEditAfterAPageWithoutAnEpochReachesTheServer() async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        let forged = OSAllocatedUnfairLock(initialState: false)
        let store = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport(server, forged: forged),
                                           configuration: makeConfiguration(clock: clock))
        await server.write(Note(id: "n", text: "real 1"))
        try await store.sync()
        forged.withLock { $0 = true }
        _ = try? await store.sync()
        forged.withLock { $0 = false }
        try await store.save(Note(id: "n", text: "A's edit"))
        for _ in 0..<3 {
            _ = try? await store.sync()
            clock.advance(by: 120)
        }
        #expect(await server.record("n")?.text == "A's edit")
        #expect(await store.pendingChanges().isEmpty)
        #expect(await store.failedChanges().isEmpty)
    }

    /// A store that never held an epoch takes pages without one, as before.
    @Test func aServerWithoutEpochsIsFollowed() async throws {
        let clock = TestClock()
        let page = OSAllocatedUnfairLock(initialState: Self.forgedPage)
        let transport = ScriptedTransport(pull: { _ in page.withLock { $0 } })
        let store = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock))
        try await store.sync()
        #expect(await store.record("n")?.text == "old copy")
        page.withLock {
            $0 = PullResponse(changes: [RemoteChange(recordID: "n", record: Note(id: "n", text: "new copy"), revision: "legacy.100000",
                                                     timestamp: nil, sequence: 100_000)],
                              token: "legacy.100000", hasMore: false, epoch: nil)
        }
        try await store.sync()
        #expect(await store.record("n")?.text == "new copy")
        #expect(await store.state.serverEpoch == nil)
    }

    // MARK: - Verifier probes of rounds 9, 10 and 12

    /// Round 9: one sync of a store that synced once is answered without an epoch, with a copy
    /// and a sequence of another deployment; the server then writes again.
    @Test func aPageWithoutAnEpochIsTakenFromOneRequest() async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        let forged = OSAllocatedUnfairLock(initialState: false)
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport(server, forged: forged),
                                       configuration: makeConfiguration(clock: clock))
        await server.write(Note(id: "n", text: "real 1"))
        try await a.sync()
        forged.withLock { $0 = true }
        _ = try? await a.sync()
        forged.withLock { $0 = false }
        await server.write(Note(id: "n", text: "real 2"))
        for _ in 0..<3 { try await a.sync() }
        #expect(await a.record("n")?.text == "real 2")
        #expect(await a.state.entries["n"]?.sequence != 99_999)
    }

    /// Round 10: the user edits after such a sync; the edit reaches the server, before and
    /// after `retryFailedChanges()`, `resetChangeToken()` and a server restart.
    @Test func anEpochlessPageWithAForgedSequenceStrandsTheRecord() async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        let forged = OSAllocatedUnfairLock(initialState: false)
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport(server, forged: forged),
                                       configuration: makeConfiguration(clock: clock))
        await server.write(Note(id: "n", text: "real 1"))
        try await a.sync()
        forged.withLock { $0 = true }
        _ = try? await a.sync()
        forged.withLock { $0 = false }
        try await a.save(Note(id: "n", text: "A's edit"))
        for _ in 0..<6 {
            _ = try? await a.sync()
            clock.advance(by: 120)
        }
        #expect(await server.record("n")?.text == "A's edit")
        #expect(await a.failedChanges().isEmpty)
        try await a.retryFailedChanges()
        try await a.resetChangeToken()
        await server.restart()
        for _ in 0..<3 {
            try await a.sync()
            clock.advance(by: 120)
        }
        #expect(await a.record("n")?.text == "A's edit")
        #expect(await a.pendingChanges().isEmpty)
    }

    /// Round 12: a store synced once or twice with its server, one page per sync, then both
    /// requests of one sync come from a deployment without epochs, with a forged sequence. The
    /// store had taken a new store's first epoch from one page, and with it this sync started a
    /// history without an epoch; the server's epoch then counted as a first one, the pull went on
    /// after the forged token, the forged sequence hid the server's versions, and every edit of
    /// the record was parked.
    @Test(arguments: [1, 2])
    func anEpochlessSyncAfterOneConfirmedOrUnconfirmedEpoch(syncsBefore: Int) async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        let forged = OSAllocatedUnfairLock(initialState: false)
        let transport = transport(server, forged: forged)
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport, configuration: makeConfiguration(clock: clock))
        await server.write(Note(id: "n", text: "real 1"))
        for _ in 0..<syncsBefore { try await a.sync() }
        let epoch = await a.state.serverEpoch
        #expect(await a.state.epochIsConfirmed)
        forged.withLock { $0 = true }
        let pullsBefore = await transport.pulls
        await #expect(throws: OfflineFirstError.self) { try await a.sync() }
        #expect(await transport.pulls - pullsBefore == 2)
        forged.withLock { $0 = false }
        #expect(await a.state.serverEpoch == epoch)
        #expect(await a.record("n")?.text == "real 1")
        try await a.save(Note(id: "n", text: "A's edit"))
        for _ in 0..<3 {
            try await a.sync()
            clock.advance(by: 120)
        }
        #expect(await server.record("n")?.text == "A's edit")
        #expect(await a.failedChanges().isEmpty)
    }

    /// Round 12, with a server whose tokens are positions: the other deployment's token "99999"
    /// made the server answer every later pull with nothing, without an error, so another
    /// device's new record and its edit never arrived.
    @Test(arguments: [false, true])
    func theRealEpochComesBackAfterTheOtherDeploymentsToken(resets: Bool) async throws {
        let clock = TestClock()
        let server = EpochFeedServer(epoch: "e1", sendsSequences: false)
        let forged = OSAllocatedUnfairLock(initialState: false)
        let ta = ScriptedTransport(push: { await server.push($0) }, pull: { token in
            if forged.withLock({ $0 }) { return PullResponse(changes: [], token: "99999", hasMore: false, epoch: nil) }
            return await server.pull(token)
        })
        let tb = ScriptedTransport(push: { await server.push($0) }, pull: { await server.pull($0) })
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: ta, configuration: makeConfiguration(clock: clock))
        let b = try OfflineStore<Note>(name: "b", storage: InMemoryStorage(), transport: tb, configuration: makeConfiguration(clock: clock))
        try await b.save(Note(id: "n", text: "B1"))
        try await b.sync()
        try await a.sync()
        forged.withLock { $0 = true }
        await #expect(throws: OfflineFirstError.self) { try await a.sync() }
        forged.withLock { $0 = false }
        try await b.save(Note(id: "m", text: "B's new note"))
        try await b.save(Note(id: "n", text: "B2"))
        try await b.sync()
        for round in 0..<3 {
            clock.advance(by: 120)
            if round == 1 && resets { try await a.resetChangeToken() }
            try await a.sync()
        }
        #expect(await a.state.token != "99999")
        #expect(await a.record("m")?.text == "B's new note")
        #expect(await a.record("n")?.text == "B2")
    }
}
