import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A feed server that also serves pages from earlier states, as a lagging replica or a cache
/// does, and answers a change ID it saw before from its memory. Sequences and change IDs are
/// optional, as the protocol allows.
private actor ReplicatedServer {
    struct Stored { var record: Note?; var revision: String; var sequence: Int; var timestamp: HLCTimestamp; var changeID: UUID }
    let sendsSequences: Bool
    let sendsChangeIDs: Bool
    private var stored: [String: Stored] = [:]
    private var sequence = 0
    private var snapshots: [Int: [String: Stored]] = [:]
    private var answers: [UUID: PushOutcome<Note>] = [:]

    init(sendsSequences: Bool, sendsChangeIDs: Bool) {
        self.sendsSequences = sendsSequences
        self.sendsChangeIDs = sendsChangeIDs
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

    func text(_ id: String) -> String? { stored[id]?.record?.text }

    private func page(after token: String?, of data: [String: Stored]) -> PullResponse<Note> {
        let after = token.flatMap { Int($0) } ?? 0
        let changed = data.filter { $0.value.sequence > after }.sorted { $0.value.sequence < $1.value.sequence }
        return PullResponse(changes: changed.map { remote($0.key, $0.value) }, token: "\(changed.last?.value.sequence ?? after)",
                            hasMore: false)
    }

    private func remote(_ id: String, _ version: Stored) -> RemoteChange<Note> {
        RemoteChange(recordID: id, record: version.record, revision: version.revision, timestamp: version.timestamp,
                     sequence: sendsSequences ? UInt64(version.sequence) : nil, changeID: sendsChangeIDs ? version.changeID : nil)
    }
}

/// An accepted push answer and a version a pull kept back while the change was in doubt
/// (``StoredEntry/deferredRemote``). The answer follows the rule of every push answer: the
/// kept-back version takes the write's place only when the server's sequences show it is newer.
/// `accept()` used to take it whenever it was another version, so a stale page that a pull kept
/// back replaced the device's own accepted write, and the next edit on it dropped what the write
/// held. When nothing orders the two, the store keeps its write and the next sync pulls from the
/// beginning, which brings a newer version if the server holds one.
@Suite("An accepted push answer and a version kept back for its change")
struct AcceptedAnswerTests {
    /// Verifier A11's probe. A server without sequences; A's edit is in doubt, its request lost
    /// before the server. After resetChangeToken() a cache answers the pull from the beginning
    /// with an old page, kept back for the push. The next push is accepted, and the pull of that
    /// sync comes from a replica that sticks to the device, or fails. The device shows its own
    /// write, and an edit on it keeps what that write held.
    @Test(arguments: [(false, false), (true, false), (true, true)])
    func anAcceptedAnswerLosesToAStalePageKeptBack(changeIDs: Bool, pullFails: Bool) async throws {
        let clock = TestClock()
        let server = ReplicatedServer(sendsSequences: false, sendsChangeIDs: changeIDs)
        let pushMode = OSAllocatedUnfairLock(initialState: 0) // 2 lost before the server
        let pullMode = OSAllocatedUnfairLock(initialState: 0) // 3 cache from the beginning, 4 sticky stale replica
        let transportA = ScriptedTransport(push: { changes in
            if pushMode.withLock({ $0 }) == 2 { throw URLError(.networkConnectionLost) }
            return await server.push(changes)
        }, pull: { token in
            switch pullMode.withLock({ $0 }) {
            case 3: return await server.stalePull(nil, at: 1)
            case 4:
                if pullFails { throw URLError(.networkConnectionLost) }
                return await server.stalePull(token, at: 1)
            default: return await server.pull(token)
            }
        })
        let transportB = ScriptedTransport(push: { await server.push($0) }, pull: { await server.pull($0) })
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transportA, configuration: makeConfiguration(clock: clock))
        let b = try OfflineStore<Note>(name: "b", storage: InMemoryStorage(), transport: transportB, configuration: makeConfiguration(clock: clock))
        try await b.save(Note(id: "n", text: "a"))
        try await b.sync()
        clock.advance(by: 1)
        try await b.save(Note(id: "n", text: "a,b"))
        try await b.sync()
        try await a.sync()
        clock.advance(by: 1)
        try await a.save(Note(id: "n", text: "a,b,c"))
        pushMode.withLock { $0 = 2 }
        _ = try? await a.sync()
        pushMode.withLock { $0 = 0 }
        try await a.resetChangeToken()
        pullMode.withLock { $0 = 3 }
        try await a.sync()
        #expect(await a.record("n")?.text == "a,b,c")

        clock.advance(by: 120)
        pullMode.withLock { $0 = 4 }
        _ = try? await a.sync()
        #expect(await server.text("n") == "a,b,c")
        #expect(await a.record("n")?.text == "a,b,c", "after an accepted push the device shows a stale page instead of its own write")

        // The user edits what the app shows.
        try await a.save(Note(id: "n", text: (await a.record("n")?.text ?? "") + ",x"))
        pullMode.withLock { $0 = 0 }
        for _ in 0..<4 {
            clock.advance(by: 120)
            _ = try? await a.sync()
        }
        try await b.sync()
        #expect(await server.text("n") == "a,b,c,x", "an edit on the stale copy dropped b and c")
        #expect(await a.record("n")?.text == "a,b,c,x")
        #expect(await b.record("n")?.text == "a,b,c,x")
        #expect(await a.pendingChanges().isEmpty)
    }

    /// The other way round: A#1 is applied and its answer lost; B pulls it and writes B#2 on
    /// top, and A pulls B#2 while A#1 is in doubt. The next push of A#1 is answered from the
    /// server's memory: accepted. The kept-back version is the newer one here, but a push answer
    /// names no epoch, so its sequence cannot show that (after a restart that lost the data the
    /// answer may come from a later history): the store shows its own write, and the next sync
    /// pulls from the beginning and brings B#2. No resolver is asked, and every device ends with
    /// the server's version.
    @Test(arguments: ScenarioPolicy.allCases, KeptBackVersionTests.options)
    func anAcceptedAnswerFromMemoryGivesWayToTheNewerVersionPulledSince(policy: ScenarioPolicy, options: ScenarioOptions) async throws {
        let world = ScenarioWorld(policy: policy, options: options)
        let a = try world.device("A")
        let b = try world.device("B", seed: 2)
        _ = try await b.store.scenarioSave(Note(id: "t", text: "B#0"))
        #expect(await scenarioSync(b.store) == nil)
        #expect(await scenarioSync(a.store) == nil)
        world.clock.advance(by: 5)
        _ = try await a.store.scenarioSave(Note(id: "t", text: "A#1"))
        await a.network.loseNextAnswers(1)
        _ = await scenarioSync(a.store)
        #expect(await scenarioSync(b.store) == nil)
        #expect(await b.store.record("t")?.text == "A#1")
        world.clock.advance(by: 5)
        _ = try await b.store.scenarioSave(Note(id: "t", text: "B#2"))
        #expect(await scenarioSync(b.store) == nil)
        // A#1 waits for its retry date; this sync only pulls B#2, which waits for A#1's push.
        _ = await scenarioSync(a.store)
        world.clock.advance(by: 120)
        #expect(await scenarioSync(a.store) == nil)
        #expect(await a.store.pendingChanges().isEmpty)
        #expect(await a.store.record("t")?.text == "A#1")
        // The app restarts; the pull from the beginning is still due.
        try a.reopen()
        #expect(await scenarioSync(a.store) == nil)
        #expect(await a.store.record("t")?.text == "B#2", "\(policy) \(options): A keeps its older write")
        for _ in 0..<2 {
            world.clock.advance(by: 120)
            _ = await scenarioSync(a.store)
            _ = await scenarioSync(b.store)
        }
        #expect(world.conflicts.all.isEmpty, "\(policy) \(options): the resolver was asked: \(world.conflicts.all)")
        #expect(world.ownWriteViolations().isEmpty, "\(world.ownWriteViolations())")
        #expect(await world.server.text("t") == "B#2")
        #expect(await a.store.record("t")?.text == "B#2")
        #expect(await b.store.record("t")?.text == "B#2")
    }
}
