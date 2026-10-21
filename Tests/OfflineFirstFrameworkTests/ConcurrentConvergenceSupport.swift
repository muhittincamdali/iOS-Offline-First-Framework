import Foundation
import os
@testable import OfflineFirstFramework

struct ModelVersion: Sendable {
    var record: Note?
    var revision: String
    var sequence: Int
    var timestamp: HLCTimestamp
    var changeID: UUID?
}

struct ModelSnapshot: Sendable {
    var stored: [String: ModelVersion]
    var sequence: Int
    var epoch: String
}

struct ModelOptions: Sendable, CustomStringConvertible {
    var sendSequence = true
    var sendChangeID = true
    var description: String { "seq=\(sendSequence) cid=\(sendChangeID)" }
}

struct StorageDied: Error {}

/// A server written from the protocol description, independent of `InMemorySyncServer` and of
/// the reference server: it keeps its data across restarts (a new epoch, the same sequence
/// counter), answers a change ID it saw from memory, and records every write it applies, so a
/// write that is applied again after a later one replaced it shows up as a lost update.
actor ModelServer {
    private var stored: [String: ModelVersion] = [:]
    private var sequence = 0
    private var epochNumber = 1
    private var answers: [UUID: PushOutcome<Note>] = [:]
    private var applied: [String: [HLCTimestamp]] = [:]
    private(set) var violations: [String] = []
    private(set) var restarts = 0
    let pageSize: Int
    let options: ModelOptions

    init(pageSize: Int, options: ModelOptions) {
        self.pageSize = pageSize
        self.options = options
    }

    var epoch: String { String(format: "%010d", epochNumber) }

    func restart() {
        epochNumber += 1
        restarts += 1
    }

    func snapshot() -> ModelSnapshot { ModelSnapshot(stored: stored, sequence: sequence, epoch: epoch) }

    func records() -> [String: String] { stored.compactMapValues { $0.record?.text } }

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
                answer = .accepted(revision: commit(change))
            }
            answers[change.id] = answer
            outcomes[change.id] = answer
        }
        return outcomes
    }

    private func commit(_ change: OutgoingChange<Note>) -> String {
        sequence += 1
        let revision = "\(epoch).\(sequence)"
        var history = applied[change.recordID, default: []]
        if let last = history.last, last != change.timestamp, history.contains(change.timestamp) {
            violations.append("lost update: \(change.recordID) write \(change.timestamp) applied again after \(last)")
        }
        history.append(change.timestamp)
        applied[change.recordID] = history
        stored[change.recordID] = ModelVersion(record: change.record, revision: revision, sequence: sequence,
                                           timestamp: change.timestamp, changeID: change.id)
        return revision
    }

    func pull(since token: String?) -> PullResponse<Note> {
        Self.page(of: snapshot(), since: token, pageSize: pageSize, options: options)
    }

    nonisolated static func remote(_ id: String, _ stored: ModelVersion, _ options: ModelOptions) -> RemoteChange<Note> {
        RemoteChange(recordID: id, record: stored.record, revision: stored.revision, timestamp: stored.timestamp,
                     sequence: options.sendSequence ? UInt64(stored.sequence) : nil,
                     changeID: options.sendChangeID ? stored.changeID : nil)
    }

    /// A page from `snapshot`: the live server, or a lagging replica that holds an older copy
    /// (possibly of an earlier epoch).
    nonisolated static func page(of snapshot: ModelSnapshot, since token: String?, pageSize: Int, options: ModelOptions) -> PullResponse<Note> {
        var after = 0
        if let token, let dot = token.firstIndex(of: "."), token[..<dot] == snapshot.epoch,
           let position = Int(token[token.index(after: dot)...]) {
            if position > snapshot.sequence {
                return PullResponse(changes: [], token: token, hasMore: false, epoch: snapshot.epoch)
            }
            after = max(0, position)
        }
        let changed = snapshot.stored.filter { $0.value.sequence > after }.sorted { $0.value.sequence < $1.value.sequence }
        let page = changed.prefix(pageSize)
        let next = page.last?.value.sequence ?? after
        return PullResponse(changes: page.map { remote($0.key, $0.value, options) }, token: "\(snapshot.epoch).\(next)",
                            hasMore: changed.count > page.count, epoch: snapshot.epoch)
    }
}

/// Storage that dies (every write throws) after a set number of writes: a crash at that point.
final class DyingStorage: StorageBackend {
    private struct State {
        var files: [String: Data] = [:]
        var crashAfter: Int?
        var dead = false
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var isDead: Bool { lock.withLock { $0.dead } }

    func arm(afterWrites count: Int) { lock.withLock { $0.crashAfter = count } }

    func revive() { lock.withLock { $0.dead = false; $0.crashAfter = nil } }

    func read(_ name: String) throws -> Data? { lock.withLock { $0.files[name] } }

    func write(_ data: Data, to name: String) throws {
        try lock.withLock { state in
            if state.dead { throw StorageDied() }
            if let remaining = state.crashAfter {
                if remaining == 0 {
                    state.dead = true
                    state.crashAfter = nil
                    throw StorageDied()
                }
                state.crashAfter = remaining - 1
            }
            state.files[name] = data
        }
    }

    func remove(_ name: String) throws { lock.withLock { _ = $0.files.removeValue(forKey: name) } }

    func move(_ name: String, to newName: String) throws {
        lock.withLock { state in
            state.files[newName] = state.files.removeValue(forKey: name)
        }
    }
}

/// One device's connection: lost requests, lost answers, duplicated pushes, a server restart
/// between a push and the pull, pages from a lagging replica, and yields so local writes
/// interleave with requests. Requests of a crashed device fail.
actor ConcurrentNetwork: SyncTransport {
    nonisolated let serverIdentity: String? = "model-server"
    let server: ModelServer
    let storage: DyingStorage
    private var random: SeededRandom
    private var failing = true
    private var replica: ModelSnapshot?

    init(server: ModelServer, storage: DyingStorage, seed: UInt64) {
        self.server = server
        self.storage = storage
        random = SeededRandom(seed: seed)
    }

    func setFailing(_ value: Bool) {
        failing = value
        if !value { replica = nil }
    }

    func setReplica(_ snapshot: ModelSnapshot?) { replica = snapshot }

    private func roll(_ percent: UInt64) -> Bool { failing && random.next() % 100 < percent }

    private func interleave() async {
        let count = Int(random.next() % 4)
        for _ in 0..<count { await Task.yield() }
    }

    private func checkAlive() throws {
        if storage.isDead { throw StorageDied() }
    }

    func push(_ changes: [OutgoingChange<Note>]) async throws -> [UUID: PushOutcome<Note>] {
        try checkAlive()
        await interleave()
        if roll(12) { throw URLError(.notConnectedToInternet) }
        let outcomes = await server.push(changes)
        if roll(5) { _ = await server.push(changes) }
        if roll(4) { await server.restart() }
        await interleave()
        try checkAlive()
        if roll(12) { throw URLError(.networkConnectionLost) }
        return outcomes
    }

    func pull(since token: String?) async throws -> PullResponse<Note> {
        try checkAlive()
        await interleave()
        if roll(10) { throw URLError(.timedOut) }
        if let replica, roll(20) {
            return ModelServer.page(of: replica, since: token, pageSize: server.pageSize, options: server.options)
        }
        let page = await server.pull(since: token)
        await interleave()
        if roll(5) { throw URLError(.networkConnectionLost) }
        return page
    }
}

/// Every write made on a device, in the order the store made it, to compute the last-write-wins
/// outcome. Writes a device removed without sending (a local delete of a record the server never
/// saw) are dropped.
final class WriteOracle: Sendable {
    private struct Write {
        let device: String
        let id: String
        let timestamp: HLCTimestamp
        let text: String?
        var dropped = false
    }

    private struct State {
        var writes: [Write] = []
        var current: [String: [Int]] = [:]
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    func add(device: String, id: String, timestamp: HLCTimestamp, text: String?) {
        lock.withLock { state in
            state.current["\(device)/\(id)", default: []].append(state.writes.count)
            state.writes.append(Write(device: device, id: id, timestamp: timestamp, text: text))
        }
    }

    func removedLocally(device: String, id: String) {
        lock.withLock { state in
            for index in state.current["\(device)/\(id)"] ?? [] { state.writes[index].dropped = true }
            state.current["\(device)/\(id)"] = nil
        }
    }

    /// The newest write's text; `.some(nil)` for a deletion; `nil` when nothing was written.
    func newest(_ id: String) -> String?? {
        lock.withLock { state in
            guard let write = state.writes.filter({ $0.id == id && !$0.dropped }).max(by: { $0.timestamp < $1.timestamp }) else {
                return nil
            }
            return .some(write.text)
        }
    }
}

final class ViolationLog: Sendable {
    private let lock = OSAllocatedUnfairLock<[String]>(initialState: [])
    func add(_ text: String) { lock.withLock { $0.append(text) } }
    var all: [String] { lock.withLock { $0 } }
}

extension OfflineStore where Record == Note {
    /// Saves and records the write in one step on the actor, so the oracle sees writes in the
    /// store's order even when operations run concurrently.
    func recordedSave(_ note: Note, device: String, oracle: WriteOracle) throws {
        try save(note)
        if let timestamp = state.entries[note.id]?.timestamp {
            oracle.add(device: device, id: note.id, timestamp: timestamp, text: note.text)
        }
    }

    func recordedDelete(_ id: String, device: String, oracle: WriteOracle) throws {
        guard let entry = state.entries[id], entry.record != nil else { return }
        try delete(id)
        if let after = state.entries[id] {
            oracle.add(device: device, id: id, timestamp: after.timestamp, text: nil)
        } else {
            oracle.removedLocally(device: device, id: id)
        }
    }
}
