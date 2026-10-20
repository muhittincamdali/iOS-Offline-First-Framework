import Foundation
import os
@testable import OfflineFirstFramework

/// The server version each device last held for each record without a local change. The
/// in-memory server numbers its writes across restarts (`<epoch>.<sequence>`), so a smaller
/// number is an older version.
struct HeldVersions {
    private var sequences: [String: UInt64] = [:]

    mutating func check(_ store: OfflineStore<Note>, device: String, step: Int, ledger: Ledger) async {
        for (id, entry) in await store.state.entries {
            let key = "\(device)/\(id)"
            guard entry.pending == nil, let revision = entry.revision,
                  let sequence = revision.split(separator: ".").last.flatMap({ UInt64($0) })
            else { continue }
            if let previous = sequences[key], sequence < previous {
                await ledger.report("\(key) went back from version \(previous) to \(sequence) at step \(step)")
            }
            sequences[key] = sequence
        }
    }
}

/// The writes made on the devices, and which of them should survive under last write wins.
struct Oracle {
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
actor Ledger {
    private var applied: [String: [HLCTimestamp]] = [:]
    private var revisions: Set<String> = []
    private var recorded: [String] = []
    /// Reports from synchronous code, such as a resolver.
    private nonisolated let reported = OSAllocatedUnfairLock<[String]>(initialState: [])

    var violations: [String] {
        recorded + reported.withLock { $0 }
    }

    func report(_ violation: String) {
        recorded.append(violation)
    }

    nonisolated func reportLater(_ violation: String) {
        reported.withLock { $0.append(violation) }
    }

    func accepted(_ change: OutgoingChange<Note>, revision: String) {
        // A repeated push answered from the server's memory of change IDs applies nothing.
        guard revisions.insert(revision).inserted else { return }
        var history = applied[change.recordID, default: []]
        if let last = history.last, last != change.timestamp, history.contains(change.timestamp) {
            recorded.append("\(change.recordID): write \(change.timestamp) applied again after \(last)")
        }
        history.append(change.timestamp)
        applied[change.recordID] = history
    }

    func acceptedTimestamps(of id: String) -> Set<HLCTimestamp> {
        Set(applied[id] ?? [])
    }
}

/// One device: a store and its file, which survives a restart.
struct Device {
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
/// answers after the server applied them, and sometimes answers a pull with a page its cache
/// returned for the same token earlier, as a lagging replica or a stale cache would: older
/// versions, and a token no further than that page reached. The cache is the device's own or
/// shared with the other device. It tells the ledger about every write the server applied.
actor FlakyNetwork: SyncTransport {
    let server: InMemorySyncServer<Note>
    let ledger: Ledger
    private var random: SeededRandom
    private var isFailing = true
    /// The last answer to each token, for replaying.
    let cache: PageCache

    init(server: InMemorySyncServer<Note>, ledger: Ledger, cache: PageCache, seed: UInt64) {
        self.server = server
        self.ledger = ledger
        self.cache = cache
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
        if let stale = await cache.page(for: key), fails(percent: 10) {
            return stale
        }
        let page = try await server.pull(since: token)
        await cache.store(page, for: key)
        return page
    }

    private func fails(percent: UInt64) -> Bool {
        isFailing && random.next() % 100 < percent
    }
}

/// The last page answered for each change token.
actor PageCache {
    private var pages: [String: PullResponse<Note>] = [:]

    func page(for key: String) -> PullResponse<Note>? {
        pages[key]
    }

    func store(_ page: PullResponse<Note>, for key: String) {
        pages[key] = page
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
