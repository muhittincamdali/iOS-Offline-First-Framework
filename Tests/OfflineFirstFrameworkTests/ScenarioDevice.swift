import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// One device's connection: pushes always reach the server; pulls may be answered by a replica.
actor ScenarioNetwork: SyncTransport {
    typealias Record = Note
    nonisolated let serverIdentity: String? = "scenario-server"
    let server: ScenarioServer
    private var random: ScenarioRandom
    private(set) var replica: ScenarioSnapshot?
    private var replicaPulls = 0
    private var restartAfterPushPercent = 0
    private var pullHook: (@Sendable () async -> Void)?
    private var failNextPushUnsent = 0
    private var loseNextAnswers = 0
    var pageSize: Int?
    var yields = 0

    init(server: ScenarioServer, seed: UInt64 = 1) {
        self.server = server
        self.random = ScenarioRandom(seed: seed)
    }

    func setReplica(_ snapshot: ScenarioSnapshot?, pulls: Int) {
        replica = snapshot
        replicaPulls = snapshot == nil ? 0 : pulls
    }
    func setRestartAfterPush(_ percent: Int) { restartAfterPushPercent = percent }
    func setPullHook(_ hook: (@Sendable () async -> Void)?) { pullHook = hook }
    func failNextPushes(unsent count: Int) { failNextPushUnsent = count }
    func loseNextAnswers(_ count: Int) { loseNextAnswers = count }
    func setYields(_ count: Int) { yields = count }
    func setPageSize(_ size: Int?) { pageSize = size }

    private func interleave() async {
        let count = yields > 0 ? random.below(yields + 1) : 0
        for _ in 0..<count { await Task.yield() }
    }

    func push(_ changes: [OutgoingChange<Note>]) async throws -> [UUID: PushOutcome<Note>] {
        await interleave()
        if failNextPushUnsent > 0 {
            failNextPushUnsent -= 1
            throw URLError(.notConnectedToInternet)
        }
        let outcomes = await server.push(changes)
        if restartAfterPushPercent > 0, random.roll(restartAfterPushPercent) { await server.restart() }
        await interleave()
        if loseNextAnswers > 0 {
            loseNextAnswers -= 1
            throw URLError(.networkConnectionLost)
        }
        return outcomes
    }

    func pull(since token: String?) async throws -> PullResponse<Note> {
        if let hook = pullHook {
            pullHook = nil
            await hook()
        }
        await interleave()
        let size: Int
        if let pageSize { size = pageSize } else { size = await server.pageSize }
        if let replica, replicaPulls > 0 {
            replicaPulls -= 1
            if replicaPulls == 0 { self.replica = nil }
            return ScenarioServer.page(of: replica, since: token, pageSize: size, options: server.options)
        }
        return await server.pull(since: token)
    }
}

struct ScenarioStorageDied: Error {}

/// Storage whose process dies at a chosen write: that write and every later one fail until the
/// device restarts.
final class ScenarioStorage: StorageBackend {
    private struct State {
        var files: [String: Data] = [:]
        var crashAfter: Int?
        var dead = false
    }
    private let lock = OSAllocatedUnfairLock(initialState: State())

    func arm(afterWrites count: Int) { lock.withLock { $0.crashAfter = count } }
    var isDead: Bool { lock.withLock { $0.dead } }
    func revive() { lock.withLock { $0.dead = false; $0.crashAfter = nil } }

    func read(_ name: String) throws -> Data? { lock.withLock { $0.files[name] } }

    private func mayWrite(_ state: inout State) throws {
        if state.dead { throw ScenarioStorageDied() }
        if let remaining = state.crashAfter {
            if remaining <= 0 {
                state.dead = true
                state.crashAfter = nil
                throw ScenarioStorageDied()
            }
            state.crashAfter = remaining - 1
        }
    }

    func write(_ data: Data, to name: String) throws {
        try lock.withLock { state in
            try mayWrite(&state)
            state.files[name] = data
        }
    }

    func remove(_ name: String) throws {
        try lock.withLock { state in
            try mayWrite(&state)
            state.files[name] = nil
        }
    }

    func move(_ name: String, to newName: String) throws {
        try lock.withLock { state in
            try mayWrite(&state)
            state.files[newName] = state.files.removeValue(forKey: name)
        }
    }
}

extension OfflineStore where Record == Note {
    func scenarioSave(_ note: Note) throws -> HLCTimestamp {
        try save(note)
        return state.entries[note.id]!.timestamp
    }

    /// Deletes a record the server knows; nil when it is only on this device.
    func scenarioDelete(_ id: String) throws -> HLCTimestamp? {
        guard let entry = state.entries[id], entry.record != nil, entry.revision != nil || entry.wasSent else { return nil }
        try delete(id)
        return state.entries[id]?.timestamp
    }

    func scenarioEpoch() -> String? { state.serverEpoch }
    func scenarioRetired() -> [String] { state.retiredEpochs }
}

/// A resolver for `policy` that records each call and flags a remote version this device wrote.
func scenarioResolver(_ policy: ScenarioPolicy, device: String, nodeID: ScenarioText, conflicts: ScenarioLines,
                      violations: ScenarioLines, merges: ScenarioCounter) -> ConflictResolver<Note> {
    ConflictResolver { conflict in
        let remote = conflict.remote?.text ?? "<deleted>"
        let local = conflict.local?.text ?? "<deleted>"
        conflicts.add("\(device) \(conflict.recordID): local=\(local) remote=\(remote)")
        let ownText = conflict.remote.map { $0.text.hasPrefix("\(device)#") } ?? false
        let ownDeletion = conflict.remote == nil && conflict.remoteTimestamp?.nodeID == nodeID.value
        if ownText || ownDeletion {
            violations.add("\(device): resolver asked about own write \(conflict.recordID) local=\(local) remote=\(remote)")
        }
        switch policy {
        case .serverWins: return .keepRemote
        case .clientWins: return .keepLocal
        case .lastWriteWins: return ConflictResolver<Note>.lastWriteWins.resolve(conflict)
        case .merge:
            guard let localRecord = conflict.local, conflict.remote != nil else {
                return ConflictResolver<Note>.lastWriteWins.resolve(conflict)
            }
            return .merged(Note(id: localRecord.id, text: "\(device)#M\(merges.next())"))
        }
    }
}

/// A device under test: its store can be reopened from its storage after a crash or app restart.
final class ScenarioDevice: @unchecked Sendable {
    let name: String
    let storage = ScenarioStorage()
    let network: ScenarioNetwork
    let configuration: OfflineStore<Note>.Configuration
    let nodeID = ScenarioText()
    private let lock = OSAllocatedUnfairLock(initialState: OfflineStore<Note>?.none)

    init(name: String, network: ScenarioNetwork, policy: ScenarioPolicy, clock: TestClock, offset: TimeInterval,
         conflicts: ScenarioLines, violations: ScenarioLines, merges: ScenarioCounter, retry: RetryPolicy) throws {
        self.name = name
        self.network = network
        configuration = OfflineStore<Note>.Configuration(
            conflictResolver: scenarioResolver(policy, device: name, nodeID: nodeID, conflicts: conflicts,
                                               violations: violations, merges: merges),
            retryPolicy: retry,
            circuitBreaker: CircuitBreaker(failureThreshold: 1_000, cooldown: .seconds(1)),
            now: { clock.now.addingTimeInterval(offset) },
            random: { 0 })
        try reopen()
    }

    var store: OfflineStore<Note> { lock.withLock { $0! } }

    func reopen() throws {
        storage.revive()
        let store = try OfflineStore<Note>(name: "scenario", storage: storage, transport: network, configuration: configuration)
        nodeID.set(store.nodeID)
        lock.withLock { $0 = store }
    }
}

/// One sync; its error, or `nil`. Errors are expected under faults.
@discardableResult
func scenarioSync(_ store: OfflineStore<Note>) async -> Error? {
    do {
        try await store.sync()
        return nil
    } catch {
        return error
    }
}

/// Holds what every scenario shares.
final class ScenarioWorld: @unchecked Sendable {
    let clock = TestClock()
    let server: ScenarioServer
    let conflicts = ScenarioLines()
    let violations = ScenarioLines()
    let merges = ScenarioCounter()
    let policy: ScenarioPolicy
    let retry: RetryPolicy

    init(policy: ScenarioPolicy, options: ScenarioOptions = ScenarioOptions(), pageSize: Int = 2,
         retry: RetryPolicy = RetryPolicy(maximumAttempts: 8, initialDelay: .seconds(10), maximumDelay: .seconds(60), jitter: 0)) {
        self.policy = policy
        self.server = ScenarioServer(options: options, pageSize: pageSize)
        self.retry = retry
    }

    func device(_ name: String, offset: TimeInterval = 0, seed: UInt64 = 1) throws -> ScenarioDevice {
        try ScenarioDevice(name: name, network: ScenarioNetwork(server: server, seed: seed), policy: policy,
                           clock: clock, offset: offset, conflicts: conflicts, violations: violations, merges: merges, retry: retry)
    }

    func ownWriteViolations() -> [String] { violations.all }
}
