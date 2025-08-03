import Foundation
import RxSwift
import CocoaLumberjack

/// Main orchestrator for offline-first architecture
/// Provides comprehensive offline data management, synchronization, and conflict resolution
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public final class OfflineFirstManager: ObservableObject {
    
    // MARK: - Properties
    
    /// Shared singleton instance
    public static let shared = OfflineFirstManager()
    
    /// Network state manager
    public let networkManager: NetworkStateManager
    
    /// Data storage manager
    public let storageManager: OfflineStorageManager
    
    /// Synchronization manager
    public let syncManager: DataSyncManager
    
    /// Analytics manager
    public let analyticsManager: OfflineAnalyticsManager
    
    /// Conflict resolution manager
    public let conflictManager: ConflictResolutionManager
    
    /// Configuration settings
    public let configuration: OfflineFirstConfiguration
    
    // MARK: - Observables
    
    /// Network connectivity status
    public var isOnline: Observable<Bool> {
        networkManager.isOnline
    }
    
    /// Sync status
    public var syncStatus: Observable<SyncStatus> {
        syncManager.syncStatus
    }
    
    /// Storage status
    public var storageStatus: Observable<StorageStatus> {
        storageManager.storageStatus
    }
    
    // MARK: - Private Properties
    
    private let disposeBag = DisposeBag()
    private let queue = DispatchQueue(label: "com.offlinefirst.manager", qos: .userInitiated)
    
    // MARK: - Initialization
    
    private init() {
        self.configuration = OfflineFirstConfiguration()
        self.networkManager = NetworkStateManager()
        self.storageManager = OfflineStorageManager()
        self.syncManager = DataSyncManager()
        self.analyticsManager = OfflineAnalyticsManager()
        self.conflictManager = ConflictResolutionManager()
        
        setupBindings()
        setupLogging()
    }
    
    // MARK: - Public Methods
    
    /// Initialize the offline-first framework with custom configuration
    /// - Parameter config: Custom configuration settings
    public func initialize(with config: OfflineFirstConfiguration) {
        configuration.update(with: config)
        
        DDLogInfo("OfflineFirstFramework initialized with configuration: \(config)")
        
        // Initialize all managers
        networkManager.initialize()
        storageManager.initialize()
        syncManager.initialize()
        analyticsManager.initialize()
        conflictManager.initialize()
        
        // Start monitoring
        startMonitoring()
    }
    
    /// Perform data synchronization
    /// - Parameter force: Force sync even if network is poor
    /// - Returns: Observable of sync result
    public func sync(force: Bool = false) -> Observable<SyncResult> {
        return syncManager.performSync(force: force)
    }
    
    /// Save data with offline-first approach
    /// - Parameter data: Data to save
    /// - Returns: Observable of save result
    public func save<T: Codable>(_ data: T) -> Observable<SaveResult> {
        return storageManager.save(data)
            .flatMap { [weak self] result in
                guard let self = self else { return .just(result) }
                
                // If online, sync immediately
                if self.networkManager.currentStatus == .online {
                    return self.syncManager.performSync(force: false)
                        .map { _ in result }
                        .catch { _ in .just(result) }
                }
                
                return .just(result)
            }
    }
    
    /// Load data with offline-first approach
    /// - Parameter type: Type of data to load
    /// - Returns: Observable of loaded data
    public func load<T: Codable>(_ type: T.Type) -> Observable<[T]> {
        return storageManager.load(type)
    }
    
    /// Delete data with offline-first approach
    /// - Parameter data: Data to delete
    /// - Returns: Observable of delete result
    public func delete<T: Codable>(_ data: T) -> Observable<DeleteResult> {
        return storageManager.delete(data)
    }
    
    /// Resolve conflicts for specific data
    /// - Parameter data: Data with conflicts
    /// - Returns: Observable of resolution result
    public func resolveConflicts<T: Codable>(for data: T) -> Observable<ConflictResolutionResult> {
        return conflictManager.resolveConflicts(for: data)
    }
    
    /// Get analytics data
    /// - Returns: Observable of analytics data
    public func getAnalytics() -> Observable<OfflineAnalytics> {
        return analyticsManager.getAnalytics()
    }
    
    /// Clear all offline data
    /// - Returns: Observable of clear result
    public func clearAllData() -> Observable<ClearResult> {
        return storageManager.clearAllData()
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Network state changes
        networkManager.isOnline
            .distinctUntilChanged()
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] isOnline in
                self?.handleNetworkStateChange(isOnline: isOnline)
            })
            .disposed(by: disposeBag)
        
        // Sync status changes
        syncManager.syncStatus
            .distinctUntilChanged()
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] status in
                self?.handleSyncStatusChange(status: status)
            })
            .disposed(by: disposeBag)
        
        // Storage status changes
        storageManager.storageStatus
            .distinctUntilChanged()
            .observe(on: MainScheduler.instance)
            .subscribe(onNext: { [weak self] status in
                self?.handleStorageStatusChange(status: status)
            })
            .disposed(by: disposeBag)
    }
    
    private func setupLogging() {
        DDLogInfo("OfflineFirstFramework setup completed")
        DDLogInfo("Configuration: \(configuration)")
    }
    
    private func startMonitoring() {
        networkManager.startMonitoring()
        storageManager.startMonitoring()
        syncManager.startMonitoring()
        analyticsManager.startMonitoring()
        
        DDLogInfo("All monitoring services started")
    }
    
    private func handleNetworkStateChange(isOnline: Bool) {
        DDLogInfo("Network state changed: \(isOnline ? "Online" : "Offline")")
        
        if isOnline {
            // Trigger sync when coming back online
            syncManager.performSync(force: false)
                .subscribe()
                .disposed(by: disposeBag)
        }
    }
    
    private func handleSyncStatusChange(status: SyncStatus) {
        DDLogInfo("Sync status changed: \(status)")
        
        switch status {
        case .completed:
            analyticsManager.recordSyncSuccess()
        case .failed(let error):
            analyticsManager.recordSyncFailure(error: error)
        default:
            break
        }
    }
    
    private func handleStorageStatusChange(status: StorageStatus) {
        DDLogInfo("Storage status changed: \(status)")
        
        switch status {
        case .lowSpace:
            analyticsManager.recordStorageWarning()
        case .full:
            analyticsManager.recordStorageFull()
        default:
            break
        }
    }
}

// MARK: - Supporting Types

/// Configuration for offline-first framework
public struct OfflineFirstConfiguration {
    public var maxStorageSize: Int64 = 100 * 1024 * 1024 // 100MB
    public var syncInterval: TimeInterval = 300 // 5 minutes
    public var retryAttempts: Int = 3
    public var enableAnalytics: Bool = true
    public var enableConflictResolution: Bool = true
    public var enableBackgroundSync: Bool = true
    
    public init() {}
    
    public mutating func update(with config: OfflineFirstConfiguration) {
        self.maxStorageSize = config.maxStorageSize
        self.syncInterval = config.syncInterval
        self.retryAttempts = config.retryAttempts
        self.enableAnalytics = config.enableAnalytics
        self.enableConflictResolution = config.enableConflictResolution
        self.enableBackgroundSync = config.enableBackgroundSync
    }
}

/// Result of save operation
public enum SaveResult {
    case success
    case failure(Error)
    case conflict(Error)
}

/// Result of delete operation
public enum DeleteResult {
    case success
    case failure(Error)
    case notFound
}

/// Result of clear operation
public enum ClearResult {
    case success
    case failure(Error)
}

/// Result of conflict resolution
public enum ConflictResolutionResult {
    case resolved
    case manualResolutionRequired
    case failure(Error)
}
