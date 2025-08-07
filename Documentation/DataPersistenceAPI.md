# 📦 Data Persistence API

## Overview

The Data Persistence API provides comprehensive local data storage capabilities for the iOS Offline-First Framework, including encryption, compression, and intelligent data management.

## OfflineStorageManager

### Properties

- `storageStatus: Observable<StorageStatus>` - Current storage status
- `storageUsage: Observable<StorageUsage>` - Storage usage information
- `encryptionStatus: Observable<EncryptionStatus>` - Encryption status
- `compressionStatus: Observable<CompressionStatus>` - Compression status

### Methods

#### `save<T: Codable>(_ data: T) -> Observable<SaveResult>`
Saves data to local storage with optional encryption and compression.

```swift
let storageManager = OfflineStorageManager()

// Save data with default settings
let user = User(id: "123", name: "John Doe", email: "john@example.com")
storageManager.save(user)
    .subscribe(onNext: { result in
        switch result {
        case .success:
            print("✅ Data saved successfully")
        case .failure(let error):
            print("❌ Save failed: \(error)")
        }
    })
    .disposed(by: disposeBag)

// Save with custom configuration
let config = StorageConfiguration()
config.enableEncryption = true
config.enableCompression = true
config.encryptionType = .aes256
config.compressionLevel = .high

storageManager.save(user, configuration: config)
    .subscribe(onNext: { result in
        print("Data saved with encryption and compression")
    })
    .disposed(by: disposeBag)
```

#### `load<T: Codable>(_ type: T.Type) -> Observable<[T]>`
Loads data from local storage.

```swift
storageManager.load(User.self)
    .subscribe(onNext: { users in
        print("📦 Loaded \(users.count) users from storage")
        for user in users {
            print("- \(user.name) (\(user.email))")
        }
    })
    .disposed(by: disposeBag)
```

#### `delete<T: Codable>(_ data: T) -> Observable<DeleteResult>`
Deletes data from local storage.

```swift
storageManager.delete(user)
    .subscribe(onNext: { result in
        switch result {
        case .success:
            print("✅ Data deleted successfully")
        case .failure(let error):
            print("❌ Delete failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## StorageConfiguration

### Basic Configuration

```swift
let config = StorageConfiguration()
config.enableEncryption = true
config.enableCompression = true
config.maxStorageSize = 100 * 1024 * 1024 // 100MB
config.enableBackup = true
config.enableMigration = true
```

### Advanced Configuration

```swift
let advancedConfig = AdvancedStorageConfiguration()
advancedConfig.encryptionType = .aes256
advancedConfig.compressionLevel = .high
advancedConfig.chunkSize = 1024 * 1024 // 1MB chunks
advancedConfig.enableDeduplication = true
advancedConfig.enableIndexing = true
advancedConfig.maxFileSize = 10 * 1024 * 1024 // 10MB max file size
```

## EncryptionManager

### Encryption Types

- `.none` - No encryption
- `.aes128` - AES-128 encryption
- `.aes256` - AES-256 encryption
- `.chacha20` - ChaCha20 encryption

### Encryption Operations

```swift
let encryptionManager = EncryptionManager()

// Encrypt data
let plainData = "Sensitive information".data(using: .utf8)!
encryptionManager.encrypt(plainData, type: .aes256)
    .subscribe(onNext: { result in
        switch result {
        case .success(let encryptedData):
            print("✅ Data encrypted successfully")
            print("Encrypted size: \(encryptedData.count) bytes")
        case .failure(let error):
            print("❌ Encryption failed: \(error)")
        }
    })
    .disposed(by: disposeBag)

// Decrypt data
encryptionManager.decrypt(encryptedData, type: .aes256)
    .subscribe(onNext: { result in
        switch result {
        case .success(let decryptedData):
            print("✅ Data decrypted successfully")
            let decryptedString = String(data: decryptedData, encoding: .utf8)
            print("Decrypted: \(decryptedString ?? "")")
        case .failure(let error):
            print("❌ Decryption failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## CompressionManager

### Compression Levels

- `.none` - No compression
- `.low` - Low compression (fast)
- `.medium` - Medium compression (balanced)
- `.high` - High compression (slow)

### Compression Operations

```swift
let compressionManager = CompressionManager()

// Compress data
let largeData = generateLargeData() // 10MB of data
compressionManager.compress(largeData, level: .high)
    .subscribe(onNext: { result in
        switch result {
        case .success(let compressedData):
            print("✅ Data compressed successfully")
            print("Original size: \(largeData.count) bytes")
            print("Compressed size: \(compressedData.count) bytes")
            print("Compression ratio: \(Double(largeData.count) / Double(compressedData.count))")
        case .failure(let error):
            print("❌ Compression failed: \(error)")
        }
    })
    .disposed(by: disposeBag)

// Decompress data
compressionManager.decompress(compressedData)
    .subscribe(onNext: { result in
        switch result {
        case .success(let decompressedData):
            print("✅ Data decompressed successfully")
            print("Decompressed size: \(decompressedData.count) bytes")
        case .failure(let error):
            print("❌ Decompression failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## StorageMonitoring

### Usage Monitoring

```swift
let storageMonitor = StorageMonitor()

// Monitor storage usage
storageMonitor.storageUsage
    .subscribe(onNext: { usage in
        print("📊 Storage Usage:")
        print("Used: \(usage.usedSpace)MB")
        print("Available: \(usage.availableSpace)MB")
        print("Total: \(usage.totalSpace)MB")
        print("Usage percentage: \(usage.usagePercentage)%")
    })
    .disposed(by: disposeBag)

// Monitor storage status
storageMonitor.storageStatus
    .subscribe(onNext: { status in
        switch status {
        case .normal:
            print("Storage status: Normal")
        case .warning:
            print("Storage status: Warning - Consider cleanup")
        case .critical:
            print("Storage status: Critical - Immediate cleanup required")
        }
    })
    .disposed(by: disposeBag)
```

## DataMigration

### Migration Manager

```swift
let migrationManager = DataMigrationManager()

// Check for migrations
migrationManager.checkForMigrations()
    .subscribe(onNext: { migrations in
        print("Found \(migrations.count) pending migrations")
        for migration in migrations {
            print("- Migration: \(migration.name) (v\(migration.version))")
        }
    })
    .disposed(by: disposeBag)

// Perform migrations
migrationManager.performMigrations()
    .subscribe(onNext: { result in
        switch result {
        case .success(let migrationResult):
            print("✅ Migrations completed successfully")
            print("Migrated items: \(migrationResult.migratedItems)")
            print("Migration time: \(migrationResult.migrationTime)s")
        case .failure(let error):
            print("❌ Migration failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## BackupManager

### Backup Operations

```swift
let backupManager = BackupManager()

// Create backup
backupManager.createBackup()
    .subscribe(onNext: { result in
        switch result {
        case .success(let backup):
            print("✅ Backup created successfully")
            print("Backup ID: \(backup.id)")
            print("Backup size: \(backup.size)MB")
            print("Backup timestamp: \(backup.timestamp)")
        case .failure(let error):
            print("❌ Backup failed: \(error)")
        }
    })
    .disposed(by: disposeBag)

// Restore from backup
backupManager.restoreFromBackup(backupId: "backup_123")
    .subscribe(onNext: { result in
        switch result {
        case .success:
            print("✅ Backup restored successfully")
        case .failure(let error):
            print("❌ Restore failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## Error Handling

### StorageError Types

```swift
enum StorageError: Error {
    case storageFull
    case dataCorruption
    case encryptionFailed
    case compressionFailed
    case migrationFailed
    case backupFailed
    case restoreFailed
    case invalidData
    case quotaExceeded
}
```

### Error Recovery

```swift
storageManager.handleStorageError(.storageFull) { error in
    // Implement storage cleanup
    return storageManager.cleanupStorage()
        .flatMap { _ in
            storageManager.retryOperation()
        }
}
```

## Best Practices

1. **Enable Encryption**: Always enable encryption for sensitive data
2. **Use Compression**: Use compression for large data sets
3. **Monitor Usage**: Monitor storage usage to prevent issues
4. **Regular Backups**: Create regular backups of important data
5. **Handle Migrations**: Implement proper data migration strategies
6. **Error Recovery**: Implement robust error recovery mechanisms
7. **Performance**: Balance compression level with performance requirements
8. **Security**: Use strong encryption for sensitive data

## Integration Example

```swift
import OfflineFirstFramework

class DataPersistenceApp {
    private let storageManager = OfflineStorageManager()
    private let encryptionManager = EncryptionManager()
    private let compressionManager = CompressionManager()
    private let disposeBag = DisposeBag()
    
    func setupDataPersistence() {
        // Configure storage
        let config = StorageConfiguration()
        config.enableEncryption = true
        config.enableCompression = true
        config.maxStorageSize = 200 * 1024 * 1024 // 200MB
        
        storageManager.configure(config)
        
        // Setup monitoring
        setupStorageMonitoring()
    }
    
    private func setupStorageMonitoring() {
        // Monitor storage usage
        storageManager.storageUsage
            .subscribe(onNext: { [weak self] usage in
                self?.handleStorageUsage(usage)
            })
            .disposed(by: disposeBag)
        
        // Monitor storage status
        storageManager.storageStatus
            .subscribe(onNext: { [weak self] status in
                self?.handleStorageStatus(status)
            })
            .disposed(by: disposeBag)
    }
    
    private func handleStorageUsage(_ usage: StorageUsage) {
        if usage.usagePercentage > 80 {
            // Trigger cleanup
            storageManager.cleanupStorage()
                .subscribe(onNext: { result in
                    print("Storage cleanup completed")
                })
                .disposed(by: disposeBag)
        }
    }
    
    private func handleStorageStatus(_ status: StorageStatus) {
        switch status {
        case .critical:
            // Immediate cleanup required
            storageManager.emergencyCleanup()
                .subscribe(onNext: { result in
                    print("Emergency cleanup completed")
                })
                .disposed(by: disposeBag)
        default:
            break
        }
    }
    
    func saveUserData(_ user: User) {
        // Save with encryption and compression
        let config = StorageConfiguration()
        config.enableEncryption = true
        config.enableCompression = true
        
        storageManager.save(user, configuration: config)
            .subscribe(onNext: { result in
                print("User data saved with encryption and compression")
            })
            .disposed(by: disposeBag)
    }
}
```
