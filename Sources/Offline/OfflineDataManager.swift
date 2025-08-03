import Foundation
import CoreData

/// Advanced offline data management system for iOS applications.
///
/// This module provides comprehensive offline data handling including
/// data synchronization, conflict resolution, and offline-first architecture.
@available(iOS 13.0, *)
public class OfflineDataManager {
    
    // MARK: - Properties
    
    /// Core Data stack
    private let coreDataStack: CoreDataStack
    
    /// Sync manager
    private let syncManager: SyncManager
    
    /// Conflict resolver
    private let conflictResolver: ConflictResolver
    
    /// Offline analytics
    private var analytics: OfflineAnalytics?
    
    /// Sync status
    @Published public private(set) var syncStatus: SyncStatus = .idle
    
    /// Last sync timestamp
    @Published public private(set) var lastSyncTimestamp: Date?
    
    /// Pending changes count
    @Published public private(set) var pendingChangesCount: Int = 0
    
    // MARK: - Initialization
    
    /// Creates a new offline data manager instance.
    ///
    /// - Parameters:
    ///   - coreDataStack: Core Data stack instance
    ///   - syncManager: Sync manager instance
    ///   - conflictResolver: Conflict resolver instance
    ///   - analytics: Optional offline analytics instance
    public init(
        coreDataStack: CoreDataStack,
        syncManager: SyncManager,
        conflictResolver: ConflictResolver,
        analytics: OfflineAnalytics? = nil
    ) {
        self.coreDataStack = coreDataStack
        self.syncManager = syncManager
        self.conflictResolver = conflictResolver
        self.analytics = analytics
        setupOfflineData()
    }
    
    // MARK: - Setup
    
    /// Sets up offline data management.
    private func setupOfflineData() {
        setupDataModels()
        setupSyncHandlers()
        setupConflictResolution()
    }
    
    /// Sets up data models for offline storage.
    private func setupDataModels() {
        // Initialize Core Data models
        coreDataStack.loadPersistentStores { error in
            if let error = error {
                self.analytics?.recordError(.dataModelSetupFailed, error: error)
            }
        }
    }
    
    /// Sets up sync handlers.
    private func setupSyncHandlers() {
        syncManager.delegate = self
        syncManager.setupSyncHandlers()
    }
    
    /// Sets up conflict resolution.
    private func setupConflictResolution() {
        conflictResolver.delegate = self
        conflictResolver.setupResolutionStrategies()
    }
    
    // MARK: - Data Operations
    
    /// Saves data to offline storage.
    ///
    /// - Parameters:
    ///   - data: Data to save
    ///   - entity: Entity type
    ///   - completion: Completion handler
    public func saveData<T: NSManagedObject>(
        _ data: [String: Any],
        entity: T.Type,
        completion: @escaping (Result<T, OfflineError>) -> Void
    ) {
        coreDataStack.performBackgroundTask { context in
            do {
                let entity = T(context: context)
                
                // Set entity properties
                for (key, value) in data {
                    entity.setValue(value, forKey: key)
                }
                
                // Mark as pending sync
                entity.setValue(true, forKey: "needsSync")
                entity.setValue(Date(), forKey: "lastModified")
                
                try context.save()
                
                self.pendingChangesCount += 1
                self.analytics?.recordDataSaved(entity: String(describing: T.self))
                
                DispatchQueue.main.async {
                    completion(.success(entity))
                }
            } catch {
                self.analytics?.recordError(.saveFailed, error: error)
                DispatchQueue.main.async {
                    completion(.failure(.saveFailed))
                }
            }
        }
    }
    
    /// Fetches data from offline storage.
    ///
    /// - Parameters:
    ///   - entity: Entity type
    ///   - predicate: Optional fetch predicate
    ///   - sortDescriptors: Optional sort descriptors
    ///   - completion: Completion handler
    public func fetchData<T: NSManagedObject>(
        entity: T.Type,
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        completion: @escaping (Result<[T], OfflineError>) -> Void
    ) {
        coreDataStack.performBackgroundTask { context in
            do {
                let request = NSFetchRequest<T>(entityName: String(describing: T.self))
                request.predicate = predicate
                request.sortDescriptors = sortDescriptors
                
                let results = try context.fetch(request)
                
                DispatchQueue.main.async {
                    completion(.success(results))
                }
            } catch {
                self.analytics?.recordError(.fetchFailed, error: error)
                DispatchQueue.main.async {
                    completion(.failure(.fetchFailed))
                }
            }
        }
    }
    
    /// Updates data in offline storage.
    ///
    /// - Parameters:
    ///   - object: Object to update
    ///   - data: Updated data
    ///   - completion: Completion handler
    public func updateData<T: NSManagedObject>(
        _ object: T,
        data: [String: Any],
        completion: @escaping (Result<T, OfflineError>) -> Void
    ) {
        coreDataStack.performBackgroundTask { context in
            do {
                // Update object properties
                for (key, value) in data {
                    object.setValue(value, forKey: key)
                }
                
                // Mark as pending sync
                object.setValue(true, forKey: "needsSync")
                object.setValue(Date(), forKey: "lastModified")
                
                try context.save()
                
                self.pendingChangesCount += 1
                self.analytics?.recordDataUpdated(entity: String(describing: T.self))
                
                DispatchQueue.main.async {
                    completion(.success(object))
                }
            } catch {
                self.analytics?.recordError(.updateFailed, error: error)
                DispatchQueue.main.async {
                    completion(.failure(.updateFailed))
                }
            }
        }
    }
    
    /// Deletes data from offline storage.
    ///
    /// - Parameters:
    ///   - object: Object to delete
    ///   - completion: Completion handler
    public func deleteData<T: NSManagedObject>(
        _ object: T,
        completion: @escaping (Result<Void, OfflineError>) -> Void
    ) {
        coreDataStack.performBackgroundTask { context in
            do {
                // Mark for deletion
                object.setValue(true, forKey: "markedForDeletion")
                object.setValue(Date(), forKey: "lastModified")
                
                try context.save()
                
                self.pendingChangesCount += 1
                self.analytics?.recordDataDeleted(entity: String(describing: T.self))
                
                DispatchQueue.main.async {
                    completion(.success(()))
                }
            } catch {
                self.analytics?.recordError(.deleteFailed, error: error)
                DispatchQueue.main.async {
                    completion(.failure(.deleteFailed))
                }
            }
        }
    }
    
    // MARK: - Sync Operations
    
    /// Starts data synchronization.
    ///
    /// - Parameter completion: Completion handler
    public func startSync(completion: @escaping (Result<Void, OfflineError>) -> Void) {
        guard syncStatus != .syncing else {
            completion(.failure(.syncAlreadyInProgress))
            return
        }
        
        syncStatus = .syncing
        analytics?.recordSyncStarted()
        
        syncManager.sync { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.syncStatus = .completed
                    self?.lastSyncTimestamp = Date()
                    self?.pendingChangesCount = 0
                    self?.analytics?.recordSyncCompleted()
                    completion(.success(()))
                case .failure(let error):
                    self?.syncStatus = .failed
                    self?.analytics?.recordSyncFailed(error: error)
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Performs background sync.
    public func performBackgroundSync() {
        guard syncStatus == .idle else { return }
        
        syncStatus = .syncing
        analytics?.recordBackgroundSyncStarted()
        
        syncManager.backgroundSync { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.syncStatus = .completed
                    self?.lastSyncTimestamp = Date()
                    self?.analytics?.recordBackgroundSyncCompleted()
                case .failure(let error):
                    self?.syncStatus = .failed
                    self?.analytics?.recordBackgroundSyncFailed(error: error)
                }
            }
        }
    }
    
    /// Resolves conflicts in offline data.
    ///
    /// - Parameter completion: Completion handler
    public func resolveConflicts(completion: @escaping (Result<Void, OfflineError>) -> Void) {
        conflictResolver.resolveConflicts { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.analytics?.recordConflictsResolved()
                    completion(.success(()))
                case .failure(let error):
                    self?.analytics?.recordConflictResolutionFailed(error: error)
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Offline Status
    
    /// Checks if device is offline.
    ///
    /// - Returns: True if offline
    public func isOffline() -> Bool {
        return !NetworkMonitor.shared.isConnected
    }
    
    /// Gets offline data statistics.
    ///
    /// - Returns: Offline data statistics
    public func getOfflineStatistics() -> OfflineStatistics {
        return OfflineStatistics(
            pendingChangesCount: pendingChangesCount,
            lastSyncTimestamp: lastSyncTimestamp,
            syncStatus: syncStatus,
            isOffline: isOffline()
        )
    }
    
    /// Gets sync progress.
    ///
    /// - Returns: Sync progress
    public func getSyncProgress() -> SyncProgress {
        return syncManager.getProgress()
    }
    
    // MARK: - Data Migration
    
    /// Migrates offline data to new schema.
    ///
    /// - Parameters:
    ///   - fromVersion: Source version
    ///   - toVersion: Target version
    ///   - completion: Completion handler
    public func migrateData(
        fromVersion: String,
        toVersion: String,
        completion: @escaping (Result<Void, OfflineError>) -> Void
    ) {
        coreDataStack.migrateData(fromVersion: fromVersion, toVersion: toVersion) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.analytics?.recordDataMigrationCompleted(fromVersion: fromVersion, toVersion: toVersion)
                    completion(.success(()))
                case .failure(let error):
                    self?.analytics?.recordDataMigrationFailed(error: error)
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - Data Backup
    
    /// Creates backup of offline data.
    ///
    /// - Parameter completion: Completion handler
    public func createBackup(completion: @escaping (Result<URL, OfflineError>) -> Void) {
        coreDataStack.createBackup { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let url):
                    self?.analytics?.recordBackupCreated(url: url)
                    completion(.success(url))
                case .failure(let error):
                    self?.analytics?.recordBackupFailed(error: error)
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Restores backup of offline data.
    ///
    /// - Parameters:
    ///   - backupURL: Backup URL
    ///   - completion: Completion handler
    public func restoreBackup(
        from backupURL: URL,
        completion: @escaping (Result<Void, OfflineError>) -> Void
    ) {
        coreDataStack.restoreBackup(from: backupURL) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.analytics?.recordBackupRestored(url: backupURL)
                    completion(.success(()))
                case .failure(let error):
                    self?.analytics?.recordBackupRestoreFailed(error: error)
                    completion(.failure(error))
                }
            }
        }
    }
}

// MARK: - SyncManagerDelegate

@available(iOS 13.0, *)
extension OfflineDataManager: SyncManagerDelegate {
    
    public func syncManager(_ manager: SyncManager, didUpdateProgress progress: Double) {
        analytics?.recordSyncProgress(progress: progress)
    }
    
    public func syncManager(_ manager: SyncManager, didEncounterConflict conflict: DataConflict) {
        conflictResolver.addConflict(conflict)
        analytics?.recordConflictDetected(conflict: conflict)
    }
}

// MARK: - ConflictResolverDelegate

@available(iOS 13.0, *)
extension OfflineDataManager: ConflictResolverDelegate {
    
    public func conflictResolver(_ resolver: ConflictResolver, didResolveConflict conflict: DataConflict) {
        analytics?.recordConflictResolved(conflict: conflict)
    }
    
    public func conflictResolver(_ resolver: ConflictResolver, didFailToResolveConflict conflict: DataConflict, error: Error) {
        analytics?.recordConflictResolutionFailed(conflict: conflict, error: error)
    }
}

// MARK: - Supporting Types

/// Sync status.
@available(iOS 13.0, *)
public enum SyncStatus {
    case idle
    case syncing
    case completed
    case failed
}

/// Offline errors.
@available(iOS 13.0, *)
public enum OfflineError: Error {
    case saveFailed
    case fetchFailed
    case updateFailed
    case deleteFailed
    case syncFailed
    case syncAlreadyInProgress
    case conflictResolutionFailed
    case dataModelSetupFailed
    case migrationFailed
    case backupFailed
    case restoreFailed
}

/// Offline statistics.
@available(iOS 13.0, *)
public struct OfflineStatistics {
    public let pendingChangesCount: Int
    public let lastSyncTimestamp: Date?
    public let syncStatus: SyncStatus
    public let isOffline: Bool
}

/// Sync progress.
@available(iOS 13.0, *)
public struct SyncProgress {
    public let progress: Double
    public let currentItem: String?
    public let totalItems: Int
    public let completedItems: Int
}

// MARK: - Offline Analytics

/// Offline analytics protocol.
@available(iOS 13.0, *)
public protocol OfflineAnalytics {
    func recordDataSaved(entity: String)
    func recordDataUpdated(entity: String)
    func recordDataDeleted(entity: String)
    func recordSyncStarted()
    func recordSyncCompleted()
    func recordSyncFailed(error: Error)
    func recordBackgroundSyncStarted()
    func recordBackgroundSyncCompleted()
    func recordBackgroundSyncFailed(error: Error)
    func recordSyncProgress(progress: Double)
    func recordConflictDetected(conflict: DataConflict)
    func recordConflictResolved(conflict: DataConflict)
    func recordConflictsResolved()
    func recordConflictResolutionFailed(error: Error)
    func recordDataMigrationCompleted(fromVersion: String, toVersion: String)
    func recordDataMigrationFailed(error: Error)
    func recordBackupCreated(url: URL)
    func recordBackupFailed(error: Error)
    func recordBackupRestored(url: URL)
    func recordBackupRestoreFailed(error: Error)
    func recordError(_ error: OfflineError, error: Error)
} 