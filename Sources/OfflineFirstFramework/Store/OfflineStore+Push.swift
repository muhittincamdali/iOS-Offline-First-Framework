import Foundation

/// Pushing local changes and handling the server's answers.
extension OfflineStore {
    func push(using transport: any SyncTransport<Record>, until deadline: ContinuousClock.Instant,
              report: inout SyncReport) async throws {
        var pushes: [Record.ID: Int] = [:]
        while true {
            try Task.checkCancellation()
            let changes = dueChanges(excluding: pushes)
            guard !changes.isEmpty else { return }
            let firstSent = try markSent(changes)
            for change in changes {
                pushes[change.recordID, default: 0] += 1
                inFlight.insert(change.recordID)
            }
            let outcomes: [UUID: PushOutcome<Record>]
            do {
                outcomes = try await Self.run(until: deadline) { try await transport.push(changes) }
            } catch {
                inFlight.subtract(changes.map(\.recordID))
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                // A failed write of the attempt count (a full disk) must not hide the reason the
                // push failed; the attempt then counts again next time.
                // A request that never left the device leaves a change in doubt only if an
                // earlier push of it may have been applied.
                try? recordFailedAttempts(changes, message: Self.message(for: error),
                                          notInDoubt: Self.wasNeverSent(error) ? firstSent : [], report: &report)
                throw error
            }
            inFlight.subtract(changes.map(\.recordID))
            try apply(outcomes, for: changes, pushes: pushes, report: &report)
        }
    }

    /// Records in `changes` the server has not confirmed are marked as sent, and the mark is
    /// written before the request leaves: the server may apply a push whose answer never
    /// arrives, so from now on deleting the record has to go through the server.
    ///
    /// Each change is also marked as in doubt until its answer arrives, so a pull meanwhile, or
    /// after a lost answer, leaves it to the next push instead of resolving it again under a new
    /// change ID: the server may already have applied it, and resolving it again could put it
    /// back over a newer write.
    ///
    /// - Returns: The changes sent for the first time, which were not in doubt before.
    @discardableResult
    private func markSent(_ changes: [OutgoingChange<Record>]) throws -> Set<UUID> {
        let unmarked = changes.filter { change in
            guard let entry = state.entries[change.recordID] else { return false }
            return (entry.revision == nil && !entry.wasSent)
                || (entry.pending?.changeID == change.id && entry.pending?.isInDoubt == false)
        }
        guard !unmarked.isEmpty else { return [] }
        return try update { state in
            var firstSent: Set<UUID> = []
            for change in unmarked {
                guard var entry = state.entries[change.recordID] else { continue }
                if entry.revision == nil { entry.wasSent = true }
                if entry.pending?.changeID == change.id, entry.pending?.isInDoubt == false {
                    entry.pending?.isInDoubt = true
                    firstSent.insert(change.id)
                }
                state.entries[change.recordID] = entry
            }
            return firstSent
        }
    }

    /// The next batch: queued, not parked, due, and pushed fewer than the limit in this sync.
    func dueChanges(excluding pushes: [Record.ID: Int]) -> [OutgoingChange<Record>] {
        let now = configuration.now()
        return state.entries.values
            .filter { entry in
                guard let pending = entry.pending, !pending.isParked else { return false }
                if let next = pending.nextAttemptAt, next > now { return false }
                return pushes[entry.id, default: 0] < Self.maximumPushesPerRecord
            }
            .sorted { ($0.pending?.sequence ?? 0) < ($1.pending?.sequence ?? 0) }
            .prefix(configuration.pushBatchSize)
            .compactMap { entry in
                guard let pending = entry.pending else { return nil }
                return OutgoingChange(id: pending.changeID, recordID: entry.id, operation: entry.record.map { .upsert($0) } ?? .delete,
                                      timestamp: entry.timestamp, baseRevision: entry.revision)
            }
    }

    private func apply(_ outcomes: [UUID: PushOutcome<Record>], for changes: [OutgoingChange<Record>], pushes: [Record.ID: Int],
                       report: inout SyncReport) throws {
        try update { state in
            for change in changes {
                guard var entry = state.entries[change.recordID] else { continue }
                // False when the record changed locally while the push was on its way.
                let isCurrent = entry.pending?.changeID == change.id
                switch outcomes[change.id] {
                case nil:
                    if isCurrent { fail(&entry, message: "The server did not answer this change.", report: &report) }
                case .accepted(let revision) where revision.utf8.count > Self.maximumRevisionLength:
                    if isCurrent {
                        fail(&entry, message: "The server answered with a revision of more than \(Self.maximumRevisionLength) bytes.",
                             report: &report)
                    }
                case .accepted(let revision):
                    report.pushed += 1
                    accept(change, as: revision, into: &entry, isCurrent: isCurrent, in: &state, report: &report)
                case .conflict(let current):
                    guard isCurrent else {
                        report.conflicts += 1
                        break
                    }
                    try settle(&entry, conflictingWith: current, pushesInThisSync: pushes[change.recordID] ?? 1, in: &state,
                               report: &report)
                case .rejected(let reason, let current):
                    report.rejected += 1
                    guard isCurrent else { break }
                    entry.pending?.isInDoubt = false
                    let deferred = entry.deferredRemote
                    entry.deferredRemote = nil
                    if let current, Self.isConsistent(current, for: entry.id) {
                        receive(current, in: &state)
                        entry = Self.entry(from: newer(deferred, than: current, in: state), replacing: entry, in: &state,
                                           configuration: configuration)
                    } else {
                        entry.pending?.isParked = true
                        entry.pending?.nextAttemptAt = nil
                        entry.pending?.lastError = String(reason.prefix(Self.maximumMessageLength))
                    }
                }
                Self.store(entry, in: &state)
            }
            Self.pruneTombstones(in: &state, limit: configuration.maximumTombstones)
        }
    }

    /// The server stored `change` as `revision`.
    private func accept(_ change: OutgoingChange<Record>, as revision: String, into entry: inout StoredEntry<Record>, isCurrent: Bool,
                        in state: inout State, report: inout SyncReport) {
        // The answer does not say where the write stands; its echo in a pull will. Until then
        // every version up to the one it replaced is known to be older.
        let replaced = entry.history == state.history ? (entry.sequence ?? entry.minimumSequence) : nil
        entry.revision = revision
        entry.history = state.history
        entry.sequence = nil
        entry.minimumSequence = replaced
        entry.serverTimestamp = change.timestamp
        let deferred = entry.deferredRemote
        entry.deferredRemote = nil
        guard isCurrent else { return }
        entry.pending = nil
        // A pull brought a newer version while this change was in doubt; the change was
        // applied before it, so that version is the server's current one.
        if let deferred, deferred.revision != revision {
            report.pulled += 1
            entry = Self.entry(from: deferred, replacing: entry, in: &state, configuration: configuration)
        }
    }

    /// Handles the server's answer that `entry`'s pending change conflicts with `current`.
    private func settle(_ entry: inout StoredEntry<Record>, conflictingWith current: RemoteChange<Record>, pushesInThisSync: Int,
                        in state: inout State, report: inout SyncReport) throws {
        // The server did not apply the change, so it is no longer in doubt.
        entry.pending?.isInDoubt = false
        let deferred = entry.deferredRemote
        entry.deferredRemote = nil
        guard Self.isConsistent(current, for: entry.id) else {
            report.conflicts += 1
            fail(&entry, message: "The server answered with a conflict that names another record or breaks the limits.",
                 report: &report)
            return
        }
        receive(current, in: &state)
        // A repeated push is answered from the server's memory of change IDs, with the version
        // that was current then; a version pulled since is newer.
        let current = newer(deferred, than: current, in: state)
        guard current.revision != entry.revision, !isStale(current, comparedWith: entry, in: state) else {
            // The version the change is based on, or an older one (a lagging replica
            // answered): nothing to resolve; the change is pushed again later.
            report.conflicts += 1
            fail(&entry, message: "The server answered with a conflict that names the same or an older version of the record.",
                 report: &report)
            return
        }
        switch authorship(of: current, comparedWith: entry) {
        case .pendingChange:
            // The server holds this very change: an earlier push of it was applied.
            report.pushed += 1
            entry = Self.entry(from: current, replacing: entry, in: &state, configuration: configuration)
        case .earlierWrite:
            // The device's own earlier write, applied although its answer was lost: the
            // pending change was made on top of it, so it goes out again on its revision.
            Self.base(&entry, on: current, in: state, configuration: configuration)
            if let pending = entry.pending {
                entry.pending = conflictAttempt(rebased(pending), pushesInThisSync: pushesInThisSync, report: &report)
            }
        case .other:
            report.conflicts += 1
            entry = try resolve(entry, against: current, in: &state, pushesInThisSync: pushesInThisSync, report: &report)
        }
    }

    /// `deferred`, the version a pull brought while the change was in doubt, when it is not
    /// older than `current`; otherwise `current`.
    func newer(_ deferred: RemoteChange<Record>?, than current: RemoteChange<Record>, in state: State) -> RemoteChange<Record> {
        guard let deferred, deferred.revision != current.revision, !isOlder(deferred, than: current, in: state) else { return current }
        return deferred
    }

    private func recordFailedAttempts(_ changes: [OutgoingChange<Record>], message: String, notInDoubt: Set<UUID>,
                                      report: inout SyncReport) throws {
        try update { state in
            for change in changes {
                guard var entry = state.entries[change.recordID], entry.pending?.changeID == change.id else { continue }
                if notInDoubt.contains(change.id) { entry.pending?.isInDoubt = false }
                fail(&entry, message: message, report: &report)
                state.entries[change.recordID] = entry
            }
        }
    }

    /// Counts a failed push and schedules the next one, or parks the change.
    private func fail(_ entry: inout StoredEntry<Record>, message: String, report: inout SyncReport) {
        guard var pending = entry.pending else { return }
        pending.attempts = pending.attempts == .max ? .max : pending.attempts + 1
        pending.lastError = message
        let policy = configuration.retryPolicy
        if policy.allowsRetry(afterAttempts: pending.attempts) {
            let delay = policy.delay(afterAttempt: pending.attempts, random: configuration.random())
            pending.nextAttemptAt = configuration.now().addingTimeInterval(delay.seconds)
        } else {
            pending.isParked = true
            pending.nextAttemptAt = nil
            report.parked += 1
        }
        entry.pending = pending
    }
}
