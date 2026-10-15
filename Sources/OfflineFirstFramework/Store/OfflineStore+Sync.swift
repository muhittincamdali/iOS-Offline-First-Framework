import Foundation

extension OfflineStore {
    /// Pushes after a conflict are limited per record and sync, so a server that answers every
    /// push with a new conflict cannot keep the sync running forever.
    static var maximumPushesPerRecord: Int { 3 }

    /// Server-provided texts (rejection reasons, error descriptions) are cut to this length.
    static var maximumMessageLength: Int { 1_000 }

    /// The longest revision or change token, in UTF-8 bytes, the store keeps. Every record
    /// stores its revision, so longer values from a server would grow the file without limit.
    static var maximumRevisionLength: Int { 1_024 }

    /// The longest node ID, in UTF-8 bytes, accepted in a server timestamp.
    static var maximumNodeIDLength: Int { 256 }

    /// Pushes local changes, then pulls server changes.
    ///
    /// Calls made while a sync runs wait for that sync and return its report. Cancelling the
    /// calling task stops the sync after the current request; what was applied so far stays.
    ///
    /// - Returns: What the sync did. Without a transport, or while the ``CircuitBreaker`` is
    ///   open, nothing happens and ``SyncReport/skipped`` is `true`.
    /// - Throws: The transport's error, or an ``OfflineFirstError``. Changes that failed are
    ///   retried by a later sync, following the ``RetryPolicy``.
    @discardableResult
    public func sync() async throws -> SyncReport {
        if let activeSync {
            return try await activeSync.value
        }
        let task = Task { try await self.performSync() }
        activeSync = task
        defer { activeSync = nil }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func performSync() async throws -> SyncReport {
        var report = SyncReport()
        guard let transport else {
            report.skipped = true
            return report
        }
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
                case .accepted(let revision):
                    report.pushed += 1
                    entry.revision = revision
                    if isCurrent { entry.pending = nil }
                case .conflict(let current):
                    report.conflicts += 1
                    guard isCurrent, Self.isConsistent(current, for: entry.id) else { break }
                    observe(current.timestamp, in: &state)
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
        for _ in 0..<configuration.maximumPullPages {
            try Task.checkCancellation()
            let token = state.token
            let response = try await transport.pull(since: token)
            if let next = response.token, next.utf8.count > Self.maximumRevisionLength {
                throw OfflineFirstError.invalidServerResponse("The change token has more than \(Self.maximumRevisionLength) bytes.")
            }
            try update { state in
                for change in response.changes {
                    try applyRemote(change, to: &state, report: &report)
                }
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

    private func applyRemote(_ change: RemoteChange<Record>, to state: inout State, report: inout SyncReport) throws {
        guard Self.isConsistent(change, for: change.recordID) else { return }
        observe(change.timestamp, in: &state)
        guard let entry = state.entries[change.recordID] else {
            guard change.record != nil else { return }
            report.pulled += 1
            Self.store(Self.entry(from: change, replacing: nil, in: &state, configuration: configuration), in: &state)
            return
        }
        // The same revision is the echo of a change this store pushed.
        guard entry.revision != change.revision else { return }
        report.pulled += 1
        if entry.pending != nil {
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
        result.revision = remote.revision
        result.pending = PendingWrite(changeID: UUID(), sequence: entry.pending?.sequence ?? state.takeSequence(),
                                      attempts: 0, nextAttemptAt: nil, lastError: nil, isParked: false)
        return result
    }

    // MARK: - Helpers

    /// The server's version as a stored entry without a pending change.
    static func entry(from remote: RemoteChange<Record>, replacing existing: StoredEntry<Record>?, in state: inout State,
                      configuration: Configuration) -> StoredEntry<Record> {
        let timestamp = remote.timestamp ?? (try? state.clock.tick(at: configuration.now())) ?? state.clock.latest
        return StoredEntry(id: remote.recordID, record: remote.record, timestamp: timestamp, revision: remote.revision,
                           position: existing?.position ?? state.takeSequence(), pending: nil)
    }

    /// Stores `entry`, or removes it when it is a deletion with nothing left to push.
    static func store(_ entry: StoredEntry<Record>, in state: inout State) {
        state.entries[entry.id] = entry.record == nil && entry.pending == nil ? nil : entry
    }

    /// A server record is ignored when its own ID differs from the ID it was sent for, or when
    /// its revision or timestamp is longer than the limits.
    static func isConsistent(_ change: RemoteChange<Record>, for id: Record.ID) -> Bool {
        change.recordID == id
            && (change.record.map { $0.id == id } ?? true)
            && change.revision.utf8.count <= maximumRevisionLength
            && (change.timestamp.map { $0.nodeID.utf8.count <= maximumNodeIDLength } ?? true)
    }

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
