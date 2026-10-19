import Foundation

extension OfflineStore {
    /// Reads the store file, or returns an empty one.
    static func load(name: String, storage: any StorageBackend, configuration: Configuration) throws -> StoreFile<Record> {
        let fileName = "\(name).store"
        let empty = StoreFile<Record>(format: StoreFile<Record>.currentFormat, schemaVersion: configuration.schemaVersion,
                                      nodeID: UUID().uuidString, clock: nil, token: nil, lastSyncedAt: nil,
                                      nextSequence: 0, entries: [])
        do {
            guard let data = try storage.read(fileName) else { return empty }
            let plaintext = try configuration.encryption.open(data, name: name)
            return try StoreFileCoder.decode(plaintext, as: Record.self, name: name,
                                             schemaVersion: configuration.schemaVersion, migrations: configuration.migrations)
        } catch let error as OfflineFirstError {
            guard case .moveAsideAndStartEmpty = configuration.corruptionPolicy, error.allowsReset else { throw error }
            let milliseconds = HybridLogicalClock.milliseconds(since1970: configuration.now())
            // The prefix keeps the new name within the 255-byte limit.
            try storage.move(fileName, to: "\(fileName.prefix(200)).corrupt-\(milliseconds)")
            return empty
        }
    }

    /// Builds the in-memory state from a decoded file, repairing values a damaged or edited file
    /// could carry: duplicate IDs, negative attempt counts, an empty node ID, and positions or
    /// sequence numbers close to `UInt64.max` (they are renumbered from zero, so incrementing
    /// them cannot overflow).
    static func makeState(from file: StoreFile<Record>, configuration: Configuration) -> State {
        var byID: [Record.ID: StoredEntry<Record>] = [:]
        for entry in file.entries {
            byID[entry.id] = entry
        }
        var sequence: UInt64 = 0
        for entry in byID.values.sorted(by: { $0.position < $1.position }) {
            byID[entry.id]?.position = sequence
            sequence += 1
        }
        let queued = byID.values.compactMap { entry in entry.pending.map { (entry.id, $0.sequence) } }
        for (id, _) in queued.sorted(by: { $0.1 < $1.1 }) {
            guard var pending = byID[id]?.pending else { continue }
            pending.sequence = sequence
            pending.attempts = max(0, pending.attempts)
            byID[id]?.pending = pending
            sequence += 1
        }
        // A deletion that is neither queued nor confirmed by the server has nothing left to do.
        byID = byID.filter { $0.value.record != nil || $0.value.pending != nil || $0.value.revision != nil }

        let nodeID = file.nodeID.isEmpty ? UUID().uuidString : file.nodeID
        let clock = HybridLogicalClock(nodeID: nodeID, maximumDrift: configuration.maximumClockDrift, latest: file.clock)
        return State(entries: byID, clock: clock, token: file.token, lastSyncedAt: file.lastSyncedAt, nextSequence: sequence,
                     serverIdentity: file.serverIdentity, serverEpoch: file.serverEpoch, history: file.history ?? 0,
                     quarantine: Array((file.quarantine ?? []).suffix(maximumQuarantinedChanges)),
                     previousEpochs: Array((file.previousEpochs ?? []).suffix(maximumPreviousEpochs)))
    }
}

extension OfflineFirstError {
    /// Errors after which ``CorruptionPolicy/moveAsideAndStartEmpty`` may reset the store: the
    /// file is damaged, or larger than the backend reads (written before writes were limited,
    /// or the limit was lowered).
    var allowsReset: Bool {
        switch self {
        case .corruptStore, .decryptionFailed, .fileTooLarge: true
        default: false
        }
    }
}
