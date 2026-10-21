import Foundation
import os
import Testing
@testable import OfflineFirstFramework

// Support for the scenario tests: a server written from ServerProtocol.md apart from the store,
// a network per device with replicas, lost requests and answers and pull hooks, and storage that
// dies at a chosen write.

enum ScenarioPolicy: String, CaseIterable, Sendable, CustomStringConvertible {
    case serverWins, clientWins, lastWriteWins, merge
    var description: String { rawValue }
}

struct ScenarioOptions: Sendable, CustomStringConvertible {
    var sequences = true
    var changeIDs = true
    var description: String { "seq=\(sequences) cid=\(changeIDs)" }
}

struct ScenarioVersion: Sendable {
    var text: String?
    var revision: String
    var sequence: UInt64
    var timestamp: HLCTimestamp
    var changeID: UUID?
}

struct ScenarioSnapshot: Sendable {
    var epoch: String
    var stored: [String: ScenarioVersion]
    var sequence: UInt64
}

struct ScenarioCommit: Sendable {
    var record: String
    var text: String?
    var changeID: UUID?
    var sequence: UInt64
}

final class ScenarioLines: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [String]())
    func add(_ line: String) { lock.withLock { $0.append(line) } }
    var all: [String] { lock.withLock { $0 } }
    var count: Int { lock.withLock { $0.count } }
}

final class ScenarioCounter: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: 0)
    func next() -> Int { lock.withLock { $0 += 1; return $0 } }
    var value: Int { lock.withLock { $0 } }
}

final class ScenarioText: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: String?.none)
    func set(_ value: String?) { lock.withLock { $0 = value } }
    var value: String? { lock.withLock { $0 } }
}

struct ScenarioRandom: Sendable {
    var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0xD1B5_4A32_D192_ED03 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(max(1, n))) }
    mutating func roll(_ percent: Int) -> Bool { below(100) < percent }
}

/// A server that follows the protocol: later epochs, growing sequences across restarts that keep
/// the data, change-ID memory across restarts, pushed timestamps kept, conflicts on a base that is
/// not current.
actor ScenarioServer {
    nonisolated let options: ScenarioOptions
    private(set) var epochNumber = 1
    private(set) var stored: [String: ScenarioVersion] = [:]
    private(set) var sequence: UInt64 = 0
    private var answers: [UUID: PushOutcome<Note>] = [:]
    private(set) var commits: [ScenarioCommit] = []
    var pageSize: Int

    init(options: ScenarioOptions = ScenarioOptions(), pageSize: Int = 2) {
        self.options = options
        self.pageSize = pageSize
    }

    var epoch: String { String(format: "%08d", epochNumber) }

    func restart() { epochNumber += 1 }
    func setPageSize(_ size: Int) { pageSize = max(1, size) }
    func snapshot() -> ScenarioSnapshot { ScenarioSnapshot(epoch: epoch, stored: stored, sequence: sequence) }
    func records() -> [String: String] { stored.compactMapValues { $0.text } }
    func text(_ id: String) -> String? { stored[id]?.text }

    /// A write of a device that is not a store under test.
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
        let revision = "\(epoch).\(sequence)"
        stored[id] = ScenarioVersion(text: text, revision: revision, sequence: sequence, timestamp: timestamp, changeID: changeID)
        commits.append(ScenarioCommit(record: id, text: text, changeID: changeID, sequence: sequence))
        return revision
    }

    func pull(since token: String?) -> PullResponse<Note> {
        return Self.page(of: snapshot(), since: token, pageSize: pageSize, options: options)
    }

    nonisolated static func remote(_ id: String, _ version: ScenarioVersion, _ options: ScenarioOptions) -> RemoteChange<Note> {
        RemoteChange(recordID: id, record: version.text.map { Note(id: id, text: $0) }, revision: version.revision,
                     timestamp: version.timestamp, sequence: options.sequences ? version.sequence : nil,
                     changeID: options.changeIDs ? version.changeID : nil)
    }

    nonisolated static func page(of snapshot: ScenarioSnapshot, since token: String?, pageSize: Int,
                                 options: ScenarioOptions) -> PullResponse<Note> {
        var after: UInt64 = 0
        if let token, let dot = token.firstIndex(of: "."), token[..<dot] == snapshot.epoch,
           let position = UInt64(token[token.index(after: dot)...]), position <= snapshot.sequence {
            after = position
        }
        let changed = snapshot.stored.filter { $0.value.sequence > after }.sorted { $0.value.sequence < $1.value.sequence }
        let page = changed.prefix(pageSize)
        let next = page.last?.value.sequence ?? after
        return PullResponse(changes: page.map { remote($0.key, $0.value, options) }, token: "\(snapshot.epoch).\(next)",
                            hasMore: changed.count > page.count, epoch: snapshot.epoch)
    }
}
