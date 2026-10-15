# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Fixes for the data-integrity findings of two audits of 2.0.0, each with a test that failed
before the fix. The documentation article "Guarantees and limits" and a section of the README
now state what the store promises and what it needs from the server.

### Fixed

- A server restart or a restore from a backup could reuse a revision. A device's older offline
  edit was then accepted over a newer write without a conflict, and a full pull skipped the
  changed record as an echo. The reference servers now put an epoch in every revision; the
  store pulls everything again when the epoch or the server changes, keeping pending changes.
- The conflict resolver was asked about server versions older than the stored one and about
  records without a local change: `.serverWins` rolled records back and brought deleted ones
  back, `.clientWins` made passive devices overwrite accepted writes. Older versions are now
  skipped, ordered by the server's `sequence` (or the timestamps), and only a real local change
  meets the resolver.
- The deletion of a record the store never held was not kept, so an older page could create
  the record. Two deletions now go to the resolver, so the newer one stays.
- A timestamp years ahead won every last-write-wins conflict on every device. Timestamps more
  than `maximumClockDrift` ahead now count as at that limit, in the store and in the reference
  servers.
- `discardChange(for:)` during a pull lost its token reset, and the server's copy never came
  back.
- A change whose push answer was lost could be resolved again by a pull and pushed over a newer
  write. It now stays in doubt until its next push shows whether the server applied it.
- After its own accepted write, the store could skip the server's newer version when that
  version had an older timestamp, and keep its own copy for good.
- A server that answered every push with a conflict kept the store pushing forever. Conflicts
  now count as failed attempts with backoff and parking; a conflict answer for another record
  counts too.
- One record the app could not decode stopped every pull, and one unknown push outcome failed
  the whole push. Such changes are now set aside in `quarantinedChanges()` and the rest goes on.
- A server could grow the store file past the size it reads, after which the store did not
  open again. `FileStore` now refuses such writes, and `.moveAsideAndStartEmpty` recovers a file
  that is too large.
- Change tokens that went round in a circle cost 100 requests per sync, a page whose token did
  not move was stored before the check, and `+` in a token reached form-decoding servers as a
  space.
- `sync()` called while a sync was pulling returned without pushing a change saved just before.
- Two store instances on one file silently dropped each other's saved records; the second
  instance's write now throws `OfflineFirstError.storeChangedElsewhere(name:)`.
- A transport that reported its cancellation as `URLError(.cancelled)` counted a failed attempt,
  and a full disk while counting an attempt hid the transport's error.

### Added

- `RemoteChange.sequence`, `PullResponse.epoch`, `PullResponse.quarantined`,
  `SyncTransport.serverIdentity` (default `nil`) and `QuarantinedChange`.
- `OfflineStore.resetChangeToken()`, `quarantinedChanges()`, `SyncReport.quarantined`,
  `Configuration.syncTimeout` (5 minutes) and `Configuration.maximumTombstones` (10,000).
- `InMemorySyncServer.restart()`.

### Changed

- The circuit breaker now pauses pulls only; changes that are due are still pushed, and
  `SyncReport.skipped` means the pull was skipped.
- `OfflineFirstError` has the new case `storeChangedElsewhere(name:)`; a `switch` over it without
  `default` needs that case.
- `HTTPSyncTransport.Failure.unknownOutcome` is no longer thrown.
- The reference server starts a new epoch on every start, also with `--data`, so each client
  pulls everything once after a restart, and it saves the answers to change IDs with its data.

## [2.0.0] - 2026-10-15

A rewrite. Version 1.0.0's manifest declared a missing `Resources` folder and unsafe compiler
flags, which Swift Package Manager does not accept in a dependency resolved by version, and its
sync managers were stubs; in June 2026 most of them were cut down further. This release replaces
all of it with a working offline store and sync engine, and merges the useful parts of the
author's SwiftPersistence package, which is being archived. Nothing from 1.0.0's API remains,
and the platform minimums rise to iOS 17, macOS 14, tvOS 17, watchOS 10 and visionOS 1.

### Added

- `OfflineStore<Record>`: an actor that keeps `Codable` records in one atomically written file,
  queues every local write (one pending change per record, with an ID that changes with each
  edit) and syncs through a `SyncTransport`: pushes in batches with the server revision each
  change was based on, then pulls pages after a saved change token. Writes run on a copy of the
  state that becomes current only after the file write succeeded. A record is marked as sent in
  the file before its first push leaves, so deleting it after a lost answer or a crash still
  reaches the server. Calls to `sync` while one runs share it; cancelling one of them stops it
  only when no other call waits, and a call made while a cancelled sync stops starts a new one.
  `save`, `save(contentsOf:)`, `delete`, `records`,
  `pendingChanges`, `failedChanges`, `retryFailedChanges`, `discardChange(for:)`, `sync`,
  `states()` and `Configuration` with defaults for every setting.
- Conflict handling: `ConflictResolver` with `lastWriteWins` (default), `serverWins`,
  `clientWins`, `merge(_:)` and `mergeable`; `Conflict` and `ConflictResolution`. Conflicts are
  resolved when a push is refused, when a pull meets a local change that is still waiting, and
  when a pull brings an older version than the stored one (pages out of order, a lagging
  replica). Deletions the server confirmed stay as tombstones, the newest 1,000 per store, so an
  older version cannot bring a deleted record back.
- Clocks: `HybridLogicalClock` and `HLCTimestamp` (total order, never backwards, refuses
  timestamps further ahead than a maximum drift); `VectorClock` with `compare(to:)`.
- Conflict-free types: `LWWRegister`, `LWWMap`, `GCounter`, `PNCounter`, `ORSet` and the
  `Mergeable` protocol.
- Transports: `HTTPSyncTransport` for a two-endpoint JSON protocol (documented in the "Server
  protocol" article; a cancelled request ends with `CancellationError`), `InMemorySyncServer`
  for tests, previews and demos, and the `SyncTransport` protocol for any other API.
- Sync control: `RetryPolicy` (exponential backoff with jitter, parking after the last
  attempt), `CircuitBreaker`, automatic sync (`startAutomaticSync`) on reconnect, after local
  edits, when retries are due and at an interval; `NetworkConnectivityMonitor` and
  `SimulatedConnectivity`.
- Storage: `StorageBackend`, `InMemoryStorage`, `StoreEncryption` (AES-GCM with the store name
  as authenticated data, optionally with a Keychain key), `RecordMigration` and `JSONValue` for
  schema changes, `CorruptionPolicy` for unreadable files.
- `FileStore` and `KeychainStore`, merged from SwiftPersistence
  (muhittincamdali/SwiftPersistence@25aaa346b1a9edfd8e4b60a89089b111843e9411). The record
  migrations follow SwiftPersistence's migration manager (@43f5cba5), and `RetryPolicy` and
  `CircuitBreaker` replace its retry helper and circuit breaker (@d7839fdf).
- `SyncedCollection`: an `@Observable` model of a store for SwiftUI.
- `OfflineFirstError` for every error the module throws.
- `Examples/OfflineTodos`, an iOS and macOS app that shows offline edits, sync, conflicts from a
  second device and background refresh; `Examples/SyncServer`, a reference server for the HTTP
  protocol in Node 24 with its own tests. Its change tokens, like those of
  `InMemorySyncServer`, carry an epoch: after a restart without its data, clients pull
  everything again instead of waiting for revisions that never come.
- DocC documentation with six articles, an end-to-end test suite that syncs two stores
  through the reference server, and a seeded test of random edits, deletes, restarts and lost
  requests and answers on two devices that checks they converge with the server.

### Changed

- The package uses tools version 6.2 and the Swift 6 language mode, and has no dependencies
  (1.0.0 declared ten, from SwiftLint and RxSwift to Charts).

### Removed

- The 1.x API: `OfflineFirstManager`, `OfflineStorageManager`, `DataSyncManager`,
  `ConflictResolutionManager`, `NetworkStateManager`, `BackgroundSyncScheduler`,
  `OfflineAnalyticsManager`, `OptimisticUpdateManager`, `RetryQueue`, `DeltaSyncEngine`,
  `MultiDeviceSyncManager`, `BandwidthOptimizer`, `CompressionEngine`, `EncryptionEngine`,
  `VectorSyncEngine` and the CRDT types of `CRDTTypes.swift`.
- The CocoaPods spec.

### Security

- Store and file names are limited to letters, digits, `.`, `_` and `-`, so they cannot point
  outside the storage directory (SwiftPersistence's `FileStore` joined any name onto its path).
- Bounded memory and loops against misbehaving servers and damaged files: outbox size, pull
  pages per sync, pushes per record per sync, HTTP response size, file size, server message,
  revision and change token length, remembered change IDs in the servers, and automatic sync
  waits between one second and one day.
- Arithmetic that could trap on decoded or extreme values saturates or is checked instead:
  counters, clock values, retry delays (including `Int.min` attempts), date conversion of NaN
  and infinite values, and sequence numbers in a damaged store file.

## [1.0.0] - 2026-02-02

First tagged release. It could not be added as a dependency by version (see 2.0.0) and is not
supported; use 2.0.0.

[Unreleased]: https://github.com/muhittincamdali/iOS-Offline-First-Framework/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/muhittincamdali/iOS-Offline-First-Framework/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/muhittincamdali/iOS-Offline-First-Framework/releases/tag/v1.0.0
