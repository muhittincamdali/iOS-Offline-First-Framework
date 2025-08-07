# 📊 Monitoring API

## Overview

The Monitoring API provides comprehensive monitoring capabilities for the iOS Offline-First Framework, including performance tracking, error monitoring, and real-time analytics.

## PerformanceMonitor

### Properties

- `performanceMetrics: Observable<PerformanceMetrics>` - Real-time performance metrics
- `memoryUsage: Observable<MemoryUsage>` - Memory usage statistics
- `cpuUsage: Observable<CPUUsage>` - CPU usage statistics
- `batteryUsage: Observable<BatteryUsage>` - Battery usage statistics

### Methods

#### `startMonitoring() -> Observable<MonitoringStatus>`
Starts performance monitoring.

```swift
let performanceMonitor = PerformanceMonitor()

performanceMonitor.startMonitoring()
    .subscribe(onNext: { status in
        switch status {
        case .started:
            print("✅ Performance monitoring started")
        case .failed(let error):
            print("❌ Performance monitoring failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

#### `getPerformanceMetrics() -> Observable<PerformanceMetrics>`
Gets current performance metrics.

```swift
performanceMonitor.getPerformanceMetrics()
    .subscribe(onNext: { metrics in
        print("📊 Performance Metrics:")
        print("Memory usage: \(metrics.memoryUsage)MB")
        print("CPU usage: \(metrics.cpuUsage)%")
        print("Battery usage: \(metrics.batteryUsage)%")
        print("Network latency: \(metrics.networkLatency)ms")
        print("Storage usage: \(metrics.storageUsage)MB")
    })
    .disposed(by: disposeBag)
```

## ErrorMonitor

### Properties

- `errorLog: Observable<[ErrorLog]>` - Error log entries
- `errorCount: Observable<Int>` - Total error count
- `errorRate: Observable<Double>` - Error rate percentage
- `criticalErrors: Observable<[CriticalError]>` - Critical errors

### Methods

#### `logError(_ error: Error, context: ErrorContext) -> Observable<LogResult>`
Logs an error with context.

```swift
let errorMonitor = ErrorMonitor()

let error = NetworkError.timeout
let context = ErrorContext(
    operation: "sync",
    timestamp: Date(),
    userInfo: ["userId": "123"]
)

errorMonitor.logError(error, context: context)
    .subscribe(onNext: { result in
        switch result {
        case .success:
            print("✅ Error logged successfully")
        case .failure(let error):
            print("❌ Error logging failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

#### `getErrorReport() -> Observable<ErrorReport>`
Gets comprehensive error report.

```swift
errorMonitor.getErrorReport()
    .subscribe(onNext: { report in
        print("📊 Error Report:")
        print("Total errors: \(report.totalErrors)")
        print("Critical errors: \(report.criticalErrors)")
        print("Error rate: \(report.errorRate)%")
        print("Most common error: \(report.mostCommonError)")
        print("Average resolution time: \(report.averageResolutionTime)s")
    })
    .disposed(by: disposeBag)
```

## NetworkMonitor

### Properties

- `networkStatus: Observable<NetworkStatus>` - Network connectivity status
- `connectionQuality: Observable<ConnectionQuality>` - Connection quality
- `bandwidthUsage: Observable<BandwidthUsage>` - Bandwidth usage
- `latencyMetrics: Observable<LatencyMetrics>` - Latency metrics

### Methods

#### `monitorNetworkPerformance() -> Observable<NetworkPerformance>`
Monitors network performance metrics.

```swift
let networkMonitor = NetworkMonitor()

networkMonitor.monitorNetworkPerformance()
    .subscribe(onNext: { performance in
        print("🌐 Network Performance:")
        print("Download speed: \(performance.downloadSpeed)Mbps")
        print("Upload speed: \(performance.uploadSpeed)Mbps")
        print("Latency: \(performance.latency)ms")
        print("Packet loss: \(performance.packetLoss)%")
        print("Connection quality: \(performance.connectionQuality)")
    })
    .disposed(by: disposeBag)
```

#### `testConnection(url: URL) -> Observable<ConnectionTestResult>`
Tests connection to a specific URL.

```swift
let testURL = URL(string: "https://api.example.com")!
networkMonitor.testConnection(url: testURL)
    .subscribe(onNext: { result in
        switch result {
        case .success(let testResult):
            print("✅ Connection test successful")
            print("Response time: \(testResult.responseTime)ms")
            print("Status code: \(testResult.statusCode)")
        case .failure(let error):
            print("❌ Connection test failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## StorageMonitor

### Properties

- `storageUsage: Observable<StorageUsage>` - Storage usage statistics
- `storageHealth: Observable<StorageHealth>` - Storage health status
- `fileOperations: Observable<[FileOperation]>` - File operation logs
- `storageErrors: Observable<[StorageError]>` - Storage errors

### Methods

#### `monitorStorageUsage() -> Observable<StorageUsage>`
Monitors storage usage in real-time.

```swift
let storageMonitor = StorageMonitor()

storageMonitor.monitorStorageUsage()
    .subscribe(onNext: { usage in
        print("💾 Storage Usage:")
        print("Used space: \(usage.usedSpace)MB")
        print("Available space: \(usage.availableSpace)MB")
        print("Total space: \(usage.totalSpace)MB")
        print("Usage percentage: \(usage.usagePercentage)%")
        print("Health status: \(usage.healthStatus)")
    })
    .disposed(by: disposeBag)
```

#### `getStorageReport() -> Observable<StorageReport>`
Gets comprehensive storage report.

```swift
storageMonitor.getStorageReport()
    .subscribe(onNext: { report in
        print("📊 Storage Report:")
        print("Total files: \(report.totalFiles)")
        print("Largest files: \(report.largestFiles)")
        print("Oldest files: \(report.oldestFiles)")
        print("Storage efficiency: \(report.storageEfficiency)%")
        print("Compression ratio: \(report.compressionRatio)")
    })
    .disposed(by: disposeBag)
```

## SyncMonitor

### Properties

- `syncStatus: Observable<SyncStatus>` - Current sync status
- `syncProgress: Observable<SyncProgress>` - Sync progress
- `syncHistory: Observable<[SyncRecord]>` - Sync history
- `syncErrors: Observable<[SyncError]>` - Sync errors

### Methods

#### `monitorSyncProgress() -> Observable<SyncProgress>`
Monitors sync progress in real-time.

```swift
let syncMonitor = SyncMonitor()

syncMonitor.monitorSyncProgress()
    .subscribe(onNext: { progress in
        print("🔄 Sync Progress:")
        print("Percentage: \(progress.percentage)%")
        print("Items processed: \(progress.itemsProcessed)")
        print("Total items: \(progress.totalItems)")
        print("Current operation: \(progress.currentOperation)")
        print("Estimated time remaining: \(progress.estimatedTimeRemaining)s")
    })
    .disposed(by: disposeBag)
```

#### `getSyncReport() -> Observable<SyncReport>`
Gets comprehensive sync report.

```swift
syncMonitor.getSyncReport()
    .subscribe(onNext: { report in
        print("📊 Sync Report:")
        print("Total syncs: \(report.totalSyncs)")
        print("Successful syncs: \(report.successfulSyncs)")
        print("Failed syncs: \(report.failedSyncs)")
        print("Average sync time: \(report.averageSyncTime)s")
        print("Last sync: \(report.lastSync)")
        print("Next sync: \(report.nextSync)")
    })
    .disposed(by: disposeBag)
```

## AnalyticsMonitor

### Properties

- `usageMetrics: Observable<UsageMetrics>` - Usage metrics
- `userBehavior: Observable<UserBehavior>` - User behavior data
- `featureUsage: Observable<FeatureUsage>` - Feature usage statistics
- `performanceMetrics: Observable<PerformanceMetrics>` - Performance metrics

### Methods

#### `trackEvent(_ event: AnalyticsEvent) -> Observable<TrackingResult>`
Tracks an analytics event.

```swift
let analyticsMonitor = AnalyticsMonitor()

let event = AnalyticsEvent(
    name: "user_login",
    properties: ["method": "email", "success": true],
    timestamp: Date()
)

analyticsMonitor.trackEvent(event)
    .subscribe(onNext: { result in
        switch result {
        case .success:
            print("✅ Event tracked successfully")
        case .failure(let error):
            print("❌ Event tracking failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

#### `getAnalyticsReport() -> Observable<AnalyticsReport>`
Gets comprehensive analytics report.

```swift
analyticsMonitor.getAnalyticsReport()
    .subscribe(onNext: { report in
        print("📊 Analytics Report:")
        print("Total events: \(report.totalEvents)")
        print("Active users: \(report.activeUsers)")
        print("Most used feature: \(report.mostUsedFeature)")
        print("Average session duration: \(report.averageSessionDuration)s")
        print("User retention rate: \(report.userRetentionRate)%")
    })
    .disposed(by: disposeBag)
```

## HealthMonitor

### Properties

- `systemHealth: Observable<SystemHealth>` - Overall system health
- `componentHealth: Observable<[ComponentHealth]>` - Individual component health
- `healthAlerts: Observable<[HealthAlert]>` - Health alerts
- `recommendations: Observable<[HealthRecommendation]>` - Health recommendations

### Methods

#### `checkSystemHealth() -> Observable<SystemHealth>`
Checks overall system health.

```swift
let healthMonitor = HealthMonitor()

healthMonitor.checkSystemHealth()
    .subscribe(onNext: { health in
        print("🏥 System Health:")
        print("Overall status: \(health.overallStatus)")
        print("Score: \(health.score)/100")
        print("Issues found: \(health.issues.count)")
        print("Recommendations: \(health.recommendations.count)")
        
        for issue in health.issues {
            print("- Issue: \(issue.description) (Severity: \(issue.severity))")
        }
    })
    .disposed(by: disposeBag)
```

#### `getHealthRecommendations() -> Observable<[HealthRecommendation]>`
Gets health improvement recommendations.

```swift
healthMonitor.getHealthRecommendations()
    .subscribe(onNext: { recommendations in
        print("💡 Health Recommendations:")
        for recommendation in recommendations {
            print("- \(recommendation.title)")
            print("  Description: \(recommendation.description)")
            print("  Priority: \(recommendation.priority)")
            print("  Impact: \(recommendation.impact)")
        }
    })
    .disposed(by: disposeBag)
```

## AlertManager

### Properties

- `activeAlerts: Observable<[Alert]>` - Active alerts
- `alertHistory: Observable<[AlertRecord]>` - Alert history
- `alertSettings: Observable<AlertSettings>` - Alert settings

### Methods

#### `createAlert(_ alert: Alert) -> Observable<AlertResult>`
Creates a new alert.

```swift
let alertManager = AlertManager()

let alert = Alert(
    type: .warning,
    title: "High Memory Usage",
    message: "Memory usage is above 80%",
    severity: .medium,
    timestamp: Date()
)

alertManager.createAlert(alert)
    .subscribe(onNext: { result in
        switch result {
        case .success:
            print("✅ Alert created successfully")
        case .failure(let error):
            print("❌ Alert creation failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

#### `getActiveAlerts() -> Observable<[Alert]>`
Gets all active alerts.

```swift
alertManager.getActiveAlerts()
    .subscribe(onNext: { alerts in
        print("🚨 Active Alerts (\(alerts.count)):")
        for alert in alerts {
            print("- \(alert.title) (\(alert.type))")
            print("  Severity: \(alert.severity)")
            print("  Time: \(alert.timestamp)")
        }
    })
    .disposed(by: disposeBag)
```

## Best Practices

1. **Monitor Continuously**: Set up continuous monitoring for all components
2. **Set Thresholds**: Define appropriate thresholds for alerts
3. **Track Performance**: Monitor performance metrics regularly
4. **Log Errors**: Log all errors with proper context
5. **Analyze Patterns**: Analyze monitoring data for patterns
6. **Optimize Based on Data**: Use monitoring data for optimization
7. **Set Up Alerts**: Configure alerts for critical issues
8. **Regular Reports**: Generate regular monitoring reports

## Integration Example

```swift
import OfflineFirstFramework

class MonitoringApp {
    private let performanceMonitor = PerformanceMonitor()
    private let errorMonitor = ErrorMonitor()
    private let networkMonitor = NetworkMonitor()
    private let storageMonitor = StorageMonitor()
    private let syncMonitor = SyncMonitor()
    private let healthMonitor = HealthMonitor()
    private let alertManager = AlertManager()
    private let disposeBag = DisposeBag()
    
    func setupMonitoring() {
        // Start all monitors
        startPerformanceMonitoring()
        startErrorMonitoring()
        startNetworkMonitoring()
        startStorageMonitoring()
        startSyncMonitoring()
        startHealthMonitoring()
        setupAlerts()
    }
    
    private func startPerformanceMonitoring() {
        performanceMonitor.startMonitoring()
            .subscribe(onNext: { status in
                print("Performance monitoring: \(status)")
            })
            .disposed(by: disposeBag)
        
        performanceMonitor.getPerformanceMetrics()
            .subscribe(onNext: { [weak self] metrics in
                self?.handlePerformanceMetrics(metrics)
            })
            .disposed(by: disposeBag)
    }
    
    private func startErrorMonitoring() {
        errorMonitor.getErrorReport()
            .subscribe(onNext: { [weak self] report in
                self?.handleErrorReport(report)
            })
            .disposed(by: disposeBag)
    }
    
    private func startNetworkMonitoring() {
        networkMonitor.monitorNetworkPerformance()
            .subscribe(onNext: { [weak self] performance in
                self?.handleNetworkPerformance(performance)
            })
            .disposed(by: disposeBag)
    }
    
    private func startStorageMonitoring() {
        storageMonitor.monitorStorageUsage()
            .subscribe(onNext: { [weak self] usage in
                self?.handleStorageUsage(usage)
            })
            .disposed(by: disposeBag)
    }
    
    private func startSyncMonitoring() {
        syncMonitor.monitorSyncProgress()
            .subscribe(onNext: { [weak self] progress in
                self?.handleSyncProgress(progress)
            })
            .disposed(by: disposeBag)
    }
    
    private func startHealthMonitoring() {
        healthMonitor.checkSystemHealth()
            .subscribe(onNext: { [weak self] health in
                self?.handleSystemHealth(health)
            })
            .disposed(by: disposeBag)
    }
    
    private func setupAlerts() {
        // Monitor for critical issues and create alerts
        Observable.combineLatest(
            performanceMonitor.getPerformanceMetrics(),
            storageMonitor.monitorStorageUsage(),
            networkMonitor.monitorNetworkPerformance()
        )
        .subscribe(onNext: { [weak self] metrics, usage, performance in
            self?.checkForAlerts(metrics: metrics, usage: usage, performance: performance)
        })
        .disposed(by: disposeBag)
    }
    
    private func handlePerformanceMetrics(_ metrics: PerformanceMetrics) {
        if metrics.memoryUsage > 80 {
            // Create memory alert
            let alert = Alert(
                type: .warning,
                title: "High Memory Usage",
                message: "Memory usage is \(metrics.memoryUsage)%",
                severity: .medium,
                timestamp: Date()
            )
            alertManager.createAlert(alert)
                .subscribe(onNext: { _ in })
                .disposed(by: disposeBag)
        }
    }
    
    private func handleErrorReport(_ report: ErrorReport) {
        if report.errorRate > 5 {
            // Create error rate alert
            let alert = Alert(
                type: .error,
                title: "High Error Rate",
                message: "Error rate is \(report.errorRate)%",
                severity: .high,
                timestamp: Date()
            )
            alertManager.createAlert(alert)
                .subscribe(onNext: { _ in })
                .disposed(by: disposeBag)
        }
    }
    
    private func handleNetworkPerformance(_ performance: NetworkPerformance) {
        if performance.latency > 1000 {
            // Create latency alert
            let alert = Alert(
                type: .warning,
                title: "High Network Latency",
                message: "Network latency is \(performance.latency)ms",
                severity: .medium,
                timestamp: Date()
            )
            alertManager.createAlert(alert)
                .subscribe(onNext: { _ in })
                .disposed(by: disposeBag)
        }
    }
    
    private func handleStorageUsage(_ usage: StorageUsage) {
        if usage.usagePercentage > 90 {
            // Create storage alert
            let alert = Alert(
                type: .critical,
                title: "Storage Almost Full",
                message: "Storage usage is \(usage.usagePercentage)%",
                severity: .high,
                timestamp: Date()
            )
            alertManager.createAlert(alert)
                .subscribe(onNext: { _ in })
                .disposed(by: disposeBag)
        }
    }
    
    private func handleSyncProgress(_ progress: SyncProgress) {
        // Handle sync progress updates
        print("Sync progress: \(progress.percentage)%")
    }
    
    private func handleSystemHealth(_ health: SystemHealth) {
        if health.score < 70 {
            // Create health alert
            let alert = Alert(
                type: .warning,
                title: "System Health Degraded",
                message: "System health score is \(health.score)/100",
                severity: .medium,
                timestamp: Date()
            )
            alertManager.createAlert(alert)
                .subscribe(onNext: { _ in })
                .disposed(by: disposeBag)
        }
    }
    
    private func checkForAlerts(metrics: PerformanceMetrics, usage: StorageUsage, performance: NetworkPerformance) {
        // Comprehensive alert checking
        if metrics.memoryUsage > 85 || usage.usagePercentage > 95 || performance.latency > 2000 {
            let alert = Alert(
                type: .critical,
                title: "Critical System Issues",
                message: "Multiple critical issues detected",
                severity: .critical,
                timestamp: Date()
            )
            alertManager.createAlert(alert)
                .subscribe(onNext: { _ in })
                .disposed(by: disposeBag)
        }
    }
}
```
