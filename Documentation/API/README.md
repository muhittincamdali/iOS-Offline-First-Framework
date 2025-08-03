# API Documentation

## OfflineFirstManager

The main orchestrator for the offline-first framework.

### Methods

#### `initialize(with config: OfflineFirstConfiguration)`
Initializes the framework with custom configuration.

#### `sync(force: Bool = false) -> Observable<SyncResult>`
Performs data synchronization.

#### `save<T: Codable>(_ data: T) -> Observable<SaveResult>`
Saves data with offline-first approach.

#### `load<T: Codable>(_ type: T.Type) -> Observable<[T]>`
Loads data with offline-first approach.

#### `delete<T: Codable>(_ data: T) -> Observable<DeleteResult>`
Deletes data with offline-first approach.

#### `resolveConflicts<T: Codable>(for data: T) -> Observable<ConflictResolutionResult>`
Resolves conflicts for specific data.

#### `getAnalytics() -> Observable<OfflineAnalytics>`
Gets analytics data.

#### `clearAllData() -> Observable<ClearResult>`
Clears all offline data.

## NetworkStateManager

Manages network connectivity and state monitoring.

### Properties

- `isOnline: Observable<Bool>` - Network connectivity status
- `connectionType: Observable<ConnectionType>` - Type of connection
- `connectionQuality: Observable<ConnectionQuality>` - Quality of connection

### Methods

#### `checkConnectivity() -> Observable<NetworkStatus>`
Checks current network connectivity.

#### `testConnection(url: URL) -> Observable<ConnectionTestResult>`
Tests connection to a specific URL.

## OfflineStorageManager

Manages offline data storage with encryption and compression.

### Properties

- `storageStatus: Observable<StorageStatus>` - Current storage status
- `storageUsage: Observable<StorageUsage>` - Storage usage information

### Methods

#### `save<T: Codable>(_ data: T) -> Observable<SaveResult>`
Saves data to local storage.

#### `load<T: Codable>(_ type: T.Type) -> Observable<[T]>`
Loads data from local storage.

#### `delete<T: Codable>(_ data: T) -> Observable<DeleteResult>`
Deletes data from local storage.

#### `clearAllData() -> Observable<ClearResult>`
Clears all stored data.

#### `getStorageInfo() -> Observable<StorageInfo>`
Gets storage information.

## DataSyncManager

Manages data synchronization between local storage and remote servers.

### Properties

- `syncStatus: Observable<SyncStatus>` - Current sync status
- `syncProgress: Observable<Double>` - Sync progress (0.0 to 1.0)

### Methods

#### `performSync(force: Bool = false) -> Observable<SyncResult>`
Performs data synchronization.

#### `pauseSync()`
Pauses synchronization.

#### `resumeSync()`
Resumes synchronization.

#### `cancelSync()`
Cancels synchronization.

## OfflineAnalyticsManager

Manages analytics for offline usage patterns and sync performance.

### Methods

#### `getAnalytics() -> Observable<OfflineAnalytics>`
Gets analytics data.

#### `recordOfflineSession(duration: TimeInterval)`
Records an offline session.

#### `recordSyncSuccess()`
Records a successful sync.

#### `recordSyncFailure(error: Error)`
Records a failed sync.

#### `recordStorageWarning()`
Records a storage warning.

#### `recordStorageFull()`
Records a storage full event.

#### `recordSyncTime(duration: TimeInterval)`
Records sync time.

#### `resetAnalytics()`
Resets analytics data.

## ConflictResolutionManager

Manages conflict detection and resolution strategies.

### Methods

#### `resolveConflicts<T: Codable>(for data: T) -> Observable<ConflictResolutionResult>`
Resolves conflicts for specific data.

#### `detectConflicts<T: Codable>(local: T, remote: T) -> Observable<[Conflict]>`
Detects conflicts between local and remote data.

#### `autoResolveConflicts(_ conflicts: [Conflict], strategy: ConflictResolutionStrategy) -> Observable<ConflictResolutionResult>`
Automatically resolves conflicts using specified strategy.

#### `manualResolveConflict(_ conflict: Conflict, resolution: ConflictResolution) -> Observable<ConflictResolutionResult>`
Manually resolves a specific conflict.
