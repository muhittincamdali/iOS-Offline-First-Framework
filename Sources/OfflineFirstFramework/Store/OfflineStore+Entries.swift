import Foundation

/// How server versions become stored entries, and which ones the store keeps.
extension OfflineStore {
    /// The longest revision or change token, in UTF-8 bytes, the store keeps. Every record
    /// stores its revision, so longer values from a server would grow the file without limit.
    static var maximumRevisionLength: Int { 1_024 }

    /// The longest node ID, in UTF-8 bytes, accepted in a server timestamp.
    static var maximumNodeIDLength: Int { 256 }

    /// Revisions an entry remembers as older than its own accepted write
    /// (``StoredEntry/olderRevisions``): one per accepted write without an echo, the oldest
    /// dropped first.
    static var maximumOlderRevisions: Int { 16 }

    /// The server's version as a stored entry without a pending change.
    static func entry(from remote: RemoteChange<Record>, replacing existing: StoredEntry<Record>?, in state: inout State,
                      configuration: Configuration) -> StoredEntry<Record> {
        let limit = driftLimit(of: state, configuration: configuration)
        let timestamp = clamped(remote.timestamp, to: limit) ?? (try? state.clock.tick(at: configuration.now())) ?? state.clock.latest
        return StoredEntry(id: remote.recordID, record: remote.record, timestamp: timestamp, revision: remote.revision,
                           position: existing?.position ?? state.takeSequence(), pending: nil, history: state.history,
                           sequence: remote.sequence, serverTimestamp: orderable(remote.timestamp, below: limit))
    }

    /// Makes `remote` the server version `entry` is based on, without touching the record or
    /// its pending change.
    static func base(_ entry: inout StoredEntry<Record>, on remote: RemoteChange<Record>, in state: State,
                     configuration: Configuration) {
        entry.revision = remote.revision
        entry.history = state.history
        entry.sequence = remote.sequence
        entry.minimumSequence = nil
        entry.olderRevisions = []
        entry.pushedInHistory = nil
        entry.serverTimestamp = orderable(remote.timestamp, below: driftLimit(of: state, configuration: configuration))
    }

    // MARK: - Time limits

    /// The latest wall time, in milliseconds, a server timestamp may carry:
    /// ``Configuration/maximumClockDrift`` after the device clock, or after the newest timestamp
    /// the store wrote or took in when that is later. Counting from the newest timestamp keeps
    /// the limit above every local write, so a device whose clock was set back does not move
    /// other devices' later edits below its own earlier ones. The newest timestamp is itself at
    /// most the drift ahead of the device clock when it was taken in, so the limit is never more
    /// than twice the drift ahead of the latest time the device clock showed.
    static func driftLimit(of state: State, configuration: Configuration) -> Int64 {
        let now = HybridLogicalClock.milliseconds(since1970: configuration.now())
        let (limit, overflow) = max(now, state.clock.latest.wallTime)
            .addingReportingOverflow(configuration.maximumClockDrift.clampedMilliseconds)
        return overflow ? .max : limit
    }

    /// `timestamp` moved back to `limit` when it is further ahead: how last write wins weighs a
    /// version against a local write. A device with a wrong clock, or a hostile one, could
    /// otherwise stamp a write years ahead, and it would win every later conflict.
    static func clamped(_ timestamp: HLCTimestamp?, to limit: Int64) -> HLCTimestamp? {
        guard let timestamp, timestamp.wallTime > limit else { return timestamp }
        return HLCTimestamp(wallTime: limit, counter: timestamp.counter, nodeID: timestamp.nodeID)
    }

    /// `timestamp` when two server versions may be ordered by it; `nil` beyond `limit`. Moved
    /// back to the limit, every such timestamp would end at the same time and their order
    /// would be lost; kept as it is, one stamped far ahead would hide every later version.
    static func orderable(_ timestamp: HLCTimestamp?, below limit: Int64) -> HLCTimestamp? {
        guard let timestamp, timestamp.wallTime <= limit else { return nil }
        return timestamp
    }

    // MARK: - Order of server versions

    /// Whether `change` is an older server version than `other`, both of the current history.
    func isOlder(_ change: RemoteChange<Record>, than other: RemoteChange<Record>, in state: State) -> Bool {
        let limit = Self.driftLimit(of: state, configuration: configuration)
        return isOlder(change.sequence, Self.orderable(change.timestamp, below: limit),
                       than: other.sequence, nil, Self.orderable(other.timestamp, below: limit))
    }

    /// Whether `change` is an older server version than the one `entry` is based on: a page out
    /// of order, a lagging replica, the earlier version of a record whose deletion the store saw.
    ///
    /// The server's ``RemoteChange/sequence`` decides when both versions have one. Until the echo
    /// of the store's own accepted write arrives, the store knows only that the write is newer
    /// than every version up to the one it replaced (``StoredEntry/minimumSequence``) and than
    /// the versions its earlier accepted writes replaced (``StoredEntry/olderRevisions``). Only a
    /// server that sends no sequences is ordered by the timestamps, which matches the server's
    /// order as long as the devices resolve conflicts by ``ConflictResolver/lastWriteWins`` or a
    /// merge. A version from an earlier server history is never newer than the server's current
    /// one. When the order is unknown, the version counts as newer: the server sends its versions
    /// in order, so a newer one follows anyway.
    ///
    /// `isConflictAnswer` is true for the version a push answer names, which comes from the
    /// server itself. What an entry moved into a new history from a push answer of the old one
    /// knows about the order (``StoredEntry/pushedInHistory``) is then not used: after a restore
    /// that set the server's sequence back, it could make the store refuse the server's current
    /// version on every push.
    func isStale(_ change: RemoteChange<Record>, comparedWith entry: StoredEntry<Record>, in state: State,
                 isConflictAnswer: Bool = false) -> Bool {
        guard entry.revision != nil, entry.history == state.history else { return false }
        if isConflictAnswer, let pushed = entry.pushedInHistory, pushed != entry.history { return false }
        if entry.olderRevisions.contains(change.revision) { return true }
        let limit = Self.driftLimit(of: state, configuration: configuration)
        return isOlder(change.sequence, Self.orderable(change.timestamp, below: limit),
                       than: entry.sequence, entry.minimumSequence, entry.serverTimestamp)
    }

    /// Orders two server versions. `heldMinimum` is a sequence the second version is known to
    /// follow; the timestamps are ``orderable(_:below:)`` ones.
    private func isOlder(_ sequence: UInt64?, _ timestamp: HLCTimestamp?, than heldSequence: UInt64?, _ heldMinimum: UInt64?,
                         _ heldTimestamp: HLCTimestamp?) -> Bool {
        if let sequence {
            if let heldSequence { return sequence < heldSequence }
            if let heldMinimum, sequence <= heldMinimum { return true }
        }
        guard sequence == nil, heldSequence == nil, let timestamp, let heldTimestamp else { return false }
        return timestamp < heldTimestamp
    }

    /// How a server version relates to `entry`'s pending change, judged by its timestamp. A
    /// version counts as the store's own only with the exact timestamp of a write the store
    /// knows the server may hold, not by the node ID alone: a store file restored onto a second
    /// device writes with the same node ID.
    enum Authorship {
        /// The pending change itself, applied by the server.
        case pendingChange
        /// An earlier write of this store. The pending change was made on top of it on this
        /// device, so it is not a conflict.
        case earlierWrite
        /// Another device's write, or one the store cannot tell.
        case other
    }

    func authorship(of change: RemoteChange<Record>, comparedWith entry: StoredEntry<Record>) -> Authorship {
        guard let pending = entry.pending, let timestamp = change.timestamp else { return .other }
        if timestamp == entry.timestamp { return .pendingChange }
        return pending.supersededInDoubt.contains(timestamp) ? .earlierWrite : .other
    }

    /// Stores `entry`. A deletion with nothing left to push is kept as a tombstone while the
    /// server confirmed it (it has a revision), so an older version of the record that arrives
    /// later is recognised; otherwise it is removed.
    static func store(_ entry: StoredEntry<Record>, in state: inout State) {
        let isGone = entry.record == nil && entry.pending == nil && entry.revision == nil
        state.entries[entry.id] = isGone ? nil : entry
    }

    /// Drops the oldest tombstones beyond `limit` (``Configuration/maximumTombstones``): those of
    /// earlier server histories first, then by the server's sequence and the timestamp.
    static func pruneTombstones(in state: inout State, limit: Int) {
        let tombstones = state.entries.values.filter { $0.record == nil && $0.pending == nil }
        guard tombstones.count > limit else { return }
        let oldestFirst = tombstones.sorted {
            ($0.history, $0.sequence ?? $0.minimumSequence ?? 0, $0.timestamp)
                < ($1.history, $1.sequence ?? $1.minimumSequence ?? 0, $1.timestamp)
        }
        for entry in oldestFirst.prefix(tombstones.count - limit) {
            state.entries[entry.id] = nil
        }
    }

    /// A server record is not used when its own ID differs from the ID it was sent for, or when
    /// its revision or timestamp is longer than the limits.
    static func isConsistent(_ change: RemoteChange<Record>, for id: Record.ID) -> Bool {
        inconsistency(of: change, for: id) == nil
    }

    /// Why a server record cannot be used for `id`, or `nil` when it can.
    static func inconsistency(of change: RemoteChange<Record>, for id: Record.ID) -> String? {
        if change.recordID != id {
            return "The change belongs to another record."
        }
        if let record = change.record, record.id != id {
            return "The record's own ID differs from the change's recordID."
        }
        if change.revision.utf8.count > maximumRevisionLength {
            return "The revision is longer than \(maximumRevisionLength) bytes."
        }
        if let timestamp = change.timestamp, timestamp.nodeID.utf8.count > maximumNodeIDLength {
            return "The timestamp's node ID is longer than \(maximumNodeIDLength) bytes."
        }
        return nil
    }

    /// Server changes the store keeps in ``OfflineStore/quarantinedChanges()``; the oldest go.
    static var maximumQuarantinedChanges: Int { 100 }

    /// Sets a server change aside, in place of an earlier entry for the same record, with every
    /// text cut to the limits.
    static func quarantine(_ change: QuarantinedChange, in state: inout State, report: inout SyncReport) {
        let entry = QuarantinedChange(recordID: String(change.recordID.prefix(maximumRevisionLength)),
                                      revision: change.revision.map { String($0.prefix(maximumRevisionLength)) },
                                      reason: String(change.reason.prefix(maximumMessageLength)))
        state.quarantine.removeAll { $0.recordID == entry.recordID }
        state.quarantine.append(entry)
        state.quarantine.removeFirst(max(0, state.quarantine.count - maximumQuarantinedChanges))
        report.quarantined += 1
    }

    /// A record ID as JSON, as ``QuarantinedChange/recordID`` holds it.
    static func describe(_ id: Record.ID) -> String {
        (try? JSONEncoder().encode(id)).map { String(decoding: $0, as: UTF8.self) } ?? String(describing: id)
    }
}
