import Foundation
import os
import Testing
@testable import OfflineFirstFramework

// For AppendChainTests (verifier C12): a server that may start without epochs and report them
// later (an upgrade), a per-device network with lost answers, requests lost before the server,
// unsent pushes, replicas, a cache shared by every device that answers pulls from the
// beginning, another deployment behind the same URL with its own epoch, and pull hooks.

struct ChainVersion: Sendable {
    var text: String?
    var revision: String
    var sequence: UInt64
    var timestamp: HLCTimestamp
    var changeID: UUID?
}

struct ChainSnapshot: Sendable {
    var epoch: String?
    var prefix: String
    var stored: [String: ChainVersion]
    var sequence: UInt64
}

actor ChainServer {
    nonisolated let options: ScenarioOptions
    private(set) var epochNumber = 1
    private(set) var reportsEpochs: Bool
    private(set) var stored: [String: ChainVersion] = [:]
    private(set) var sequence: UInt64 = 0
    private var answers: [UUID: PushOutcome<Note>] = [:]
    var pageSize: Int

    init(options: ScenarioOptions, reportsEpochs: Bool, pageSize: Int) {
        self.options = options
        self.reportsEpochs = reportsEpochs
        self.pageSize = pageSize
    }

    var prefix: String { String(format: "%08d", epochNumber) }
    func restart() { epochNumber += 1 }
    func startReportingEpochs() { reportsEpochs = true }
    func snapshot() -> ChainSnapshot { ChainSnapshot(epoch: reportsEpochs ? prefix : nil, prefix: prefix, stored: stored, sequence: sequence) }
    func records() -> [String: String] { stored.compactMapValues { $0.text } }
    func text(_ id: String) -> String? { stored[id]?.text }

    @discardableResult
    func write(_ id: String, _ text: String?, at timestamp: HLCTimestamp) -> String {
        commit(id, text: text, timestamp: timestamp, changeID: nil)
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
                answer = .conflict(current: Self.remote(change.recordID, current, options))
            } else {
                answer = .accepted(revision: commit(change.recordID, text: change.record?.text, timestamp: change.timestamp,
                                                    changeID: change.id))
            }
            answers[change.id] = answer
            outcomes[change.id] = answer
        }
        return outcomes
    }

    private func commit(_ id: String, text: String?, timestamp: HLCTimestamp, changeID: UUID?) -> String {
        sequence += 1
        let revision = "\(prefix).\(sequence)"
        stored[id] = ChainVersion(text: text, revision: revision, sequence: sequence, timestamp: timestamp, changeID: changeID)
        return revision
    }

    func pull(since token: String?) -> PullResponse<Note> {
        Self.page(of: snapshot(), since: token, pageSize: pageSize, options: options)
    }

    nonisolated static func remote(_ id: String, _ version: ChainVersion, _ options: ScenarioOptions) -> RemoteChange<Note> {
        RemoteChange(recordID: id, record: version.text.map { Note(id: id, text: $0) }, revision: version.revision,
                     timestamp: version.timestamp, sequence: options.sequences ? version.sequence : nil,
                     changeID: options.changeIDs ? version.changeID : nil)
    }

    nonisolated static func page(of snapshot: ChainSnapshot, since token: String?, pageSize: Int,
                                 options: ScenarioOptions) -> PullResponse<Note> {
        var after: UInt64 = 0
        if let token, let dot = token.firstIndex(of: "."), token[..<dot] == snapshot.prefix,
           let position = UInt64(token[token.index(after: dot)...]), position <= snapshot.sequence {
            after = position
        }
        let changed = snapshot.stored.filter { $0.value.sequence > after }.sorted { $0.value.sequence < $1.value.sequence }
        let page = changed.prefix(pageSize)
        let next = page.last?.value.sequence ?? after
        return PullResponse(changes: page.map { remote($0.key, $0.value, options) }, token: "\(snapshot.prefix).\(next)",
                            hasMore: changed.count > page.count, epoch: snapshot.epoch)
    }
}

/// A cache every device shares that answers pulls from the beginning.
final class ChainCache: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: (ChainSnapshot?.none, 0))
    func set(_ snapshot: ChainSnapshot?, requests: Int) { lock.withLock { $0 = (snapshot, snapshot == nil ? 0 : requests) } }
    func take() -> ChainSnapshot? {
        lock.withLock { state in
            guard let snapshot = state.0, state.1 > 0 else { return nil }
            state.1 -= 1
            if state.1 == 0 { state.0 = nil }
            return snapshot
        }
    }
}

enum ChainPushFault: Sendable { case lose, unsent, lostBeforeServer }

actor ChainNetwork: SyncTransport {
    typealias Record = Note
    nonisolated let serverIdentity: String? = "chain-server"
    let server: ChainServer
    let cache: ChainCache
    private var random: ScenarioRandom
    private var replica: ChainSnapshot?
    private var replicaPulls = 0
    private var foreignPulls = 0
    private var foreignEpoch: String?
    private var foreignRecord = "s"
    private var plan: [ChainPushFault] = []
    private var restartAfterPushPercent = 0
    private var pullHook: (@Sendable () async -> Void)?
    private(set) var pullTokens: [String?] = []

    init(server: ChainServer, cache: ChainCache, seed: UInt64) {
        self.server = server
        self.cache = cache
        self.random = ScenarioRandom(seed: seed)
    }

    func setReplica(_ snapshot: ChainSnapshot?, pulls: Int) {
        replica = snapshot
        replicaPulls = snapshot == nil ? 0 : pulls
    }
    func setForeign(pulls: Int, epoch: String?, record: String) {
        foreignPulls = pulls
        foreignEpoch = epoch
        foreignRecord = record
    }
    func planPushes(_ faults: [ChainPushFault]) { plan = faults }
    func setRestartAfterPush(_ percent: Int) { restartAfterPushPercent = percent }
    func setPullHook(_ hook: (@Sendable () async -> Void)?) { pullHook = hook }
    func clearFaults() {
        replica = nil
        replicaPulls = 0
        foreignPulls = 0
        plan = []
        restartAfterPushPercent = 0
        pullHook = nil
    }
    func clearTokens() { pullTokens = [] }

    func push(_ changes: [OutgoingChange<Note>]) async throws -> [UUID: PushOutcome<Note>] {
        if !plan.isEmpty {
            switch plan.removeFirst() {
            case .unsent: throw URLError(.notConnectedToInternet)
            case .lostBeforeServer: throw URLError(.networkConnectionLost)
            case .lose:
                _ = await server.push(changes)
                if restartAfterPushPercent > 0, random.roll(restartAfterPushPercent) { await server.restart() }
                throw URLError(.networkConnectionLost)
            }
        }
        let outcomes = await server.push(changes)
        if restartAfterPushPercent > 0, random.roll(restartAfterPushPercent) { await server.restart() }
        return outcomes
    }

    func pull(since token: String?) async throws -> PullResponse<Note> {
        pullTokens.append(token)
        if let hook = pullHook {
            pullHook = nil
            await hook()
        }
        let size = await server.pageSize
        if foreignPulls > 0 {
            foreignPulls -= 1
            let change = RemoteChange(recordID: foreignRecord, record: Note(id: foreignRecord, text: "foreign"), revision: "F.900000",
                                      timestamp: HLCTimestamp(wallTime: 1_700_000_000_000, nodeID: "foreign"),
                                      sequence: server.options.sequences ? 900_000 : nil, changeID: nil)
            return PullResponse(changes: [change], token: "F.900000", hasMore: false, epoch: foreignEpoch)
        }
        if token == nil, let cached = cache.take() {
            return ChainServer.page(of: cached, since: nil, pageSize: size, options: server.options)
        }
        if let replica, replicaPulls > 0 {
            replicaPulls -= 1
            if replicaPulls == 0 { self.replica = nil }
            return ChainServer.page(of: replica, since: token, pageSize: size, options: server.options)
        }
        return await server.pull(since: token)
    }
}

final class ChainDevice: @unchecked Sendable {
    let name: String
    let storage = ScenarioStorage()
    let network: ChainNetwork
    let configuration: OfflineStore<Note>.Configuration
    let nodeID = ScenarioText()
    private let lock = OSAllocatedUnfairLock(initialState: OfflineStore<Note>?.none)

    init(name: String, network: ChainNetwork, policy: ScenarioPolicy, clock: TestClock, offset: TimeInterval,
         conflicts: ScenarioLines, violations: ScenarioLines, merges: ScenarioCounter, retry: RetryPolicy, maximumPullPages: Int = 100) throws {
        self.name = name
        self.network = network
        configuration = OfflineStore<Note>.Configuration(
            conflictResolver: scenarioResolver(policy, device: name, nodeID: nodeID, conflicts: conflicts,
                                               violations: violations, merges: merges),
            retryPolicy: retry,
            circuitBreaker: CircuitBreaker(failureThreshold: 1_000, cooldown: .seconds(1)),
            maximumPullPages: maximumPullPages,
            now: { clock.now.addingTimeInterval(offset) },
            random: { 0 })
        try reopen()
    }

    var store: OfflineStore<Note> { lock.withLock { $0! } }

    func reopen() throws {
        storage.revive()
        let store = try OfflineStore<Note>(name: "chain", storage: storage, transport: network, configuration: configuration)
        nodeID.set(store.nodeID)
        lock.withLock { $0 = store }
    }
}

final class ChainWorld: @unchecked Sendable {
    let clock = TestClock()
    let server: ChainServer
    let cache = ChainCache()
    let conflicts = ScenarioLines()
    let violations = ScenarioLines()
    let merges = ScenarioCounter()
    let policy: ScenarioPolicy
    let retry = RetryPolicy(maximumAttempts: 6, initialDelay: .seconds(10), maximumDelay: .seconds(60), jitter: 0)

    init(policy: ScenarioPolicy, options: ScenarioOptions, reportsEpochs: Bool = true, pageSize: Int = 2) {
        self.policy = policy
        server = ChainServer(options: options, reportsEpochs: reportsEpochs, pageSize: pageSize)
    }

    func device(_ name: String, offset: TimeInterval = 0, seed: UInt64 = 1, maximumPullPages: Int = 100) throws -> ChainDevice {
        try ChainDevice(name: name, network: ChainNetwork(server: server, cache: cache, seed: seed), policy: policy, clock: clock,
                      offset: offset, conflicts: conflicts, violations: violations, merges: merges, retry: retry,
                      maximumPullPages: maximumPullPages)
    }
}

/// Syncs every device until nothing is left, with faults cleared; the last errors.
@discardableResult
func chainSettle(_ devices: [ChainDevice], world: ChainWorld, rounds: Int = 10) async throws -> [String] {
    for device in devices {
        await device.network.clearFaults()
        device.storage.revive()
        try device.reopen()
    }
    world.cache.set(nil, requests: 0)
    var errors: [String] = []
    for _ in 0..<rounds {
        world.clock.advance(by: 600)
        for device in devices {
            try? await device.store.retryFailedChanges()
            for _ in 0..<30 {
                do {
                    let report = try await device.store.sync()
                    if !report.hasMoreChanges { break }
                } catch {
                    errors.append("\(device.name): \(error)")
                    break
                }
            }
        }
    }
    return errors
}

/// What differs between the devices and the server once settled.
func chainDivergence(_ devices: [ChainDevice], server: ChainServer) async -> [String] {
    var problems: [String] = []
    let onServer = await server.records()
    for device in devices {
        let store = device.store
        let records = Dictionary(uniqueKeysWithValues: await store.records().map { ($0.id, $0.text) })
        if records != onServer { problems.append("\(device.name) shows \(records.sorted { $0.key < $1.key }) server \(onServer.sorted { $0.key < $1.key })") }
        let pending = await store.pendingChanges()
        if !pending.isEmpty {
            problems.append("\(device.name) pending \(pending.map { "\($0.recordID) parked=\($0.isParked) \($0.lastError ?? "")" })")
        }
    }
    return problems
}
