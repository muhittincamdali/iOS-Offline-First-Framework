import Foundation

/// A local change that has not reached the server yet.
struct PendingWrite: Codable, Hashable, Sendable {
    /// Changes whenever the record changes locally, so an answer to an older push is recognised.
    var changeID: UUID
    /// Order in which changes were queued.
    var sequence: UInt64
    var attempts: Int
    var nextAttemptAt: Date?
    var lastError: String?
    /// Parked changes wait for ``OfflineStore/retryFailedChanges()``.
    var isParked: Bool
    /// Whether this version was sent and no answer came back, so the server may have applied
    /// it. Written before the request goes out. A pull does not resolve such a change: only
    /// its next push, under the same change ID, can tell whether it was applied.
    var isInDoubt = false
}

extension PendingWrite {
    private enum CodingKeys: String, CodingKey {
        case changeID, sequence, attempts, nextAttemptAt, lastError, isParked, isInDoubt
    }

    /// Files written before `isInDoubt` existed have no such key.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        changeID = try container.decode(UUID.self, forKey: .changeID)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        attempts = try container.decode(Int.self, forKey: .attempts)
        nextAttemptAt = try container.decodeIfPresent(Date.self, forKey: .nextAttemptAt)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        isParked = try container.decode(Bool.self, forKey: .isParked)
        isInDoubt = try container.decodeIfPresent(Bool.self, forKey: .isInDoubt) ?? false
    }
}

/// One record of the store, with its sync state.
struct StoredEntry<Record: SyncableRecord>: Codable, Sendable {
    let id: Record.ID
    /// `nil` while a local delete waits to be confirmed by the server.
    var record: Record?
    /// When the record last changed, locally or on the server.
    var timestamp: HLCTimestamp
    /// The last server revision of the record, or `nil` if the server has never confirmed it.
    var revision: String?
    /// The order the record was first stored in.
    var position: UInt64
    var pending: PendingWrite?
    /// Whether a push of this record was ever sent. Written to the file before the request goes
    /// out: when the answer is lost, or the app ends before it arrives, the server may hold the
    /// record although ``revision`` is still `nil`, so a later delete must reach the server.
    var wasSent = false
    /// The server history (``OfflineStore/State/history``) ``revision`` belongs to. A version
    /// from an earlier history says nothing about the order of the server's current versions.
    var history: UInt64 = 0
    /// The ``RemoteChange/sequence`` of the server version ``revision`` names, if known.
    var sequence: UInt64? = nil
    /// Every server version of the record whose sequence is at most this one is older than
    /// the version ``revision`` names. Set when the server accepted the store's own write on top
    /// of a version whose sequence the store knew; the write's echo in a pull tells its own
    /// ``sequence``.
    var minimumSequence: UInt64? = nil
    /// The timestamp of the server version ``revision`` names, if the server sent one the store
    /// can order versions by: not further ahead than the drift limit when it arrived (see
    /// ``OfflineStore/Configuration/maximumClockDrift``). `nil` says nothing about the order.
    /// ``timestamp`` is the local write's while a change is pending.
    var serverTimestamp: HLCTimestamp? = nil
    /// The newest server version a pull brought while the pending change was in doubt
    /// (``PendingWrite/isInDoubt``). It is newer than that change, so it replaces the record
    /// once the next push shows the change was applied; a conflict answer makes it moot.
    var deferredRemote: RemoteChange<Record>? = nil
}

extension StoredEntry {
    private enum CodingKeys: String, CodingKey {
        case id, record, timestamp, revision, position, pending, wasSent, history, sequence, minimumSequence, serverTimestamp,
             deferredRemote
    }

    /// Files written before `wasSent` existed have no such key; their records count as unsent.
    /// Files written before `history` existed belong to the first history. Files written before
    /// `serverTimestamp` existed kept the server's timestamp as ``timestamp`` while no change
    /// was pending; newer files always write the key, `null` when the server sent none.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Record.ID.self, forKey: .id)
        record = try container.decodeIfPresent(Record.self, forKey: .record)
        timestamp = try container.decode(HLCTimestamp.self, forKey: .timestamp)
        revision = try container.decodeIfPresent(String.self, forKey: .revision)
        position = try container.decode(UInt64.self, forKey: .position)
        pending = try container.decodeIfPresent(PendingWrite.self, forKey: .pending)
        wasSent = try container.decodeIfPresent(Bool.self, forKey: .wasSent) ?? false
        history = try container.decodeIfPresent(UInt64.self, forKey: .history) ?? 0
        sequence = try container.decodeIfPresent(UInt64.self, forKey: .sequence)
        minimumSequence = try container.decodeIfPresent(UInt64.self, forKey: .minimumSequence)
        if container.contains(.serverTimestamp) {
            serverTimestamp = try container.decodeIfPresent(HLCTimestamp.self, forKey: .serverTimestamp)
        } else {
            serverTimestamp = pending == nil ? timestamp : nil
        }
        deferredRemote = try container.decodeIfPresent(RemoteChange<Record>.self, forKey: .deferredRemote)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(record, forKey: .record)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(revision, forKey: .revision)
        try container.encode(position, forKey: .position)
        try container.encodeIfPresent(pending, forKey: .pending)
        try container.encode(wasSent, forKey: .wasSent)
        try container.encode(history, forKey: .history)
        try container.encodeIfPresent(sequence, forKey: .sequence)
        try container.encodeIfPresent(minimumSequence, forKey: .minimumSequence)
        // Written also when it is nil, so a file tells a server version without a timestamp
        // from a file of a version before the key existed.
        if let serverTimestamp {
            try container.encode(serverTimestamp, forKey: .serverTimestamp)
        } else {
            try container.encodeNil(forKey: .serverTimestamp)
        }
        try container.encodeIfPresent(deferredRemote, forKey: .deferredRemote)
    }
}

/// The file an ``OfflineStore`` writes.
struct StoreFile<Record: SyncableRecord>: Codable, Sendable {
    static var currentFormat: Int { 1 }

    var format: Int
    var schemaVersion: Int
    var nodeID: String
    var clock: HLCTimestamp?
    var token: String?
    var lastSyncedAt: Date?
    var nextSequence: UInt64
    var entries: [StoredEntry<Record>]
    /// The ``SyncTransport/serverIdentity`` the token belongs to.
    var serverIdentity: String? = nil
    /// The last ``PullResponse/epoch`` the server reported.
    var serverEpoch: String? = nil
    /// Counts the server histories the store has seen; `nil` in files from before it existed.
    var history: UInt64? = nil
    /// Server changes set aside; `nil` when there are none.
    var quarantine: [QuarantinedChange]? = nil
}

/// The two fields read before the rest of the file, to pick the migrations.
private struct StoreFileHeader: Decodable {
    var format: Int
    var schemaVersion: Int
}

enum StoreFileCoder {
    static func encode<Record>(_ file: StoreFile<Record>) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(file)
    }

    /// Decodes a store file and runs the record migrations it needs.
    ///
    /// - Throws: ``OfflineFirstError/unsupportedSchemaVersion(found:supported:)`` and
    ///   ``OfflineFirstError/migrationFailed(toVersion:description:)`` as they are, and
    ///   ``OfflineFirstError/corruptStore(name:description:)`` for anything that cannot be read.
    static func decode<Record>(
        _ data: Data,
        as type: Record.Type,
        name: String,
        schemaVersion: Int,
        migrations: [RecordMigration]
    ) throws -> StoreFile<Record> {
        let decoder = JSONDecoder()
        let header: StoreFileHeader
        do {
            header = try decoder.decode(StoreFileHeader.self, from: data)
        } catch {
            throw OfflineFirstError.corruptStore(name: name, description: String(describing: error))
        }
        guard header.format == StoreFile<Record>.currentFormat else {
            throw OfflineFirstError.corruptStore(name: name, description: "unknown file format \(header.format)")
        }
        var payload = data
        if header.schemaVersion != schemaVersion {
            payload = try migrate(data, from: header.schemaVersion, to: schemaVersion, name: name, migrations: migrations)
        }
        do {
            return try decoder.decode(StoreFile<Record>.self, from: payload)
        } catch {
            throw OfflineFirstError.corruptStore(name: name, description: String(describing: error))
        }
    }

    private static func migrate(_ data: Data, from stored: Int, to current: Int, name: String, migrations: [RecordMigration]) throws -> Data {
        guard case .object(var file) = try decodeTree(data, name: name),
              case .array(var entries) = file["entries"] ?? .array([])
        else {
            throw OfflineFirstError.corruptStore(name: name, description: "the file has no list of entries")
        }
        // Only live records are migrated; a deleted one has no "record" key.
        let liveIndices = entries.indices.filter { entries[$0]["record"].map { $0 != .null } ?? false }
        var records = liveIndices.compactMap { entries[$0]["record"] }
        try RecordMigration.migrate(&records, from: stored, to: current, using: migrations)
        for (index, record) in zip(liveIndices, records) {
            entries[index]["record"] = record
        }
        file["entries"] = .array(entries)
        file["schemaVersion"] = .integer(Int64(current))
        do {
            return try JSONEncoder().encode(JSONValue.object(file))
        } catch {
            throw OfflineFirstError.migrationFailed(toVersion: current, description: String(describing: error))
        }
    }

    private static func decodeTree(_ data: Data, name: String) throws -> JSONValue {
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw OfflineFirstError.corruptStore(name: name, description: String(describing: error))
        }
    }
}
