# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
