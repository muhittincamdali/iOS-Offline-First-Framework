import Foundation

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
    /// of a version whose sequence the store knew, or on top of none (0: every other version
    /// came after it); the write's echo in a pull tells its own ``sequence``.
    var minimumSequence: UInt64? = nil
    /// Revisions of versions that the store's own accepted writes replaced, up to ``revision``,
    /// whose order the sequences do not tell: earlier writes of the store without an echo, and
    /// a version of an earlier history the write was based on. Each is older than ``revision``,
    /// since a server never gives a revision twice. Kept until a pull tells the sequence of
    /// ``revision``.
    var olderRevisions: [String] = []
    /// The ``history`` the store was in when a push answer set ``revision``: the server accepted
    /// the store's write, or answered a conflict with its current version. `nil` once a pull
    /// brought that version or another one. The server may have answered from a later history
    /// than the store's, after a restart the store has not seen yet, so when a pull starts a
    /// later epoch such an entry moves into the new history and keeps what it knows about the
    /// order (see ``OfflineStore/beginHistory(epoch:isLaterEpoch:isAnotherServer:in:)``). An
    /// entry whose ``history`` differs from this one was moved so.
    var pushedInHistory: UInt64? = nil
    /// The newest server version a pull brought while the pending change was in doubt
    /// (``PendingWrite/isInDoubt``). It is newer than that change, so it replaces the record
    /// once the next push shows the change was applied; a conflict answer makes it moot. For a
    /// change of an earlier server history that is not in doubt, the version of the new history
    /// a pull brought, kept until the change is sent.
    var deferredRemote: RemoteChange<Record>? = nil
    /// The change IDs of this store's writes of the record that the server holds or held: those
    /// it accepted, those a pull or a conflict answer showed it applied, and the versions of a
    /// change that were in doubt when a push answer settled it, which the server may have
    /// applied (``PendingWrite/supersededChangeIDs``). Newest last, at most
    /// ``maximumOwnWrites``. A server version that one of them wrote is the device's own write,
    /// whatever the store shows for the record: when a stale page took the record back to an
    /// older version and the user edited on top of that, the server's answer that names the
    /// device's accepted write is not a conflict (see
    /// ``OfflineStore/authorship(of:comparedWith:)``). Kept across server histories, since a
    /// change ID names one write on every server.
    var ownChangeIDs: [UUID] = []
    /// The timestamps of the same writes, by which the store knows them on a server that does
    /// not send change IDs. Newest last, at most ``maximumOwnWrites``.
    var ownTimestamps: [HLCTimestamp] = []

    /// Own writes an entry remembers, by change ID and by timestamp: 16, the oldest dropped first.
    static var maximumOwnWrites: Int { 16 }

    /// Remembers a write of this store that the server holds, by the change ID and timestamp it
    /// was pushed with, or by those a server version names.
    mutating func rememberOwnWrite(changeID: UUID?, timestamp: HLCTimestamp?) {
        if let changeID, !ownChangeIDs.contains(changeID) {
            ownChangeIDs = Array((ownChangeIDs + [changeID]).suffix(Self.maximumOwnWrites))
        }
        if let timestamp, !ownTimestamps.contains(timestamp) {
            ownTimestamps = Array((ownTimestamps + [timestamp]).suffix(Self.maximumOwnWrites))
        }
    }
}

extension StoredEntry {
    private enum CodingKeys: String, CodingKey {
        case id, record, timestamp, revision, position, pending, wasSent, history, sequence, minimumSequence, olderRevisions,
             pushedInHistory, deferredRemote, ownChangeIDs, ownTimestamps
    }

    /// Files written before `wasSent` existed have no such key; their records count as unsent.
    /// Files written before `history` existed belong to the first history. Files written before
    /// `ownChangeIDs` and `ownTimestamps` existed know no own writes; a damaged file keeps the
    /// newest within the limit.
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
        olderRevisions = try container.decodeIfPresent([String].self, forKey: .olderRevisions) ?? []
        pushedInHistory = try container.decodeIfPresent(UInt64.self, forKey: .pushedInHistory)
        deferredRemote = try container.decodeIfPresent(RemoteChange<Record>.self, forKey: .deferredRemote)
        ownChangeIDs = try Array((container.decodeIfPresent([UUID].self, forKey: .ownChangeIDs) ?? []).suffix(Self.maximumOwnWrites))
        ownTimestamps = try Array((container.decodeIfPresent([HLCTimestamp].self, forKey: .ownTimestamps) ?? [])
            .suffix(Self.maximumOwnWrites))
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
        if !olderRevisions.isEmpty {
            try container.encode(olderRevisions, forKey: .olderRevisions)
        }
        try container.encodeIfPresent(pushedInHistory, forKey: .pushedInHistory)
        try container.encodeIfPresent(deferredRemote, forKey: .deferredRemote)
        if !ownChangeIDs.isEmpty {
            try container.encode(ownChangeIDs, forKey: .ownChangeIDs)
        }
        if !ownTimestamps.isEmpty {
            try container.encode(ownTimestamps, forKey: .ownTimestamps)
        }
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
    /// Whether two requests reported ``serverEpoch``, or that the server reports none; `nil`
    /// when not, as in files from before it existed: the next sync checks the epoch with a second
    /// request.
    var epochIsConfirmed: Bool? = nil
    /// Counts the server histories the store has seen; `nil` in files from before it existed.
    var history: UInt64? = nil
    /// Server changes set aside; `nil` when there are none.
    var quarantine: [QuarantinedChange]? = nil
    /// Epochs the store left for a later one, oldest first; `nil` when there are none.
    var retiredEpochs: [String]? = nil
    /// Whether the next sync pulls from the beginning; `nil` when not.
    var pullsFromBeginning: Bool? = nil
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
