import Foundation

/// A collection of records that works without a connection and syncs with a server when it can.
///
/// Reads and writes go to the device first: ``save(_:)`` and ``delete(_:)`` store the change
/// in a file and queue it, so the app never waits for the network. ``sync()`` pushes the queued
/// changes through your ``SyncTransport``, pulls what changed on the server and settles
/// conflicts with the ``Configuration/conflictResolver``.
///
/// ```swift
/// let store = try OfflineStore<Note>(name: "notes", transport: NotesAPI())
/// try await store.save(Note(id: UUID(), text: "Buy milk"))
/// let report = try await store.sync()
/// ```
public actor OfflineStore<Record: SyncableRecord> {
    /// Everything the store persists, changed as one unit by ``update(_:)``.
    struct State: Sendable {
        var entries: [Record.ID: StoredEntry<Record>]
        var clock: HybridLogicalClock
        var cursor: String?
        var lastSyncedAt: Date?
        var nextSequence: UInt64

        mutating func takeSequence() -> UInt64 {
            defer { nextSequence += 1 }
            return nextSequence
        }
    }

    /// The store name; the file is `<name>.store`.
    public nonisolated let name: String

    /// Identifies this device in timestamps. Created once and kept in the store file.
    public nonisolated let nodeID: String

    let storage: any StorageBackend
    let transport: (any SyncTransport<Record>)?
    let configuration: Configuration
    var state: State
    var breaker: CircuitBreaker
    var observers: [UUID: AsyncStream<StoreState<Record>>.Continuation] = [:]
    var activeSync: Task<SyncReport, any Error>?
    /// Records whose push is waiting for the server's answer.
    var inFlight: Set<Record.ID> = []
    var automaticSync: AutomaticSync?

    /// What the store is doing about sync.
    public internal(set) var status: SyncStatus = .idle

    var fileName: String { "\(name).store" }

    /// Opens the store `name`, or creates it.
    ///
    /// - Parameters:
    ///   - name: 1 to 249 letters, digits, `.`, `_` or `-`, not starting with a dot. Each store
    ///     needs its own name.
    ///   - storage: Where the file lives. `nil` uses `Application Support/OfflineFirst`.
    ///   - transport: The connection to your server, or `nil` for a store that only keeps data
    ///     on the device (``sync()`` then does nothing).
    ///   - configuration: Conflict policy, encryption, retries, migrations and limits.
    /// - Throws: ``OfflineFirstError`` when the name is invalid or the file cannot be read
    ///   (see ``CorruptionPolicy``).
    public init(
        name: String,
        storage: (any StorageBackend)? = nil,
        transport: (any SyncTransport<Record>)? = nil,
        configuration: Configuration = Configuration()
    ) throws {
        try StorageName.validate("\(name).store")
        let configuration = configuration.normalized
        let storage = try storage ?? FileStore.applicationSupport()
        let file = try Self.load(name: name, storage: storage, configuration: configuration)
        let state = Self.makeState(from: file, configuration: configuration)
        self.name = name
        self.nodeID = state.clock.nodeID
        self.storage = storage
        self.transport = transport
        self.configuration = configuration
        self.breaker = configuration.circuitBreaker
        self.state = state
    }

    // MARK: - Reading

    /// The record with `id`, or `nil`.
    public func record(_ id: Record.ID) -> Record? {
        state.entries[id]?.record
    }

    /// All records, in the order they were first stored.
    public func records() -> [Record] {
        sortedEntries().compactMap(\.record)
    }

    /// The number of records.
    public var count: Int {
        state.entries.values.count { $0.record != nil }
    }

    /// When the last sync finished successfully.
    public var lastSyncedAt: Date? {
        state.lastSyncedAt
    }

    /// Local changes not yet accepted by the server, oldest first.
    public func pendingChanges() -> [PendingChange<Record>] {
        state.entries.values
            .compactMap { entry in entry.pending.map { (entry, $0) } }
            .sorted { $0.1.sequence < $1.1.sequence }
            .map { entry, pending in
                PendingChange(id: pending.changeID, recordID: entry.id, record: entry.record, attempts: pending.attempts,
                              nextAttemptAt: pending.nextAttemptAt, lastError: pending.lastError, isParked: pending.isParked)
            }
    }

    /// Changes that ran out of attempts or that the server rejected.
    public func failedChanges() -> [PendingChange<Record>] {
        pendingChanges().filter(\.isParked)
    }

    /// The records and sync state as one value.
    public func currentState() -> StoreState<Record> {
        let pending = state.entries.values.compactMap(\.pending)
        return StoreState(records: records(), pendingCount: pending.count, failedCount: pending.count { $0.isParked },
                          status: status, lastSyncedAt: state.lastSyncedAt)
    }

    // MARK: - Writing

    /// Stores `record`, replacing a record with the same ID, and queues it for the server.
    ///
    /// - Throws: ``OfflineFirstError/outboxFull(limit:)`` when too many changes wait, or a
    ///   storage error; the store is unchanged then.
    public func save(_ record: Record) throws {
        try save(contentsOf: [record])
    }

    /// Stores several records with one file write.
    public func save<S: Sequence>(contentsOf records: S) throws where S.Element == Record {
        try update { state in
            for record in records {
                try Self.write(record, id: record.id, into: &state, configuration: configuration)
            }
        }
        localChangeDidHappen()
    }

    /// Deletes the record with `id` and queues the deletion for the server. A record the
    /// server has never seen is removed right away. Deleting a missing record does nothing.
    public func delete(_ id: Record.ID) throws {
        guard let entry = state.entries[id], entry.record != nil else { return }
        let reachedServer = entry.revision != nil || inFlight.contains(id)
        try update { state in
            if reachedServer {
                try Self.write(nil, id: id, into: &state, configuration: configuration)
            } else {
                state.entries[id] = nil
            }
        }
        if reachedServer { localChangeDidHappen() }
    }

    /// Puts parked changes back in the queue with a fresh attempt count.
    public func retryFailedChanges() throws {
        guard state.entries.values.contains(where: { $0.pending?.isParked == true }) else { return }
        try update { state in
            for (id, entry) in state.entries where entry.pending?.isParked == true {
                state.entries[id]?.pending?.isParked = false
                state.entries[id]?.pending?.attempts = 0
                state.entries[id]?.pending?.nextAttemptAt = nil
            }
        }
        localChangeDidHappen()
    }

    /// Drops the waiting change of record `id`. A record the server has never seen is removed;
    /// for one it knows, the local version is removed too and the next sync pulls all server
    /// changes again from the start, which brings back the server's copy.
    public func discardChange(for id: Record.ID) throws {
        guard let entry = state.entries[id], entry.pending != nil, !inFlight.contains(id) else { return }
        try update { state in
            state.entries[id] = nil
            if entry.revision != nil {
                state.cursor = nil
            }
        }
    }

    // MARK: - Observing

    /// A stream of the store's state: the current state first, then one after every change.
    /// A slow reader gets the latest state, not every intermediate one.
    public func states() -> AsyncStream<StoreState<Record>> {
        let (stream, continuation) = AsyncStream.makeStream(of: StoreState<Record>.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        observers[id] = continuation
        continuation.yield(currentState())
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    private func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    func notifyObservers() {
        guard !observers.isEmpty else { return }
        let snapshot = currentState()
        for continuation in observers.values {
            continuation.yield(snapshot)
        }
    }

    // MARK: - Persistence

    /// Runs `body` on a copy of the state, writes the copy, and only then makes it current, so
    /// a failed write leaves the store as it was.
    @discardableResult
    func update<T>(_ body: (inout State) throws -> T) throws -> T {
        var copy = state
        let result = try body(&copy)
        try persist(copy)
        state = copy
        notifyObservers()
        return result
    }

    private func persist(_ state: State) throws {
        let entries = state.entries.values.sorted { $0.position < $1.position }
        let clock = state.clock.latest.wallTime == .min ? nil : state.clock.latest
        let file = StoreFile(format: StoreFile<Record>.currentFormat, schemaVersion: configuration.schemaVersion, nodeID: nodeID,
                             clock: clock, cursor: state.cursor, lastSyncedAt: state.lastSyncedAt,
                             nextSequence: state.nextSequence, entries: entries)
        let data = try configuration.encryption.seal(StoreFileCoder.encode(file), name: name)
        try storage.write(data, to: fileName)
    }

    func sortedEntries() -> [StoredEntry<Record>] {
        state.entries.values.sorted { $0.position < $1.position }
    }

    /// Writes a local version (`nil` for a deletion) and queues it.
    static func write(_ record: Record?, id: Record.ID, into state: inout State, configuration: Configuration) throws {
        let timestamp: HLCTimestamp
        do {
            timestamp = try state.clock.tick(at: configuration.now())
        } catch {
            throw OfflineFirstError.clock(error)
        }
        var entry = state.entries[id]
            ?? StoredEntry(id: id, record: nil, timestamp: timestamp, revision: nil, position: state.takeSequence(), pending: nil)
        if entry.pending == nil {
            let waiting = state.entries.values.count { $0.pending != nil }
            guard waiting < configuration.maximumPendingChanges else {
                throw OfflineFirstError.outboxFull(limit: configuration.maximumPendingChanges)
            }
        }
        entry.record = record
        entry.timestamp = timestamp
        entry.pending = PendingWrite(changeID: UUID(), sequence: entry.pending?.sequence ?? state.takeSequence(),
                                     attempts: 0, nextAttemptAt: nil, lastError: nil, isParked: false)
        state.entries[id] = entry
    }
}
