import os

/// One sync run that every caller of ``OfflineStore/sync()`` waits for while it runs.
///
/// The run is cancelled only when every caller waiting for it was cancelled, so one caller
/// that gives up (a view that disappears, say) does not stop the sync for the others. Once
/// that happens the run is abandoned: it ends with `CancellationError`, and a later caller
/// cannot join it.
final class SharedSync: Sendable {
    private struct Callers {
        var waiting = 0
        var abandoned = false
        var pushed = false
    }

    let task: Task<SyncReport, any Error>
    private let callers = OSAllocatedUnfairLock(initialState: Callers())

    init(_ operation: @escaping @Sendable () async throws -> SyncReport) {
        task = Task(operation: operation)
    }

    /// Adds a caller, who then waits with ``value()``. Returns `false` when the run is
    /// abandoned, because its result would be a `CancellationError` this caller did not cause,
    /// and when the caller has changes to push (`needsPush`) but the run is past its push.
    func join(needsPush: Bool = false) -> Bool {
        callers.withLock { callers in
            guard !callers.abandoned, !(needsPush && callers.pushed) else { return false }
            callers.waiting += 1
            return true
        }
    }

    /// Marks the end of the run's push; callers with changes to push no longer join it.
    func finishPushing() {
        callers.withLock { $0.pushed = true }
    }

    /// Waits for the run after ``join()`` returned `true`. Cancelling the calling task
    /// withdraws this caller; the run stops after its current request when no caller is left.
    func value() async throws -> SyncReport {
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            let nobodyWaits = callers.withLock { callers in
                callers.waiting -= 1
                if callers.waiting == 0 { callers.abandoned = true }
                return callers.abandoned
            }
            if nobodyWaits { task.cancel() }
        }
    }
}
