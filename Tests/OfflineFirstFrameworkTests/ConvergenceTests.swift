import Foundation
import Testing
@testable import OfflineFirstFramework

/// Random saves, deletes, syncs (also two at once), app restarts and `resetChangeToken()` on two
/// devices that fetch one, two, three or a hundred pages per sync from a server with small or
/// large pages, with requests lost on the way, answers lost on the
/// way back, stale pages from a lagging replica or a cache and server restarts; then a quiet
/// network. For every conflict policy the server and both devices must end with the same
/// records and nothing left in the queues, and a write the server accepted must never be
/// accepted again after a later write replaced it (a lost update by a stale copy).
/// Along the way no device may go back to an older server version of a record it holds without
/// a local change (a stale page that rolls a record back), and no resolver may be asked about a
/// version the device wrote itself (a conflict that is none). With last write wins every
/// record must also end as its newest write on either device, so a lost acknowledged write, a
/// delete that never reaches the server or a record that comes back shows up as a mismatch.
@Suite("Offline store: convergence")
struct ConvergenceTests {
    enum Policy: String, CaseIterable, Sendable {
        case lastWriteWins, serverWins, clientWins, merge

        var resolver: ConflictResolver<Note> {
            switch self {
            case .lastWriteWins: .lastWriteWins
            case .serverWins: .serverWins
            case .clientWins: .clientWins
            // Deterministic and bounded: keeps one of the two texts, as a new write.
            case .merge: .merge { local, remote in Note(id: local.id, text: max(local.text, remote.text)) }
            }
        }
    }

    static let recordIDs = ["a", "b", "c", "d", "e"]
    static let steps = 250
    /// Seeds per policy: 24, or `CONVERGENCE_SEEDS` for a longer run
    /// (`CONVERGENCE_SEEDS=2000 swift test --filter ConvergenceTests`).
    static let seeds: [UInt64] = Array(0..<(UInt64(ProcessInfo.processInfo.environment["CONVERGENCE_SEEDS"] ?? "") ?? 24))

    /// Each device has a cache of its own.
    @Test(arguments: Policy.allCases, seeds)
    func randomOperationsFailuresAndRestartsConverge(policy: Policy, seed: UInt64) async throws {
        try await run(policy: policy, seed: seed, sharedCache: false)
    }

    /// One cache in front of the server for both devices, keyed by the change token: a device
    /// can get a page the other device got earlier, also the first page of a new epoch from
    /// before the device's own write was accepted, or a page of an epoch it never saw.
    @Test(arguments: Policy.allCases, seeds)
    func aPageCacheSharedByBothDevicesConverges(policy: Policy, seed: UInt64) async throws {
        try await run(policy: policy, seed: seed, sharedCache: true)
    }

    private func run(policy: Policy, seed: UInt64, sharedCache: Bool) async throws {
        let clock = TestClock()
        var random = SeededRandom(seed: seed)
        let server = InMemorySyncServer<Note>(pageSize: [2, 3, 100][Int(seed % 3)], now: { [clock] in clock.now })
        let ledger = Ledger()
        let resolver = Self.checking(policy.resolver, into: ledger)
        let shared = PageCache()
        var devices = try ["phone", "laptop"].enumerated().map { index, name in
            try Device(name: name, network: FlakyNetwork(server: server, ledger: ledger, cache: sharedCache ? shared : PageCache(),
                                                         seed: seed &+ UInt64(index)),
                       clock: clock, resolver: resolver, pullPages: [1, 2, 3, 100][Int((seed &+ UInt64(index)) % 4)])
        }
        var oracle = Oracle()
        var held = HeldVersions()

        for step in 0..<Self.steps {
            let device = Int(random.next() % 2)
            let id = Self.recordIDs[Int(random.next() % UInt64(Self.recordIDs.count))]
            let store = devices[device].store
            let name = devices[device].name
            switch random.next() % 43 {
            case 0..<16:
                let note = Note(id: id, text: "\(name) \(step)")
                try await store.save(note)
                let timestamp = try #require(await store.state.entries[id]?.timestamp)
                oracle.add(.init(device: name, id: id, timestamp: timestamp, record: note))
            case 16..<22:
                guard await store.record(id) != nil else { continue }
                try await store.delete(id)
                if let timestamp = await store.state.entries[id]?.timestamp {
                    oracle.add(.init(device: name, id: id, timestamp: timestamp, record: nil))
                } else {
                    oracle.removedOnTheDeviceOnly(device: name, id: id, accepted: await ledger.acceptedTimestamps(of: id))
                }
            case 22..<32:
                _ = try? await store.sync()
                await held.check(store, device: name, step: step, ledger: ledger)
            case 32..<34:
                async let first = try? store.sync()
                async let second = try? store.sync()
                _ = await (first, second)
                await held.check(store, device: name, step: step, ledger: ledger)
            case 34..<36: try devices[device].restart()
            case 36: await server.restart()
            case 37: try await store.resetChangeToken()
            default: clock.advance(by: Double(random.next() % 90))
            }
        }

        for device in devices {
            await device.network.setFailing(false)
        }
        for _ in 0..<6 {
            clock.advance(by: 3_600)
            for device in devices {
                try await device.store.retryFailedChanges()
                // A device that fetches few pages per sync needs several syncs for a full pull.
                var syncs = 0
                while try await device.store.sync().hasMoreChanges, syncs < 10 { syncs += 1 }
                await held.check(device.store, device: device.name, step: Self.steps, ledger: ledger)
            }
        }

        let context = "\(policy) seed \(seed)\(sharedCache ? ", shared cache" : "")"
        let violations = await ledger.violations
        #expect(violations.isEmpty, "\(context): \(violations)")
        let serverRecords = Self.byID(await server.records())
        if policy == .lastWriteWins {
            for id in Self.recordIDs {
                #expect(serverRecords[id] == oracle.newest(id)?.text, "\(context), record \(id)")
            }
        }
        for device in devices {
            let pending = await device.store.pendingChanges()
            #expect(pending.isEmpty, "\(context), \(device.name): \(pending.map { ($0.recordID, $0.lastError ?? "") })")
            let records = Self.byID(await device.store.records())
            #expect(records == serverRecords, "\(context), \(device.name): \(records) vs server \(serverRecords)")
        }
    }

    private static func byID(_ notes: [Note]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0.text) })
    }

    /// `resolver`, reporting a conflict whose server version the device wrote itself: the
    /// device's change was made on top of it, so there is nothing to resolve.
    private static func checking(_ resolver: ConflictResolver<Note>, into ledger: Ledger) -> ConflictResolver<Note> {
        ConflictResolver { conflict in
            if let remote = conflict.remoteTimestamp, remote.nodeID == conflict.localTimestamp.nodeID {
                ledger.reportLater("\(conflict.recordID): the resolver was asked about the device's own write \(remote)")
            }
            return resolver.resolve(conflict)
        }
    }
}
