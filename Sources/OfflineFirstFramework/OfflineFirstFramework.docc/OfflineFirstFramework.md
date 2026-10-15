# ``OfflineFirstFramework``

Keep app data on the device, let people change it without a connection, and sync it with your server when the connection is back.

## Overview

An ``OfflineStore`` holds the records of one collection in a file on the device. Every write
goes to that file first and is queued, so the app never waits for the network. When the device
is online, the store pushes the queued changes through a ``SyncTransport``, pulls what changed
on the server, and settles records that changed on both sides with a ``ConflictResolver``.

```swift
import OfflineFirstFramework

struct Todo: SyncableRecord {
    var id = UUID()
    var title: String
    var isDone = false
}

let transport = HTTPSyncTransport<Todo>(baseURL: URL(string: "https://api.example.com/sync/todos")!)
let store = try OfflineStore<Todo>(name: "todos", transport: transport)

try await store.save(Todo(title: "Buy milk"))   // stored and queued, works offline
await store.startAutomaticSync()                 // pushes and pulls whenever the device is online
```

In SwiftUI, ``SyncedCollection`` follows a store as an observable model. The package has no
dependencies and builds in the Swift 6 language mode for iOS 17, macOS 14, tvOS 17,
watchOS 10 and visionOS 1.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:GuaranteesAndLimits>
- ``OfflineStore``
- ``SyncableRecord``
- ``SyncedCollection``

### Connecting to a server

- <doc:ConnectingToYourServer>
- <doc:ServerProtocol>
- ``SyncTransport``
- ``HTTPSyncTransport``
- ``InMemorySyncServer``
- ``OutgoingChange``
- ``RemoteChange``
- ``PushOutcome``
- ``PullResponse``
- ``QuarantinedChange``

### Conflicts

- <doc:ResolvingConflicts>
- ``ConflictResolver``
- ``Conflict``
- ``ConflictResolution``
- ``Mergeable``
- ``LWWRegister``
- ``LWWMap``
- ``GCounter``
- ``PNCounter``
- ``ORSet``

### Sync behaviour

- <doc:SyncingInTheBackground>
- ``SyncStatus``
- ``SyncReport``
- ``StoreState``
- ``PendingChange``
- ``RetryPolicy``
- ``CircuitBreaker``
- ``ConnectivityMonitor``
- ``NetworkConnectivityMonitor``
- ``SimulatedConnectivity``

### Storage, encryption and migrations

- <doc:ProtectingAndMigratingData>
- ``StorageBackend``
- ``FileStore``
- ``InMemoryStorage``
- ``StorageName``
- ``StoreEncryption``
- ``KeychainStore``
- ``RecordMigration``
- ``JSONValue``
- ``CorruptionPolicy``

### Clocks

- ``HybridLogicalClock``
- ``HLCTimestamp``
- ``VectorClock``

### Errors

- ``OfflineFirstError``
