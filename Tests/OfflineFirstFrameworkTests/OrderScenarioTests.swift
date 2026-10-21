import Foundation
import Testing
@testable import OfflineFirstFramework

@Suite("Scenarios: pages out of order")
struct OrderScenarioTests {
    /// A lagging replica of the same epoch serves older versions of every record while the
    /// device holds newer ones and an edit waits.
    @Test(arguments: ScenarioPolicy.allCases, [true, false])
    func laggingReplicaOfTheSameEpoch(policy: ScenarioPolicy, sequences: Bool) async throws {
        // Without sequences only last write wins and a merge are ordered by the store.
        guard sequences || policy == .lastWriteWins || policy == .merge else { return }
        let world = ScenarioWorld(policy: policy, options: ScenarioOptions(sequences: sequences, changeIDs: true), pageSize: 2)
        let a = try world.device("A")
        let x = HLCTimestamp(wallTime: 1_699_999_000_000, counter: 0, nodeID: "X")
        await world.server.write("r", "X#r1", at: x)
        await world.server.write("s", "X#s1", at: x)
        let lagging = await world.server.snapshot()
        let later = HLCTimestamp(wallTime: 1_699_999_500_000, counter: 0, nodeID: "X")
        await world.server.write("r", "X#r2", at: later)
        await world.server.write("s", "X#s2", at: later)
        try await a.store.sync()
        _ = try await a.store.scenarioSave(Note(id: "r", text: "A#1"))
        await a.network.failNextPushes(unsent: 1)
        _ = await scenarioSync(a.store)
        try await a.store.resetChangeToken()
        await a.network.setReplica(lagging, pulls: 1_000)
        for _ in 0..<3 { _ = await scenarioSync(a.store) }
        #expect(await a.store.record("s")?.text == "X#s2", "a record without a pending change went back")
        #expect(await a.store.record("r")?.text == "A#1")
        #expect(world.conflicts.all.isEmpty, "the stale version reached the resolver: \(world.conflicts.all)")
        await a.network.setReplica(nil, pulls: 0)
        world.clock.advance(by: 120)
        try await a.store.sync()
        #expect(await world.server.text("r") == "A#1")
        #expect(world.conflicts.all.isEmpty, "\(world.conflicts.all)")
    }

    /// One page that lists the newer version first and the older one after it.
    @Test(arguments: ScenarioPolicy.allCases)
    func olderVersionAfterTheNewerOneInOnePage(policy: ScenarioPolicy) async throws {
        let conflicts = ScenarioLines()
        let violations = ScenarioLines()
        let node = ScenarioText()
        let newer = RemoteChange(recordID: "r", record: Note(id: "r", text: "X#2"), revision: "e.2",
                                 timestamp: HLCTimestamp(wallTime: 1_699_999_900_000, counter: 0, nodeID: "X"), sequence: 2)
        let older = RemoteChange(recordID: "r", record: Note(id: "r", text: "X#1"), revision: "e.1",
                                 timestamp: HLCTimestamp(wallTime: 1_699_999_800_000, counter: 0, nodeID: "X"), sequence: 1)
        let transport = ScriptedTransport(
            push: { changes in Dictionary(uniqueKeysWithValues: changes.map { ($0.id, .accepted(revision: "e.3")) }) },
            pull: { token in
                token == nil ? PullResponse(changes: [newer, older], token: "t1", hasMore: false, epoch: "e")
                    : PullResponse(changes: [], token: token, hasMore: false, epoch: "e")
            })
        let clock = TestClock()
        let store = try OfflineStore<Note>(
            name: "order", storage: InMemoryStorage(), transport: transport,
            configuration: .init(conflictResolver: scenarioResolver(policy, device: "A", nodeID: node, conflicts: conflicts,
                                                                    violations: violations, merges: ScenarioCounter()),
                                 now: { clock.now }))
        try await store.sync()
        #expect(await store.record("r")?.text == "X#2")
    }
}

@Suite("Scenarios: local changes during a pull, two syncs")
struct ConcurrencyScenarioTests {
    static let flags: [(Bool, Bool)] = [(false, false), (false, true), (true, false), (true, true)]

    @Test(arguments: ScenarioPolicy.allCases, flags)
    func localChangeDuringPull(policy: ScenarioPolicy, flags: (Bool, Bool)) async throws {
        let (deleting, restartFirst) = flags
        let world = ScenarioWorld(policy: policy)
        let a = try world.device("A")
        let b = try world.device("B", seed: 2)
        _ = try await a.store.scenarioSave(Note(id: "r", text: "A#1"))
        try await a.store.sync()
        try await b.store.sync()
        world.clock.advance(by: 1)
        _ = try await b.store.scenarioSave(Note(id: "r", text: "B#1"))
        try await b.store.sync()
        if restartFirst { await world.server.restart() }
        world.clock.advance(by: 1)
        let store = a.store
        await a.network.setPullHook {
            if deleting { _ = try? await store.scenarioDelete("r") } else { _ = try? await store.scenarioSave(Note(id: "r", text: "A#2")) }
        }
        _ = await scenarioSync(a.store)
        for _ in 0..<3 {
            _ = await scenarioSync(a.store)
            _ = await scenarioSync(b.store)
        }
        let serverText = await world.server.text("r")
        let expected: String? = switch (policy, deleting) {
        case (.serverWins, _): "B#1"
        case (.clientWins, false), (.lastWriteWins, false): "A#2"
        case (.clientWins, true), (.lastWriteWins, true), (.merge, true): nil
        case (.merge, false): serverText.flatMap { $0.hasPrefix("A#M") ? $0 : nil } ?? "A#M?"
        }
        #expect(serverText == expected, "\(world.conflicts.all)")
        #expect(await a.store.record("r")?.text == serverText)
        #expect(await b.store.record("r")?.text == serverText)
        #expect(world.conflicts.all.count == 1, "the policy must meet the conflict once: \(world.conflicts.all)")
        #expect(world.ownWriteViolations().isEmpty, "\(world.ownWriteViolations())")
        #expect(await a.store.pendingChanges().isEmpty)
    }

    /// Two syncs at once, a save between them, answers lost: each local version reaches the
    /// server once.
    @Test(arguments: ScenarioPolicy.allCases, [false, true])
    func twoSyncsAtOnce(policy: ScenarioPolicy, loseAnswer: Bool) async throws {
        let world = ScenarioWorld(policy: policy)
        let a = try world.device("A")
        await a.network.setYields(6)
        for index in 0..<5 { _ = try await a.store.scenarioSave(Note(id: "n\(index)", text: "A#\(index)")) }
        if loseAnswer { await a.network.loseNextAnswers(1) }
        let store = a.store
        async let first = scenarioSync(store)
        async let second = scenarioSync(store)
        await Task.yield()
        _ = try await store.scenarioSave(Note(id: "n0", text: "A#0b"))
        _ = await (first, second)
        world.clock.advance(by: 120)
        for _ in 0..<3 { _ = await scenarioSync(store) }
        let commits = await world.server.commits
        let texts = commits.compactMap(\.text)
        #expect(Set(texts).count == texts.count, "a version was applied twice: \(texts)")
        #expect(await world.server.records() == Dictionary(uniqueKeysWithValues: (await store.records()).map { ($0.id, $0.text) }))
        #expect(await world.server.text("n0") == "A#0b")
        #expect(await store.pendingChanges().isEmpty)
        #expect(world.conflicts.all.isEmpty, "\(world.conflicts.all)")
    }
}

@Suite("Scenarios: every crash point of a sync")
struct CrashScenarioTests {
    private struct Outcome: Equatable {
        var server: [String: String]
        var device: [String: String]
    }

    private static func normalized(_ records: [String: String]) -> [String: String] {
        records.mapValues { $0.contains("#M") ? String($0.prefix(while: { $0 != "M" })) + "M" : $0 }
    }

    private func run(policy: ScenarioPolicy, crashAfter: Int?, loseAnswer: Bool, restartAfterPush: Bool,
                     violations: ScenarioLines) async throws -> (Outcome, Bool) {
        let world = ScenarioWorld(policy: policy, pageSize: 1)
        let a = try world.device("A")
        let x = try world.device("X", seed: 3)
        for id in ["a", "b", "c", "d"] { _ = try await x.store.scenarioSave(Note(id: id, text: "X#\(id)1")) }
        try await x.store.sync()
        try await a.store.sync()
        world.clock.advance(by: 1)
        _ = try await x.store.scenarioSave(Note(id: "b", text: "X#b2"))
        _ = try await x.store.scenarioSave(Note(id: "d", text: "X#d2"))
        _ = try await x.store.scenarioSave(Note(id: "e", text: "X#e1"))
        try await x.store.sync()
        world.clock.advance(by: 1)
        _ = try await a.store.scenarioSave(Note(id: "a", text: "A#a"))
        _ = try await a.store.scenarioSave(Note(id: "b", text: "A#b"))
        _ = try await a.store.scenarioDelete("c")
        _ = try await a.store.scenarioSave(Note(id: "f", text: "A#f"))
        if loseAnswer { await a.network.loseNextAnswers(1) }
        if restartAfterPush { await a.network.setRestartAfterPush(100) }
        if let crashAfter { a.storage.arm(afterWrites: crashAfter) }
        _ = await scenarioSync(a.store)
        await a.network.setRestartAfterPush(0)
        var crashed = a.storage.isDead
        if crashed { try a.reopen() }
        for _ in 0..<6 {
            world.clock.advance(by: 120)
            try? await a.store.retryFailedChanges()
            _ = await scenarioSync(a.store)
            if a.storage.isDead {
                crashed = true
                try a.reopen()
            }
            _ = await scenarioSync(x.store)
        }
        for line in world.violations.all { violations.add(line) }
        let commits = await world.server.commits
        let texts = commits.compactMap(\.text).filter { $0.hasPrefix("A#") && !$0.contains("#M") }
        if Set(texts).count != texts.count {
            violations.add("crash \(String(describing: crashAfter)): a version was applied twice: \(texts)")
        }
        if !(await a.store.pendingChanges().isEmpty) {
            let pending = await a.store.pendingChanges().map(\.recordID)
            violations.add("crash \(String(describing: crashAfter)): changes still pending: \(pending)")
        }
        let device = Dictionary(uniqueKeysWithValues: (await a.store.records()).map { ($0.id, $0.text) })
        let other = Dictionary(uniqueKeysWithValues: (await x.store.records()).map { ($0.id, $0.text) })
        let server = await world.server.records()
        if device != server || other != server {
            violations.add("crash \(String(describing: crashAfter)): not converged server=\(server) A=\(device) X=\(other)")
        }
        return (Outcome(server: Self.normalized(server), device: Self.normalized(device)), crashed)
    }

    static let flags: [(Bool, Bool)] = [(false, false), (false, true), (true, false), (true, true)]

    @Test(arguments: ScenarioPolicy.allCases, flags)
    func everyCrashPoint(policy: ScenarioPolicy, flags: (Bool, Bool)) async throws {
        let (loseAnswer, restartAfterPush) = flags
        let violations = ScenarioLines()
        let (reference, _) = try await run(policy: policy, crashAfter: nil, loseAnswer: loseAnswer, restartAfterPush: restartAfterPush,
                                           violations: violations)
        var crashes = 0
        for point in 0..<30 {
            let (outcome, crashed) = try await run(policy: policy, crashAfter: point, loseAnswer: loseAnswer,
                                                   restartAfterPush: restartAfterPush, violations: violations)
            if crashed { crashes += 1 }
            #expect(outcome == reference, "crash after write \(point): \(outcome) vs \(reference)")
        }
        #expect(crashes > 5)
        #expect(violations.all.isEmpty, "\(violations.all)")
    }
}
