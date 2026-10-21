import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A feed server that also serves pages from earlier states, as a lagging replica or a cache
/// does, and answers a change ID it saw before from its memory.
private actor SnapshotServer {
    struct Stored { var record: Note?; var revision: String; var sequence: Int; var timestamp: HLCTimestamp; var changeID: UUID? }
    let sendsSequences: Bool
    private var stored: [String: Stored] = [:]
    private var sequence = 0
    private var snapshots: [Int: [String: Stored]] = [:]
    private var answers: [UUID: PushOutcome<Note>] = [:]

    init(sendsSequences: Bool) { self.sendsSequences = sendsSequences }

    private func remote(_ id: String, _ version: Stored) -> RemoteChange<Note> {
        RemoteChange(recordID: id, record: version.record, revision: version.revision, timestamp: version.timestamp,
                     sequence: sendsSequences ? UInt64(version.sequence) : nil, changeID: version.changeID)
    }

    func push(_ changes: [OutgoingChange<Note>]) -> [UUID: PushOutcome<Note>] {
        var outcomes: [UUID: PushOutcome<Note>] = [:]
        for change in changes {
            if let answer = answers[change.id] {
                outcomes[change.id] = answer
                continue
            }
            let answer: PushOutcome<Note>
            if let current = stored[change.recordID], current.revision != change.baseRevision {
                answer = .conflict(current: remote(change.recordID, current))
            } else {
                sequence += 1
                stored[change.recordID] = Stored(record: change.record, revision: "v\(sequence)", sequence: sequence,
                                                 timestamp: change.timestamp, changeID: change.id)
                answer = .accepted(revision: "v\(sequence)")
            }
            answers[change.id] = answer
            outcomes[change.id] = answer
        }
        snapshots[sequence] = stored
        return outcomes
    }

    func pull(_ token: String?) -> PullResponse<Note> { page(after: token, of: stored) }

    /// A page as a replica that stopped at `sequence` serves it.
    func stalePull(_ token: String?, at sequence: Int) -> PullResponse<Note> { page(after: token, of: snapshots[sequence] ?? [:]) }

    private func page(after token: String?, of data: [String: Stored]) -> PullResponse<Note> {
        let after = token.flatMap { Int($0) } ?? 0
        let changed = data.filter { $0.value.sequence > after }.sorted { $0.value.sequence < $1.value.sequence }
        return PullResponse(changes: changed.map { remote($0.key, $0.value) }, token: "\(changed.last?.value.sequence ?? after)",
                            hasMore: false)
    }

    func text(_ id: String) -> String? { stored[id]?.record?.text }
    var currentSequence: Int { sequence }
}

/// Union of comma-separated items, the kind of merge the docs show for checklists.
private func unionMerge(_ local: Note, _ remote: Note) -> Note {
    let items = Set(local.text.split(separator: ",").map(String.init)).union(remote.text.split(separator: ",").map(String.init))
    return Note(id: local.id, text: items.sorted().joined(separator: ","))
}

/// A version a pull keeps back for a change in doubt (``StoredEntry/deferredRemote``) and the
/// conflict answer of the change's next push. The answer decides: a version the device wrote
/// itself is not a conflict whatever the pull kept back, and the kept-back version takes the
/// answer's place only when the server's sequences show it is newer. Without sequences the
/// kept-back version may come from a stale page and the answer from the server's memory of
/// change IDs, so the change goes out again for a fresh answer, and the resolver meets the
/// server's current version.
@Suite("A version kept back for a change in doubt and its push's answer")
struct KeptBackVersionTests {
    static let options: [ScenarioOptions] = [
        ScenarioOptions(sequences: false, changeIDs: true), ScenarioOptions(sequences: false, changeIDs: false),
        ScenarioOptions(sequences: true, changeIDs: true), ScenarioOptions(sequences: true, changeIDs: false),
    ]

    /// A#1 is applied and its answer lost; A#2 on top of it gets a conflict answer naming A#1,
    /// lost too. While A#2 waits, a lagging replica brings B's old version. The next push is
    /// answered from the server's memory with A#1, the device's own write: A#2 goes out on it.
    @Test(arguments: ScenarioPolicy.allCases, Self.options)
    func anAnswerThatNamesAnOwnWriteOutweighsAStaleKeptBackVersion(policy: ScenarioPolicy, options: ScenarioOptions) async throws {
        let world = ScenarioWorld(policy: policy, options: options)
        let a = try world.device("A")
        let b = try world.device("B", seed: 2)
        _ = try await b.store.scenarioSave(Note(id: "t", text: "B#0a"))
        #expect(await scenarioSync(b.store) == nil)
        let early = await world.server.snapshot()
        world.clock.advance(by: 5)
        _ = try await b.store.scenarioSave(Note(id: "t", text: "B#0b"))
        #expect(await scenarioSync(b.store) == nil)
        world.clock.advance(by: 5)
        #expect(await scenarioSync(a.store) == nil)
        #expect(await a.store.record("t")?.text == "B#0b")
        world.clock.advance(by: 5)
        _ = try await a.store.scenarioSave(Note(id: "t", text: "A#1"))
        await a.network.loseNextAnswers(1)
        _ = await scenarioSync(a.store)
        world.clock.advance(by: 5)
        _ = try await a.store.scenarioSave(Note(id: "t", text: "A#2"))
        await a.network.loseNextAnswers(1)
        _ = await scenarioSync(a.store)
        #expect(await world.server.text("t") == "A#1")
        // A#2 waits for its retry date; this sync only pulls, and a lagging replica answers.
        await a.network.setReplica(early, pulls: 1)
        _ = await scenarioSync(a.store)
        for _ in 0..<4 {
            world.clock.advance(by: 120)
            _ = await scenarioSync(a.store)
            _ = await scenarioSync(b.store)
        }
        let onServer = await world.server.text("t")
        #expect(world.ownWriteViolations().isEmpty, "\(world.ownWriteViolations())")
        #expect(onServer == "A#2", "\(policy) \(options): the last edit was lost: server=\(onServer ?? "nil") resolver=\(world.conflicts.all)")
        #expect(world.conflicts.all.isEmpty, "\(policy) \(options): the resolver was asked: \(world.conflicts.all)")
        #expect(await a.store.pendingChanges().isEmpty)
        #expect(await a.store.record("t")?.text == onServer)
        #expect(await b.store.record("t")?.text == onServer)
    }

    /// A's push of A#1 meets B#1, and the conflict answer is lost. B writes B#2, and A pulls it
    /// while A#1 is in doubt. The server answers A#1's next push from its memory, with B#1:
    /// the resolver meets B#2, the server's current version, and every device ends with what
    /// the server holds.
    @Test(arguments: ScenarioPolicy.allCases, Self.options)
    func aRememberedAnswerMeetsTheNewerVersionPulledSince(policy: ScenarioPolicy, options: ScenarioOptions) async throws {
        let world = ScenarioWorld(policy: policy, options: options)
        let a = try world.device("A")
        let b = try world.device("B", seed: 2)
        _ = try await b.store.scenarioSave(Note(id: "t", text: "B#0"))
        #expect(await scenarioSync(b.store) == nil)
        #expect(await scenarioSync(a.store) == nil)
        world.clock.advance(by: 5)
        _ = try await a.store.scenarioSave(Note(id: "t", text: "A#1"))
        _ = try await b.store.scenarioSave(Note(id: "t", text: "B#1"))
        #expect(await scenarioSync(b.store) == nil)
        await a.network.loseNextAnswers(1)
        _ = await scenarioSync(a.store)
        world.clock.advance(by: 5)
        _ = try await b.store.scenarioSave(Note(id: "t", text: "B#2"))
        #expect(await scenarioSync(b.store) == nil)
        // A#1 waits for its retry date; this sync only pulls B#2.
        _ = await scenarioSync(a.store)
        for _ in 0..<4 {
            world.clock.advance(by: 120)
            _ = await scenarioSync(a.store)
            _ = await scenarioSync(b.store)
        }
        let calls = world.conflicts.all
        #expect(world.ownWriteViolations().isEmpty, "\(world.ownWriteViolations())")
        #expect(calls.first == "A t: local=A#1 remote=B#2", "\(policy) \(options): \(calls)")
        #expect(!calls.contains { $0.hasSuffix("remote=B#1") }, "\(policy) \(options): the resolver met the remembered answer: \(calls)")
        #expect(await a.store.pendingChanges().isEmpty)
        let onServer = await world.server.text("t")
        #expect(await a.store.record("t")?.text == onServer, "\(policy) \(options): A differs from the server")
        #expect(await b.store.record("t")?.text == onServer)
    }

    /// A pushes an edit whose request is lost before the server. B removes an item. A replica
    /// that lags behind B's removal answers A's pull while A's change is in doubt. The resolver
    /// meets the version the server's conflict answer names, so B's removal stays.
    @Test(arguments: [false, true])
    func aStalePageWhileInDoubtMeetsTheResolver(withSequences: Bool) async throws {
        let clock = TestClock()
        let server = SnapshotServer(sendsSequences: withSequences)
        let seen = OSAllocatedUnfairLock<[String]>(initialState: [])
        let resolver = ConflictResolver<Note> { conflict in
            seen.withLock { $0.append(conflict.remote?.text ?? "nil") }
            guard let local = conflict.local, let remote = conflict.remote else { return .keepRemote }
            return .merged(unionMerge(local, remote))
        }
        let mode = OSAllocatedUnfairLock(initialState: 0) // 0 normal, 1 lose the push, 2 stale pull
        let staleAt = OSAllocatedUnfairLock(initialState: 0)
        let transportA = ScriptedTransport(push: { changes in
            if mode.withLock({ $0 }) == 1 { throw URLError(.networkConnectionLost) }
            return await server.push(changes)
        }, pull: { token in
            if mode.withLock({ $0 }) == 2 { return await server.stalePull(token, at: staleAt.withLock { $0 }) }
            return await server.pull(token)
        })
        let transportB = ScriptedTransport(push: { await server.push($0) }, pull: { await server.pull($0) })
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transportA,
                                       configuration: makeConfiguration(clock: clock, resolver: resolver, retry: RetryPolicy()))
        let b = try OfflineStore<Note>(name: "b", storage: InMemoryStorage(), transport: transportB,
                                       configuration: makeConfiguration(clock: clock))
        try await b.save(Note(id: "x", text: "a,b"))
        try await b.sync()
        try await a.sync()
        clock.advance(by: 1)
        try await b.save(Note(id: "x", text: "a,b,d"))
        try await b.sync()
        let staleSequence = await server.currentSequence
        staleAt.withLock { $0 = staleSequence }
        clock.advance(by: 1)
        try await b.save(Note(id: "x", text: "a,d"))
        try await b.sync()

        clock.advance(by: 1)
        try await a.save(Note(id: "x", text: "a,c"))
        mode.withLock { $0 = 1 }
        _ = try? await a.sync()
        mode.withLock { $0 = 2 }
        _ = try? await a.sync()
        mode.withLock { $0 = 0 }
        clock.advance(by: 600)
        for _ in 0..<6 {
            _ = try? await a.sync()
            clock.advance(by: 600)
        }
        try await b.sync()
        #expect(seen.withLock { $0 }.first == "a,d", "the resolver met a stale page, not the server's conflict answer: \(seen.withLock { $0 })")
        #expect(await server.text("x") == "a,c,d", "B's removal of b was undone by the stale copy")
        #expect(await a.record("x")?.text == "a,c,d")
        #expect(await b.record("x")?.text == "a,c,d")
        #expect(await a.pendingChanges().isEmpty)
    }

    /// A1 is applied but its answer is lost; A2, made on top of A1, goes out and its request is
    /// lost before it reaches the server. After resetChangeToken() a cache answers the pull from
    /// the beginning with an old page. The push answer names A1, the device's own write: A2 goes
    /// out on it without the resolver.
    @Test(arguments: [(false, false), (false, true), (true, false), (true, true)])
    func aCachedPageAfterAResetDecidesTheLastEdit(withSequences: Bool, withStalePage: Bool) async throws {
        let clock = TestClock()
        let server = SnapshotServer(sendsSequences: withSequences)
        let asked = OSAllocatedUnfairLock<[String]>(initialState: [])
        let resolver = ConflictResolver<Note> { conflict in
            asked.withLock { $0.append(conflict.remote?.text ?? "nil") }
            return .keepRemote
        }
        let mode = OSAllocatedUnfairLock(initialState: 0) // 1 apply and lose the answer, 2 lose before the server, 3 cached page
        let transportA = ScriptedTransport(push: { changes in
            switch mode.withLock({ $0 }) {
            case 1:
                _ = await server.push(changes)
                throw URLError(.timedOut)
            case 2:
                throw URLError(.networkConnectionLost)
            default:
                return await server.push(changes)
            }
        }, pull: { token in
            if mode.withLock({ $0 }) == 3 { return await server.stalePull(nil, at: 1) }
            return await server.pull(token)
        })
        let transportB = ScriptedTransport(push: { await server.push($0) }, pull: { await server.pull($0) })
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transportA,
                                       configuration: makeConfiguration(clock: clock, resolver: resolver, retry: RetryPolicy()))
        let b = try OfflineStore<Note>(name: "b", storage: InMemoryStorage(), transport: transportB,
                                       configuration: makeConfiguration(clock: clock))
        try await b.save(Note(id: "x", text: "B0"))
        try await b.sync()
        clock.advance(by: 1)
        try await b.save(Note(id: "x", text: "B1"))
        try await b.sync()
        try await a.sync()
        clock.advance(by: 1)
        try await a.save(Note(id: "x", text: "A1"))
        mode.withLock { $0 = 1 }
        _ = try? await a.sync()
        try await a.save(Note(id: "x", text: "A2"))
        mode.withLock { $0 = 2 }
        _ = try? await a.sync()
        if withStalePage {
            try await a.resetChangeToken()
            mode.withLock { $0 = 3 }
            _ = try? await a.sync()
        }
        mode.withLock { $0 = 0 }
        for _ in 0..<6 {
            clock.advance(by: 600)
            _ = try? await a.sync()
        }
        try await b.sync()
        #expect(asked.withLock { $0 }.isEmpty, "the resolver was asked although the answer named the device's own write: \(asked.withLock { $0 })")
        #expect(await server.text("x") == "A2", "the user's last edit was dropped")
        #expect(await a.record("x")?.text == "A2")
        #expect(await b.record("x")?.text == "A2")
        #expect(await a.pendingChanges().isEmpty)
    }
}
