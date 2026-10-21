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
                    // A version a pull kept back before the change went out says nothing its
                    // answer will not say better: an accepted push was applied after it, and a
                    // conflict answer brings the server's current version.
                    entry.deferredRemote = nil
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
                if let next = pending.nextAttemptAt, configuration.retryPolicy.isWaiting(until: next, now: now) { return false }
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
                        let answered = Self.entry(from: current, replacing: entry, in: &state, configuration: configuration)
                        entry = weigh(keptBack: deferred, against: answered, in: &state)
                        if entry.revision == current.revision { entry.pushedInHistory = state.history }
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
        // the versions up to the one it replaced are known to be older.
        let replaced = entry
        entry.revision = revision
        entry.history = state.history
        entry.pushedInHistory = state.history
        entry.sequence = nil
        Self.order(&entry, asWriteReplacing: replaced, in: state)
        entry.rememberOwnWrite(changeID: change.id, timestamp: change.timestamp)
        let deferred = entry.deferredRemote
        entry.deferredRemote = nil
        // The server applied this change on top of the version it was based on, so no earlier
        // version in doubt can be its current one any more.
        Self.settleVersionsInDoubt(of: &entry)
        guard isCurrent else { return }
        entry.pending = nil
        // A version a pull kept back while the change was in doubt follows the rule of every
        // push answer (weigh(keptBack:against:in:)): it never replaces the write. It may be a
        // stale page (a lagging replica, a cache after resetChangeToken()) or a version of the
        // history before a restart that lost the data, and showing it would make the next edit
        // drop what the write held. When it may be newer, the next sync pulls from the beginning.
        entry = weigh(keptBack: deferred, against: entry, in: &state)
    }

    /// Handles the server's answer that `entry`'s pending change conflicts with `answer`.
    ///
    /// Who wrote the version the answer names decides first: the device's own write is never a
    /// conflict, whatever a pull kept back meanwhile. A version a pull kept back while the change
    /// was in doubt never takes the answer's place (see ``order(ofKeptBack:against:in:)``), the
    /// rule an accepted answer and a rejection follow too; when it may be newer, the change goes
    /// out again under a new change ID, so the server answers with its current version.
    private func settle(_ entry: inout StoredEntry<Record>, conflictingWith answer: RemoteChange<Record>, pushesInThisSync: Int,
                        in state: inout State, report: inout SyncReport) throws {
        // The server did not apply the change, so it is no longer in doubt, and neither are its
        // earlier versions; those the server may have applied stay known as the device's own.
        entry.pending?.isInDoubt = false
        Self.settleVersionsInDoubt(of: &entry)
        let deferred = entry.deferredRemote
        entry.deferredRemote = nil
        guard Self.isConsistent(answer, for: entry.id) else {
            report.conflicts += 1
            fail(&entry, message: "The server answered with a conflict that names another record or breaks the limits.",
                 report: &report)
            return
        }
        receive(answer, in: &state)
        // The version the change is based on, which a conflict cannot name, or one the server's
        // sequences, or the store's own accepted write, show to be older (a lagging replica
        // answered): nothing to resolve; the change is pushed again later. A timestamp never
        // makes an answer older; without sequences the server's answer is its current version.
        guard answer.revision != entry.revision else {
            report.conflicts += 1
            fail(&entry, message: "The server answered with a conflict that names the version the change is based on.", report: &report)
            return
        }
        guard !isStale(answer, comparedWith: entry, in: state, isConflictAnswer: true) else {
            report.conflicts += 1
            fail(&entry, message: "The server answered with a conflict that names an older version of the record than the store holds.",
                 report: &report)
            return
        }
        switch authorship(of: answer, comparedWith: entry) {
        case .pendingChange:
            // The server holds this very change: an earlier push of it was applied, on top of
            // the version the change is based on, as for an accepted answer.
            report.pushed += 1
            entry.rememberOwnWrite(changeID: entry.pending?.changeID, timestamp: entry.timestamp)
            var answered = Self.entry(from: answer, replacing: entry, in: &state, configuration: configuration)
            if answer.sequence == nil { Self.order(&answered, asWriteReplacing: entry, in: state) }
            entry = weigh(keptBack: deferred, against: answered, in: &state)
        case .earlierWrite:
            // The device's own earlier write: applied although its answer was lost, or accepted
            // before a stale page took the record back. The pending change was made on this
            // device after it, so it goes out again on its revision, and the next answer tells
            // whether another device wrote since.
            entry.rememberOwnWrite(changeID: answer.changeID, timestamp: answer.timestamp)
            Self.base(&entry, on: answer, in: state, configuration: configuration)
            if let pending = entry.pending {
                entry.pending = conflictAttempt(renewed(pending), pushesInThisSync: pushesInThisSync, report: &report)
            }
        case .other:
            var answered = entry
            Self.base(&answered, on: answer, in: state, configuration: configuration)
            let keptBack = order(ofKeptBack: deferred, against: answered, in: state)
            if let pending = entry.pending, keptBack == .unknown {
                // A pull kept another version back, and nothing tells which of the two the server
                // holds now: the answer may come from the server's memory of change IDs, from
                // before the version pulled since, the pulled version may come from a stale page,
                // and a later sequence of it may belong to a history the server left. The resolver meets neither. The change goes out again under a new
                // change ID on the same base, so the server answers with its current version.
                entry.pending = conflictAttempt(renewed(pending), pushesInThisSync: pushesInThisSync, report: &report)
                return
            }
            report.conflicts += 1
            entry = try resolve(entry, against: answer, in: &state, pushesInThisSync: pushesInThisSync, report: &report)
        }
        // Every path above makes the version the answer named the version the entry is based on.
        entry.pushedInHistory = state.history
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
