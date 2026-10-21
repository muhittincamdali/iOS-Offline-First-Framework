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
    /// it. Written before the request goes out. A pull does not resolve such a change unless it
    /// brings the change itself (its timestamp); otherwise only its next push, under the same
    /// change ID, can tell whether it was applied.
    var isInDoubt = false
    /// The timestamps of earlier versions of this change that were in doubt when the record
    /// changed again, newest last. The server may have applied any of them; a server version
    /// with one of these timestamps is the device's own earlier write, which the pending change
    /// was made on top of, not another device's. Emptied once the server's answer or a new
    /// base shows that none of them can be the server's current version.
    var supersededInDoubt: [HLCTimestamp] = []
    /// The change IDs of the same earlier versions, for a server that names the change that
    /// wrote a version (``RemoteChange/changeID``).
    var supersededChangeIDs: [UUID] = []

    /// Superseded versions in doubt a change remembers; more than one needs several lost
    /// answers between edits.
    static var maximumSupersededInDoubt: Int { 16 }
}

extension PendingWrite {
    private enum CodingKeys: String, CodingKey {
        case changeID, sequence, attempts, nextAttemptAt, lastError, isParked, isInDoubt, supersededInDoubt, supersededChangeIDs
    }

    /// Files written before `isInDoubt`, `supersededInDoubt` or `supersededChangeIDs` existed
    /// have no such keys.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        changeID = try container.decode(UUID.self, forKey: .changeID)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        attempts = try container.decode(Int.self, forKey: .attempts)
        nextAttemptAt = try container.decodeIfPresent(Date.self, forKey: .nextAttemptAt)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
        isParked = try container.decode(Bool.self, forKey: .isParked)
        isInDoubt = try container.decodeIfPresent(Bool.self, forKey: .isInDoubt) ?? false
        supersededInDoubt = try container.decodeIfPresent([HLCTimestamp].self, forKey: .supersededInDoubt) ?? []
        supersededChangeIDs = try container.decodeIfPresent([UUID].self, forKey: .supersededChangeIDs) ?? []
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(changeID, forKey: .changeID)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(attempts, forKey: .attempts)
        try container.encodeIfPresent(nextAttemptAt, forKey: .nextAttemptAt)
        try container.encodeIfPresent(lastError, forKey: .lastError)
        try container.encode(isParked, forKey: .isParked)
        try container.encode(isInDoubt, forKey: .isInDoubt)
        if !supersededInDoubt.isEmpty {
            try container.encode(supersededInDoubt, forKey: .supersededInDoubt)
        }
        if !supersededChangeIDs.isEmpty {
            try container.encode(supersededChangeIDs, forKey: .supersededChangeIDs)
        }
    }
}
