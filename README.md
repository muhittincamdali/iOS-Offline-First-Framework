# iOS Offline-First Framework

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-5.9+-F05138?style=flat&logo=swift&logoColor=white" alt="Swift"></a>
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-15.0+-000000?style=flat&logo=apple&logoColor=white" alt="iOS"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green.svg" alt="License"></a>
</p>

<p align="center">
  <b>Build apps that work offline with automatic sync, conflict resolution, and data persistence.</b>
</p>

---

## Features

- **Offline Storage** — Local data persistence with Core Data/SwiftData
- **Sync Engine** — Automatic background synchronization
- **Conflict Resolution** — Handle merge conflicts gracefully
- **Network Monitor** — Detect connectivity changes
- **Queue Management** — Offline action queue with retry

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/muhittincamdali/iOS-Offline-First-Framework.git", from: "1.0.0")
]
```

## Quick Start

```swift
import OfflineFirst

// Configure sync engine
let syncEngine = SyncEngine(
    local: CoreDataStorage(),
    remote: APIService(),
    conflictStrategy: .serverWins
)

// Save data (works offline)
try await syncEngine.save(user)

// Data syncs automatically when online
syncEngine.onSyncComplete { result in
    print("Sync completed: \(result)")
}

// Check sync status
let pendingChanges = syncEngine.pendingChangesCount
```

## Network Monitoring

```swift
let monitor = NetworkMonitor()

monitor.onStatusChange { status in
    switch status {
    case .connected:
        syncEngine.sync()
    case .disconnected:
        showOfflineBanner()
    }
}
```

## Conflict Resolution

```swift
let engine = SyncEngine(
    conflictStrategy: .custom { local, remote in
        // Merge logic
        return local.updatedAt > remote.updatedAt ? local : remote
    }
)
```

## Requirements

- iOS 15.0+
- Xcode 15.0+
- Swift 5.9+

## License

MIT License. See [LICENSE](LICENSE).

## Author

**Muhittin Camdali** — [@muhittincamdali](https://github.com/muhittincamdali)
