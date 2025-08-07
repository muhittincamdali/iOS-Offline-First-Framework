# 🏆 OfflineFirstManager API

## Overview

The OfflineFirstManager is the main orchestrator for the iOS Offline-First Framework, providing comprehensive offline data management, synchronization, and conflict resolution capabilities.

## Core Properties

### Singleton Instance
```swift
public static let shared = OfflineFirstManager()
```

### Manager Components
- `networkManager: NetworkStateManager` - Network connectivity management
- `storageManager: OfflineStorageManager` - Local data storage
- `syncManager: DataSyncManager` - Data synchronization
- `analyticsManager: OfflineAnalyticsManager` - Analytics collection
- `conflictManager: ConflictResolutionManager` - Conflict resolution

### Observable Properties
- `isOnline: Observable<Bool>` - Network connectivity status
- `syncStatus: Observable<SyncStatus>` - Current sync status
- `storageStatus: Observable<StorageStatus>` - Storage status

## Initialization

### Basic Initialization
```swift
import OfflineFirstFramework

// Initialize with default configuration
OfflineFirstManager.shared.initialize(with: OfflineFirstConfiguration())
```

### Custom Configuration
```swift
let config = OfflineFirstConfiguration()
config.enableOfflineMode = true
config.enableSynchronization = true
config.enableConflictResolution = true
config.enableDataPersistence = true
config.maxStorageSize = 100 * 1024 * 1024 // 100MB
config.syncInterval = 300 // 5 minutes

OfflineFirstManager.shared.initialize(with: config)
```

## Core Methods

### Data Operations

#### `save<T: Codable>(_ data: T) -> Observable<SaveResult>`
Saves data with offline-first approach.

```swift
let user = User(id: "123", name: "John Doe", email: "john@example.com")

OfflineFirstManager.shared.save(user)
    .subscribe(onNext: { result in
        switch result {
        case .success:
            print("✅ Data saved successfully")
        case .failure(let error):
            print("❌ Save failed: \(error)")
        case .conflict(let error):
            print("⚠️ Conflict detected: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

#### `load<T: Codable>(_ type: T.Type) -> Observable<[T]>`
Loads data with offline-first approach.

```swift
OfflineFirstManager.shared.load(User.self)
    .subscribe(onNext: { users in
        print("📱 Found \(users.count) users")
        for user in users {
            print("- \(user.name) (\(user.email))")
        }
    })
    .disposed(by: disposeBag)
```

#### `delete<T: Codable>(_ data: T) -> Observable<DeleteResult>`
Deletes data with offline-first approach.

```swift
OfflineFirstManager.shared.delete(user)
    .subscribe(onNext: { result in
        switch result {
        case .success:
            print("✅ Data deleted successfully")
        case .failure(let error):
            print("❌ Delete failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

### Synchronization

#### `sync(force: Bool = false) -> Observable<SyncResult>`
Performs data synchronization.

```swift
// Normal sync
OfflineFirstManager.shared.sync()
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

// Force sync
OfflineFirstManager.shared.sync(force: true)
    .subscribe(onNext: { result in
        print("Forced sync completed")
    })
    .disposed(by: disposeBag)
```

### Conflict Resolution

#### `resolveConflicts<T: Codable>(for data: T) -> Observable<ConflictResolutionResult>`
Resolves conflicts for specific data.

```swift
OfflineFirstManager.shared.resolveConflicts(for: user)
    .subscribe(onNext: { result in
        switch result {
        case .success(let resolvedData):
            print("✅ Conflicts resolved successfully")
            print("Resolved data: \(resolvedData)")
        case .failure(let error):
            print("❌ Conflict resolution failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

### Analytics

#### `getAnalytics() -> Observable<OfflineAnalytics>`
Gets analytics data.

```swift
OfflineFirstManager.shared.getAnalytics()
    .subscribe(onNext: { analytics in
        print("📊 Analytics Report:")
        print("Total operations: \(analytics.totalOperations)")
        print("Offline operations: \(analytics.offlineOperations)")
        print("Sync success rate: \(analytics.syncSuccessRate)%")
        print("Average sync time: \(analytics.averageSyncTime)s")
        print("Storage usage: \(analytics.storageUsage)MB")
    })
    .disposed(by: disposeBag)
```

### Data Management

#### `clearAllData() -> Observable<ClearResult>`
Clears all offline data.

```swift
OfflineFirstManager.shared.clearAllData()
    .subscribe(onNext: { result in
        switch result {
        case .success:
            print("✅ All data cleared successfully")
        case .failure(let error):
            print("❌ Data clearing failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## Configuration

### OfflineFirstConfiguration

```swift
let config = OfflineFirstConfiguration()

// Enable features
config.enableOfflineMode = true
config.enableSynchronization = true
config.enableConflictResolution = true
config.enableDataPersistence = true
config.enableAnalytics = true

// Storage settings
config.maxStorageSize = 100 * 1024 * 1024 // 100MB
config.enableEncryption = true
config.enableCompression = true

// Sync settings
config.syncInterval = 300 // 5 minutes
config.maxRetries = 3
config.enableBackgroundSync = true

// Conflict resolution settings
config.conflictResolutionStrategy = .lastWriteWins
config.enableManualResolution = true
config.enableConflictLogging = true

// Network settings
config.enableNetworkAdaptation = true
config.minimumBandwidth = 1.0 // 1 Mbps
config.maximumLatency = 5000 // 5 seconds
```

## Status Monitoring

### Network Status
```swift
OfflineFirstManager.shared.isOnline
    .subscribe(onNext: { isOnline in
        print("🌐 Network: \(isOnline ? "Online" : "Offline")")
    })
    .disposed(by: disposeBag)
```

### Sync Status
```swift
OfflineFirstManager.shared.syncStatus
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

### Storage Status
```swift
OfflineFirstManager.shared.storageStatus
    .subscribe(onNext: { status in
        switch status {
        case .normal:
            print("Storage status: Normal")
        case .warning:
            print("Storage status: Warning")
        case .critical:
            print("Storage status: Critical")
        }
    })
    .disposed(by: disposeBag)
```

## Error Handling

### Error Types
```swift
enum OfflineFirstError: Error {
    case initializationFailed
    case networkUnavailable
    case storageFull
    case syncFailed
    case conflictUnresolved
    case dataCorruption
    case authenticationFailed
}
```

### Error Recovery
```swift
OfflineFirstManager.shared.handleError(.networkUnavailable) { error in
    // Implement retry logic
    return OfflineFirstManager.shared.retryOperation()
        .delay(.seconds(30), scheduler: MainScheduler.instance)
        .retry(3)
}
```

## Best Practices

1. **Initialize Early**: Initialize the manager early in app lifecycle
2. **Monitor Status**: Always monitor network, sync, and storage status
3. **Handle Errors**: Implement proper error handling and recovery
4. **Use Observables**: Leverage RxSwift observables for reactive programming
5. **Configure Properly**: Configure all settings based on app requirements
6. **Monitor Analytics**: Track usage analytics for optimization
7. **Handle Conflicts**: Implement proper conflict resolution strategies
8. **Test Thoroughly**: Test offline scenarios thoroughly

## Integration Example

```swift
import OfflineFirstFramework
import RxSwift

class OfflineFirstApp {
    private let disposeBag = DisposeBag()
    
    func setupOfflineFirst() {
        // Configure the framework
        let config = OfflineFirstConfiguration()
        config.enableOfflineMode = true
        config.enableSynchronization = true
        config.enableConflictResolution = true
        config.maxStorageSize = 200 * 1024 * 1024 // 200MB
        config.syncInterval = 600 // 10 minutes
        
        // Initialize
        OfflineFirstManager.shared.initialize(with: config)
        
        // Setup monitoring
        setupMonitoring()
        
        // Setup periodic sync
        setupPeriodicSync()
    }
    
    private func setupMonitoring() {
        // Monitor network status
        OfflineFirstManager.shared.isOnline
            .subscribe(onNext: { [weak self] isOnline in
                self?.handleNetworkChange(isOnline)
            })
            .disposed(by: disposeBag)
        
        // Monitor sync status
        OfflineFirstManager.shared.syncStatus
            .subscribe(onNext: { [weak self] status in
                self?.handleSyncStatus(status)
            })
            .disposed(by: disposeBag)
    }
    
    private func setupPeriodicSync() {
        Observable<Int>.interval(.seconds(600), scheduler: MainScheduler.instance)
            .flatMap { _ in
                OfflineFirstManager.shared.sync()
            }
            .subscribe(onNext: { result in
                print("Periodic sync completed")
            })
            .disposed(by: disposeBag)
    }
    
    private func handleNetworkChange(_ isOnline: Bool) {
        if isOnline {
            // Trigger sync when network becomes available
            OfflineFirstManager.shared.sync()
                .subscribe(onNext: { result in
                    print("Network sync completed")
                })
                .disposed(by: disposeBag)
        }
    }
    
    private func handleSyncStatus(_ status: SyncStatus) {
        switch status {
        case .syncing:
            // Show sync progress
            print("Syncing data...")
        case .completed:
            // Hide sync progress
            print("Sync completed")
        case .failed(let error):
            // Show error
            print("Sync failed: \(error)")
        default:
            break
        }
    }
}
```
