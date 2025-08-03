# iOS Offline First Framework

[![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-iOS%2015%2B-blue.svg)](https://developer.apple.com/ios/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/Version-1.0.0-brightgreen.svg)](CHANGELOG.md)

A comprehensive offline-first architecture framework for iOS applications with data synchronization, conflict resolution, and offline analytics.

## 🚀 Features

- **Offline-First Architecture**: Complete offline data management with local-first approach
- **Data Synchronization**: Intelligent sync strategies with conflict resolution
- **Network State Management**: Real-time network connectivity monitoring
- **Offline Analytics**: Comprehensive analytics for offline usage patterns
- **Conflict Resolution**: Advanced conflict detection and resolution strategies
- **Storage Management**: Encrypted local storage with compression
- **Performance Optimization**: Optimized for speed and battery efficiency

## 📱 Requirements

- iOS 15.0+
- Xcode 14.0+
- Swift 5.9+

## 🛠 Installation

### Swift Package Manager

Add the following dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/muhittincamdali/iOS-Offline-First-Framework", from: "1.0.0")
]
```

### Manual Installation

1. Download the source code
2. Add `OfflineFirstFramework.xcodeproj` to your project
3. Link the framework in your target

## 📖 Quick Start

### Basic Setup

```swift
import OfflineFirstFramework

// Initialize the framework
let config = OfflineFirstConfiguration()
OfflineFirstManager.shared.initialize(with: config)

// Save data offline
let userData = UserData(name: "John", email: "john@example.com")
OfflineFirstManager.shared.save(userData)
    .subscribe(onNext: { result in
        print("Data saved: \(result)")
    })
    .disposed(by: disposeBag)
```

### Data Synchronization

```swift
// Perform sync when online
OfflineFirstManager.shared.sync()
    .subscribe(onNext: { result in
        switch result {
        case .success(let syncedItems):
            print("Synced \(syncedItems.count) items")
        case .failure(let error):
            print("Sync failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

### Network State Monitoring

```swift
// Monitor network connectivity
OfflineFirstManager.shared.isOnline
    .subscribe(onNext: { isOnline in
        print("Network status: \(isOnline ? "Online" : "Offline")")
    })
    .disposed(by: disposeBag)
```

## 🏗 Architecture

### Core Components

- **OfflineFirstManager**: Main orchestrator for the framework
- **NetworkStateManager**: Network connectivity monitoring
- **OfflineStorageManager**: Local data storage with encryption
- **DataSyncManager**: Data synchronization strategies
- **ConflictResolutionManager**: Conflict detection and resolution
- **OfflineAnalyticsManager**: Analytics for offline usage

### Data Flow

```
User Action → Local Storage → Network Check → Sync → Conflict Resolution
```

## 📊 Analytics

Track offline usage patterns and sync performance:

```swift
OfflineFirstManager.shared.getAnalytics()
    .subscribe(onNext: { analytics in
        print("Offline sessions: \(analytics.offlineSessions)")
        print("Sync success rate: \(analytics.syncSuccessRate)%")
        print("Average sync time: \(analytics.averageSyncTime)s")
    })
    .disposed(by: disposeBag)
```

## 🔧 Configuration

Customize the framework behavior:

```swift
var config = OfflineFirstConfiguration()
config.maxStorageSize = 200 * 1024 * 1024 // 200MB
config.syncInterval = 600 // 10 minutes
config.retryAttempts = 5
config.enableAnalytics = true
config.enableConflictResolution = true
config.enableBackgroundSync = true

OfflineFirstManager.shared.initialize(with: config)
```

## 🧪 Testing

Run the test suite:

```bash
swift test
```

## 📚 Documentation

- [API Documentation](Documentation/API/)
- [Architecture Guide](Documentation/Architecture/)
- [Integration Guide](Documentation/Guides/)

## �� Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- [Issues](https://github.com/muhittincamdali/iOS-Offline-First-Framework/issues)
- [Discussions](https://github.com/muhittincamdali/iOS-Offline-First-Framework/discussions)
- [Wiki](https://github.com/muhittincamdali/iOS-Offline-First-Framework/wiki)

## 📈 Roadmap

- [ ] Background sync improvements
- [ ] Advanced conflict resolution strategies
- [ ] Multi-device sync support
- [ ] Cloud storage integration
- [ ] Performance optimizations

## 🙏 Acknowledgments

- [Alamofire](https://github.com/Alamofire/Alamofire) for networking
- [RxSwift](https://github.com/ReactiveX/RxSwift) for reactive programming
- [CocoaLumberjack](https://github.com/CocoaLumberjack/CocoaLumberjack) for logging

---

Made with ❤️ by [Muhittin Camdali](https://github.com/muhittincamdali)
