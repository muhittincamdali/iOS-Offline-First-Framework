import Foundation
@preconcurrency import Combine

/// Main orchestrator for offline-first architecture
/// Provides comprehensive offline data management, synchronization, and conflict resolution
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
@MainActor
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
    public var configuration: OfflineFirstConfiguration
    
    // MARK: - Publishers
    
    /// Network connectivity status
    public var isOnlinePublisher: AnyPublisher<Bool, Never> {
        networkManager.isOnline.eraseToAnyPublisher()
    }
    
    /// Sync status
    public var syncStatusPublisher: AnyPublisher<SyncStatus, Never> {
        syncManager.syncStatus.eraseToAnyPublisher()
    }
    
    /// Storage status
    public var storageStatusPublisher: AnyPublisher<StorageStatus, Never> {
        storageManager.storageStatus.eraseToAnyPublisher()
    }
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        self.configuration = OfflineFirstConfiguration()
        self.networkManager = NetworkStateManager()
        self.storageManager = OfflineStorageManager()
        self.syncManager = DataSyncManager()
        self.analyticsManager = OfflineAnalyticsManager()
        self.conflictManager = ConflictResolutionManager()
        
        setupBindings()
    }
    
    // MARK: - Public Methods
    
    /// Initialize the offline-first framework with custom configuration
    /// - Parameter config: Custom configuration settings
    public func initialize(with config: OfflineFirstConfiguration) {
        self.configuration = config
        
        Logger.info("OfflineFirstFramework initialized")
        
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
    public func sync(force: Bool = false) async throws -> SyncResult {
        return try await syncManager.performSync(force: force)
    }
    
    /// Save data with offline-first approach
    /// - Parameter data: Data to save
    public func save<T: Codable>(_ data: T) async throws -> SaveResult {
        let result = try await storageManager.save(data)
        
        // If online, trigger sync in background
        if networkManager.isOnline.value {
            Task {
                try? await syncManager.performSync(force: false)
            }
        }
        
        return result
    }
    
    /// Load data with offline-first approach
    /// - Parameter type: Type of data to load
    public func load<T: Codable>(_ type: T.Type) async throws -> [T] {
        return try await storageManager.load(type)
    }
    
    /// Delete data with offline-first approach
    /// - Parameter data: Data to delete
    public func delete<T: Codable>(_ data: T) async throws -> DeleteResult {
        return try await storageManager.delete(data)
    }
    
    /// Resolve conflicts for specific data
    /// - Parameter data: Data with conflicts
    public func resolveConflicts<T: Codable>(for data: T) async throws -> ConflictResolutionResult {
        let encodedData = try JSONEncoder().encode(data)
        return try await conflictManager.resolveConflicts(for: encodedData)
    }
    
    /// Get analytics data
    public func getAnalytics() async throws -> OfflineAnalytics {
        return try await analyticsManager.getAnalytics()
    }
    
    /// Clear all offline data
    public func clearAllData() async throws -> ClearResult {
        return try await storageManager.clearAllData()
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Network state changes
        networkManager.isOnline
            .receive(on: RunLoop.main)
            .sink { [weak self] isOnline in
                self?.handleNetworkStateChange(isOnline: isOnline)
            }
            .store(in: &cancellables)
        
        // Sync status changes
        syncManager.syncStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.handleSyncStatusChange(status: status)
            }
            .store(in: &cancellables)
        
        // Storage status changes
        storageManager.storageStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.handleStorageStatusChange(status: status)
            }
            .store(in: &cancellables)
    }
    
    private func startMonitoring() {
        networkManager.startMonitoring()
        storageManager.startMonitoring()
        syncManager.startMonitoring()
        analyticsManager.startMonitoring()
        
        Logger.info("All monitoring services started")
    }
    
    private func handleNetworkStateChange(isOnline: Bool) {
        Logger.info("Network state changed: \(isOnline ? "Online" : "Offline")")
        
        if isOnline {
            Task {
                try? await syncManager.performSync(force: false)
            }
        }
    }
    
    private func handleSyncStatusChange(status: SyncStatus) {
        Logger.info("Sync status changed: \(status)")
        
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
        Logger.info("Storage status changed: \(status)")
        
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
public struct OfflineFirstConfiguration: Sendable {
    public var maxStorageSize: Int64 = 100 * 1024 * 1024 // 100MB
    public var syncInterval: TimeInterval = 300 // 5 minutes
    public var retryAttempts: Int = 3
    public var enableAnalytics: Bool = true
    public var enableConflictResolution: Bool = true
    public var enableBackgroundSync: Bool = true
    
    public init() {}
}

/// Result of save operation
public enum SaveResult: Sendable {
    case success
    case failure(Error)
    case conflict(Error)
}

/// Result of delete operation
public enum DeleteResult: Sendable {
    case success
    case failure(Error)
    case notFound
}

/// Result of clear operation
public enum ClearResult: Sendable {
    case success
    case failure(Error)
}

/// Result of conflict resolution
public enum ConflictResolutionResult: Sendable {
    case resolved
    case manualResolutionRequired
    case failure(Error)
}
