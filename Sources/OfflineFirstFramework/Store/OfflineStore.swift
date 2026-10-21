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
        var token: String?
        var lastSyncedAt: Date?
        var nextSequence: UInt64
        /// The ``SyncTransport/serverIdentity`` the token and revisions belong to.
        var serverIdentity: String?
        /// The last ``PullResponse/epoch`` the server reported.
        var serverEpoch: String?
        /// Grows by one whenever the server's history changes: a new epoch or another server.
        var history: UInt64
        /// Server changes set aside, oldest first.
        var quarantine: [QuarantinedChange] = []
        /// An earlier epoch than ``serverEpoch`` that the last syncs in a row refused.
        var epochRefusal: EpochRefusal? = nil
        /// Set by ``OfflineStore/resetChangeToken()``: an earlier epoch than ``serverEpoch`` is
        /// taken in the next sync that confirms it, without the refusals.
        var takesNextEpoch = false

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
    var activeSync: SharedSync?
    /// Records whose push is waiting for the server's answer.
    var inFlight: Set<Record.ID> = []
    var automaticSync: AutomaticSync?
    /// Grows whenever the token is reset outside a pull, so a pull that was on its way at that
    /// moment does not store its page and token over the reset.
    var tokenGeneration: UInt64 = 0
    /// Identifies the file among the stores of this process; see ``FileClaims``.
    let fileKey: String?
    /// The file's generation when this store last read or wrote it.
    var fileGeneration: UInt64
    /// Set while the file cannot be written; see ``StorageWait``.
    var storageWait: StorageWait?

    /// What the store is doing about sync.
    public internal(set) var status: SyncStatus = .idle

    var fileName: String { "\(name).store" }

    /// Opens the store `name`, or creates it.
    ///
    /// - Parameters:
    ///   - name: 1 to 249 letters, digits, `.`, `_` or `-`, not starting with a dot. Each store
    ///     needs its own name, and one file one instance at a time: a second instance on the
    ///     same file in this process cannot write after the first one did
    ///     (``OfflineFirstError/storeChangedElsewhere(name:)``).
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
        // The generation is read before the file: a write by another instance in between makes
        // this one refuse its first write instead of dropping that write.
        let fileKey = FileClaims.key(for: storage, name: "\(name).store")
        self.fileGeneration = fileKey.map { FileClaims.shared.generation(of: $0) } ?? 0
        self.fileKey = fileKey
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

    /// Server changes the store set aside because it could not use them, oldest first: a
    /// record that does not decode, or a change whose IDs do not match. The pull went on
    /// without them; see ``QuarantinedChange``.
    public func quarantinedChanges() -> [QuarantinedChange] {
        state.quarantine
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
    /// - Throws: ``OfflineFirstError/outboxFull(limit:)`` when too many changes wait,
    ///   ``OfflineFirstError/recordNestedTooDeeply(limit:)`` for a record that nests deeper than
    ///   ``maximumRecordDepth``, or a storage error; the store is unchanged then.
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

    /// Deletes the record with `id` and queues the deletion for the server. A record that was
    /// never sent to the server is removed right away. Deleting a missing record does nothing.
    public func delete(_ id: Record.ID) throws {
        guard let entry = state.entries[id], entry.record != nil else { return }
        let reachedServer = entry.revision != nil || entry.wasSent
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

    /// Drops the waiting change of record `id`. A record that was never sent is removed; for one
    /// the server may know, the local version is removed too and the next sync pulls all server
    /// changes again from the start, which brings back the server's copy. That holds also when
    /// a sync is pulling at that moment: its page is dropped and the pull starts over.
    public func discardChange(for id: Record.ID) throws {
        guard let entry = state.entries[id], entry.pending != nil, !inFlight.contains(id) else { return }
        let reachedServer = entry.revision != nil || entry.wasSent
        try update { state in
            state.entries[id] = nil
            if reachedServer {
                state.token = nil
            }
        }
        if reachedServer { tokenGeneration &+= 1 }
    }

    /// Forgets the change token, so the next sync pulls every server change from the
    /// beginning; a pull that is on its way starts over. Records and pending changes stay, and
    /// the list of ``quarantinedChanges()`` is cleared, since those changes come again.
    ///
    /// Another ``PullResponse/epoch`` than the store's is believed, as always, once two requests
    /// of one sync report it: the pull from the beginning and the pull after its token. A later
    /// epoch then starts a new server history as after a restart, keeping what push answers
    /// told; an earlier one is taken at once instead of after eight syncs in a row. One page
    /// from a stale replica or cache therefore still cannot roll the store back.
    ///
    /// Use it when the server can no longer continue after the token, for example when it
    /// answers every pull with an error for it; after an app update that can read records the
    /// store set aside; or when the store refuses the server's pages as coming from an earlier
    /// epoch because it took a later one from elsewhere (another deployment behind the same
    /// URL). Without it, the store follows such a server after eight syncs in a row.
    public func resetChangeToken() throws {
        try update { state in
            state.token = nil
            state.quarantine.removeAll()
            state.epochRefusal = nil
            state.takesNextEpoch = true
        }
        tokenGeneration &+= 1
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
        do {
            try persist(copy)
        } catch {
            storageWait = StorageWait(after: storageWait, error: error, retryPolicy: configuration.retryPolicy,
                                      now: configuration.now(), random: configuration.random())
            throw error
        }
        storageWait = nil
        state = copy
        notifyObservers()
        return result
    }

    private func persist(_ state: State) throws {
        let entries = state.entries.values.sorted { $0.position < $1.position }
        let clock = state.clock.latest.wallTime == .min ? nil : state.clock.latest
        let file = StoreFile(format: StoreFile<Record>.currentFormat, schemaVersion: configuration.schemaVersion, nodeID: nodeID,
                             clock: clock, token: state.token, lastSyncedAt: state.lastSyncedAt,
                             nextSequence: state.nextSequence, entries: entries, serverIdentity: state.serverIdentity,
                             serverEpoch: state.serverEpoch, history: state.history,
                             quarantine: state.quarantine.isEmpty ? nil : state.quarantine,
                             epochRefusal: state.epochRefusal, takesNextEpoch: state.takesNextEpoch ? true : nil)
        let data = try configuration.encryption.seal(StoreFileCoder.encode(file), name: name)
        guard let fileKey else {
            try storage.write(data, to: fileName)
            return
        }
        guard let generation = try FileClaims.shared.write(fileKey, expecting: fileGeneration, { try storage.write(data, to: fileName) }) else {
            throw OfflineFirstError.storeChangedElsewhere(name: name)
        }
        fileGeneration = generation
    }

    func sortedEntries() -> [StoredEntry<Record>] {
        state.entries.values.sorted { $0.position < $1.position }
    }

    /// Writes a local version (`nil` for a deletion) and queues it.
    static func write(_ record: Record?, id: Record.ID, into state: inout State, configuration: Configuration) throws {
        if let record, NestingDepth.exceeds(record, limit: maximumRecordDepth) {
            throw OfflineFirstError.recordNestedTooDeeply(limit: maximumRecordDepth)
        }
        let timestamp = try tick(&state, configuration: configuration)
        var entry = state.entries[id]
            ?? StoredEntry(id: id, record: nil, timestamp: timestamp, revision: nil, position: state.takeSequence(), pending: nil,
                           history: state.history)
        // A record saved again after its deletion reached the server is new to the list.
        if entry.revision != nil, entry.record == nil, entry.pending == nil, record != nil {
            entry.position = state.takeSequence()
        }
        if entry.pending == nil {
            let waiting = state.entries.values.count { $0.pending != nil }
            guard waiting < configuration.maximumPendingChanges else {
                throw OfflineFirstError.outboxFull(limit: configuration.maximumPendingChanges)
            }
        }
        // The version this one replaces may have been applied although its answer was lost; its
        // change ID and timestamp let the store recognise it on the server as its own earlier write.
        var superseded = entry.pending?.supersededInDoubt ?? []
        var supersededIDs = entry.pending?.supersededChangeIDs ?? []
        if let pending = entry.pending, pending.isInDoubt {
            superseded.append(entry.timestamp)
            supersededIDs.append(pending.changeID)
        }
        entry.record = record
        entry.timestamp = timestamp
        // A new local version is pushed on its own base; its conflict answer brings the current one.
        entry.deferredRemote = nil
        entry.pending = PendingWrite(changeID: UUID(), sequence: entry.pending?.sequence ?? state.takeSequence(),
                                     attempts: 0, nextAttemptAt: nil, lastError: nil, isParked: false,
                                     supersededInDoubt: Array(superseded.suffix(PendingWrite.maximumSupersededInDoubt)),
                                     supersededChangeIDs: Array(supersededIDs.suffix(PendingWrite.maximumSupersededInDoubt)))
        state.entries[id] = entry
    }
}
