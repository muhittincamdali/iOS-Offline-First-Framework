#if os(iOS)
import BackgroundTasks
import OfflineFirstFramework

/// Syncs while the app is in the background, with the system's app refresh tasks.
enum BackgroundRefresh {
    /// Listed in Info.plist under `BGTaskSchedulerPermittedIdentifiers`.
    static let identifier = "io.github.muhittincamdali.OfflineTodos.sync"

    /// Asks the system for a refresh in about 15 minutes. It decides the actual time.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Runs in the background task: asks for the next refresh, then syncs. When the system
    /// ends the task early, SwiftUI cancels this function and the sync stops after the current
    /// request; the rest is pushed next time.
    static func run(store: OfflineStore<Todo>) async {
        schedule()
        _ = try? await store.sync()
    }
}
#endif
