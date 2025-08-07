# 🚀 Getting Started Guide

## Overview

This guide will help you get started with the iOS Offline-First Framework quickly and efficiently. You'll learn how to integrate the framework into your iOS app and implement basic offline-first functionality.

## Prerequisites

Before you begin, ensure you have:

- **iOS 15.0+** with iOS 15.0+ SDK
- **Swift 5.9+** programming language
- **Xcode 15.0+** development environment
- **Git** version control system
- **Swift Package Manager** for dependency management

## Installation

### Swift Package Manager

1. **Open your Xcode project**
2. **Go to File → Add Package Dependencies**
3. **Enter the repository URL**: `https://github.com/muhittincamdali/iOS-Offline-First-Framework`
4. **Select the latest version**
5. **Add to your target**

### Manual Installation

1. **Download the source code**
2. **Add `OfflineFirstFramework.xcodeproj` to your project**
3. **Link the framework in your target**

## Quick Start

### Step 1: Import the Framework

```swift
import OfflineFirstFramework
```

### Step 2: Initialize the Framework

```swift
// Initialize with default configuration
OfflineFirstManager.shared.initialize(with: OfflineFirstConfiguration())
```

### Step 3: Configure Basic Settings

```swift
// Create custom configuration
let config = OfflineFirstConfiguration()

// Enable core features
config.enableOfflineMode = true
config.enableSynchronization = true
config.enableConflictResolution = true
config.enableDataPersistence = true

// Set storage limits
config.maxStorageSize = 100 * 1024 * 1024 // 100MB

// Set sync intervals
config.syncInterval = 300 // 5 minutes

// Initialize with custom configuration
OfflineFirstManager.shared.initialize(with: config)
```

### Step 4: Define Your Data Models

```swift
// Define your data models
struct User: Codable {
    let id: String
    let name: String
    let email: String
    let createdAt: Date
    let lastModified: Date
}

struct Post: Codable {
    let id: String
    let title: String
    let content: String
    let authorId: String
    let createdAt: Date
    let lastModified: Date
}
```

### Step 5: Save Data Offline

```swift
// Create user data
let user = User(
    id: UUID().uuidString,
    name: "John Doe",
    email: "john@example.com",
    createdAt: Date(),
    lastModified: Date()
)

// Save user offline
OfflineFirstManager.shared.save(user)
    .subscribe(onNext: { result in
        switch result {
        case .success:
            print("✅ User saved successfully")
        case .failure(let error):
            print("❌ Save failed: \(error)")
        case .conflict(let error):
            print("⚠️ Conflict detected: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

### Step 6: Load Data

```swift
// Load all users
OfflineFirstManager.shared.load(User.self)
    .subscribe(onNext: { users in
        print("📱 Found \(users.count) users")
        for user in users {
            print("- \(user.name) (\(user.email))")
        }
    })
    .disposed(by: disposeBag)
```

### Step 7: Monitor Network Status

```swift
// Monitor network connectivity
OfflineFirstManager.shared.isOnline
    .subscribe(onNext: { isOnline in
        print("🌐 Network: \(isOnline ? "Online" : "Offline")")
    })
    .disposed(by: disposeBag)
```

### Step 8: Perform Synchronization

```swift
// Perform manual sync
OfflineFirstManager.shared.sync()
    .subscribe(onNext: { result in
        switch result {
        case .success(let syncResult):
            print("✅ Sync completed successfully")
            print("Synced items: \(syncResult.syncedItems)")
            print("Conflicts resolved: \(syncResult.conflictsResolved)")
        case .failure(let error):
            print("❌ Sync failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## Basic Example

Here's a complete example showing how to implement basic offline-first functionality:

```swift
import OfflineFirstFramework
import RxSwift

class OfflineFirstViewController: UIViewController {
    
    private let disposeBag = DisposeBag()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupOfflineFirst()
    }
    
    private func setupOfflineFirst() {
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
    }
    
    private func setupMonitoring() {
        // Monitor network status
        OfflineFirstManager.shared.isOnline
            .subscribe(onNext: { [weak self] isOnline in
                self?.updateNetworkStatus(isOnline)
            })
            .disposed(by: disposeBag)
        
        // Monitor sync status
        OfflineFirstManager.shared.syncStatus
            .subscribe(onNext: { [weak self] status in
                self?.updateSyncStatus(status)
            })
            .disposed(by: disposeBag)
    }
    
    private func updateNetworkStatus(_ isOnline: Bool) {
        DispatchQueue.main.async {
            self.networkStatusLabel.text = isOnline ? "🌐 Online" : "📱 Offline"
            self.networkStatusLabel.textColor = isOnline ? .systemGreen : .systemOrange
        }
    }
    
    private func updateSyncStatus(_ status: SyncStatus) {
        DispatchQueue.main.async {
            switch status {
            case .idle:
                self.syncStatusLabel.text = "Idle"
                self.syncStatusLabel.textColor = .systemGray
            case .syncing:
                self.syncStatusLabel.text = "🔄 Syncing..."
                self.syncStatusLabel.textColor = .systemBlue
            case .completed:
                self.syncStatusLabel.text = "✅ Synced"
                self.syncStatusLabel.textColor = .systemGreen
            case .failed(let error):
                self.syncStatusLabel.text = "❌ Sync Failed"
                self.syncStatusLabel.textColor = .systemRed
            }
        }
    }
    
    @IBAction func createUserButtonTapped(_ sender: UIButton) {
        let user = User(
            id: UUID().uuidString,
            name: "New User",
            email: "newuser@example.com",
            createdAt: Date(),
            lastModified: Date()
        )
        
        OfflineFirstManager.shared.save(user)
            .subscribe(onNext: { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success:
                        self.showAlert(title: "Success", message: "User created successfully")
                    case .failure(let error):
                        self.showAlert(title: "Error", message: "Failed to create user: \(error)")
                    case .conflict(let error):
                        self.showAlert(title: "Conflict", message: "Conflict detected: \(error)")
                    }
                }
            })
            .disposed(by: disposeBag)
    }
    
    @IBAction func loadUsersButtonTapped(_ sender: UIButton) {
        OfflineFirstManager.shared.load(User.self)
            .subscribe(onNext: { users in
                DispatchQueue.main.async {
                    self.updateUsersList(users)
                }
            })
            .disposed(by: disposeBag)
    }
    
    @IBAction func syncButtonTapped(_ sender: UIButton) {
        OfflineFirstManager.shared.sync()
            .subscribe(onNext: { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let syncResult):
                        self.showAlert(title: "Sync Complete", message: "Synced \(syncResult.syncedItems) items")
                    case .failure(let error):
                        self.showAlert(title: "Sync Failed", message: "Sync failed: \(error)")
                    }
                }
            })
            .disposed(by: disposeBag)
    }
    
    private func updateUsersList(_ users: [User]) {
        // Update your UI with the users list
        print("Loaded \(users.count) users")
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
```

## Advanced Configuration

### Custom Storage Configuration

```swift
// Configure storage with encryption and compression
let storageConfig = StorageConfiguration()
storageConfig.enableEncryption = true
storageConfig.enableCompression = true
storageConfig.maxStorageSize = 500 * 1024 * 1024 // 500MB

// Apply storage configuration
OfflineFirstManager.shared.configureStorage(storageConfig)
```

### Custom Sync Configuration

```swift
// Configure sync with custom intervals
let syncConfig = SyncConfiguration()
syncConfig.syncInterval = 1800 // 30 minutes
syncConfig.maxRetries = 5
syncConfig.enableBackgroundSync = true

// Apply sync configuration
OfflineFirstManager.shared.configureSync(syncConfig)
```

### Custom Conflict Resolution

```swift
// Configure conflict resolution
let conflictConfig = ConflictResolutionConfiguration()
conflictConfig.enableAutoResolution = true
conflictConfig.defaultStrategy = .lastWriteWins
conflictConfig.enableManualResolution = true

// Apply conflict resolution configuration
OfflineFirstManager.shared.configureConflictResolution(conflictConfig)
```

## Testing Your Implementation

### Test Offline Functionality

1. **Enable Airplane Mode** on your device
2. **Create data** - it should be saved locally
3. **Load data** - it should work offline
4. **Disable Airplane Mode** - sync should occur automatically

### Test Conflict Resolution

1. **Create the same data** on multiple devices
2. **Modify the data** on different devices
3. **Sync the data** - conflicts should be resolved automatically

### Test Performance

1. **Monitor memory usage** during operations
2. **Check storage usage** regularly
3. **Monitor sync performance** and adjust intervals

## Troubleshooting

### Common Issues

#### Framework Not Initializing
```swift
// Ensure proper initialization
OfflineFirstManager.shared.initialize(with: OfflineFirstConfiguration())
```

#### Data Not Saving
```swift
// Check storage configuration
let config = OfflineFirstConfiguration()
config.enableDataPersistence = true
config.maxStorageSize = 100 * 1024 * 1024 // 100MB
```

#### Sync Not Working
```swift
// Check network and sync configuration
let config = OfflineFirstConfiguration()
config.enableSynchronization = true
config.syncInterval = 300 // 5 minutes
```

#### Conflicts Not Resolving
```swift
// Check conflict resolution configuration
let config = OfflineFirstConfiguration()
config.enableConflictResolution = true
config.conflictResolutionStrategy = .lastWriteWins
```

### Debug Mode

Enable debug logging for troubleshooting:

```swift
// Enable debug mode
OfflineFirstManager.shared.enableDebugMode()

// Check logs in Xcode console
```

## Next Steps

After completing this guide, you can:

1. **Explore Advanced Features**: Learn about advanced synchronization, conflict resolution, and analytics
2. **Customize Configuration**: Fine-tune the framework for your specific needs
3. **Implement Analytics**: Add monitoring and analytics to track usage
4. **Optimize Performance**: Implement performance optimizations
5. **Add Security**: Implement additional security measures
6. **Test Thoroughly**: Test all offline scenarios thoroughly

## Additional Resources

- [API Documentation](Documentation/API/) - Complete API reference
- [Examples](Examples/) - Code examples and sample projects
- [Architecture Guide](Documentation/Architecture/) - Framework architecture
- [Best Practices](Documentation/BestPractices/) - Development best practices
- [Troubleshooting](Documentation/Troubleshooting/) - Common issues and solutions

## Support

If you encounter any issues:

1. **Check the documentation** for solutions
2. **Review the examples** for implementation patterns
3. **Enable debug mode** for detailed logging
4. **Create an issue** on GitHub for bugs
5. **Ask questions** in the community discussions

Happy coding with the iOS Offline-First Framework! 🚀
