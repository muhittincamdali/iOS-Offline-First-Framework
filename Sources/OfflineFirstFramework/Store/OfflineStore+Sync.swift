import Foundation

extension OfflineStore {
    /// Pushes after a conflict are limited per record and sync, so a server that answers every
    /// push with a new conflict cannot keep the sync running forever.
    static var maximumPushesPerRecord: Int { 3 }

    /// Server-provided texts (rejection reasons, error descriptions) are cut to this length.
    static var maximumMessageLength: Int { 1_000 }

    /// Pushes local changes, then pulls server changes.
    ///
    /// Calls made while a sync runs wait for that sync and return its report. Cancelling the
    /// calling task stops the sync after the current request when no other call waits for it;
    /// what was applied so far stays. While other calls still wait, the sync goes on and the
    /// cancelled call returns its report too. A call made after every caller of the running
    /// sync was cancelled waits for that sync to stop and then starts a new one.
    ///
    /// - Returns: What the sync did. Without a transport, or while the ``CircuitBreaker`` is
    ///   open, nothing happens and ``SyncReport/skipped`` is `true`.
    /// - Throws: The transport's error, or an ``OfflineFirstError``. Changes that failed are
    ///   retried by a later sync, following the ``RetryPolicy``.
    @discardableResult
    public func sync() async throws -> SyncReport {
        while let running = activeSync {
            if running.join() {
                return try await running.value()
            }
            // Every caller of that sync was cancelled; let it stop before starting over, so two
            // syncs never push at the same time.
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
        try bind(to: transport)
        guard breaker.allowsAttempt(at: configuration.now()) else {
            if case .open(let until) = breaker.state { setStatus(.paused(until: until)) }
            report.skipped = true
            return report
        }
        setStatus(.syncing)
        do {
            try await push(using: transport, report: &report)
            try await pull(using: transport, report: &report)
            breaker.recordSuccess()
            try update { $0.lastSyncedAt = configuration.now() }
            setStatus(.idle)
            return report
        } catch is CancellationError {
            setStatus(.idle)
            throw CancellationError()
        } catch {
            breaker.recordFailure(at: configuration.now())
            setStatus(Self.isConnectivityError(error) ? .offline : .failed(Self.message(for: error)))
            throw error
        }
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

    private func push(using transport: any SyncTransport<Record>, report: inout SyncReport) async throws {
        var pushes: [Record.ID: Int] = [:]
        while true {
            try Task.checkCancellation()
            let changes = dueChanges(excluding: pushes)
            guard !changes.isEmpty else { return }
            try markSent(changes)
            for change in changes {
                pushes[change.recordID, default: 0] += 1
                inFlight.insert(change.recordID)
            }
            let outcomes: [UUID: PushOutcome<Record>]
            do {
                outcomes = try await transport.push(changes)
            } catch {
                inFlight.subtract(changes.map(\.recordID))
                if !(error is CancellationError) {
                    try recordFailedAttempts(changes, message: Self.message(for: error), report: &report)
                }
                throw error
            }
            inFlight.subtract(changes.map(\.recordID))
            try apply(outcomes, for: changes, report: &report)
        }
    }

    /// Records in `changes` the server has not confirmed are marked as sent, and the mark is
    /// written before the request leaves: the server may apply a push whose answer never
    /// arrives, so from now on deleting the record has to go through the server.
    private func markSent(_ changes: [OutgoingChange<Record>]) throws {
        let unmarked = changes.map(\.recordID).filter { id in
            guard let entry = state.entries[id] else { return false }
            return entry.revision == nil && !entry.wasSent
        }
        guard !unmarked.isEmpty else { return }
        try update { state in
            for id in unmarked {
                state.entries[id]?.wasSent = true
            }
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

    private func apply(_ outcomes: [UUID: PushOutcome<Record>], for changes: [OutgoingChange<Record>], report: inout SyncReport) throws {
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
                    entry.revision = revision
                    entry.history = state.history
                    // The answer does not say where the write stands; its echo in a pull will.
                    entry.sequence = nil
                    entry.serverTimestamp = change.timestamp
                    if isCurrent { entry.pending = nil }
                case .conflict(let current):
                    report.conflicts += 1
                    guard isCurrent, Self.isConsistent(current, for: entry.id) else { break }
                    observe(current.timestamp, in: &state)
                    guard current.revision != entry.revision, !Self.isStale(current, comparedWith: entry, history: state.history) else {
                        // The version the change is based on, or an older one (a lagging replica
                        // answered): nothing to resolve; the change is pushed again later.
                        fail(&entry, message: "The server answered with a conflict that names the same or an older version of the record.",
                             report: &report)
                        break
                    }
                    entry = try resolve(entry, against: current, in: &state)
                case .rejected(let reason, let current):
                    report.rejected += 1
                    guard isCurrent else { break }
                    if let current, Self.isConsistent(current, for: entry.id) {
                        entry = Self.entry(from: current, replacing: entry, in: &state, configuration: configuration)
                    } else {
                        entry.pending?.isParked = true
                        entry.pending?.nextAttemptAt = nil
                        entry.pending?.lastError = String(reason.prefix(Self.maximumMessageLength))
                    }
                }
                Self.store(entry, in: &state)
            }
            Self.pruneTombstones(in: &state)
        }
    }

    private func recordFailedAttempts(_ changes: [OutgoingChange<Record>], message: String, report: inout SyncReport) throws {
        try update { state in
            for change in changes {
                guard var entry = state.entries[change.recordID], entry.pending?.changeID == change.id else { continue }
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

    private func pull(using transport: any SyncTransport<Record>, report: inout SyncReport) async throws {
        var historyChanged = false
        for _ in 0..<configuration.maximumPullPages {
            try Task.checkCancellation()
            let token = state.token
            let response = try await transport.pull(since: token)
            if let next = response.token, next.utf8.count > Self.maximumRevisionLength {
                throw OfflineFirstError.invalidServerResponse("The change token has more than \(Self.maximumRevisionLength) bytes.")
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
            try update { state in
                if epochChanged {
                    Self.beginHistory(epoch: response.epoch, in: &state)
                } else if state.serverEpoch == nil {
                    // The first epoch the server reports, for example after an update of the server.
                    state.serverEpoch = response.epoch
                }
                for change in response.changes {
                    try applyRemote(change, to: &state, report: &report)
                }
                Self.pruneTombstones(in: &state)
                // A page without a token keeps the previous one.
                state.token = response.token ?? state.token
            }
            guard response.hasMore else { return }
            guard response.token != nil, response.token != token else {
                throw OfflineFirstError.pullTokenDidNotAdvance(token: token)
            }
        }
        report.hasMoreChanges = true
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
        guard Self.isConsistent(change, for: change.recordID) else { return }
        observe(change.timestamp, in: &state)
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
            entry.sequence = change.sequence ?? entry.sequence
            entry.serverTimestamp = change.timestamp ?? entry.serverTimestamp
            state.entries[change.recordID] = entry
            return
        }
        // A server version older than the one the store holds (a page out of order, a lagging
        // replica, the earlier version of a deleted record) is skipped: the server already has
        // something newer, and it comes in its turn.
        guard !Self.isStale(change, comparedWith: entry, history: state.history) else { return }
        report.pulled += 1
        if entry.pending != nil {
            // Changed on the device and on the server: a conflict for the resolver.
            report.conflicts += 1
            Self.store(try resolve(entry, against: change, in: &state), in: &state)
        } else {
            Self.store(Self.entry(from: change, replacing: entry, in: &state, configuration: configuration), in: &state)
        }
    }

    // MARK: - Conflicts

    private func resolve(_ entry: StoredEntry<Record>, against remote: RemoteChange<Record>, in state: inout State) throws -> StoredEntry<Record> {
        if entry.record == nil && remote.record == nil {
            return Self.entry(from: remote, replacing: entry, in: &state, configuration: configuration)
        }
        let conflict = Conflict(recordID: entry.id, local: entry.record, localTimestamp: entry.timestamp,
                                remote: remote.record, remoteTimestamp: remote.timestamp)
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
        // The local or merged version goes out again on top of the server's revision, under a
        // new change ID so the server does not answer it from an idempotency cache.
        Self.base(&result, on: remote, history: state.history)
        result.pending = PendingWrite(changeID: UUID(), sequence: entry.pending?.sequence ?? state.takeSequence(),
                                      attempts: 0, nextAttemptAt: nil, lastError: nil, isParked: false)
        return result
    }

    // MARK: - Helpers

    /// Moves the clock past a server timestamp; one too far in the future is ignored.
    private func observe(_ timestamp: HLCTimestamp?, in state: inout State) {
        guard let timestamp else { return }
        _ = try? state.clock.receive(timestamp, at: configuration.now())
    }

    static func message(for error: any Error) -> String {
        let text = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
        return String(text.prefix(maximumMessageLength))
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
