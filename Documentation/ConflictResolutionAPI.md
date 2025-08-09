# ⚡ Conflict Resolution API

<!-- TOC START -->
## Table of Contents
- [⚡ Conflict Resolution API](#-conflict-resolution-api)
- [Overview](#overview)
- [ConflictResolutionManager](#conflictresolutionmanager)
  - [Properties](#properties)
  - [Methods](#methods)
    - [`detectConflicts<T: Codable>(localData: T, remoteData: T) -> Observable<[Conflict]>`](#detectconflictst-codablelocaldata-t-remotedata-t-observableconflict)
    - [`resolveConflicts<T: Codable>(_ conflicts: [Conflict], strategy: ResolutionStrategy) -> Observable<ConflictResolutionResult>`](#resolveconflictst-codable-conflicts-conflict-strategy-resolutionstrategy-observableconflictresolutionresult)
- [Resolution Strategies](#resolution-strategies)
  - [Strategy Types](#strategy-types)
  - [Strategy Implementation](#strategy-implementation)
- [Conflict Types](#conflict-types)
  - [Conflict Categories](#conflict-categories)
  - [Conflict Detection](#conflict-detection)
- [Auto-Resolution](#auto-resolution)
  - [Auto-Resolution Configuration](#auto-resolution-configuration)
  - [Auto-Resolution Rules](#auto-resolution-rules)
- [Manual Resolution](#manual-resolution)
  - [Manual Resolution Interface](#manual-resolution-interface)
  - [Resolution Options](#resolution-options)
- [Conflict Analytics](#conflict-analytics)
  - [Analytics Collection](#analytics-collection)
- [Conflict Prevention](#conflict-prevention)
  - [Prevention Strategies](#prevention-strategies)
- [Error Handling](#error-handling)
  - [ConflictError Types](#conflicterror-types)
  - [Error Recovery](#error-recovery)
- [Best Practices](#best-practices)
- [Integration Example](#integration-example)
<!-- TOC END -->


## Overview

The Conflict Resolution API provides advanced conflict detection and resolution capabilities for the iOS Offline-First Framework, ensuring data consistency across offline and online operations.

## ConflictResolutionManager

### Properties

- `conflictStatus: Observable<ConflictStatus>` - Current conflict resolution status
- `pendingConflicts: Observable<[Conflict]>` - Pending conflicts to resolve
- `resolutionHistory: Observable<[ResolutionRecord]>` - Conflict resolution history
- `autoResolutionEnabled: Observable<Bool>` - Auto-resolution status

### Methods

#### `detectConflicts<T: Codable>(localData: T, remoteData: T) -> Observable<[Conflict]>`
Detects conflicts between local and remote data.

```swift
let conflictManager = ConflictResolutionManager()

// Detect conflicts
conflictManager.detectConflicts(localData: localUser, remoteData: remoteUser)
    .subscribe(onNext: { conflicts in
        print("🔍 Found \(conflicts.count) conflicts")
        for conflict in conflicts {
            print("Field: \(conflict.field)")
            print("Local value: \(conflict.localValue)")
            print("Remote value: \(conflict.remoteValue)")
            print("Conflict type: \(conflict.type)")
        }
    })
    .disposed(by: disposeBag)
```

#### `resolveConflicts<T: Codable>(_ conflicts: [Conflict], strategy: ResolutionStrategy) -> Observable<ConflictResolutionResult>`
Resolves conflicts using specified strategy.

```swift
// Resolve with last write wins strategy
conflictManager.resolveConflicts(conflicts, strategy: .lastWriteWins)
    .subscribe(onNext: { result in
        switch result {
        case .success(let resolvedData):
            print("✅ Conflicts resolved successfully")
            print("Resolved data: \(resolvedData)")
        case .failure(let error):
            print("❌ Conflict resolution failed: \(error)")
        }
    })
    .disposed(by: disposeBag)
```

## Resolution Strategies

### Strategy Types

- `.lastWriteWins` - Use the most recent change
- `.localWins` - Always use local data
- `.remoteWins` - Always use remote data
- `.merge` - Merge conflicting data
- `.manual` - Require manual resolution
- `.custom` - Custom resolution logic

### Strategy Implementation

```swift
// Last write wins
let lastWriteStrategy = LastWriteWinsStrategy()
lastWriteStrategy.resolve(conflicts)
    .subscribe(onNext: { result in
        print("Last write wins resolution completed")
    })
    .disposed(by: disposeBag)

// Merge strategy
let mergeStrategy = MergeStrategy()
mergeStrategy.resolve(conflicts)
    .subscribe(onNext: { result in
        print("Merge resolution completed")
    })
    .disposed(by: disposeBag)

// Manual resolution
let manualStrategy = ManualResolutionStrategy()
manualStrategy.resolve(conflicts, userResolution: userChoice)
    .subscribe(onNext: { result in
        print("Manual resolution completed")
    })
    .disposed(by: disposeBag)
```

## Conflict Types

### Conflict Categories

- `.valueConflict` - Different values for same field
- `.deletionConflict` - One side deleted, other modified
- `.additionConflict` - Both sides added different items
- `.modificationConflict` - Both sides modified same item
- `.structuralConflict` - Structural changes conflict

### Conflict Detection

```swift
// Detect different types of conflicts
conflictManager.detectValueConflicts(localData: localUser, remoteData: remoteUser)
    .subscribe(onNext: { conflicts in
        print("Value conflicts: \(conflicts.count)")
    })
    .disposed(by: disposeBag)

conflictManager.detectDeletionConflicts(localData: localUser, remoteData: remoteUser)
    .subscribe(onNext: { conflicts in
        print("Deletion conflicts: \(conflicts.count)")
    })
    .disposed(by: disposeBag)
```

## Auto-Resolution

### Auto-Resolution Configuration

```swift
let autoConfig = AutoResolutionConfiguration()
autoConfig.enableAutoResolution = true
autoConfig.defaultStrategy = .lastWriteWins
autoConfig.enableConflictLogging = true
autoConfig.enableConflictAnalytics = true

conflictManager.configureAutoResolution(autoConfig)
```

### Auto-Resolution Rules

```swift
// Define auto-resolution rules
let rules = [
    AutoResolutionRule(field: "name", strategy: .lastWriteWins),
    AutoResolutionRule(field: "email", strategy: .remoteWins),
    AutoResolutionRule(field: "preferences", strategy: .merge),
    AutoResolutionRule(field: "sensitiveData", strategy: .manual)
]

conflictManager.setAutoResolutionRules(rules)
```

## Manual Resolution

### Manual Resolution Interface

```swift
// Present conflict resolution UI
conflictManager.presentConflictResolution(conflicts) { resolution in
    // User provides resolution choice
    return conflictManager.applyManualResolution(conflicts, resolution: resolution)
}
    .subscribe(onNext: { result in
        print("Manual resolution applied")
    })
    .disposed(by: disposeBag)
```

### Resolution Options

```swift
enum ResolutionOption {
    case useLocal
    case useRemote
    case merge
    case keepBoth
    case delete
    case custom(Any)
}
```

## Conflict Analytics

### Analytics Collection

```swift
let conflictAnalytics = ConflictAnalytics()

// Track conflict resolution
conflictAnalytics.trackConflictResolution(
    conflictType: .valueConflict,
    resolutionStrategy: .lastWriteWins,
    resolutionTime: 2.5
)

// Get conflict analytics
conflictAnalytics.getConflictReport()
    .subscribe(onNext: { report in
        print("Conflict Analytics Report:")
        print("Total conflicts: \(report.totalConflicts)")
        print("Auto-resolved: \(report.autoResolved)")
        print("Manual resolved: \(report.manualResolved)")
        print("Average resolution time: \(report.averageResolutionTime)s")
        print("Most common strategy: \(report.mostCommonStrategy)")
    })
    .disposed(by: disposeBag)
```

## Conflict Prevention

### Prevention Strategies

```swift
let preventionManager = ConflictPreventionManager()

// Implement optimistic locking
preventionManager.enableOptimisticLocking()
    .subscribe(onNext: { result in
        print("Optimistic locking enabled")
    })
    .disposed(by: disposeBag)

// Implement version control
preventionManager.enableVersionControl()
    .subscribe(onNext: { result in
        print("Version control enabled")
    })
    .disposed(by: disposeBag)
```

## Error Handling

### ConflictError Types

```swift
enum ConflictError: Error {
    case unresolvableConflict
    case manualResolutionRequired
    case strategyNotApplicable
    case dataCorruption
    case resolutionTimeout
    case invalidResolution
}
```

### Error Recovery

```swift
conflictManager.handleConflictError(.unresolvableConflict) { error in
    // Implement fallback strategy
    return conflictManager.applyFallbackStrategy()
        .flatMap { _ in
            conflictManager.retryResolution()
        }
}
```

## Best Practices

1. **Use Appropriate Strategies**: Choose resolution strategies based on data type
2. **Enable Auto-Resolution**: Use auto-resolution for non-critical conflicts
3. **Manual Resolution**: Require manual resolution for sensitive data
4. **Track Analytics**: Monitor conflict patterns for optimization
5. **Prevent Conflicts**: Implement conflict prevention strategies
6. **Handle Errors**: Implement robust error recovery
7. **User Feedback**: Provide clear feedback during resolution
8. **Test Thoroughly**: Test conflict scenarios thoroughly

## Integration Example

```swift
import OfflineFirstFramework

class ConflictAwareApp {
    private let conflictManager = ConflictResolutionManager()
    private let disposeBag = DisposeBag()
    
    func setupConflictResolution() {
        // Configure auto-resolution
        let config = AutoResolutionConfiguration()
        config.enableAutoResolution = true
        config.defaultStrategy = .lastWriteWins
        config.enableConflictLogging = true
        
        conflictManager.configureAutoResolution(config)
        
        // Setup conflict monitoring
        setupConflictMonitoring()
    }
    
    private func setupConflictMonitoring() {
        // Monitor conflict status
        conflictManager.conflictStatus
            .subscribe(onNext: { [weak self] status in
                self?.handleConflictStatus(status)
            })
            .disposed(by: disposeBag)
        
        // Monitor pending conflicts
        conflictManager.pendingConflicts
            .subscribe(onNext: { [weak self] conflicts in
                self?.handlePendingConflicts(conflicts)
            })
            .disposed(by: disposeBag)
    }
    
    private func handleConflictStatus(_ status: ConflictStatus) {
        switch status {
        case .resolving:
            print("Resolving conflicts...")
        case .resolved:
            print("Conflicts resolved")
        case .failed(let error):
            print("Conflict resolution failed: \(error)")
        default:
            break
        }
    }
    
    private func handlePendingConflicts(_ conflicts: [Conflict]) {
        if !conflicts.isEmpty {
            print("Found \(conflicts.count) pending conflicts")
            
            // Auto-resolve if possible
            conflictManager.resolveConflicts(conflicts, strategy: .lastWriteWins)
                .subscribe(onNext: { result in
                    print("Auto-resolution completed")
                })
                .disposed(by: disposeBag)
        }
    }
    
    func resolveUserConflicts(localUser: User, remoteUser: User) {
        // Detect conflicts
        conflictManager.detectConflicts(localData: localUser, remoteData: remoteUser)
            .flatMap { conflicts in
                // Resolve conflicts
                self.conflictManager.resolveConflicts(conflicts, strategy: .lastWriteWins)
            }
            .subscribe(onNext: { result in
                print("User conflicts resolved")
            })
            .disposed(by: disposeBag)
    }
}
```
