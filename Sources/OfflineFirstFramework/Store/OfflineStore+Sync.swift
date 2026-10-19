import Foundation

extension OfflineStore {
    /// Pushes of one record in one sync. A second conflict already makes the change wait for
    /// its retry date; the limit also holds with a ``RetryPolicy`` without delays.
    static var maximumPushesPerRecord: Int { 3 }

    /// Server-provided texts (rejection reasons, error descriptions) are cut to this length.
    static var maximumMessageLength: Int { 1_000 }

    /// Pushes local changes, then pulls server changes.
    ///
    /// Calls made while a sync runs wait for that sync and return its report. A call made after
    /// the running sync finished pushing, while local changes are due that it did not push
    /// (saved during its pull, say), waits for it and then starts a new sync, so the call does
    /// not return before its changes were pushed. Cancelling the calling task stops the sync
    /// after the current request when no other call waits for it; what was applied so far
    /// stays. While other calls still wait, the sync goes on and the cancelled call returns its
    /// report too. A call made after every caller of the running sync was cancelled waits for
    /// that sync to stop and then starts a new one.
    ///
    /// - Returns: What the sync did. Without a transport nothing happens and
    ///   ``SyncReport/skipped`` is `true`; while the ``CircuitBreaker`` is open, only changes
    ///   that are due are pushed, and ``SyncReport/skipped`` is `true` too.
    /// - Throws: The transport's error, or an ``OfflineFirstError``. Changes that failed are
    ///   retried by a later sync, following the ``RetryPolicy``. After the store file could not
    ///   be written, syncs throw that error without a request until the ``RetryPolicy`` delay
    ///   for the failed writes in a row has passed; a write that succeeds ends the wait.
    @discardableResult
    public func sync() async throws -> SyncReport {
        while let running = activeSync {
            if running.join(needsPush: !dueChanges(excluding: [:]).isEmpty) {
                return try await running.value()
            }
            // Every caller of that sync was cancelled, or it is past its push and changes wait;
            // let it end before starting over, so two syncs never push at the same time.
            _ = await running.task.result
            if activeSync === running { activeSync = nil }
            try Task.checkCancellation()
        }
        let shared = SharedSync { try await self.performSync() }
        activeSync = shared
        _ = shared.join()
        defer { if activeSync === shared { activeSync = nil } }
        return try await shared.value()
    }

    private func performSync() async throws -> SyncReport {
        var report = SyncReport()
        guard let transport else {
            report.skipped = true
            return report
        }
        if let wait = storageWait, wait.until > configuration.now() {
            throw failed(with: wait.error)
        }
        try bind(to: transport)
        // The circuit breaker pauses pulls only. Due changes are pushed anyway: each waits for
        // its own retry date, so a server that is down is not hit harder, and a server whose
        // pulls fail still gets the device's edits.
        let mayPull = breaker.allowsAttempt(at: configuration.now())
        guard mayPull || !dueChanges(excluding: [:]).isEmpty else {
            if case .open(let until) = breaker.state { setStatus(.paused(until: until)) }
            report.skipped = true
            return report
        }
        setStatus(.syncing)
        let deadline = ContinuousClock.now + configuration.syncTimeout
        do {
            try await push(using: transport, until: deadline, report: &report)
        } catch {
            throw failed(with: error)
        }
        activeSync?.finishPushing()
        guard mayPull else {
            report.skipped = true
            if case .open(let until) = breaker.state { setStatus(.paused(until: until)) }
            return report
        }
        do {
            try await pull(using: transport, until: deadline, report: &report)
            try update { $0.lastSyncedAt = configuration.now() }
        } catch {
            let error = failed(with: error)
            if !(error is CancellationError) { breaker.recordFailure(at: configuration.now()) }
            throw error
        }
        breaker.recordSuccess()
        setStatus(.idle)
        return report
    }

    /// Sets the status after a failed sync and returns the error to throw. A transport may report
    /// its cancellation with an error of its own, such as URLError(.cancelled); the sync was
    /// still cancelled, not failed.
    private func failed(with error: any Error) -> any Error {
        if error is CancellationError || Task.isCancelled {
            setStatus(.idle)
            return CancellationError()
        }
        setStatus(Self.isConnectivityError(error) ? .offline : .failed(Self.message(for: error)))
        return error
    }

    /// Keeps the transport's identity with the token. A store opened with another server
    /// starts a new history instead of sending that server the old one's token. A store that
    /// has no identity yet (a new store, or a file from before identities) takes the
    /// transport's.
    private func bind(to transport: any SyncTransport<Record>) throws {
        guard let identity = transport.serverIdentity, identity != state.serverIdentity else { return }
        try update { state in
            if state.serverIdentity != nil {
                Self.beginHistory(epoch: nil, in: &state)
                // Another server's epochs say nothing about this one's.
                state.previousEpochs.removeAll()
            }
            state.serverIdentity = identity
        }
    }

    func setStatus(_ newStatus: SyncStatus) {
        guard status != newStatus else { return }
        status = newStatus
        notifyObservers()
    }

    // MARK: - Push

    private func push(using transport: any SyncTransport<Record>, until deadline: ContinuousClock.Instant,
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
    private func dueChanges(excluding pushes: [Record.ID: Int]) -> [OutgoingChange<Record>] {
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
    private func newer(_ deferred: RemoteChange<Record>?, than current: RemoteChange<Record>, in state: State) -> RemoteChange<Record> {
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

    // MARK: - Pull

    private func pull(using transport: any SyncTransport<Record>, until deadline: ContinuousClock.Instant,
                      report: inout SyncReport) async throws {
        var historyChanged = false
        // The tokens this sync has pulled with since it last started from the beginning.
        var requested: Set<String> = []
        for _ in 0..<configuration.maximumPullPages {
            try Task.checkCancellation()
            let token = state.token
            if let token { requested.insert(token) } else { requested.removeAll() }
            let generation = tokenGeneration
            let response = try await Self.run(until: deadline) { try await transport.pull(since: token) }
            // The token was reset while the request was on its way (discardChange(for:),
            // resetChangeToken()): the page belongs to the old position, so it is dropped and the
            // pull starts again from the beginning.
            guard generation == tokenGeneration else { continue }
            if let next = response.token, next.utf8.count > Self.maximumRevisionLength {
                throw OfflineFirstError.invalidServerResponse("The change token has more than \(Self.maximumRevisionLength) bytes.")
            }
            // A server reports a new epoch when its history changes and never goes back to an
            // earlier one; a page of a history the store left comes from a stale replica or
            // cache, and its versions would roll records back.
            if let epoch = response.epoch, state.previousEpochs.contains(epoch) {
                throw OfflineFirstError.invalidServerResponse(
                    "The server answered from an earlier history (epoch “\(epoch.prefix(100))”), as a stale replica or cache would.")
            }
            let epochChanged = try Self.isNewEpoch(response.epoch, after: state.serverEpoch)
            if epochChanged {
                guard !historyChanged else {
                    throw OfflineFirstError.invalidServerResponse("The server's epoch changed twice during one sync.")
                }
                historyChanged = true
                if token != nil {
                    // The page answers a token of the old history; start over from the beginning.
                    try update { Self.beginHistory(epoch: response.epoch, in: &$0) }
                    continue
                }
            }
            // A page is checked before it is stored, so a broken one changes nothing.
            try Self.checkProgress(of: response, after: token, requested: requested)
            try update { state in
                if epochChanged {
                    Self.beginHistory(epoch: response.epoch, in: &state)
                } else if state.serverEpoch == nil {
                    // The first epoch the server reports, for example after an update of the server.
                    state.serverEpoch = response.epoch
                }
                for change in response.quarantined {
                    Self.quarantine(change, in: &state, report: &report)
                }
                for change in response.changes {
                    try applyRemote(change, to: &state, report: &report)
                }
                Self.pruneTombstones(in: &state, limit: configuration.maximumTombstones)
                // A page without a token keeps the previous one.
                state.token = response.token ?? state.token
            }
            guard response.hasMore else { return }
        }
        report.hasMoreChanges = true
    }

    /// Throws when a page that says more changes follow would not move the pull forward: it
    /// has no token, the same one, or one this sync pulled with before (the tokens go round in
    /// a circle), which would repeat pages up to the page limit on every sync.
    private static func checkProgress(of response: PullResponse<Record>, after token: String?, requested: Set<String>) throws {
        guard response.hasMore else { return }
        guard let next = response.token, next != token else {
            throw OfflineFirstError.pullTokenDidNotAdvance(token: token)
        }
        guard !requested.contains(next) else {
            throw OfflineFirstError.invalidServerResponse(
                "The server sent the change token “\(next.prefix(100))” a second time in one sync, so the pull would go round in circles.")
        }
    }

    /// Whether `epoch` names another server history than `known`. A server that reports no
    /// epoch, or the first one, does not change the history.
    private static func isNewEpoch(_ epoch: String?, after known: String?) throws -> Bool {
        guard let epoch else { return false }
        guard epoch.utf8.count <= maximumRevisionLength else {
            throw OfflineFirstError.invalidServerResponse("The epoch has more than \(maximumRevisionLength) bytes.")
        }
        return known.map { $0 != epoch } ?? false
    }

    private func applyRemote(_ change: RemoteChange<Record>, to state: inout State, report: inout SyncReport) throws {
        // A change that cannot be used is set aside and reported; the rest of the page goes on.
        if let reason = Self.inconsistency(of: change, for: change.recordID) {
            Self.quarantine(QuarantinedChange(recordID: Self.describe(change.recordID), revision: change.revision, reason: reason),
                            in: &state, report: &report)
            return
        }
        if !state.quarantine.isEmpty {
            let recordID = Self.describe(change.recordID)
            state.quarantine.removeAll { $0.recordID == recordID }
        }
        receive(change, in: &state)
        guard var entry = state.entries[change.recordID] else {
            // A deletion is kept as a tombstone too, so an older version of the record that
            // arrives later (a page out of order) does not bring it back.
            if change.record != nil { report.pulled += 1 }
            Self.store(Self.entry(from: change, replacing: nil, in: &state, configuration: configuration), in: &state)
            return
        }
        // The same revision is the same version (a server never reuses one): the echo of a change
        // this store pushed, or a record the server kept across a restart. It may tell where the
        // version stands.
        guard entry.revision != change.revision else {
            entry.history = state.history
            if let sequence = change.sequence {
                entry.sequence = sequence
                entry.minimumSequence = nil
            }
            entry.serverTimestamp = Self.orderable(change.timestamp, below: Self.driftLimit(of: state, configuration: configuration))
            state.entries[change.recordID] = entry
            return
        }
        // A server version older than the one the store holds (a page out of order, a lagging
        // replica, the earlier version of a deleted record) is skipped: the server already has
        // something newer, and it comes in its turn.
        guard !isStale(change, comparedWith: entry, in: state) else { return }
        guard let pending = entry.pending else {
            report.pulled += 1
            Self.store(Self.entry(from: change, replacing: entry, in: &state, configuration: configuration), in: &state)
            return
        }
        switch authorship(of: change, comparedWith: entry) {
        case .pendingChange:
            // The pending change itself: the server applied it, although no answer said so.
            Self.store(Self.entry(from: newer(entry.deferredRemote, than: change, in: state), replacing: entry, in: &state,
                                  configuration: configuration), in: &state)
            return
        case .earlierWrite:
            // The device's own earlier write: the pending change was made on top of it. A
            // change in doubt learns from its next push where it stands; one that is not goes
            // out on this revision.
            guard !pending.isInDoubt else { return }
            Self.base(&entry, on: change, in: state, configuration: configuration)
            entry.pending = rebased(pending)
            state.entries[change.recordID] = entry
            return
        case .other:
            break
        }
        // A change whose push may have been applied waits for its next push, which learns its
        // fate under the same change ID; resolving it here could put it back over this version.
        // The version is kept, since the token moves past it: if the push shows the change was
        // applied, this newer version replaces it.
        if pending.isInDoubt {
            if let deferred = entry.deferredRemote, deferred.revision == change.revision || isOlder(change, than: deferred, in: state) {
                return
            }
            entry.deferredRemote = change
            state.entries[change.recordID] = entry
            return
        }
        // Changed on the device and on the server: a conflict for the resolver.
        report.pulled += 1
        report.conflicts += 1
        Self.store(try resolve(entry, against: change, in: &state, pushesInThisSync: nil, report: &report), in: &state)
    }

    // MARK: - Conflicts

    /// Asks the resolver about `entry`'s pending change and `remote`, the server's newer version.
    ///
    /// - Parameter pushesInThisSync: For a conflict the server answered to a push, how often the
    ///   change was pushed in this sync; `nil` for a conflict found by a pull, which is not a
    ///   failed attempt.
    private func resolve(_ entry: StoredEntry<Record>, against remote: RemoteChange<Record>, in state: inout State,
                         pushesInThisSync: Int?, report: inout SyncReport) throws -> StoredEntry<Record> {
        // Two deletions are a conflict too: with last write wins the newer one has to stay on the
        // server, or an older edit based on the older deletion would bring the record back.
        let limit = Self.driftLimit(of: state, configuration: configuration)
        let conflict = Conflict(recordID: entry.id, local: entry.record, localTimestamp: entry.timestamp,
                                remote: remote.record, remoteTimestamp: Self.clamped(remote.timestamp, to: limit))
        var result = entry
        switch configuration.conflictResolver.resolve(conflict) {
        case .keepRemote:
            return Self.entry(from: remote, replacing: entry, in: &state, configuration: configuration)
        case .merged(let merged) where merged.id != entry.id:
            return Self.entry(from: remote, replacing: entry, in: &state, configuration: configuration)
        case .merged(let merged):
            result.record = merged
            do {
                result.timestamp = try state.clock.tick(at: configuration.now())
            } catch {
                throw OfflineFirstError.clock(error)
            }
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
    /// from an idempotency cache.
    private func rebased(_ pending: PendingWrite) -> PendingWrite {
        var pending = pending
        pending.changeID = UUID()
        pending.isInDoubt = false
        return pending
    }

    /// Counts a conflict answer as a failed attempt of the resolved change. The first one in a
    /// sync is pushed again right away, which settles an ordinary conflict; when the server
    /// answers that push with a conflict too, the change waits as the ``RetryPolicy`` says, and
    /// after its last attempt it is parked. Two devices that both keep their own version
    /// (``ConflictResolver/clientWins``) or a server that conflicts on every push therefore
    /// cannot keep the store pushing.
    private func conflictAttempt(_ pending: PendingWrite, pushesInThisSync: Int, report: inout SyncReport) -> PendingWrite {
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

    // MARK: - Helpers

    /// Moves the clock past a server version's timestamp; one further ahead of the device clock
    /// than ``Configuration/maximumClockDrift`` is ignored. The version keeps its timestamp: the
    /// store weighs it against local writes no further ahead than ``driftLimit(of:configuration:)``
    /// and orders server versions by it only within that limit.
    private func receive(_ change: RemoteChange<Record>, in state: inout State) {
        guard let timestamp = change.timestamp else { return }
        _ = try? state.clock.receive(timestamp, at: configuration.now())
    }

    /// Runs a transport call, or cancels it and throws `URLError(.timedOut)` once `deadline`
    /// passes. The call ends when the transport honours the cancellation. When the sync itself
    /// is cancelled, the call decides how it ends, as without a deadline: an answer that still
    /// arrives is used.
    static func run<T: Sendable>(until deadline: ContinuousClock.Instant,
                                 _ request: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: DeadlineRace<T>.self) { group in
            group.addTask { .answered(try await request()) }
            group.addTask {
                do {
                    try await Task.sleep(until: deadline, clock: .continuous)
                    return .timedOut
                } catch {
                    return .stopped
                }
            }
            defer { group.cancelAll() }
            while let result = try await group.next() {
                switch result {
                case .answered(let value): return value
                case .timedOut: throw URLError(.timedOut)
                case .stopped: continue
                }
            }
            throw CancellationError()
        }
    }

    static func message(for error: any Error) -> String {
        let text = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
        return String(text.prefix(maximumMessageLength))
    }

    /// Whether a push that failed with `error` certainly did not reach the server: the device had
    /// no connection, or could not find or reach the host. After other errors, such as a lost
    /// connection or a timeout, the server may have applied it.
    static func wasNeverSent(_ error: any Error) -> Bool {
        guard let error = error as? URLError else { return false }
        let unsentCodes: Set<URLError.Code> = [
            .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .dataNotAllowed,
            .internationalRoamingOff, .callIsActive
        ]
        return unsentCodes.contains(error.code)
    }

    static func isConnectivityError(_ error: any Error) -> Bool {
        guard let error = error as? URLError else { return false }
        let offlineCodes: Set<URLError.Code> = [
            .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
            .dnsLookupFailed, .timedOut, .dataNotAllowed, .internationalRoamingOff, .callIsActive
        ]
        return offlineCodes.contains(error.code)
    }
}

/// The first of a transport call and its deadline.
enum DeadlineRace<Value: Sendable>: Sendable {
    case answered(Value)
    case timedOut
    /// The deadline's timer was cancelled because the sync was.
    case stopped
}
