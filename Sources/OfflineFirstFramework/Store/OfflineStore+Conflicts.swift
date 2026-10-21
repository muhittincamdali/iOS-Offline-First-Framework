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
        var pending = rebased(entry.pending
            ?? PendingWrite(changeID: UUID(), sequence: state.takeSequence(), attempts: 0, nextAttemptAt: nil, lastError: nil, isParked: false))
        if let pushesInThisSync {
            pending = conflictAttempt(pending, pushesInThisSync: pushesInThisSync, report: &report)
        }
        result.pending = pending
        return result
    }

    /// `pending` under a new change ID, so the server does not answer its push on a new base
    /// from an idempotency cache. On the new base, no earlier version in doubt can become the
    /// server's current one: its request names an older base.
    func rebased(_ pending: PendingWrite) -> PendingWrite {
        var pending = pending
        pending.changeID = UUID()
        pending.isInDoubt = false
        pending.supersededInDoubt = []
        pending.supersededChangeIDs = []
        return pending
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
