import Foundation

/// A value that an ``OfflineStore`` keeps on the device and syncs with a server.
///
/// Any `Codable` struct with a stable identifier works:
///
/// ```swift
/// struct Note: SyncableRecord {
///     var id: UUID
///     var text: String
/// }
/// ```
public protocol SyncableRecord: Codable, Sendable, Identifiable where ID: Codable & Sendable {}

/// A local change on its way to the server.
public struct OutgoingChange<Record: SyncableRecord>: Sendable, Identifiable {
    /// What the change does.
    public enum Operation: Sendable {
        /// Create the record or replace the server's copy.
        case upsert(Record)
        /// Delete the record.
        case delete
    }

    /// Identifies this version of the change. A retry of the same local version reuses the ID,
    /// so the server can use it as an idempotency key and apply a change only once.
    public let id: UUID

    /// The record the change applies to.
    public let recordID: Record.ID

    /// What the change does.
    public let operation: Operation

    /// When the change was made, from the store's ``HybridLogicalClock``.
    public let timestamp: HLCTimestamp

    /// The server revision the change was based on, or `nil` for a record the server has not
    /// confirmed yet. A server that has a different revision should answer
    /// ``PushOutcome/conflict(current:)``.
    public let baseRevision: String?

    /// Creates a change.
    public init(id: UUID, recordID: Record.ID, operation: Operation, timestamp: HLCTimestamp, baseRevision: String?) {
        self.id = id
        self.recordID = recordID
        self.operation = operation
        self.timestamp = timestamp
        self.baseRevision = baseRevision
    }

    /// The record for an upsert, or `nil` for a delete.
    public var record: Record? {
        if case .upsert(let record) = operation { return record }
        return nil
    }
}

/// The server's version of a record, sent in a pull or with a conflict.
public struct RemoteChange<Record: SyncableRecord>: Sendable {
    /// The record the change applies to.
    public let recordID: Record.ID

    /// The record, or `nil` when it was deleted on the server.
    public let record: Record?

    /// The server's revision of the record. Any string works, such as a version number or an
    /// ETag, as long as the server never gives the same string to two different versions of
    /// the record, not even after a restart or a restore from a backup: the store treats an
    /// equal revision as the same version. The reference servers put their ``PullResponse/epoch``
    /// in front of a counter (`"9f2c41d07ab35e18.43"`).
    public let revision: String

    /// When the record was last changed, if the server keeps the timestamps it receives.
    /// ``ConflictResolver/lastWriteWins`` lets the server's copy win when it is missing.
    public let timestamp: HLCTimestamp?

    /// Creates a server record.
    public init(recordID: Record.ID, record: Record?, revision: String, timestamp: HLCTimestamp?) {
        self.recordID = recordID
        self.record = record
        self.revision = revision
        self.timestamp = timestamp
    }
}

extension RemoteChange: Codable {}

/// The server's answer to one pushed change.
public enum PushOutcome<Record: SyncableRecord>: Sendable {
    /// The server stored the change as `revision`.
    case accepted(revision: String)

    /// The server's copy changed since ``OutgoingChange/baseRevision``. The store asks its
    /// ``ConflictResolver`` and, if the local version should win, pushes it again on top of
    /// `current`.
    case conflict(current: RemoteChange<Record>)

    /// The server refuses the change for good, for example because it fails validation. With
    /// `current`, the store goes back to the server's copy; without it, the change is parked in
    /// ``OfflineStore/failedChanges()`` with `reason`.
    case rejected(reason: String, current: RemoteChange<Record>?)
}

/// One page of server changes.
public struct PullResponse<Record: SyncableRecord>: Sendable {
    /// Changed records, oldest first.
    public let changes: [RemoteChange<Record>]

    /// The position after these changes. The store saves it and passes it to the next pull.
    public let token: String?

    /// Whether more changes follow; the store pulls again right away.
    public let hasMore: Bool

    /// Names the server's history of the records, if the server reports it. A server that may
    /// have lost or replaced its data (an in-memory server that restarted, a restore from a
    /// backup, a different database) reports a new epoch. The store then pulls everything again
    /// from the start and keeps its own pending changes.
    public let epoch: String?

    /// Creates a page.
    public init(changes: [RemoteChange<Record>], token: String?, hasMore: Bool, epoch: String? = nil) {
        self.changes = changes
        self.token = token
        self.hasMore = hasMore
        self.epoch = epoch
    }
}

/// The connection between an ``OfflineStore`` and your server.
///
/// Implement the two calls with your networking code (`URLSession`, a GraphQL client, a
/// database SDK). Throw for a failure that is worth retrying, such as no connection or a 5xx
/// status; answer ``PushOutcome/rejected(reason:current:)`` for a change that will never
/// succeed. Both calls should stop when their task is cancelled: the store cancels a request
/// when every caller of the sync gave up.
///
/// ```swift
/// struct NotesAPI: SyncTransport {
///     func push(_ changes: [OutgoingChange<Note>]) async throws -> [UUID: PushOutcome<Note>] {
///         // POST the changes, map each answer to a PushOutcome.
///     }
///
///     func pull(since token: String?) async throws -> PullResponse<Note> {
///         // GET /notes/changes?since=<token>
///     }
/// }
/// ```
///
/// ``InMemorySyncServer`` implements the protocol for tests, previews and demos.
public protocol SyncTransport<Record>: Sendable {
    /// The record type the transport syncs.
    associatedtype Record: SyncableRecord

    /// Identifies the server and collection the transport talks to, for example its URL. The
    /// store keeps it with its change token; when the store is opened with a transport of
    /// another identity, it pulls everything again instead of sending the old server's token.
    /// Default: `nil`, which is not checked.
    var serverIdentity: String? { get }

    /// Sends local changes and returns an outcome for each change ID. A change without an
    /// outcome counts as a failed attempt and is retried later.
    func push(_ changes: [OutgoingChange<Record>]) async throws -> [UUID: PushOutcome<Record>]

    /// Returns server changes after `token`, which is `nil` on the first sync.
    func pull(since token: String?) async throws -> PullResponse<Record>
}

extension SyncTransport {
    /// No identity: the store keeps its token whatever transport it is opened with.
    public var serverIdentity: String? { nil }
}
