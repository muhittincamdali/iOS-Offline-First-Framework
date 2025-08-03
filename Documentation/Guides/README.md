# Integration Guide

## Getting Started

### Prerequisites
- iOS 15.0+
- Xcode 14.0+
- Swift 5.9+
- Basic knowledge of RxSwift

### Installation

#### Swift Package Manager
1. Open your Xcode project
2. Go to File → Add Package Dependencies
3. Enter the repository URL: `https://github.com/muhittincamdali/iOS-Offline-First-Framework`
4. Select the latest version
5. Add to your target

#### Manual Installation
1. Download the source code
2. Add `OfflineFirstFramework.xcodeproj` to your project
3. Link the framework in your target

## Basic Integration

### 1. Initialize the Framework

```swift
import OfflineFirstFramework

// Initialize with default configuration
OfflineFirstManager.shared.initialize(with: OfflineFirstConfiguration())

// Or with custom configuration
var config = OfflineFirstConfiguration()
config.maxStorageSize = 200 * 1024 * 1024 // 200MB
config.syncInterval = 600 // 10 minutes
config.enableAnalytics = true

OfflineFirstManager.shared.initialize(with: config)
```

### 2. Define Your Data Models

```swift
struct User: Codable {
    let id: String
    let name: String
    let email: String
    let createdAt: Date
}

struct Post: Codable {
    let id: String
    let title: String
    let content: String
    let authorId: String
    let createdAt: Date
}
```

### 3. Save Data Offline

```swift
let user = User(
    id: UUID().uuidString,
    name: "John Doe",
    email: "john@example.com",
    createdAt: Date()
)

OfflineFirstManager.shared.save(user)
    .subscribe(onNext: { result in
        switch result {
        case .success:
            print("✅ User saved successfully")
        case .failure(let error):
            print("❌ Failed to save: \(error)")
        case .conflict(let error):
            print("⚠️ Conflict detected: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

### 4. Load Data

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

### 5. Monitor Network Status

```swift
OfflineFirstManager.shared.isOnline
    .subscribe(onNext: { isOnline in
        if isOnline {
            print("🌐 Network: Online")
            // Trigger sync when back online
            OfflineFirstManager.shared.sync()
        } else {
            print("🌐 Network: Offline")
        }
    })
    .disposed(by: disposeBag)
```

### 6. Perform Synchronization

```swift
OfflineFirstManager.shared.sync()
    .subscribe(onNext: { result in
        switch result {
        case .success(let syncedData):
            print("✅ Sync completed: \(syncedData.syncedItems) items synced")
            if syncedData.conflicts > 0 {
                print("⚠️ \(syncedData.conflicts) conflicts resolved")
            }
        case .failure(let error):
            print("❌ Sync failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## Advanced Usage

### Custom Conflict Resolution

```swift
// Define custom conflict resolution strategy
let conflict = Conflict(
    id: "conflict-1",
    type: .dataConflict,
    severity: .medium,
    localValue: "Local data",
    remoteValue: "Remote data",
    timestamp: Date()
)

let resolution = ConflictResolution(
    conflictId: conflict.id,
    resolution: "Use remote data",
    timestamp: Date()
)

OfflineFirstManager.shared.conflictManager.manualResolveConflict(conflict, resolution: resolution)
    .subscribe(onNext: { result in
        switch result {
        case .resolved:
            print("✅ Conflict resolved")
        case .manualResolutionRequired:
            print("⚠️ Manual resolution required")
        case .failure(let error):
            print("❌ Resolution failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

### Analytics Integration

```swift
OfflineFirstManager.shared.getAnalytics()
    .subscribe(onNext: { analytics in
        print("📊 Analytics Report:")
        print("- Offline sessions: \(analytics.offlineSessions)")
        print("- Total offline time: \(analytics.totalOfflineTime)s")
        print("- Sync success rate: \(analytics.syncSuccessRate)%")
        print("- Average sync time: \(analytics.averageSyncTime)s")
        print("- Storage warnings: \(analytics.storageWarnings)")
    })
    .disposed(by: disposeBag)
```

### Storage Management

```swift
// Check storage status
OfflineFirstManager.shared.storageStatus
    .subscribe(onNext: { status in
        switch status {
        case .normal:
            print("💾 Storage: Normal")
        case .lowSpace:
            print("⚠️ Storage: Low space")
        case .full:
            print("❌ Storage: Full")
        }
    })
    .disposed(by: disposeBag)

// Clear all data
OfflineFirstManager.shared.clearAllData()
    .subscribe(onNext: { result in
        switch result {
        case .success:
            print("✅ All data cleared")
        case .failure(let error):
            print("❌ Failed to clear data: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## Best Practices

### 1. Error Handling
- Always handle all possible error cases
- Provide user-friendly error messages
- Implement retry mechanisms for transient failures

### 2. Performance
- Use appropriate data structures
- Implement pagination for large datasets
- Monitor memory usage

### 3. User Experience
- Show sync status to users
- Provide offline indicators
- Handle conflicts gracefully

### 4. Testing
- Write unit tests for all components
- Test offline scenarios
- Test conflict resolution

## Troubleshooting

### Common Issues

#### Sync Not Working
1. Check network connectivity
2. Verify sync configuration
3. Check for conflicts

#### Storage Full
1. Clear old data
2. Increase storage limit
3. Implement data cleanup

#### Performance Issues
1. Monitor memory usage
2. Optimize data structures
3. Implement caching

### Debug Mode

Enable debug logging:

```swift
// Add to your AppDelegate or main app file
import CocoaLumberjack

DDLog.add(DDOSLogger.sharedInstance)
DDLog.setLogLevel(.debug)
```
