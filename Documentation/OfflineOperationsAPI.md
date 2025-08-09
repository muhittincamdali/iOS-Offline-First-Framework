# 📱 Offline Operations API

<!-- TOC START -->
## Table of Contents
- [📱 Offline Operations API](#-offline-operations-api)
- [Overview](#overview)
- [OfflineDataManager](#offlinedatamanager)
  - [Properties](#properties)
  - [Methods](#methods)
    - [`performOfflineOperation<T: Codable>(_ operation: OfflineOperation, data: T) -> Observable<OfflineOperationResult>`](#performofflineoperationt-codable-operation-offlineoperation-data-t-observableofflineoperationresult)
    - [`getOfflineData<T: Codable>(_ type: T.Type) -> Observable<[T]>`](#getofflinedatat-codable-type-ttype-observablet)
    - [`updateOfflineData<T: Codable>(_ data: T) -> Observable<UpdateResult>`](#updateofflinedatat-codable-data-t-observableupdateresult)
- [OfflineQueueManager](#offlinequeuemanager)
  - [Queue Management](#queue-management)
  - [Priority Levels](#priority-levels)
- [OfflineStorageManager](#offlinestoragemanager)
  - [Storage Operations](#storage-operations)
- [OfflineSyncManager](#offlinesyncmanager)
  - [Sync Operations](#sync-operations)
- [OfflineAnalytics](#offlineanalytics)
  - [Analytics Collection](#analytics-collection)
- [OfflineStatusManager](#offlinestatusmanager)
  - [Status Monitoring](#status-monitoring)
- [Error Handling](#error-handling)
  - [OfflineError Types](#offlineerror-types)
  - [Error Recovery](#error-recovery)
- [Best Practices](#best-practices)
- [Integration Example](#integration-example)
<!-- TOC END -->


## Overview

The Offline Operations API provides comprehensive offline data management capabilities, including local storage, offline queues, and seamless offline-to-online transitions.

## OfflineDataManager

### Properties

- `offlineStatus: Observable<OfflineStatus>` - Current offline status
- `queuedOperations: Observable<[OfflineOperation]>` - Pending offline operations
- `storageUsage: Observable<StorageUsage>` - Local storage usage
- `lastSyncTimestamp: Observable<Date?>` - Last successful sync timestamp

### Methods

#### `performOfflineOperation<T: Codable>(_ operation: OfflineOperation, data: T) -> Observable<OfflineOperationResult>`
Performs an operation in offline mode with automatic queuing.

```swift
let offlineManager = OfflineDataManager()

// Create user offline
let userData = UserData(id: "123", name: "John Doe", email: "john@example.com")
offlineManager.performOfflineOperation(.createUser, data: userData)
    .subscribe(onNext: { result in
        switch result {
        case .success(let operation):
            print("✅ Offline operation completed")
            print("Operation ID: \(operation.id)")
            print("Queue position: \(operation.queuePosition)")
        case .failure(let error):
            print("❌ Offline operation failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

#### `getOfflineData<T: Codable>(_ type: T.Type) -> Observable<[T]>`
Retrieves data from local storage.

```swift
offlineManager.getOfflineData(UserData.self)
    .subscribe(onNext: { users in
        print("📱 Found \(users.count) users offline")
        for user in users {
            print("- \(user.name) (\(user.email))")
        }
    })
    .disposed(by: disposeBag)
```

#### `updateOfflineData<T: Codable>(_ data: T) -> Observable<UpdateResult>`
Updates data in local storage.

```swift
let updatedUser = UserData(id: "123", name: "John Updated", email: "john.updated@example.com")
offlineManager.updateOfflineData(updatedUser)
    .subscribe(onNext: { result in
        switch result {
        case .success:
            print("✅ Offline data updated")
        case .failure(let error):
            print("❌ Offline update failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## OfflineQueueManager

### Queue Management

```swift
let queueManager = OfflineQueueManager()

// Add operations to queue
queueManager.enqueue(operation: .createUser, data: userData, priority: .high)
queueManager.enqueue(operation: .updateUser, data: updatedUser, priority: .normal)
queueManager.enqueue(operation: .deleteUser, data: userId, priority: .low)

// Process queue when online
queueManager.processQueue()
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

## OfflineStorageManager

### Storage Operations

```swift
let storageManager = OfflineStorageManager()

// Store data offline
storageManager.store(key: "user_123", data: userData)
    .subscribe(onNext: { result in
        switch result {
        case .success:
            print("✅ Data stored offline")
        case .failure(let error):
            print("❌ Offline storage failed: \(error)")
        }
    })
    .disposed(by: disposeBag)

// Retrieve data from offline storage
storageManager.retrieve(key: "user_123")
    .subscribe(onNext: { result in
        switch result {
        case .success(let data):
            print("✅ Data retrieved from offline storage")
            print("User: \(data.name)")
        case .failure(let error):
            print("❌ Offline retrieval failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## OfflineSyncManager

### Sync Operations

```swift
let syncManager = OfflineSyncManager()

// Sync offline changes when online
syncManager.syncOfflineChanges()
    .subscribe(onNext: { result in
        switch result {
        case .success(let syncResult):
            print("✅ Offline changes synced")
            print("Synced operations: \(syncResult.syncedOperations)")
            print("Conflicts resolved: \(syncResult.conflictsResolved)")
        case .failure(let error):
            print("❌ Offline sync failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## OfflineAnalytics

### Analytics Collection

```swift
let analytics = OfflineAnalytics()

// Track offline usage
analytics.trackOfflineUsage(
    operation: .createUser,
    duration: 2.5,
    dataSize: 1024
)

// Get offline analytics
analytics.getOfflineReport()
    .subscribe(onNext: { report in
        print("Offline analytics report:")
        print("Total offline operations: \(report.totalOperations)")
        print("Average operation time: \(report.averageOperationTime)s")
        print("Data stored: \(report.totalDataStored)MB")
        print("Sync success rate: \(report.syncSuccessRate)%")
    })
    .disposed(by: disposeBag)
```

## OfflineStatusManager

### Status Monitoring

```swift
let statusManager = OfflineStatusManager()

// Monitor offline status
statusManager.offlineStatus
    .subscribe(onNext: { status in
        switch status {
        case .online:
            print("🌐 App is online")
        case .offline:
            print("📱 App is offline")
        case .syncing:
            print("🔄 App is syncing")
        case .error(let error):
            print("❌ Offline error: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## Error Handling

### OfflineError Types

```swift
enum OfflineError: Error {
    case storageFull
    case dataCorruption
    case operationFailed
    case syncFailed
    case networkUnavailable
    case quotaExceeded
    case invalidData
}
```

### Error Recovery

```swift
offlineManager.handleOfflineError(.storageFull) { error in
    // Implement storage cleanup
    return storageManager.cleanupStorage()
        .flatMap { _ in
            offlineManager.retryOperation()
        }
}
```

## Best Practices

1. **Queue Operations**: Always queue operations when offline
2. **Monitor Storage**: Monitor local storage usage
3. **Handle Conflicts**: Implement proper conflict resolution
4. **Sync When Online**: Sync offline changes when network is available
5. **Data Validation**: Validate data before storing offline
6. **Error Recovery**: Implement robust error recovery mechanisms
7. **Analytics**: Track offline usage for optimization
8. **User Feedback**: Provide clear offline status indicators

## Integration Example

```swift
import OfflineFirstFramework

class OfflineAwareApp {
    private let offlineManager = OfflineDataManager()
    private let queueManager = OfflineQueueManager()
    private let statusManager = OfflineStatusManager()
    private let disposeBag = DisposeBag()
    
    func setupOfflineOperations() {
        // Monitor offline status
        statusManager.offlineStatus
            .subscribe(onNext: { [weak self] status in
                self?.handleOfflineStatus(status)
            })
            .disposed(by: disposeBag)
        
        // Setup offline operations
        setupOfflineHandlers()
    }
    
    private func setupOfflineHandlers() {
        // Handle user creation
        createUserButton.rx.tap
            .flatMap { [weak self] _ in
                self?.offlineManager.performOfflineOperation(.createUser, data: userData) ?? .empty()
            }
            .subscribe(onNext: { result in
                print("User creation handled")
            })
            .disposed(by: disposeBag)
    }
    
    private func handleOfflineStatus(_ status: OfflineStatus) {
        switch status {
        case .online:
            // Sync offline changes
            queueManager.processQueue()
                .subscribe(onNext: { result in
                    print("Offline changes synced")
                })
                .disposed(by: disposeBag)
        case .offline:
            // Switch to offline mode
            print("Switching to offline mode")
        case .syncing:
            // Show sync progress
            print("Syncing offline changes")
        case .error(let error):
            // Handle error
            print("Offline error: \(error)")
        }
    }
}
```
