import Foundation

/// The bookkeeping of automatic sync.
struct AutomaticSync {
    var interval: Duration?
    var debounce: Duration
    var listener: Task<Void, Never>?
    var timer: Task<Void, Never>?
    var isOnline = false
    var isRunning = false
    var needsAnotherRun = false
}

extension OfflineStore {
    /// Syncs on its own: when the device comes online, a moment after local changes, when a
    /// failed change is due again, and every `interval` while online.
    ///
    /// ```swift
    /// await store.startAutomaticSync()
    /// ```
    ///
    /// Errors are not thrown here; they show up in ``status`` and ``StoreState/status``. Calling
    /// it again replaces the previous settings. Automatic sync runs while the app runs; for
    /// sync in the background, call ``sync()`` from a background task (see the documentation
    /// article "Syncing in the background").
    ///
    /// - Parameters:
    ///   - monitor: Where the online state comes from. Default: `NWPathMonitor`.
    ///   - interval: Time between syncs while online, from one second to one day, or `nil` to
    ///     sync only on the other triggers. Default: 5 minutes.
    ///   - debounce: Wait after a local change, so a burst of edits goes out in one push, up to
    ///     one hour. Default: 2 seconds.
    public func startAutomaticSync(
        monitor: any ConnectivityMonitor = NetworkConnectivityMonitor(),
        interval: Duration? = .seconds(300),
        debounce: Duration = .seconds(2)
    ) {
        stopAutomaticSync()
        var settings = AutomaticSync(interval: interval.map { Self.clampedDelay($0) }, debounce: min(max(.zero, debounce), .seconds(3_600)))
        settings.listener = Task { [weak self] in
            for await online in monitor.updates() {
                guard let self else { return }
                await self.connectivityChanged(online)
            }
        }
        automaticSync = settings
    }

    /// Stops automatic sync. A sync that is running finishes.
    public func stopAutomaticSync() {
        automaticSync?.listener?.cancel()
        automaticSync?.timer?.cancel()
        automaticSync = nil
    }

    /// Whether automatic sync is on.
    public var isAutomaticSyncEnabled: Bool {
        automaticSync != nil
    }

    func localChangeDidHappen() {
        guard let settings = automaticSync, settings.isOnline else { return }
        scheduleAutomaticSync(after: settings.debounce)
    }

    private func connectivityChanged(_ online: Bool) {
        guard automaticSync != nil else { return }
        automaticSync?.isOnline = online
        if online {
            scheduleAutomaticSync(after: .zero)
        } else {
            automaticSync?.timer?.cancel()
            if status != .syncing { setStatus(.offline) }
        }
    }

    /// Replaces the pending timer. A running sync is never cancelled for this; it is followed by
    /// another run instead.
    private func scheduleAutomaticSync(after delay: Duration) {
        guard automaticSync != nil else { return }
        if automaticSync?.isRunning == true {
            automaticSync?.needsAnotherRun = true
            return
        }
        automaticSync?.timer?.cancel()
        automaticSync?.timer = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            await self?.runAutomaticSync()
        }
    }

    private func runAutomaticSync() async {
        guard let settings = automaticSync, settings.isOnline, !settings.isRunning else { return }
        automaticSync?.isRunning = true
        automaticSync?.needsAnotherRun = false
        _ = try? await sync()
        guard automaticSync != nil else { return }
        automaticSync?.isRunning = false
        if automaticSync?.needsAnotherRun == true {
            scheduleAutomaticSync(after: settings.debounce)
        } else if let next = nextAutomaticSyncDelay(interval: settings.interval) {
            scheduleAutomaticSync(after: next)
        }
    }

    /// The wait until the earliest of: the next interval, the next due retry, the end of a
    /// circuit breaker pause.
    private func nextAutomaticSyncDelay(interval: Duration?) -> Duration? {
        let now = configuration.now()
        // A change still waiting without a retry date was pushed the maximum number of times in
        // this run (the server kept answering with conflicts); give the server a moment.
        let shortly = now.addingTimeInterval(max(5, (automaticSync?.debounce ?? .zero).seconds))
        var dates: [Date] = state.entries.values.compactMap { entry in
            guard let pending = entry.pending, !pending.isParked else { return nil }
            return pending.nextAttemptAt ?? shortly
        }
        if case .open(let until) = breaker.state {
            dates = dates.map { max($0, until) }
        }
        var delays = dates.map { Self.clampedDelay(seconds: $0.timeIntervalSince(now)) }
        if let interval {
            delays.append(Self.clampedDelay(interval))
        }
        return delays.min()
    }

    /// Keeps a wait between one second and one day, so a retry date far in the future (from a
    /// damaged file, say) or a huge interval does not turn into a sleep that never ends.
    static func clampedDelay(_ delay: Duration) -> Duration {
        min(max(.seconds(1), delay), .seconds(86_400))
    }

    /// The same limits for a wait in seconds. The value is clamped before it becomes a
    /// `Duration`, because `Duration.seconds(_:)` traps for values like 1e300 that a damaged
    /// file can produce; a value that is not a number waits the longest.
    static func clampedDelay(seconds: Double) -> Duration {
        guard !seconds.isNaN else { return .seconds(86_400) }
        return .seconds(min(max(1, seconds), 86_400))
    }
}
