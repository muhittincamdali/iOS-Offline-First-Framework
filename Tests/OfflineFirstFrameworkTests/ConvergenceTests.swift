import Foundation
import Testing
@testable import OfflineFirstFramework

/// Random saves, deletes, syncs and app restarts on two devices, with requests lost on the way
/// and answers lost on the way back; then a quiet network. Every record must end as its newest
/// write on either device (last write wins), on the server and on both devices, with nothing
/// left in the queues. A lost acknowledged write, a delete that never reaches the server or a
/// record that comes back all show up as a mismatch.
@Suite("Offline store: convergence")
struct ConvergenceTests {
    static let recordIDs = ["a", "b", "c", "d", "e"]
    static let steps = 250

    @Test(arguments: 0..<24)
    func randomOperationsAndFailuresConverge(seed: UInt64) async throws {
        let clock = TestClock()
        var random = SeededRandom(seed: seed)
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let network = FlakyNetwork(server: server, seed: seed)
        var devices = try ["phone", "laptop"].map { try Device(name: $0, network: network, clock: clock) }
        var oracle = Oracle()

        for step in 0..<Self.steps {
            let device = Int(random.next() % 2)
            let id = Self.recordIDs[Int(random.next() % UInt64(Self.recordIDs.count))]
            let store = devices[device].store
            let name = devices[device].name
            switch random.next() % 20 {
            case 0..<8:
                let note = Note(id: id, text: "\(name) \(step)")
                try await store.save(note)
                let timestamp = try #require(await store.state.entries[id]?.timestamp)
                oracle.add(.init(device: name, id: id, timestamp: timestamp, record: note))
            case 8..<11:
                guard await store.record(id) != nil else { continue }
                try await store.delete(id)
                if let timestamp = await store.state.entries[id]?.timestamp {
                    oracle.add(.init(device: name, id: id, timestamp: timestamp, record: nil))
                } else {
                    oracle.removedOnTheDeviceOnly(device: name, id: id, accepted: await network.acceptedTimestamps(of: id))
                }
            case 11..<17: _ = try? await store.sync()
            case 17: try devices[device].restart()
            default: clock.advance(by: Double(random.next() % 90))
            }
        }

        await network.setFailing(false)
        for _ in 0..<6 {
            clock.advance(by: 3_600)
            for device in devices {
                try await device.store.retryFailedChanges()
                _ = try await device.store.sync()
            }
        }

        let serverRecords = Self.byID(await server.records())
        for id in Self.recordIDs {
            #expect(serverRecords[id] == oracle.newest(id)?.text, "seed \(seed), record \(id)")
        }
        for device in devices {
            #expect(await device.store.pendingChanges().isEmpty, "seed \(seed), \(device.name)")
            #expect(Self.byID(await device.store.records()) == serverRecords, "seed \(seed), \(device.name)")
        }
    }

    private static func byID(_ notes: [Note]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0.text) })
    }
}

/// The writes made on the devices, and which of them should survive.
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

/// One device: a store and its file, which survives a restart.
private struct Device {
    let name: String
    let storage = InMemoryStorage()
    let network: FlakyNetwork
    let clock: TestClock
    var store: OfflineStore<Note>

    init(name: String, network: FlakyNetwork, clock: TestClock) throws {
        self.name = name
        self.network = network
        self.clock = clock
        store = try OfflineStore<Note>(name: name, storage: storage, transport: network, configuration: makeConfiguration(clock: clock))
    }

    /// The app ends and starts again with the same file.
    mutating func restart() throws {
        store = try OfflineStore<Note>(name: name, storage: storage, transport: network, configuration: makeConfiguration(clock: clock))
    }
}

/// Forwards to the server, but loses some requests before they arrive and some answers after
/// the server applied them. It notes the timestamp of every change the server accepted.
private actor FlakyNetwork: SyncTransport {
    let server: InMemorySyncServer<Note>
    private var random: SeededRandom
    private var isFailing = true
    private var accepted: [String: Set<HLCTimestamp>] = [:]

    init(server: InMemorySyncServer<Note>, seed: UInt64) {
        self.server = server
        random = SeededRandom(seed: seed &+ 0x5EED)
    }

    func setFailing(_ failing: Bool) {
        isFailing = failing
    }

    func acceptedTimestamps(of id: String) -> Set<HLCTimestamp> {
        accepted[id] ?? []
    }

    func push(_ changes: [OutgoingChange<Note>]) async throws -> [UUID: PushOutcome<Note>] {
        if fails(percent: 15) { throw URLError(.notConnectedToInternet) }
        let outcomes = try await server.push(changes)
        for change in changes {
            if case .accepted? = outcomes[change.id] {
                accepted[change.recordID, default: []].insert(change.timestamp)
            }
        }
        if fails(percent: 15) { throw URLError(.networkConnectionLost) }
        return outcomes
    }

    func pull(since token: String?) async throws -> PullResponse<Note> {
        if fails(percent: 15) { throw URLError(.timedOut) }
        return try await server.pull(since: token)
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
