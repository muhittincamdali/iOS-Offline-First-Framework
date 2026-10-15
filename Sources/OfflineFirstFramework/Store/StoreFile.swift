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
}

extension StoredEntry {
    private enum CodingKeys: String, CodingKey {
        case id, record, timestamp, revision, position, pending, wasSent
    }

    /// Files written before `wasSent` existed have no such key; their records count as unsent.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Record.ID.self, forKey: .id)
        record = try container.decodeIfPresent(Record.self, forKey: .record)
        timestamp = try container.decode(HLCTimestamp.self, forKey: .timestamp)
        revision = try container.decodeIfPresent(String.self, forKey: .revision)
        position = try container.decode(UInt64.self, forKey: .position)
        pending = try container.decodeIfPresent(PendingWrite.self, forKey: .pending)
        wasSent = try container.decodeIfPresent(Bool.self, forKey: .wasSent) ?? false
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
