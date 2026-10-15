import Foundation

/// A sync server that lives in memory, for tests, SwiftUI previews and demos.
///
/// It behaves like a real backend: every write gets a new revision, a push based on an old
/// revision gets a conflict, pulls return changes after a token in pages, change IDs are
/// remembered so a repeated push is not applied twice, and ``isOnline`` simulates losing the
/// connection. Change tokens name the server instance, so a store that kept a token from an
/// earlier instance (an app relaunched with a fresh demo server) pulls everything again.
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
        var revision: Int
        var timestamp: HLCTimestamp
    }

    /// Change IDs the server remembers for idempotent pushes; older ones are forgotten.
    public static var rememberedChangeLimit: Int { 10_000 }

    private var stored: [Record.ID: Stored] = [:]
    private var revision = 0
    /// Identifies this instance in change tokens.
    private let epoch = String(UUID().uuidString.prefix(8))
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

    /// All records on the server, in revision order.
    public func records() -> [Record] {
        stored.values.sorted { $0.revision < $1.revision }.compactMap(\.record)
    }

    /// The server's current revision of a record.
    public func revision(of id: Record.ID) -> String? {
        stored[id].map { String($0.revision) }
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
        let changed = stored.filter { $0.value.revision > after }.sorted { $0.value.revision < $1.value.revision }
        let page = changed.prefix(pageSize)
        let next = page.last?.value.revision ?? after
        return PullResponse(
            changes: page.map { RemoteChange(recordID: $0.key, record: $0.value.record, revision: String($0.value.revision), timestamp: $0.value.timestamp) },
            token: "\(epoch).\(next)",
            hasMore: changed.count > page.count
        )
    }

    // MARK: - Internals

    /// The revision a token stands for. A token of another instance, or one this instance has
    /// not reached, starts from the beginning: the client then gets every record again instead
    /// of waiting for revisions that may never come.
    private func position(of token: String?) -> Int {
        guard let token, let dot = token.firstIndex(of: "."), token[..<dot] == epoch,
              let after = Int(token[token.index(after: dot)...]), (0...revision).contains(after)
        else { return 0 }
        return after
    }

    private func handle(_ change: OutgoingChange<Record>) -> PushOutcome<Record> {
        let current = stored[change.recordID]
        if current.map({ String($0.revision) }) != change.baseRevision {
            if let current {
                return .conflict(current: remote(change.recordID, current))
            }
            // The client knows a revision the server never had; treat the record as new.
        }
        if let record = change.record, let reason = validate(record) {
            return .rejected(reason: reason, current: current.map { remote(change.recordID, $0) })
        }
        _ = try? clock.receive(change.timestamp, at: now())
        return .accepted(revision: commit(change.record, id: change.recordID, timestamp: change.timestamp))
    }

    private func commit(_ record: Record?, id: Record.ID, timestamp: HLCTimestamp) -> String {
        revision += 1
        stored[id] = Stored(record: record, revision: revision, timestamp: timestamp)
        return String(revision)
    }

    private func remote(_ id: Record.ID, _ stored: Stored) -> RemoteChange<Record> {
        RemoteChange(recordID: id, record: stored.record, revision: String(stored.revision), timestamp: stored.timestamp)
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
