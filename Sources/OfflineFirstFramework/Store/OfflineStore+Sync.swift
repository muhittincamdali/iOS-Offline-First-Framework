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
        if let wait = storageWait, configuration.retryPolicy.isWaiting(until: wait.until, now: configuration.now()) {
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
            // Another server's epochs say nothing about this one's: its first one is taken.
            if state.serverIdentity != nil {
                Self.beginHistory(epoch: nil, keepingPushAnswers: false, in: &state)
            }
            state.serverIdentity = identity
        }
    }

    func setStatus(_ newStatus: SyncStatus) {
        guard status != newStatus else { return }
        status = newStatus
        notifyObservers()
    }

    // MARK: - Helpers

    /// Moves the clock past a server version's timestamp; one further ahead of the device clock
    /// than ``Configuration/maximumClockDrift`` is ignored. The version keeps its timestamp: the
    /// store weighs it against local writes no further ahead than ``driftLimit(of:configuration:)``
    /// and orders server versions by it only within that limit.
    func receive(_ change: RemoteChange<Record>, in state: inout State) {
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
