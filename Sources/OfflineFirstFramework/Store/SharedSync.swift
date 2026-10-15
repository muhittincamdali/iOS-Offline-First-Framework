import os

/// One sync run that every caller of ``OfflineStore/sync()`` waits for while it runs.
///
/// The run is cancelled only when every caller waiting for it was cancelled, so one caller
/// that gives up (a view that disappears, say) does not stop the sync for the others.
final class SharedSync: Sendable {
    let task: Task<SyncReport, any Error>
    private let waiters = OSAllocatedUnfairLock(initialState: 0)

    init(_ operation: @escaping @Sendable () async throws -> SyncReport) {
        task = Task(operation: operation)
    }

    /// Waits for the run. Cancelling the calling task withdraws this caller; the run stops
    /// after its current request when no caller is left.
    func value() async throws -> SyncReport {
        waiters.withLock { $0 += 1 }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            let nobodyWaits = waiters.withLock { count in
                count -= 1
                return count == 0
            }
            if nobodyWaits { task.cancel() }
        }
    }
}
