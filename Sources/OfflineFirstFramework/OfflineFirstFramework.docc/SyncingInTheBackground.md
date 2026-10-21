# Syncing in the background

Sync while the app runs, when the connection comes back, and in background refresh tasks on iOS.

## Overview

``OfflineStore/sync()`` pushes queued changes and pulls server changes. You can call it from
anywhere: a pull-to-refresh, a button, a timer or a background task. Calls that arrive while a
sync runs wait for that sync instead of starting another one.

## While the app runs

``OfflineStore/startAutomaticSync(monitor:interval:debounce:)`` syncs when the device comes
online, shortly after local changes, when a failed change is due again, and at an interval:

```swift
await store.startAutomaticSync(interval: .seconds(300), debounce: .seconds(2))
```

The online state comes from ``NetworkConnectivityMonitor`` (`NWPathMonitor`). Errors do not
throw here; they appear in ``OfflineStore/status`` and in ``StoreState/status``, which
``SyncedCollection`` exposes to SwiftUI.

## Failed changes

When a push fails, the change waits according to the ``RetryPolicy``: exponential backoff from
two seconds up to ten minutes with random jitter, eight attempts by default. After the last
attempt the change is parked: it stays on the device and in
``OfflineStore/failedChanges()``, and ``OfflineStore/retryFailedChanges()`` queues it again.
Rejected changes are parked the same way unless the server sent its current version.

After five failed pulls in a row the ``CircuitBreaker`` pauses pulling for a minute; the status
is then ``SyncStatus/paused(until:)``. Changes that are due are still pushed meanwhile, each
after its own retry date, so edits reach a server whose pulls fail.

## In a background refresh task (iOS)

Register an identifier in your target's Info.plist under `BGTaskSchedulerPermittedIdentifiers`,
turn on the **Background fetch** mode, then let SwiftUI run the sync:

```swift
import BackgroundTasks
import OfflineFirstFramework
import SwiftUI

@main
struct TodosApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup { ContentView() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { scheduleRefresh() }
            }
            .backgroundTask(.appRefresh("com.example.todos.sync")) {
                scheduleRefresh()
                _ = try? await TodoStore.shared.sync()
            }
    }

    private func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.example.todos.sync")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
```

When the system ends the background time, SwiftUI cancels the closure; the sync stops after
the current request, and everything already applied is saved. The rest goes out next time.

Store files use the `completeUntilFirstUserAuthentication` protection class by default, so a
background task can read them after the user unlocked the device once since it started. A
Keychain key for ``StoreEncryption`` uses the matching `afterFirstUnlockThisDeviceOnly`
accessibility.

The example app `OfflineTodos` in the repository uses exactly this setup in
`BackgroundRefresh.swift`.
