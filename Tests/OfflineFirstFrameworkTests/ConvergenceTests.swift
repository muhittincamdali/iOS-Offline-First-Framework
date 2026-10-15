import Foundation
import Testing
@testable import OfflineFirstFramework

/// Random saves, deletes, syncs and app restarts on two devices, with requests lost on the way,
/// answers lost on the way back, stale pages from a lagging replica and server restarts; then
/// a quiet network. For every conflict policy the server and both devices must end with the
/// same records and nothing left in the queues, and a write the server accepted must never be
/// accepted again after a later write replaced it (a lost update by a stale copy). With last
/// write wins every record must also end as its newest write on either device, so a lost
/// acknowledged write, a delete that never reaches the server or a record that comes back
/// shows up as a mismatch.
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

    @Test(arguments: Policy.allCases, seeds)
    func randomOperationsFailuresAndRestartsConverge(policy: Policy, seed: UInt64) async throws {
        let clock = TestClock()
        var random = SeededRandom(seed: seed)
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let ledger = Ledger()
        var devices = try ["phone", "laptop"].enumerated().map { index, name in
            try Device(name: name, network: FlakyNetwork(server: server, ledger: ledger, seed: seed &+ UInt64(index)),
                       clock: clock, resolver: policy.resolver)
        }
        var oracle = Oracle()

        for step in 0..<Self.steps {
            let device = Int(random.next() % 2)
            let id = Self.recordIDs[Int(random.next() % UInt64(Self.recordIDs.count))]
            let store = devices[device].store
            let name = devices[device].name
            switch random.next() % 40 {
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
            case 22..<34: _ = try? await store.sync()
            case 34..<36: try devices[device].restart()
            case 36: await server.restart()
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
                _ = try await device.store.sync()
            }
        }

        let context = "\(policy) seed \(seed)"
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
}

/// The writes made on the devices, and which of them should survive under last write wins.
private struct Oracle {
    struct Write {
        let device: String
        let id: String
        let timestamp: HLCTimestamp
        let record: Note?
    }

    private var writes: [Write] = []
    /// Per device and record: the writes since the record last vanished from that device.
    private var current: [String: [Int]] = [:]

    mutating func add(_ write: Write) {
        current["\(write.device)/\(write.id)", default: []].append(writes.count)
        writes.append(write)
    }

    /// A delete removed the record on the device without queuing anything. That is right only if
    /// the server never accepted any of the device's writes of it: then they are dropped. If the
    /// server did accept one, the user's delete has to win, so it counts as the newest write.
    mutating func removedOnTheDeviceOnly(device: String, id: String, accepted: Set<HLCTimestamp>) {
        let key = "\(device)/\(id)"
        let local = current[key] ?? []
        current[key] = nil
        if local.contains(where: { accepted.contains(writes[$0].timestamp) }) {
            add(Write(device: device, id: id, timestamp: HLCTimestamp(wallTime: .max, nodeID: device), record: nil))
            current[key] = nil
        } else {
            for index in local {
                writes[index] = Write(device: device, id: id, timestamp: HLCTimestamp(wallTime: .min, nodeID: device), record: nil)
            }
        }
    }

    /// The surviving version of `id`: the write with the newest timestamp; `nil` if deleted.
    func newest(_ id: String) -> Note? {
        writes.filter { $0.id == id }.max { $0.timestamp < $1.timestamp }?.record
    }
}

/// Every write the server applied, in order, per record. A write (identified by its HLC
/// timestamp, unique per device write) that the server applies again after another write
/// replaced it is a lost update: a stale copy overwrote an acknowledged write.
private actor Ledger {
    private var applied: [String: [HLCTimestamp]] = [:]
    private var revisions: Set<String> = []
    private(set) var violations: [String] = []

    func accepted(_ change: OutgoingChange<Note>, revision: String) {
        // A repeated push answered from the server's memory of change IDs applies nothing.
        guard revisions.insert(revision).inserted else { return }
        var history = applied[change.recordID, default: []]
        if let last = history.last, last != change.timestamp, history.contains(change.timestamp) {
            violations.append("\(change.recordID): write \(change.timestamp) applied again after \(last)")
        }
        history.append(change.timestamp)
        applied[change.recordID] = history
    }

    func acceptedTimestamps(of id: String) -> Set<HLCTimestamp> {
        Set(applied[id] ?? [])
    }
}

/// One device: a store and its file, which survives a restart.
private struct Device {
    let name: String
    let storage = InMemoryStorage()
    let network: FlakyNetwork
    let clock: TestClock
    let resolver: ConflictResolver<Note>
    var store: OfflineStore<Note>

    init(name: String, network: FlakyNetwork, clock: TestClock, resolver: ConflictResolver<Note>) throws {
        self.name = name
        self.network = network
        self.clock = clock
        self.resolver = resolver
        store = try OfflineStore<Note>(name: name, storage: storage, transport: network,
                                       configuration: makeConfiguration(clock: clock, resolver: resolver))
    }

    /// The app ends and starts again with the same file.
    mutating func restart() throws {
        store = try OfflineStore<Note>(name: name, storage: storage, transport: network,
                                       configuration: makeConfiguration(clock: clock, resolver: resolver))
    }
}

/// One device's connection to the server. It loses some requests before they arrive and some
/// answers after the server applied them, and sometimes answers a pull with the page it returned
/// for the same token earlier, as a lagging replica or a stale cache would: older versions, and a
/// token no further than that page reached. It tells the ledger about every write the server
/// applied.
private actor FlakyNetwork: SyncTransport {
    let server: InMemorySyncServer<Note>
    let ledger: Ledger
    private var random: SeededRandom
    private var isFailing = true
    /// The last answer to each token, for replaying.
    private var pages: [String: PullResponse<Note>] = [:]

    init(server: InMemorySyncServer<Note>, ledger: Ledger, seed: UInt64) {
        self.server = server
        self.ledger = ledger
        random = SeededRandom(seed: seed &+ 0x5EED)
    }

    func setFailing(_ failing: Bool) {
        isFailing = failing
    }

    func push(_ changes: [OutgoingChange<Note>]) async throws -> [UUID: PushOutcome<Note>] {
        if fails(percent: 15) { throw URLError(.notConnectedToInternet) }
        let outcomes = try await server.push(changes)
        for change in changes {
            if case .accepted(let revision)? = outcomes[change.id] {
                await ledger.accepted(change, revision: revision)
            }
        }
        if fails(percent: 15) { throw URLError(.networkConnectionLost) }
        return outcomes
    }

    func pull(since token: String?) async throws -> PullResponse<Note> {
        if fails(percent: 15) { throw URLError(.timedOut) }
        let key = token ?? ""
        if let stale = pages[key], fails(percent: 10) {
            return stale
        }
        let page = try await server.pull(since: token)
        pages[key] = page
        return page
    }

    private func fails(percent: UInt64) -> Bool {
        isFailing && random.next() % 100 < percent
    }
}

/// SplitMix64, so every seed replays the same run.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
