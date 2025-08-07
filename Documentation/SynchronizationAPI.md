# 🔄 Synchronization API

## Overview

The Synchronization API provides comprehensive data synchronization capabilities for the iOS Offline-First Framework, including bidirectional sync, conflict resolution, and intelligent sync strategies.

## DataSyncManager

### Properties

- `syncStatus: Observable<SyncStatus>` - Current synchronization status
- `lastSyncTimestamp: Observable<Date?>` - Last successful sync timestamp
- `pendingChanges: Observable<Int>` - Number of pending changes
- `syncProgress: Observable<SyncProgress>` - Real-time sync progress

### Methods

#### `performSync(force: Bool = false) -> Observable<SyncResult>`
Performs data synchronization with optional force parameter.

```swift
let syncManager = DataSyncManager()

// Perform normal sync
syncManager.performSync()
    .subscribe(onNext: { result in
        switch result {
        case .success(let syncResult):
            print("✅ Sync completed successfully")
            print("Synced items: \(syncResult.syncedItems)")
            print("Conflicts resolved: \(syncResult.conflictsResolved)")
            print("Sync time: \(syncResult.syncTime)s")
        case .failure(let error):
            print("❌ Sync failed: \(error)")
        }
    })
    .disposed(by: disposeBag)

// Force sync even if network is poor
syncManager.performSync(force: true)
    .subscribe(onNext: { result in
        print("Forced sync completed")
    })
    .disposed(by: disposeBag)
```

#### `syncIncremental(since: Date) -> Observable<IncrementalSyncResult>`
Performs incremental synchronization since a specific timestamp.

```swift
let lastSync = Date().addingTimeInterval(-3600) // 1 hour ago
syncManager.syncIncremental(since: lastSync)
    .subscribe(onNext: { result in
        print("Incremental sync completed")
        print("Delta items: \(result.deltaItems)")
        print("Compression ratio: \(result.compressionRatio)")
        print("Bandwidth used: \(result.bandwidthUsed)MB")
    })
    .disposed(by: disposeBag)
```

#### `syncBidirectional() -> Observable<BidirectionalSyncResult>`
Performs bidirectional synchronization (upload and download).

```swift
syncManager.syncBidirectional()
    .subscribe(onNext: { result in
        print("Bidirectional sync completed")
        print("Uploaded items: \(result.uploadedItems)")
        print("Downloaded items: \(result.downloadedItems)")
        print("Conflicts detected: \(result.conflictsDetected)")
    })
    .disposed(by: disposeBag)
```

## SyncConfiguration

### Basic Configuration

```swift
let syncConfig = SyncConfiguration()
syncConfig.enableIncrementalSync = true
syncConfig.enableBidirectionalSync = true
syncConfig.syncInterval = 300 // 5 minutes
syncConfig.maxRetries = 3
syncConfig.enableBackgroundSync = true
syncConfig.enableConflictResolution = true
```

### Advanced Configuration

```swift
let advancedConfig = AdvancedSyncConfiguration()
advancedConfig.enableCompression = true
advancedConfig.enableEncryption = true
advancedConfig.chunkSize = 1024 * 1024 // 1MB chunks
advancedConfig.maxConcurrentOperations = 5
advancedConfig.timeout = 30 // 30 seconds
advancedConfig.enableResume = true
```

## SyncStrategies

### Strategy Types

- `.full` - Full synchronization
- `.incremental` - Incremental synchronization
- `.bidirectional` - Bidirectional synchronization
- `.selective` - Selective synchronization
- `.background` - Background synchronization

### Strategy Implementation

```swift
let strategy = SyncStrategy.incremental
syncManager.performSyncWithStrategy(strategy)
    .subscribe(onNext: { result in
        print("Strategy-based sync completed")
    })
    .disposed(by: disposeBag)
```

## SyncQueue

### Queue Management

```swift
let syncQueue = SyncQueue()

// Add sync operations to queue
syncQueue.enqueue(operation: .syncUsers, priority: .high)
syncQueue.enqueue(operation: .syncPosts, priority: .normal)
syncQueue.enqueue(operation: .syncComments, priority: .low)

// Process queue
syncQueue.processQueue()
    .subscribe(onNext: { result in
        print("Queue processed: \(result.completedOperations) operations")
        print("Failed operations: \(result.failedOperations)")
    })
    .disposed(by: disposeBag)
```

### Priority Levels

- `.critical` - Critical operations (immediate execution)
- `.high` - High priority operations
- `.normal` - Standard operations
- `.low` - Low priority operations
- `.background` - Background operations

## ConflictResolution

### Conflict Detection

```swift
let conflictResolver = ConflictResolver()

// Detect conflicts
conflictResolver.detectConflicts(
    localData: localUser,
    remoteData: remoteUser
) { result in
    switch result {
    case .success(let conflicts):
        print("Conflicts detected: \(conflicts.count)")
        for conflict in conflicts {
            print("Field: \(conflict.field)")
            print("Local value: \(conflict.localValue)")
            print("Remote value: \(conflict.remoteValue)")
        }
    case .failure(let error):
        print("Conflict detection failed: \(error)")
    }
}
```

### Resolution Strategies

```swift
// Last write wins
conflictResolver.resolveWithStrategy(.lastWriteWins, conflicts: conflicts)
    .subscribe(onNext: { result in
        print("Conflicts resolved with last write wins")
    })
    .disposed(by: disposeBag)

// Manual resolution
conflictResolver.resolveManually(conflicts: conflicts, resolution: userResolution)
    .subscribe(onNext: { result in
        print("Manual conflict resolution completed")
    })
    .disposed(by: disposeBag)

// Merge strategy
conflictResolver.resolveWithStrategy(.merge, conflicts: conflicts)
    .subscribe(onNext: { result in
        print("Conflicts resolved with merge strategy")
    })
    .disposed(by: disposeBag)
```

## SyncMonitoring

### Real-time Monitoring

```swift
let syncMonitor = SyncMonitor()

// Monitor sync progress
syncMonitor.syncProgress
    .subscribe(onNext: { progress in
        print("Sync progress: \(progress.percentage)%")
        print("Current operation: \(progress.currentOperation)")
        print("Items processed: \(progress.itemsProcessed)")
        print("Total items: \(progress.totalItems)")
    })
    .disposed(by: disposeBag)

// Monitor sync status
syncMonitor.syncStatus
    .subscribe(onNext: { status in
        switch status {
        case .idle:
            print("Sync is idle")
        case .syncing:
            print("Sync in progress")
        case .completed:
            print("Sync completed")
        case .failed(let error):
            print("Sync failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## SyncAnalytics

### Analytics Collection

```swift
let syncAnalytics = SyncAnalytics()

// Track sync metrics
syncAnalytics.trackSync(
    strategy: .incremental,
    itemsSynced: 150,
    syncTime: 45.5,
    conflictsResolved: 3
)

// Get analytics report
syncAnalytics.getReport()
    .subscribe(onNext: { report in
        print("Sync analytics report:")
        print("Total syncs: \(report.totalSyncs)")
        print("Average sync time: \(report.averageSyncTime)s")
        print("Success rate: \(report.successRate)%")
        print("Conflicts per sync: \(report.averageConflicts)")
    })
    .disposed(by: disposeBag)
```

## Error Handling

### SyncError Types

```swift
enum SyncError: Error {
    case networkUnavailable
    case serverUnreachable
    case authenticationFailed
    case dataCorruption
    case conflictUnresolved
    case timeout
    case quotaExceeded
    case serverError(Int)
}
```

### Error Recovery

```swift
syncManager.handleSyncError(.networkUnavailable) { error in
    // Implement retry logic
    return syncManager.retrySync()
        .delay(.seconds(30), scheduler: MainScheduler.instance)
        .retry(3)
}
```

## Best Practices

1. **Use Incremental Sync**: Prefer incremental sync over full sync
2. **Handle Conflicts Gracefully**: Implement proper conflict resolution
3. **Monitor Progress**: Always monitor sync progress
4. **Queue Operations**: Use queues for better performance
5. **Background Sync**: Use background sync for better UX
6. **Error Recovery**: Implement robust error recovery
7. **Analytics**: Track sync metrics for optimization
8. **Compression**: Use compression for large data transfers

## Integration Example

```swift
import OfflineFirstFramework

class SyncManager {
    private let dataSyncManager = DataSyncManager()
    private let syncQueue = SyncQueue()
    private let conflictResolver = ConflictResolver()
    private let disposeBag = DisposeBag()
    
    func setupSynchronization() {
        // Configure sync
        let config = SyncConfiguration()
        config.enableIncrementalSync = true
        config.syncInterval = 300 // 5 minutes
        config.enableBackgroundSync = true
        
        dataSyncManager.configure(config)
        
        // Setup conflict resolution
        conflictResolver.configure { config in
            config.defaultStrategy = .lastWriteWins
            config.enableManualResolution = true
        }
        
        // Start periodic sync
        startPeriodicSync()
    }
    
    private func startPeriodicSync() {
        Observable<Int>.interval(.seconds(300), scheduler: MainScheduler.instance)
            .flatMap { _ in
                self.dataSyncManager.performSync()
            }
            .subscribe(onNext: { result in
                print("Periodic sync completed")
            })
            .disposed(by: disposeBag)
    }
    
    func syncUserData() {
        // Add user sync to queue
        syncQueue.enqueue(operation: .syncUsers, priority: .high)
        
        // Process queue
        syncQueue.processQueue()
            .subscribe(onNext: { result in
                print("User data synced successfully")
            })
            .disposed(by: disposeBag)
    }
}
```
