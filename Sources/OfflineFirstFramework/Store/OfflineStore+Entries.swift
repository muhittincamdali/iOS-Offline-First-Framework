import Foundation

/// How server versions become stored entries, and which ones the store keeps.
extension OfflineStore {
    /// The longest revision or change token, in UTF-8 bytes, the store keeps. Every record
    /// stores its revision, so longer values from a server would grow the file without limit.
    static var maximumRevisionLength: Int { 1_024 }

    /// The longest node ID, in UTF-8 bytes, accepted in a server timestamp.
    static var maximumNodeIDLength: Int { 256 }

    /// The server's version as a stored entry without a pending change.
    static func entry(from remote: RemoteChange<Record>, replacing existing: StoredEntry<Record>?, in state: inout State,
                      configuration: Configuration) -> StoredEntry<Record> {
        let timestamp = remote.timestamp ?? (try? state.clock.tick(at: configuration.now())) ?? state.clock.latest
        return StoredEntry(id: remote.recordID, record: remote.record, timestamp: timestamp, revision: remote.revision,
                           position: existing?.position ?? state.takeSequence(), pending: nil, history: state.history,
                           sequence: remote.sequence, serverTimestamp: remote.timestamp)
    }

    /// Makes `remote` the server version `entry` is based on, without touching the record or
    /// its pending change.
    static func base(_ entry: inout StoredEntry<Record>, on remote: RemoteChange<Record>, history: UInt64) {
        entry.revision = remote.revision
        entry.history = history
        entry.sequence = remote.sequence
        entry.serverTimestamp = remote.timestamp
    }

    /// Starts a new server history: the server lost or replaced its data, or the store talks to
    /// another server. The token goes, so the next pull starts from the beginning. Entries keep
    /// their revisions (a pending change still names its base) but belong to the old history,
    /// so the server's current versions replace them whatever their timestamps say.
    static func beginHistory(epoch: String?, in state: inout State) {
        state.history &+= 1
        state.serverEpoch = epoch
        state.token = nil
    }

    /// Whether `change` is an older server version than the one `entry` is based on: a page out
    /// of order, a lagging replica, the earlier version of a record whose deletion the store saw.
    ///
    /// The server's ``RemoteChange/sequence`` decides when both versions have one. Otherwise
    /// the timestamps do, which matches the server's order as long as the devices resolve
    /// conflicts by ``ConflictResolver/lastWriteWins`` or a merge. A version from an earlier
    /// server history is never newer than the server's current one, and without either value
    /// the store cannot tell, so the version counts as newer.
    static func isStale(_ change: RemoteChange<Record>, comparedWith entry: StoredEntry<Record>, history: UInt64) -> Bool {
        guard entry.revision != nil, entry.history == history else { return false }
        if let incoming = change.sequence, let held = entry.sequence {
            return incoming < held
        }
        if let incoming = change.timestamp, let held = entry.heldServerTimestamp {
            return incoming < held
        }
        return false
    }

    /// Stores `entry`. A deletion with nothing left to push is kept as a tombstone while the
    /// server confirmed it (it has a revision), so an older version of the record that arrives
    /// later is recognised; otherwise it is removed.
    static func store(_ entry: StoredEntry<Record>, in state: inout State) {
        let isGone = entry.record == nil && entry.pending == nil && entry.revision == nil
        state.entries[entry.id] = isGone ? nil : entry
    }

    /// Tombstones kept per store; the oldest are dropped first.
    static var maximumTombstones: Int { 1_000 }

    /// Drops the oldest tombstones beyond ``maximumTombstones``.
    static func pruneTombstones(in state: inout State) {
        let tombstones = state.entries.values.filter { $0.record == nil && $0.pending == nil }
        guard tombstones.count > maximumTombstones else { return }
        let oldestFirst = tombstones.sorted { ($0.history, $0.sequence ?? 0, $0.timestamp) < ($1.history, $1.sequence ?? 0, $1.timestamp) }
        for entry in oldestFirst.prefix(tombstones.count - maximumTombstones) {
            state.entries[entry.id] = nil
        }
    }

    /// A server record is ignored when its own ID differs from the ID it was sent for, or when
    /// its revision or timestamp is longer than the limits.
    static func isConsistent(_ change: RemoteChange<Record>, for id: Record.ID) -> Bool {
        change.recordID == id
            && (change.record.map { $0.id == id } ?? true)
            && change.revision.utf8.count <= maximumRevisionLength
            && (change.timestamp.map { $0.nodeID.utf8.count <= maximumNodeIDLength } ?? true)
    }
}
