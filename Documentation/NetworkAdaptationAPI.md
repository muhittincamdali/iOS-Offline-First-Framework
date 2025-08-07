# 🔄 Network Adaptation API

## Overview

The Network Adaptation API provides intelligent network connectivity management, adaptive synchronization, and network-aware operations for the iOS Offline-First Framework.

## NetworkStateManager

### Properties

- `isOnline: Observable<Bool>` - Network connectivity status
- `connectionType: Observable<ConnectionType>` - Type of connection (WiFi, Cellular, etc.)
- `connectionQuality: Observable<ConnectionQuality>` - Quality of connection
- `bandwidth: Observable<Bandwidth>` - Available bandwidth

### Methods

#### `checkConnectivity() -> Observable<NetworkStatus>`
Checks current network connectivity and returns detailed status.

```swift
let networkManager = NetworkStateManager()
networkManager.checkConnectivity()
    .subscribe(onNext: { status in
        print("Network: \(status.isOnline ? "Online" : "Offline")")
        print("Type: \(status.connectionType)")
        print("Quality: \(status.connectionQuality)")
    })
    .disposed(by: disposeBag)
```

#### `testConnection(url: URL) -> Observable<ConnectionTestResult>`
Tests connection to a specific URL with detailed metrics.

```swift
let testURL = URL(string: "https://api.example.com")!
networkManager.testConnection(url: testURL)
    .subscribe(onNext: { result in
        print("Latency: \(result.latency)ms")
        print("Bandwidth: \(result.bandwidth)Mbps")
        print("Success: \(result.isSuccessful)")
    })
    .disposed(by: disposeBag)
```

#### `monitorNetworkChanges() -> Observable<NetworkChangeEvent>`
Monitors network changes and provides real-time updates.

```swift
networkManager.monitorNetworkChanges()
    .subscribe(onNext: { event in
        switch event {
        case .connected(let type):
            print("Connected via \(type)")
        case .disconnected:
            print("Disconnected")
        case .qualityChanged(let quality):
            print("Quality changed to \(quality)")
        }
    })
    .disposed(by: disposeBag)
```

## AdaptiveSyncManager

### Configuration

```swift
let adaptiveConfig = AdaptiveSyncConfiguration()
adaptiveConfig.enableBandwidthOptimization = true
adaptiveConfig.enableQualityAdaptation = true
adaptiveConfig.minimumBandwidth = 1.0 // 1 Mbps
adaptiveConfig.maximumLatency = 5000 // 5 seconds
```

### Methods

#### `syncWithAdaptation(config: AdaptiveSyncConfiguration) -> Observable<AdaptiveSyncResult>`
Performs adaptive synchronization based on network conditions.

```swift
let adaptiveSync = AdaptiveSyncManager()
adaptiveSync.syncWithAdaptation(config: adaptiveConfig)
    .subscribe(onNext: { result in
        print("Adaptive sync completed")
        print("Items synced: \(result.syncedItems)")
        print("Bandwidth used: \(result.bandwidthUsed)MB")
        print("Sync time: \(result.syncTime)s")
    })
    .disposed(by: disposeBag)
```

## NetworkQueueManager

### Queue Management

```swift
let queueManager = NetworkQueueManager()

// Add operation to queue
queueManager.enqueue(operation: .syncData, priority: .high)
queueManager.enqueue(operation: .uploadFile, priority: .normal)

// Process queue
queueManager.processQueue()
    .subscribe(onNext: { result in
        print("Queue processed: \(result.completedOperations) operations")
    })
    .disposed(by: disposeBag)
```

### Priority Levels

- `.critical` - Immediate execution
- `.high` - High priority operations
- `.normal` - Standard operations
- `.low` - Background operations

## BandwidthOptimizer

### Optimization Strategies

```swift
let optimizer = BandwidthOptimizer()

// Configure optimization
let optimizationConfig = BandwidthOptimizationConfiguration()
optimizationConfig.enableCompression = true
optimizationConfig.enableChunking = true
optimizationConfig.chunkSize = 1024 * 1024 // 1MB chunks

// Optimize data transfer
optimizer.optimizeTransfer(data: largeData, config: optimizationConfig)
    .subscribe(onNext: { result in
        print("Transfer optimized")
        print("Original size: \(result.originalSize)MB")
        print("Compressed size: \(result.compressedSize)MB")
        print("Compression ratio: \(result.compressionRatio)")
    })
    .disposed(by: disposeBag)
```

## ConnectionManager

### Connection Types

- `.wifi` - WiFi connection
- `.cellular` - Cellular connection
- `.ethernet` - Ethernet connection
- `.unknown` - Unknown connection type

### Quality Levels

- `.excellent` - Excellent connection quality
- `.good` - Good connection quality
- `.fair` - Fair connection quality
- `.poor` - Poor connection quality
- `.unusable` - Unusable connection

## Error Handling

### NetworkError Types

```swift
enum NetworkError: Error {
    case noConnection
    case poorConnection
    case timeout
    case serverError
    case bandwidthExceeded
    case connectionLost
}
```

### Error Recovery

```swift
networkManager.handleError(.timeout) { error in
    // Implement retry logic
    return networkManager.retryOperation()
        .delay(.seconds(5), scheduler: MainScheduler.instance)
}
```

## Best Practices

1. **Monitor Network Changes**: Always monitor network state changes
2. **Adapt to Quality**: Adjust sync behavior based on connection quality
3. **Queue Operations**: Use queues for non-critical operations
4. **Optimize Bandwidth**: Compress data when bandwidth is limited
5. **Handle Errors Gracefully**: Implement proper error recovery mechanisms
6. **Test Connections**: Regularly test connection quality
7. **Background Sync**: Use background sync for better user experience

## Integration Example

```swift
import OfflineFirstFramework

class NetworkAwareApp {
    private let networkManager = NetworkStateManager()
    private let adaptiveSync = AdaptiveSyncManager()
    private let disposeBag = DisposeBag()
    
    func setupNetworkAdaptation() {
        // Monitor network changes
        networkManager.monitorNetworkChanges()
            .subscribe(onNext: { [weak self] event in
                self?.handleNetworkChange(event)
            })
            .disposed(by: disposeBag)
        
        // Configure adaptive sync
        let config = AdaptiveSyncConfiguration()
        config.enableBandwidthOptimization = true
        config.minimumBandwidth = 2.0
        
        // Perform adaptive sync
        adaptiveSync.syncWithAdaptation(config: config)
            .subscribe(onNext: { result in
                print("Adaptive sync completed successfully")
            })
            .disposed(by: disposeBag)
    }
    
    private func handleNetworkChange(_ event: NetworkChangeEvent) {
        switch event {
        case .connected(let type):
            print("Network connected via \(type)")
            // Trigger sync when network becomes available
            adaptiveSync.syncWithAdaptation(config: AdaptiveSyncConfiguration())
        case .disconnected:
            print("Network disconnected")
            // Switch to offline mode
        case .qualityChanged(let quality):
            print("Network quality changed to \(quality)")
            // Adjust sync behavior based on quality
        }
    }
}
```
