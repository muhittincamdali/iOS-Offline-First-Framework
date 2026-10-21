import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A feed server without epochs, as the protocol allows: sequences optional, change IDs sent.
private actor EpochlessServer {
    struct Version { var record: Note?; var revision: String; var position: Int; var changeID: UUID }
    let sendsSequences: Bool
    private var stored: [String: Version] = [:]
    private var position = 0

    init(sendsSequences: Bool) { self.sendsSequences = sendsSequences }

    func push(_ changes: [OutgoingChange<Note>]) -> [UUID: PushOutcome<Note>] {
        var outcomes: [UUID: PushOutcome<Note>] = [:]
        for change in changes {
            if let current = stored[change.recordID], current.revision != change.baseRevision {
                outcomes[change.id] = .conflict(current: remote(change.recordID, current))
                continue
            }
            position += 1
            stored[change.recordID] = Version(record: change.record, revision: "v\(position)", position: position, changeID: change.id)
            outcomes[change.id] = .accepted(revision: "v\(position)")
        }
        return outcomes
    }

    func pull(_ token: String?) -> PullResponse<Note> {
        let after = token.flatMap { Int($0) } ?? 0
        let changed = stored.filter { $0.value.position > after }.sorted { $0.value.position < $1.value.position }
        return PullResponse(changes: changed.map { remote($0.key, $0.value) }, token: "\(changed.last?.value.position ?? after)",
                            hasMore: false)
    }

    func text(_ id: String) -> String? { stored[id]?.record?.text }

    private func remote(_ id: String, _ version: Version) -> RemoteChange<Note> {
        RemoteChange(recordID: id, record: version.record, revision: version.revision, timestamp: nil,
                     sequence: sendsSequences ? UInt64(version.position) : nil, changeID: version.changeID)
    }
}

/// Answers the next `count` pulls with `page` (made from the token asked for), the rest as the
/// server does: another deployment behind the same URL that answers a few requests.
private func forging(_ server: EpochlessServer, _ forged: OSAllocatedUnfairLock<Int>,
                     page: @escaping @Sendable (String?) -> PullResponse<Note>) -> ScriptedTransport {
    ScriptedTransport(push: { await server.push($0) }, pull: { token in
        let isForged = forged.withLock { count -> Bool in
            guard count > 0 else { return false }
            count -= 1
            return true
        }
        return isForged ? page(token) : await server.pull(token)
    })
}

/// The first epoch a store hears of. It used to be taken from a single page, and once the store
/// held an epoch, every page without one was refused: one page with an epoch from another
/// deployment behind the same URL locked a store of a server without epochs out for good, also
/// after `resetChangeToken()`, and the edits of other devices never reached it. The first epoch
/// is now checked by a second request like any other, so the store holds only an epoch two
/// requests reported, and a page without an epoch is refused only against such an epoch.
@Suite("Offline store: the first epoch")
struct FirstEpochTests {
    /// Verifier A11's probe: one request of a store that synced with a server without epochs is
    /// answered with a page that names an epoch and brings a copy, a token and, with sequences,
    /// a sequence of its own. Afterwards the real server answers every pull.
    @Test(arguments: [false, true])
    func oneForgedEpochLocksAStoreOfAnEpochlessServerOut(withSequences: Bool) async throws {
        let clock = TestClock()
        let server = EpochlessServer(sendsSequences: withSequences)
        let forged = OSAllocatedUnfairLock(initialState: 0)
        let transportA = forging(server, forged) { _ in
            PullResponse(changes: [RemoteChange(recordID: "n", record: Note(id: "n", text: "staging copy"), revision: "staging.99999",
                                                timestamp: nil, sequence: withSequences ? 99_999 : nil)],
                         token: "99999", hasMore: false, epoch: "0001")
        }
        let transportB = ScriptedTransport(push: { await server.push($0) }, pull: { await server.pull($0) })
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transportA, configuration: makeConfiguration(clock: clock))
        let b = try OfflineStore<Note>(name: "b", storage: InMemoryStorage(), transport: transportB, configuration: makeConfiguration(clock: clock))
        try await b.save(Note(id: "n", text: "B1"))
        try await b.sync()
        try await a.sync()
        #expect(await a.record("n")?.text == "B1")

        // One request answered by the other deployment: the check asks the server, which has no
        // epoch, and the page is dropped.
        forged.withLock { $0 = 1 }
        try await a.sync()
        #expect(await a.state.serverEpoch == nil)
        #expect(await a.record("n")?.text == "B1")
        #expect(await a.state.entries["n"]?.revision?.hasPrefix("staging") == false)

        try await b.save(Note(id: "n", text: "B2"))
        try await b.save(Note(id: "m", text: "B's new note"))
        try await b.sync()
        var failures = 0
        for round in 0..<6 {
            clock.advance(by: 120)
            if round == 3 { try await a.resetChangeToken(); try await a.retryFailedChanges() }
            do { try await a.sync() } catch { failures += 1 }
        }
        #expect(failures == 0, "one forged page locks the store out of its server for good")
        #expect(await a.record("m")?.text == "B's new note")
        #expect(await a.record("n")?.text == "B2")

        try await a.save(Note(id: "n", text: "A's edit"))
        for _ in 0..<4 {
            clock.advance(by: 120)
            _ = try? await a.sync()
        }
        #expect(await server.text("n") == "A's edit")
        #expect(await a.failedChanges().isEmpty)
    }

    /// The same with a page that brings nothing but the epoch.
    @Test func anEmptyForgedPageWithAnEpochLocksOut() async throws {
        let clock = TestClock()
        let server = EpochlessServer(sendsSequences: false)
        let forged = OSAllocatedUnfairLock(initialState: 0)
        let transport = forging(server, forged) { token in PullResponse(changes: [], token: token, hasMore: false, epoch: "x") }
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport, configuration: makeConfiguration(clock: clock))
        try await a.sync()
        forged.withLock { $0 = 1 }
        try await a.sync()
        #expect(await a.state.serverEpoch == nil)
        _ = await server.push([OutgoingChange(id: UUID(), recordID: "n", operation: .upsert(Note(id: "n", text: "B")),
                                              timestamp: HLCTimestamp(wallTime: 1, nodeID: "b"), baseRevision: nil)])
        var failures = 0
        for _ in 0..<5 {
            clock.advance(by: 120)
            do { try await a.sync() } catch { failures += 1 }
        }
        #expect(failures == 0)
        #expect(await a.record("n")?.text == "B")
    }

    /// A new store's very first page comes from the other deployment. Nothing of the store's can
    /// be overwritten, so the page is taken, but its epoch counts as reported once: the server's
    /// pages without an epoch are not refused for it, and once both requests of a sync agree,
    /// the store starts a new history with the server.
    @Test(arguments: [false, true])
    func aNewStoreLeavesAFirstEpochThatOneRequestReported(withSequences: Bool) async throws {
        let clock = TestClock()
        let server = EpochlessServer(sendsSequences: withSequences)
        _ = await server.push([OutgoingChange(id: UUID(), recordID: "n", operation: .upsert(Note(id: "n", text: "real")),
                                              timestamp: HLCTimestamp(wallTime: 1, nodeID: "b"), baseRevision: nil)])
        let forged = OSAllocatedUnfairLock(initialState: 1)
        let transport = forging(server, forged) { _ in
            PullResponse(changes: [RemoteChange(recordID: "n", record: Note(id: "n", text: "staging copy"), revision: "staging.7",
                                                timestamp: nil, sequence: withSequences ? 99_999 : nil)],
                         token: "99999", hasMore: false, epoch: "0001")
        }
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport, configuration: makeConfiguration(clock: clock))
        try await a.sync()
        #expect(await a.state.serverEpoch == "0001")
        #expect(await a.state.epochIsConfirmed == false)

        try await a.sync()
        #expect(await a.state.serverEpoch == nil)
        #expect(await a.record("n")?.text == "real")

        try await a.save(Note(id: "n", text: "A's edit"))
        for _ in 0..<3 {
            clock.advance(by: 120)
            try await a.sync()
        }
        #expect(await server.text("n") == "A's edit")
        #expect(await a.failedChanges().isEmpty)
    }

    /// A new store's first epoch from its real server counts once another request reports it,
    /// the next page of the same pull or the next sync; from then on a page without an epoch
    /// is refused.
    @Test func aFirstEpochIsConfirmedByTheNextRequest() async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        let withoutEpoch = OSAllocatedUnfairLock(initialState: false)
        let transport = ScriptedTransport(push: { try await server.push($0) }, pull: { token in
            let page = try await server.pull(since: token)
            guard withoutEpoch.withLock({ $0 }) else { return page }
            return PullResponse(changes: page.changes, token: page.token, hasMore: page.hasMore)
        })
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport, configuration: makeConfiguration(clock: clock))
        await server.write(Note(id: "n", text: "one"))
        try await a.sync()
        let epoch = await a.state.serverEpoch
        #expect(epoch != nil)
        #expect(await a.state.epochIsConfirmed == false)
        try await a.sync()
        #expect(await a.state.epochIsConfirmed == true)

        withoutEpoch.withLock { $0 = true }
        await #expect(throws: OfflineFirstError.self) { try await a.sync() }
        #expect(await a.state.serverEpoch == epoch)
        #expect(await a.record("n")?.text == "one")
    }

    /// A server that starts to report epochs keeps its history: once two requests name the
    /// first epoch, the store holds it and goes on after its token, without pulling everything
    /// again or starting a new history.
    @Test func aServerThatStartsToReportEpochsIsFollowedAfterTheToken() async throws {
        let clock = TestClock()
        let server = EpochlessServer(sendsSequences: true)
        let epoch = OSAllocatedUnfairLock<String?>(initialState: nil)
        let tokens = OSAllocatedUnfairLock<[String?]>(initialState: [])
        let transport = ScriptedTransport(push: { await server.push($0) }, pull: { token in
            tokens.withLock { $0.append(token) }
            let page = await server.pull(token)
            return PullResponse(changes: page.changes, token: page.token, hasMore: page.hasMore, epoch: epoch.withLock { $0 })
        })
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport, configuration: makeConfiguration(clock: clock))
        try await a.save(Note(id: "n", text: "one"))
        try await a.sync()
        let history = await a.state.history
        let token = await a.state.token
        #expect(token != nil)

        epoch.withLock { $0 = "1" }
        _ = await server.push([OutgoingChange(id: UUID(), recordID: "m", operation: .upsert(Note(id: "m", text: "B's note")),
                                              timestamp: HLCTimestamp(wallTime: 1, nodeID: "b"), baseRevision: nil)])
        tokens.withLock { $0 = [] }
        try await a.sync()
        // The pull with the token, and the pull from the beginning that checks the epoch.
        #expect(tokens.withLock { $0 } == [token, nil])
        #expect(await a.state.serverEpoch == "1")
        #expect(await a.state.history == history)
        #expect(await a.record("m")?.text == "B's note")
        #expect(await a.state.token == "2")

        // Held after two requests, the epoch is now required on every page.
        epoch.withLock { $0 = nil }
        await #expect(throws: OfflineFirstError.self) { try await a.sync() }
        #expect(await a.state.serverEpoch == "1")
    }
}
