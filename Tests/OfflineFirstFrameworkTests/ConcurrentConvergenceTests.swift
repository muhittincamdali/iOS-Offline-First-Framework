import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// Three devices with skewed clocks run one to three operations at once per step: saves and
/// deletes interleave with pulls and pushes on the same device, two syncs overlap, and
/// `resetChangeToken()` comes in between. The server, written apart from the store's own test
/// server, restarts (also between the push and the pull of one sync) and gets pushes twice; a
/// lagging replica serves older snapshots, also of an earlier epoch, after a reset as well;
/// requests and answers get lost; storage dies at random writes and the device restarts from
/// its file. Then the network is quiet.
///
/// For every policy no write the server accepted may be applied again after a later one
/// replaced it, no device may go back to an older server version of a record without a local
/// change, the resolver is never asked about the device's own write, and every device ends with
/// the server's records and nothing queued; with last write wins every record ends as its
/// newest write. 120 runs by default; `CONCURRENT_CONVERGENCE_SEEDS=120` makes 1,200
/// (`swift test --filter ConcurrentConvergenceTests`).
@Suite("Offline store: concurrent operations, restarts, replicas and crashes")
struct ConcurrentConvergenceTests {
    typealias Policy = ConvergenceTests.Policy

    static let ids = ["a", "b", "c", "d"]
    static let steps = Int(ProcessInfo.processInfo.environment["CONCURRENT_CONVERGENCE_STEPS"] ?? "") ?? 160
    static let seeds: [UInt64] = Array(0..<(UInt64(ProcessInfo.processInfo.environment["CONCURRENT_CONVERGENCE_SEEDS"] ?? "") ?? 12))

    @Test(arguments: Policy.allCases, seeds)
    func withSequencesAndChangeIDs(policy: Policy, seed: UInt64) async throws {
        try await run(policy: policy, seed: seed, options: ModelOptions(sendSequence: true, sendChangeID: true))
    }

    /// Without change IDs the store recognises its own writes by the exact timestamp.
    @Test(arguments: Policy.allCases, seeds)
    func withSequencesWithoutChangeIDs(policy: Policy, seed: UInt64) async throws {
        try await run(policy: policy, seed: seed, options: ModelOptions(sendSequence: true, sendChangeID: false))
    }

    /// Without sequences the store orders versions by their timestamps, which matches the
    /// server's order for last write wins and merges only (documented).
    @Test(arguments: [Policy.lastWriteWins, .merge], seeds)
    func withoutSequences(policy: Policy, seed: UInt64) async throws {
        try await run(policy: policy, seed: seed, options: ModelOptions(sendSequence: false, sendChangeID: true))
    }

    final class Device: @unchecked Sendable {
        let name: String
        let storage = DyingStorage()
        let network: ConcurrentNetwork
        let configuration: OfflineStore<Note>.Configuration
        var store: OfflineStore<Note>

        init(name: String, server: ModelServer, clock: TestClock, offset: TimeInterval, resolver: ConflictResolver<Note>,
             pages: Int, seed: UInt64) throws {
            self.name = name
            network = ConcurrentNetwork(server: server, storage: storage, seed: seed)
            configuration = OfflineStore<Note>.Configuration(
                conflictResolver: resolver,
                retryPolicy: RetryPolicy(maximumAttempts: 3, initialDelay: .seconds(10), maximumDelay: .seconds(60), jitter: 0),
                circuitBreaker: CircuitBreaker(failureThreshold: 100, cooldown: .seconds(1)),
                maximumPullPages: pages,
                now: { clock.now.addingTimeInterval(offset) },
                random: { 0 })
            store = try OfflineStore<Note>(name: name, storage: storage, transport: network, configuration: configuration)
        }

        func restart() throws {
            storage.revive()
            store = try OfflineStore<Note>(name: name, storage: storage, transport: network, configuration: configuration)
        }
    }

    enum Operation: Sendable {
        case save(Int, String), delete(Int, String), sync(Int), twoSyncs(Int), reset(Int), serverRestart, replica(Int), crash(Int, Int)
    }

    private func run(policy: Policy, seed: UInt64, options: ModelOptions) async throws {
        let clock = TestClock()
        var random = SeededRandom(seed: seed &* 7919 &+ 17)
        let server = ModelServer(pageSize: [1, 2, 3, 50][Int(seed % 4)], options: options)
        let violations = ViolationLog()
        let oracle = WriteOracle()
        let offsets: [TimeInterval] = [0, 90, -90]
        let devices = try ["phone", "laptop", "tablet"].enumerated().map { index, name in
            try Device(name: name, server: server, clock: clock, offset: offsets[index],
                       resolver: Self.checking(policy.resolver, device: name, into: violations),
                       pages: [1, 2, 100][Int((seed &+ UInt64(index)) % 3)], seed: seed &* 31 &+ UInt64(index))
        }
        var held: [String: Int] = [:]
        let context = "\(policy) seed \(seed) \(options)"

        for step in 0..<Self.steps {
            var operations: [Operation] = []
            var restarts: [Int] = []
            for _ in 0..<(1 + Int(random.next() % 3)) {
                let device = Int(random.next() % 3)
                let id = Self.ids[Int(random.next() % UInt64(Self.ids.count))]
                switch random.next() % 50 {
                case 0..<15: operations.append(.save(device, id))
                case 15..<20: operations.append(.delete(device, id))
                case 20..<32: operations.append(.sync(device))
                case 32..<35: operations.append(.twoSyncs(device))
                case 35: operations.append(.reset(device))
                case 36..<38: operations.append(.serverRestart)
                case 38..<40: operations.append(.replica(device))
                case 40..<42: operations.append(.crash(device, Int(random.next() % 4)))
                case 42..<44: restarts.append(device)
                default: clock.advance(by: Double(random.next() % 60))
                }
            }
            let stores = devices.map(\.store)
            let names = devices.map(\.name)
            for operation in operations {
                switch operation {
                case .replica(let device): await devices[device].network.setReplica(await server.snapshot())
                case .crash(let device, let writes): devices[device].storage.arm(afterWrites: writes)
                default: break
                }
            }
            await withTaskGroup(of: Void.self) { group in
                for operation in operations {
                    group.addTask {
                        switch operation {
                        case .save(let device, let id):
                            try? await stores[device].recordedSave(Note(id: id, text: "\(names[device]) \(step)"), device: names[device], oracle: oracle)
                        case .delete(let device, let id):
                            try? await stores[device].recordedDelete(id, device: names[device], oracle: oracle)
                        case .sync(let device):
                            _ = try? await stores[device].sync()
                        case .twoSyncs(let device):
                            async let first = try? stores[device].sync()
                            async let second = try? stores[device].sync()
                            _ = await (first, second)
                        case .reset(let device):
                            try? await stores[device].resetChangeToken()
                        case .serverRestart:
                            await server.restart()
                        case .replica, .crash:
                            break
                        }
                    }
                }
            }
            for (index, device) in devices.enumerated() where device.storage.isDead || restarts.contains(index) {
                try device.restart()
            }
            for device in devices {
                await Self.checkHeld(device.store, device: device.name, step: step, held: &held, into: violations)
            }
        }

        for device in devices {
            await device.network.setFailing(false)
            if device.storage.isDead { try device.restart() }
            device.storage.revive()
        }
        for _ in 0..<8 {
            clock.advance(by: 3_600)
            for device in devices {
                try await device.store.retryFailedChanges()
                var syncs = 0
                while try await device.store.sync().hasMoreChanges, syncs < 40 { syncs += 1 }
                await Self.checkHeld(device.store, device: device.name, step: Self.steps, held: &held, into: violations)
            }
        }

        let serverViolations = await server.violations
        #expect(serverViolations.isEmpty, "\(context): \(serverViolations)")
        #expect(violations.all.isEmpty, "\(context): \(violations.all)")
        let serverRecords = await server.records()
        if policy == .lastWriteWins {
            for id in Self.ids {
                let expected: String? = oracle.newest(id) ?? nil
                #expect(serverRecords[id] == expected, "\(context), record \(id): server \(serverRecords[id] ?? "nil") oracle \(expected ?? "nil")")
            }
        }
        for device in devices {
            let pending = await device.store.pendingChanges()
            #expect(pending.isEmpty, "\(context), \(device.name) pending: \(pending.map { ($0.recordID, $0.lastError ?? "", $0.isParked) })")
            let quarantined = await device.store.quarantinedChanges()
            #expect(quarantined.isEmpty, "\(context), \(device.name) quarantined: \(quarantined)")
            let records = Dictionary(uniqueKeysWithValues: await device.store.records().map { ($0.id, $0.text) })
            #expect(records == serverRecords, "\(context), \(device.name): \(records) vs server \(serverRecords)")
        }
    }

    /// No device goes back to an older server version of a record it holds without a local change.
    private static func checkHeld(_ store: OfflineStore<Note>, device: String, step: Int, held: inout [String: Int],
                                  into violations: ViolationLog) async {
        for (id, entry) in await store.state.entries {
            guard entry.pending == nil, let revision = entry.revision,
                  let sequence = revision.split(separator: ".").last.flatMap({ Int($0) }) else { continue }
            let key = "\(device)/\(id)"
            if let previous = held[key], sequence < previous {
                violations.add("\(key) went back from \(previous) to \(sequence) at step \(step)")
            }
            held[key] = sequence
        }
    }

    private static func checking(_ resolver: ConflictResolver<Note>, device: String, into violations: ViolationLog) -> ConflictResolver<Note> {
        ConflictResolver { conflict in
            if let remote = conflict.remoteTimestamp, remote.nodeID == conflict.localTimestamp.nodeID {
                violations.add("\(device): resolver asked about own write \(conflict.recordID) \(remote)")
            }
            return resolver.resolve(conflict)
        }
    }
}
