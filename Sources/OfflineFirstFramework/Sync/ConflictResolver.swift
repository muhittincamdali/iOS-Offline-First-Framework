/// Two versions of a record that changed on the device and on the server since the last sync.
public struct Conflict<Record: SyncableRecord>: Sendable {
    /// The record both versions belong to.
    public let recordID: Record.ID

    /// The device's version, or `nil` when the record was deleted on the device.
    public let local: Record?

    /// When the device's version was written.
    public let localTimestamp: HLCTimestamp

    /// The server's version, or `nil` when the record was deleted on the server.
    public let remote: Record?

    /// When the server's version was written, if the server keeps timestamps.
    public let remoteTimestamp: HLCTimestamp?

    /// Creates a conflict.
    public init(recordID: Record.ID, local: Record?, localTimestamp: HLCTimestamp, remote: Record?, remoteTimestamp: HLCTimestamp?) {
        self.recordID = recordID
        self.local = local
        self.localTimestamp = localTimestamp
        self.remote = remote
        self.remoteTimestamp = remoteTimestamp
    }
}

/// What to do with a ``Conflict``.
public enum ConflictResolution<Record: SyncableRecord>: Sendable {
    /// Keep the device's version and push it again on top of the server's.
    case keepLocal
    /// Take the server's version and drop the device's change.
    case keepRemote
    /// Store this combination of both versions and push it. Its `id` must be the conflict's
    /// ``Conflict/recordID``; a record with another ID is ignored and the server's version is
    /// kept.
    case merged(Record)
}

/// Decides what happens when a record changed on the device and on the server.
///
/// ```swift
/// // The newest edit wins (the default).
/// let store = try OfflineStore<Note>(name: "notes", conflictResolver: .lastWriteWins)
///
/// // Keep both edits of a checklist.
/// let resolver = ConflictResolver<Checklist>.merge { local, remote in
///     var merged = local
///     merged.items = local.items.merged(with: remote.items)
///     return merged
/// }
/// ```
public struct ConflictResolver<Record: SyncableRecord>: Sendable {
    private let decide: @Sendable (Conflict<Record>) -> ConflictResolution<Record>

    /// Creates a resolver from a function.
    public init(_ decide: @escaping @Sendable (Conflict<Record>) -> ConflictResolution<Record>) {
        self.decide = decide
    }

    /// Decides `conflict`.
    public func resolve(_ conflict: Conflict<Record>) -> ConflictResolution<Record> {
        decide(conflict)
    }

    /// The server's version always wins.
    public static var serverWins: ConflictResolver {
        ConflictResolver { _ in .keepRemote }
    }

    /// The device's version always wins.
    public static var clientWins: ConflictResolver {
        ConflictResolver { _ in .keepLocal }
    }

    /// The version with the newer ``HLCTimestamp`` wins; deletions count as writes. When the
    /// server sends no timestamp, its version wins.
    public static var lastWriteWins: ConflictResolver {
        ConflictResolver { conflict in
            guard let remoteTimestamp = conflict.remoteTimestamp else { return .keepRemote }
            return conflict.localTimestamp > remoteTimestamp ? .keepLocal : .keepRemote
        }
    }

    /// Combines both versions with `merge` when both exist. When one side deleted the record,
    /// ``lastWriteWins`` decides.
    public static func merge(_ merge: @escaping @Sendable (_ local: Record, _ remote: Record) -> Record) -> ConflictResolver {
        ConflictResolver { conflict in
            guard let local = conflict.local, let remote = conflict.remote else {
                return lastWriteWins.resolve(conflict)
            }
            return .merged(merge(local, remote))
        }
    }
}

extension ConflictResolver where Record: Mergeable {
    /// Combines both versions with the record's own ``Mergeable/merged(with:)``.
    public static var mergeable: ConflictResolver {
        merge { local, remote in local.merged(with: remote) }
    }
}
