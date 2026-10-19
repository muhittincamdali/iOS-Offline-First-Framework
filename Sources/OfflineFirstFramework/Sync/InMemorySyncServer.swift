import Foundation
import os

/// A sync server that lives in memory, for tests, SwiftUI previews and demos.
///
/// It behaves like a real backend: every write gets a new revision, a push based on an old
/// revision gets a conflict, pulls return changes after a token in pages, change IDs are
/// remembered so a repeated push is not applied twice, and ``isOnline`` simulates losing the
/// connection. Revisions and change tokens start with an epoch that is new for every instance
/// and every ``restart()``, and later than every earlier one, so a revision is never handed out
/// twice, a store that kept a token from an earlier instance (an app relaunched with a fresh demo
/// server) pulls everything again, and a page answered from before a restart is recognised.
///
/// ```swift
/// let server = InMemorySyncServer<Note>()
/// let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: server)
/// await server.write(Note(id: UUID(), text: "Written on another device"))
/// try await store.sync()
/// ```
public actor InMemorySyncServer<Record: SyncableRecord>: SyncTransport {
    private struct Stored {
        var record: Record?
        /// `<epoch>.<sequence>` of the write that stored this version.
        var revision: String
        /// The position of the write in the change feed.
        var sequence: Int
        var timestamp: HLCTimestamp
    }

    /// Change IDs the server remembers for idempotent pushes; older ones are forgotten.
    public static var rememberedChangeLimit: Int { 10_000 }

    private var stored: [Record.ID: Stored] = [:]
    /// The number of writes so far; the last write's position in the change feed.
    private var sequence = 0
    /// Names this run of the server in revisions and change tokens.
    private var epoch = InMemorySyncServer.makeEpoch()

    /// Different for every instance, so a store that is opened with a new server instance
    /// pulls everything again.
    public nonisolated let serverIdentity: String? = "in-memory-\(UUID().uuidString)"
    private var clock: HybridLogicalClock
    private var answers: [UUID: PushOutcome<Record>] = [:]
    private var answerOrder: [UUID] = []

    /// Whether requests succeed. While `false`, push and pull throw
    /// `URLError(.notConnectedToInternet)`.
    public private(set) var isOnline = true

    /// The most changes a pull returns.
    public private(set) var pageSize: Int

    /// How long each request takes.
    public private(set) var latency: Duration

    /// Returns a reason to reject a pushed record, or `nil` to accept it.
    private let validate: @Sendable (Record) -> String?

    /// The server's current time.
    private let now: @Sendable () -> Date

    /// Push requests received, including failed ones.
    public private(set) var pushRequests = 0

    /// Pull requests received, including failed ones.
    public private(set) var pullRequests = 0

    /// Creates an empty server.
    ///
    /// - Parameters:
    ///   - pageSize: The most changes per pull, at least 1.
    ///   - latency: How long each request takes.
    ///   - validate: Returns a reason to reject a pushed record, or `nil` to accept it.
    ///   - now: The server's current time. Replace it in tests.
    public init(
        pageSize: Int = 100,
        latency: Duration = .zero,
        validate: @escaping @Sendable (Record) -> String? = { _ in nil },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.pageSize = max(1, pageSize)
        self.latency = max(.zero, latency)
        self.validate = validate
        self.now = now
        self.clock = HybridLogicalClock(nodeID: "server", maximumDrift: .seconds(300))
    }

    /// Simulates losing or regaining the connection.
    public func setOnline(_ online: Bool) {
        isOnline = online
    }

    /// Changes how long each request takes.
    public func setLatency(_ latency: Duration) {
        self.latency = max(.zero, latency)
    }

    /// The server's copy of a record.
    public func record(_ id: Record.ID) -> Record? {
        stored[id]?.record
    }

    /// All records on the server, in the order they were last written.
    public func records() -> [Record] {
        stored.values.sorted { $0.sequence < $1.sequence }.compactMap(\.record)
    }

    /// The server's current revision of a record.
    public func revision(of id: Record.ID) -> String? {
        stored[id]?.revision
    }

    /// Simulates a restart of a server that keeps its records and the change IDs it answered.
    ///
    /// The server starts a new, later epoch: change tokens handed out before make the next pull
    /// start from the beginning, and writes from now on get revisions that the earlier run never
    /// handed out, so a push based on a revision from before the restart is still checked
    /// against the record's current revision.
    public func restart() {
        epoch = Self.makeEpoch()
    }

    /// Writes a record as another device would, with a new revision.
    ///
    /// - Parameters:
    ///   - record: The record to store.
    ///   - date: When the other device made the change; the server's current time if `nil`.
    @discardableResult
    public func write(_ record: Record, at date: Date? = nil) -> String {
        commit(record, id: record.id, timestamp: (try? clock.tick(at: date ?? now())) ?? clock.latest)
    }

    /// Deletes a record as another device would.
    @discardableResult
    public func delete(_ id: Record.ID, at date: Date? = nil) -> String {
        commit(nil, id: id, timestamp: (try? clock.tick(at: date ?? now())) ?? clock.latest)
    }

    // MARK: - SyncTransport

    public func push(_ changes: [OutgoingChange<Record>]) async throws -> [UUID: PushOutcome<Record>] {
        pushRequests += 1
        try await simulateNetwork()
        var outcomes: [UUID: PushOutcome<Record>] = [:]
        for change in changes {
            if let answer = answers[change.id] {
                outcomes[change.id] = answer
                continue
            }
            let answer = handle(change)
            remember(answer, for: change.id)
            outcomes[change.id] = answer
        }
        return outcomes
    }

    public func pull(since token: String?) async throws -> PullResponse<Record> {
        pullRequests += 1
        try await simulateNetwork()
        let after = position(of: token)
        let changed = stored.filter { $0.value.sequence > after }.sorted { $0.value.sequence < $1.value.sequence }
        let page = changed.prefix(pageSize)
        let next = page.last?.value.sequence ?? after
        return PullResponse(
            changes: page.map { remote($0.key, $0.value) },
            token: "\(epoch).\(next)",
            hasMore: changed.count > page.count,
            epoch: epoch
        )
    }

    // MARK: - Internals

    /// The feed position a token stands for. A token of another epoch, or one this run has not
    /// reached, starts from the beginning: the client then gets every record again instead of
    /// waiting for writes that may never come.
    private func position(of token: String?) -> Int {
        guard let token, let dot = token.firstIndex(of: "."), token[..<dot] == epoch,
              let after = Int(token[token.index(after: dot)...]), (0...sequence).contains(after)
        else { return 0 }
        return after
    }

    private func handle(_ change: OutgoingChange<Record>) -> PushOutcome<Record> {
        let current = stored[change.recordID]
        if current?.revision != change.baseRevision {
            if let current {
                return .conflict(current: remote(change.recordID, current))
            }
            // The client knows a revision the server never had; treat the record as new.
        }
        if let record = change.record, let reason = validate(record) {
            return .rejected(reason: reason, current: current.map { remote(change.recordID, $0) })
        }
        _ = try? clock.receive(change.timestamp, at: now())
        // The timestamp is kept as it was pushed: the device recognises its own write by it
        // after a lost answer. Devices count one too far ahead as at their drift limit.
        return .accepted(revision: commit(change.record, id: change.recordID, timestamp: change.timestamp))
    }

    private func commit(_ record: Record?, id: Record.ID, timestamp: HLCTimestamp) -> String {
        sequence += 1
        let revision = "\(epoch).\(sequence)"
        stored[id] = Stored(record: record, revision: revision, sequence: sequence, timestamp: timestamp)
        return revision
    }

    private func remote(_ id: Record.ID, _ stored: Stored) -> RemoteChange<Record> {
        RemoteChange(recordID: id, record: stored.record, revision: stored.revision, timestamp: stored.timestamp,
                     sequence: UInt64(stored.sequence))
    }

    /// A new epoch, later than every earlier one of this process: the time in microseconds
    /// since 1970, or one more than the last epoch when that is later, as 16 hexadecimal
    /// digits, so the order of the texts is the order of the numbers.
    private static func makeEpoch() -> String {
        let microseconds = UInt64(max(0, Date().timeIntervalSince1970 * 1_000_000))
        let epoch = lastEpoch.withLock { last in
            last = max(last &+ 1, microseconds)
            return last
        }
        return String(format: "%016llx", epoch)
    }

    private func remember(_ answer: PushOutcome<Record>, for changeID: UUID) {
        answers[changeID] = answer
        answerOrder.append(changeID)
        if answerOrder.count > Self.rememberedChangeLimit {
            answers[answerOrder.removeFirst()] = nil
        }
    }

    private func simulateNetwork() async throws {
        if latency > .zero {
            try await Task.sleep(for: latency)
        }
        guard isOnline else { throw URLError(.notConnectedToInternet) }
    }
}

/// The last epoch an ``InMemorySyncServer`` of this process handed out.
private let lastEpoch = OSAllocatedUnfairLock(initialState: UInt64(0))
