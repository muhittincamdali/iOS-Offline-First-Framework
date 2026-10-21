import Foundation

/// Settling conflicts with the ``ConflictResolver``.
extension OfflineStore {
    /// Asks the resolver about `entry`'s pending change and `remote`, the server's newer version.
    ///
    /// - Parameter pushesInThisSync: For a conflict the server answered to a push, how often the
    ///   change was pushed in this sync; `nil` for a conflict found by a pull, which is not a
    ///   failed attempt.
    func resolve(_ entry: StoredEntry<Record>, against remote: RemoteChange<Record>, in state: inout State,
                 pushesInThisSync: Int?, report: inout SyncReport) throws -> StoredEntry<Record> {
        // Two deletions are a conflict too: with last write wins the newer one has to stay on the
        // server, or an older edit based on the older deletion would bring the record back.
        let conflict = Conflict(recordID: entry.id, local: entry.record, localTimestamp: entry.timestamp, remote: remote.record,
                                remoteTimestamp: Self.clamped(remote.timestamp, to: Self.driftLimit(of: state, around: entry.timestamp,
                                                                                                  configuration: configuration)))
        var result = entry
        switch configuration.conflictResolver.resolve(conflict) {
        case .keepRemote:
            return Self.entry(from: remote, replacing: entry, in: &state, configuration: configuration)
        case .merged(let merged) where merged.id != entry.id || NestingDepth.exceeds(merged, limit: Self.maximumRecordDepth):
            // A merge for another record, or one the store could not write: the server's version.
            return Self.entry(from: remote, replacing: entry, in: &state, configuration: configuration)
        case .merged(let merged):
            result.record = merged
            result.timestamp = try Self.tick(&state, configuration: configuration)
        case .keepLocal:
            break
        }
        // The local or merged version goes out again on top of the server's revision.
        Self.base(&result, on: remote, in: state, configuration: configuration)
        var pending = renewed(entry.pending
            ?? PendingWrite(changeID: UUID(), sequence: state.takeSequence(), attempts: 0, nextAttemptAt: nil, lastError: nil, isParked: false))
        if let pushesInThisSync {
            pending = conflictAttempt(pending, pushesInThisSync: pushesInThisSync, report: &report)
        }
        result.pending = pending
        return result
    }

    /// `pending` under a new change ID, for a push on a new base: the server does not answer it
    /// from its memory of change IDs with the answer to the old base.
    ///
    /// The earlier versions in doubt stay with the change (``PendingWrite/supersededInDoubt``).
    /// The server may hold one of them although no answer said so, and a new base from a page
    /// does not tell otherwise: a page out of order, or the first page of a new epoch, can list
    /// an older version before them, also an older write of the device itself. Only a push
    /// answer settles them (``settleVersionsInDoubt(of:)``).
    func renewed(_ pending: PendingWrite) -> PendingWrite {
        var pending = pending
        pending.changeID = UUID()
        return pending
    }

    /// Settles the earlier versions in doubt of `entry`'s pending change once a push answer
    /// showed the server's current version, accepted or in conflict: from then on the server's
    /// answers tell where the change stands. The server may have applied one of those versions
    /// before, or apply one whose request is still on its way, so they move to the device's own
    /// writes (``StoredEntry/ownChangeIDs``): a page or an answer that brings one of them later
    /// is the device's own write, never a conflict.
    static func settleVersionsInDoubt(of entry: inout StoredEntry<Record>) {
        guard let pending = entry.pending else { return }
        for changeID in pending.supersededChangeIDs {
            entry.rememberOwnWrite(changeID: changeID, timestamp: nil)
        }
        for timestamp in pending.supersededInDoubt {
            entry.rememberOwnWrite(changeID: nil, timestamp: timestamp)
        }
        entry.pending?.supersededInDoubt = []
        entry.pending?.supersededChangeIDs = []
    }

    /// Counts a conflict answer as a failed attempt of the resolved change. The first one in a
    /// sync is pushed again right away, which settles an ordinary conflict; when the server
    /// answers that push with a conflict too, the change waits as the ``RetryPolicy`` says, and
    /// after its last attempt it is parked. Two devices that both keep their own version
    /// (``ConflictResolver/clientWins``) or a server that conflicts on every push therefore
    /// cannot keep the store pushing.
    func conflictAttempt(_ pending: PendingWrite, pushesInThisSync: Int, report: inout SyncReport) -> PendingWrite {
        var pending = pending
        pending.attempts = pending.attempts == .max ? .max : pending.attempts + 1
        let policy = configuration.retryPolicy
        guard policy.allowsRetry(afterAttempts: pending.attempts) else {
            pending.isParked = true
            pending.nextAttemptAt = nil
            pending.lastError = "The server answered with a conflict again after \(pending.attempts) attempts."
            report.parked += 1
            return pending
        }
        pending.lastError = "The server answered with a conflict."
        if pushesInThisSync > 1 {
            let delay = policy.delay(afterAttempt: pending.attempts, random: configuration.random())
            pending.nextAttemptAt = configuration.now().addingTimeInterval(delay.seconds)
        } else {
            pending.nextAttemptAt = nil
        }
        return pending
    }
}
