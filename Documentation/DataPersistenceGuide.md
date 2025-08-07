# 📦 Data Persistence Guide

## Overview

This guide covers data persistence implementation with the iOS Offline-First Framework, including storage configuration, encryption, compression, and data management strategies.

## Storage Configuration

### Basic Storage Setup

```swift
import OfflineFirstFramework

// Configure basic storage
let storageConfig = StorageConfiguration()
storageConfig.maxStorageSize = 100 * 1024 * 1024 // 100MB
storageConfig.enableEncryption = true
storageConfig.enableCompression = true
storageConfig.enableStorageMonitoring = true

// Apply configuration
OfflineFirstManager.shared.configureStorage(storageConfig)
```

### Advanced Storage Configuration

```swift
// Advanced storage configuration
let advancedConfig = AdvancedStorageConfiguration()
advancedConfig.chunkSize = 1024 * 1024 // 1MB chunks
advancedConfig.enableDeduplication = true
advancedConfig.enableIndexing = true
advancedConfig.maxFileSize = 10 * 1024 * 1024 // 10MB max file size
advancedConfig.enableBackup = true
advancedConfig.backupInterval = 86400 // 24 hours

// Apply advanced configuration
OfflineFirstManager.shared.configureAdvancedStorage(advancedConfig)
```

## Data Models

### Designing Offline-First Models

```swift
// Base model for offline-first entities
protocol OfflineFirstEntity: Codable {
    var id: String { get }
    var createdAt: Date { get }
    var lastModified: Date { get }
    var syncStatus: SyncStatus { get set }
    var version: Int { get set }
}

// User model example
struct User: OfflineFirstEntity {
    let id: String
    let name: String
    let email: String
    let createdAt: Date
    var lastModified: Date
    var syncStatus: SyncStatus
    var version: Int
    
    // Computed properties
    var isSynced: Bool {
        return syncStatus == .synced
    }
    
    var needsSync: Bool {
        return syncStatus == .pending
    }
    
    var hasConflicts: Bool {
        return syncStatus == .conflicted
    }
}

// Post model example
struct Post: OfflineFirstEntity {
    let id: String
    let title: String
    let content: String
    let authorId: String
    let createdAt: Date
    var lastModified: Date
    var syncStatus: SyncStatus
    var version: Int
    
    // Relationships
    var author: User?
    var comments: [Comment]?
}
```

### Model Validation

```swift
// Model validation extension
extension User {
    var isValid: Bool {
        return !id.isEmpty && 
               !name.isEmpty && 
               !email.isEmpty &&
               email.contains("@")
    }
    
    func validate() -> ValidationResult {
        var errors: [String] = []
        
        if id.isEmpty {
            errors.append("User ID is required")
        }
        
        if name.isEmpty {
            errors.append("Name is required")
        }
        
        if email.isEmpty {
            errors.append("Email is required")
        } else if !email.contains("@") {
            errors.append("Invalid email format")
        }
        
        return ValidationResult(isValid: errors.isEmpty, errors: errors)
    }
}

struct ValidationResult {
    let isValid: Bool
    let errors: [String]
}
```

## Storage Operations

### Basic CRUD Operations

```swift
// Create operation
func createUser(_ user: User) -> Observable<SaveResult> {
    return OfflineFirstManager.shared.save(user)
        .do(onNext: { result in
            switch result {
            case .success:
                print("✅ User created successfully")
            case .failure(let error):
                print("❌ User creation failed: \(error)")
            case .conflict(let error):
                print("⚠️ Conflict detected: \(error)")
            }
        })
}

// Read operation
func loadUsers() -> Observable<[User]> {
    return OfflineFirstManager.shared.load(User.self)
        .do(onNext: { users in
            print("📱 Loaded \(users.count) users")
        })
}

// Update operation
func updateUser(_ user: User) -> Observable<SaveResult> {
    var updatedUser = user
    updatedUser.lastModified = Date()
    updatedUser.syncStatus = .pending
    
    return OfflineFirstManager.shared.save(updatedUser)
        .do(onNext: { result in
            switch result {
            case .success:
                print("✅ User updated successfully")
            case .failure(let error):
                print("❌ User update failed: \(error)")
            case .conflict(let error):
                print("⚠️ Conflict detected: \(error)")
            }
        })
}

// Delete operation
func deleteUser(_ user: User) -> Observable<DeleteResult> {
    return OfflineFirstManager.shared.delete(user)
        .do(onNext: { result in
            switch result {
            case .success:
                print("✅ User deleted successfully")
            case .failure(let error):
                print("❌ User deletion failed: \(error)")
            }
        })
}
```

### Batch Operations

```swift
// Batch save operation
func saveUsers(_ users: [User]) -> Observable<BatchSaveResult> {
    let operations = users.map { user in
        OfflineFirstManager.shared.save(user)
    }
    
    return Observable.zip(operations)
        .map { results in
            let successful = results.filter { $0.isSuccess }.count
            let failed = results.filter { !$0.isSuccess }.count
            return BatchSaveResult(successful: successful, failed: failed)
        }
}

// Batch delete operation
func deleteUsers(_ users: [User]) -> Observable<BatchDeleteResult> {
    let operations = users.map { user in
        OfflineFirstManager.shared.delete(user)
    }
    
    return Observable.zip(operations)
        .map { results in
            let successful = results.filter { $0.isSuccess }.count
            let failed = results.filter { !$0.isSuccess }.count
            return BatchDeleteResult(successful: successful, failed: failed)
        }
}
```

## Encryption and Security

### Data Encryption

```swift
// Encryption manager
class DataEncryptionManager {
    private let keychain = KeychainWrapper.standard
    private let encryptionKey = "offline_first_encryption_key"
    
    func encryptData(_ data: Data) -> Data? {
        guard let key = getEncryptionKey() else {
            return nil
        }
        
        // Implement AES encryption
        return performEncryption(data, with: key)
    }
    
    func decryptData(_ data: Data) -> Data? {
        guard let key = getEncryptionKey() else {
            return nil
        }
        
        // Implement AES decryption
        return performDecryption(data, with: key)
    }
    
    private func getEncryptionKey() -> Data? {
        if let existingKey = keychain.data(forKey: encryptionKey) {
            return existingKey
        }
        
        // Generate new key
        let key = generateSecureKey()
        keychain.set(key, forKey: encryptionKey)
        return key
    }
    
    private func generateSecureKey() -> Data {
        var key = Data(count: 32) // 256-bit key
        _ = key.withUnsafeMutableBytes { bytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, bytes.baseAddress!)
        }
        return key
    }
    
    private func performEncryption(_ data: Data, with key: Data) -> Data? {
        // Implement AES encryption
        return data // Placeholder
    }
    
    private func performDecryption(_ data: Data, with key: Data) -> Data? {
        // Implement AES decryption
        return data // Placeholder
    }
}
```

### Secure Storage

```swift
// Secure storage manager
class SecureStorageManager {
    private let keychain = KeychainWrapper.standard
    
    func storeSecurely<T: Codable>(_ data: T, forKey key: String) -> Bool {
        do {
            let encodedData = try JSONEncoder().encode(data)
            return keychain.set(encodedData, forKey: key)
        } catch {
            print("❌ Failed to encode data: \(error)")
            return false
        }
    }
    
    func retrieveSecurely<T: Codable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = keychain.data(forKey: key) else {
            return nil
        }
        
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            print("❌ Failed to decode data: \(error)")
            return nil
        }
    }
    
    func deleteSecurely(forKey key: String) -> Bool {
        return keychain.removeObject(forKey: key)
    }
    
    func clearAllSecureData() -> Bool {
        return keychain.removeAllKeys()
    }
}
```

## Compression and Optimization

### Data Compression

```swift
// Compression manager
class DataCompressionManager {
    enum CompressionLevel {
        case none
        case low
        case medium
        case high
    }
    
    func compressData(_ data: Data, level: CompressionLevel = .medium) -> Data? {
        switch level {
        case .none:
            return data
        case .low:
            return performCompression(data, level: 1)
        case .medium:
            return performCompression(data, level: 5)
        case .high:
            return performCompression(data, level: 9)
        }
    }
    
    func decompressData(_ data: Data) -> Data? {
        return performDecompression(data)
    }
    
    private func performCompression(_ data: Data, level: Int) -> Data? {
        // Implement compression logic
        return data // Placeholder
    }
    
    private func performDecompression(_ data: Data) -> Data? {
        // Implement decompression logic
        return data // Placeholder
    }
}
```

### Storage Optimization

```swift
// Storage optimization manager
class StorageOptimizationManager {
    func optimizeStorage() -> Observable<OptimizationResult> {
        return Observable.create { observer in
            // Perform storage optimization
            let result = self.performOptimization()
            observer.onNext(result)
            observer.onCompleted()
            return Disposables.create()
        }
    }
    
    private func performOptimization() -> OptimizationResult {
        // Implement optimization logic
        return OptimizationResult(
            spaceFreed: 0,
            filesOptimized: 0,
            compressionRatio: 1.0
        )
    }
    
    func cleanupOldData() -> Observable<CleanupResult> {
        return Observable.create { observer in
            // Clean up old data
            let result = self.performCleanup()
            observer.onNext(result)
            observer.onCompleted()
            return Disposables.create()
        }
    }
    
    private func performCleanup() -> CleanupResult {
        // Implement cleanup logic
        return CleanupResult(
            itemsRemoved: 0,
            spaceFreed: 0
        )
    }
}

struct OptimizationResult {
    let spaceFreed: Int64
    let filesOptimized: Int
    let compressionRatio: Double
}

struct CleanupResult {
    let itemsRemoved: Int
    let spaceFreed: Int64
}
```

## Data Migration

### Migration Manager

```swift
// Migration manager
class DataMigrationManager {
    func checkForMigrations() -> Observable<[Migration]> {
        return Observable.create { observer in
            let migrations = self.detectMigrations()
            observer.onNext(migrations)
            observer.onCompleted()
            return Disposables.create()
        }
    }
    
    func performMigrations() -> Observable<MigrationResult> {
        return Observable.create { observer in
            let result = self.executeMigrations()
            observer.onNext(result)
            observer.onCompleted()
            return Disposables.create()
        }
    }
    
    private func detectMigrations() -> [Migration] {
        // Detect required migrations
        return []
    }
    
    private func executeMigrations() -> MigrationResult {
        // Execute migrations
        return MigrationResult(
            migrationsApplied: 0,
            itemsMigrated: 0,
            migrationTime: 0.0
        )
    }
}

struct Migration {
    let id: String
    let version: Int
    let description: String
    let isRequired: Bool
}

struct MigrationResult {
    let migrationsApplied: Int
    let itemsMigrated: Int
    let migrationTime: TimeInterval
}
```

## Backup and Restore

### Backup Manager

```swift
// Backup manager
class BackupManager {
    func createBackup() -> Observable<Backup> {
        return Observable.create { observer in
            let backup = self.performBackup()
            observer.onNext(backup)
            observer.onCompleted()
            return Disposables.create()
        }
    }
    
    func restoreFromBackup(_ backup: Backup) -> Observable<RestoreResult> {
        return Observable.create { observer in
            let result = self.performRestore(backup)
            observer.onNext(result)
            observer.onCompleted()
            return Disposables.create()
        }
    }
    
    func listBackups() -> Observable<[Backup]> {
        return Observable.create { observer in
            let backups = self.getBackups()
            observer.onNext(backups)
            observer.onCompleted()
            return Disposables.create()
        }
    }
    
    private func performBackup() -> Backup {
        // Perform backup operation
        return Backup(
            id: UUID().uuidString,
            timestamp: Date(),
            size: 0,
            description: "Manual backup"
        )
    }
    
    private func performRestore(_ backup: Backup) -> RestoreResult {
        // Perform restore operation
        return RestoreResult(
            success: true,
            itemsRestored: 0,
            restoreTime: 0.0
        )
    }
    
    private func getBackups() -> [Backup] {
        // Get list of available backups
        return []
    }
}

struct Backup {
    let id: String
    let timestamp: Date
    let size: Int64
    let description: String
}

struct RestoreResult {
    let success: Bool
    let itemsRestored: Int
    let restoreTime: TimeInterval
}
```

## Monitoring and Analytics

### Storage Monitoring

```swift
// Storage monitor
class StorageMonitor {
    func monitorStorageUsage() -> Observable<StorageUsage> {
        return Observable.create { observer in
            let usage = self.getStorageUsage()
            observer.onNext(usage)
            observer.onCompleted()
            return Disposables.create()
        }
    }
    
    func getStorageReport() -> Observable<StorageReport> {
        return Observable.create { observer in
            let report = self.generateStorageReport()
            observer.onNext(report)
            observer.onCompleted()
            return Disposables.create()
        }
    }
    
    private func getStorageUsage() -> StorageUsage {
        // Get current storage usage
        return StorageUsage(
            usedSpace: 0,
            availableSpace: 0,
            totalSpace: 0,
            usagePercentage: 0.0
        )
    }
    
    private func generateStorageReport() -> StorageReport {
        // Generate storage report
        return StorageReport(
            totalFiles: 0,
            largestFiles: [],
            oldestFiles: [],
            storageEfficiency: 0.0,
            compressionRatio: 1.0
        )
    }
}

struct StorageUsage {
    let usedSpace: Int64
    let availableSpace: Int64
    let totalSpace: Int64
    let usagePercentage: Double
}

struct StorageReport {
    let totalFiles: Int
    let largestFiles: [String]
    let oldestFiles: [String]
    let storageEfficiency: Double
    let compressionRatio: Double
}
```

## Best Practices

### 1. Data Validation

Always validate data before storing:

```swift
// Data validation before storage
func saveUserWithValidation(_ user: User) -> Observable<SaveResult> {
    let validation = user.validate()
    
    guard validation.isValid else {
        return .error(ValidationError.invalidData(validation.errors))
    }
    
    return OfflineFirstManager.shared.save(user)
}
```

### 2. Error Handling

Implement comprehensive error handling:

```swift
// Error handling for storage operations
func handleStorageError(_ error: Error) {
    switch error {
    case let storageError as StorageError:
        switch storageError {
        case .storageFull:
            cleanupStorage()
        case .dataCorruption:
            repairData()
        case .encryptionFailed:
            regenerateEncryptionKey()
        default:
            logError(storageError)
        }
    default:
        logError(error)
    }
}
```

### 3. Performance Optimization

Optimize storage performance:

```swift
// Performance optimization
func optimizeStoragePerformance() {
    // Enable compression for large files
    let config = StorageConfiguration()
    config.enableCompression = true
    config.compressionThreshold = 1024 * 1024 // 1MB
    
    // Enable indexing for faster queries
    config.enableIndexing = true
    
    // Set appropriate chunk size
    config.chunkSize = 512 * 1024 // 512KB
    
    OfflineFirstManager.shared.configureStorage(config)
}
```

### 4. Security Best Practices

Implement security measures:

```swift
// Security best practices
func implementSecurityMeasures() {
    // Enable encryption
    let config = StorageConfiguration()
    config.enableEncryption = true
    config.encryptionType = .aes256
    
    // Enable secure deletion
    config.enableSecureDeletion = true
    
    // Set access controls
    config.enableAccessControl = true
    
    OfflineFirstManager.shared.configureStorage(config)
}
```

## Integration Example

```swift
import OfflineFirstFramework

class DataPersistenceApp {
    private let disposeBag = DisposeBag()
    
    func setupDataPersistence() {
        // Configure storage
        let config = StorageConfiguration()
        config.maxStorageSize = 200 * 1024 * 1024 // 200MB
        config.enableEncryption = true
        config.enableCompression = true
        config.enableStorageMonitoring = true
        
        OfflineFirstManager.shared.configureStorage(config)
        
        // Setup monitoring
        setupStorageMonitoring()
    }
    
    private func setupStorageMonitoring() {
        // Monitor storage usage
        StorageMonitor().monitorStorageUsage()
            .subscribe(onNext: { [weak self] usage in
                self?.handleStorageUsage(usage)
            })
            .disposed(by: disposeBag)
    }
    
    private func handleStorageUsage(_ usage: StorageUsage) {
        if usage.usagePercentage > 80 {
            // Trigger cleanup
            StorageOptimizationManager().cleanupOldData()
                .subscribe(onNext: { result in
                    print("Storage cleanup completed: \(result.itemsRemoved) items removed")
                })
                .disposed(by: disposeBag)
        }
    }
    
    func saveUserData(_ user: User) {
        // Validate before saving
        let validation = user.validate()
        guard validation.isValid else {
            print("❌ Validation failed: \(validation.errors)")
            return
        }
        
        // Save with encryption and compression
        OfflineFirstManager.shared.save(user)
            .subscribe(onNext: { result in
                switch result {
                case .success:
                    print("✅ User data saved successfully")
                case .failure(let error):
                    print("❌ Save failed: \(error)")
                    self.handleStorageError(error)
                case .conflict(let error):
                    print("⚠️ Conflict detected: \(error)")
                }
            })
            .disposed(by: disposeBag)
    }
}
```

## Conclusion

This guide covers the essential aspects of data persistence with the iOS Offline-First Framework. Key takeaways:

1. **Configure Storage Properly**: Set appropriate limits and enable security features
2. **Design Models Carefully**: Include offline-first properties in your data models
3. **Implement Security**: Use encryption and secure storage practices
4. **Optimize Performance**: Use compression and monitoring for better performance
5. **Handle Errors Gracefully**: Implement comprehensive error handling
6. **Monitor Usage**: Track storage usage and optimize as needed

Remember to test your data persistence implementation thoroughly, especially in offline scenarios, and monitor performance to ensure optimal user experience.
