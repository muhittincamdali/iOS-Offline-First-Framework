import Foundation

/// What an ``OfflineStore`` is doing about sync.
public enum SyncStatus: Hashable, Sendable {
    /// Not syncing. Local changes may still be waiting; see ``StoreState/pendingCount``.
    case idle
    /// A sync is running.
    case syncing
    /// The last sync failed because the device has no connection.
    case offline
    /// Sync attempts are skipped until the date after repeated failures (see ``CircuitBreaker``).
    case paused(until: Date)
    /// The last sync failed with this message.
    case failed(String)
}

/// The result of one ``OfflineStore/sync()``.
public struct SyncReport: Hashable, Sendable {
    /// Local changes the server accepted.
    public var pushed = 0
    /// Server changes applied to the store.
    public var pulled = 0
    /// Conflicts the ``ConflictResolver`` decided.
    public var conflicts = 0
    /// Changes the server rejected for good.
    public var rejected = 0
    /// Changes that ran out of attempts in this sync and were parked.
    public var parked = 0
    /// Whether the server still had changes after the page limit; the next sync continues.
    public var hasMoreChanges = false
    /// Whether the sync was skipped: no transport, or the circuit breaker is open.
    public var skipped = false

    /// Creates an empty report.
    public init() {}
}

/// A local change waiting for the server, as listed by ``OfflineStore/pendingChanges()``.
public struct PendingChange<Record: SyncableRecord>: Sendable, Identifiable {
    /// The ID of the current version of the change.
    public let id: UUID
    /// The changed record.
    public let recordID: Record.ID
    /// The record as it will be pushed, or `nil` for a delete.
    public let record: Record?
    /// Failed pushes of this change so far, conflicts included.
    public let attempts: Int
    /// The earliest time of the next automatic push, or `nil` for the next sync.
    public let nextAttemptAt: Date?
    /// Why the last push failed.
    public let lastError: String?
    /// Whether the change ran out of attempts or was rejected and waits for
    /// ``OfflineStore/retryFailedChanges()`` or ``OfflineStore/discardChange(for:)``.
    public let isParked: Bool

    /// Whether the change deletes the record.
    public var isDelete: Bool {
        record == nil
    }
}

/// A snapshot of an ``OfflineStore``, delivered by ``OfflineStore/states()``.
public struct StoreState<Record: SyncableRecord>: Sendable {
    /// The records, in the order they were first stored.
    public let records: [Record]
    /// Local changes not yet accepted by the server, parked ones included.
    public let pendingCount: Int
    /// Parked changes; see ``OfflineStore/failedChanges()``.
    public let failedCount: Int
    /// What the store is doing about sync.
    public let status: SyncStatus
    /// When the last sync finished successfully.
    public let lastSyncedAt: Date?
}

/// What to do when the store file cannot be read.
public enum CorruptionPolicy: Sendable {
    /// Throw the error from the initializer. The default.
    case fail
    /// Rename the unreadable file (damaged, or larger than the storage backend reads) to
    /// `<name>.store.corrupt-<milliseconds>` and start with an empty store; the next sync pulls
    /// the server's data again. Local changes that had not been pushed stay only in the renamed
    /// file. A store written by a newer schema version is never reset.
    case moveAsideAndStartEmpty
}
