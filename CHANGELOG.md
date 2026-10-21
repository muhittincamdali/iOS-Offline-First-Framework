# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Fixes for the data-integrity findings of two audits of 2.0.0 and of their second, third,
fourth, fifth, sixth, seventh and eighth rounds, each with a test that failed before the fix. The documentation article "Guarantees and limits" and a section of the README
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
  than `maximumClockDrift` ahead now count as at that limit when the store weighs them, and the
  reference servers move a pushed timestamp more than five minutes ahead of their clock back to
  that limit. They send back the change ID that wrote each version, by which a device whose
  clock runs ahead still recognises its own write whose answer was lost.
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
- Two store instances on one file silently dropped each other's saved records. With
  `FileStore`, `InMemoryStorage` and a custom backend that reports
  `StorageBackend.claimIdentity` (a backend that wraps a built-in one can forward its
  identity), the second instance's write now throws
  `OfflineFirstError.storeChangedElsewhere(name:)`; a `FileStore` reached through a symbolic
  link shares the protection. A custom backend without an identity, the default, is not
  protected: the instance that writes last still drops the other's records.
- A transport that reported its cancellation as `URLError(.cancelled)` counted a failed attempt,
  and a full disk while counting an attempt hid the transport's error.
- Right after the server accepted the store's own write, a page from a lagging replica rolled
  the record back or brought back the store's own deletion, with every policy, and an edit of
  the rolled-back copy replaced the acknowledged write. Until the write's echo arrives, the store
  now knows the write is newer than every version up to the one it replaced, its own earlier
  accepted writes included, and keeps that in its file.
- A change made on top of a change whose answer was lost met the device's own earlier write as
  a conflict: `.serverWins` dropped the new edit or brought a deleted record back, and a union
  merge brought back a removed item. A change now remembers the timestamps of its earlier
  versions that were in doubt, and a server version with one of them is recognised as the
  device's own write: the newer change goes out on top of it without the resolver, and a
  pending change the server already holds is settled as accepted. Node IDs alone are not
  trusted for this, since a store file restored onto a second device shares its node ID.
- On a server without sequences, a version without a timestamp was ordered by the time the
  store received it, so another device's newer version could be skipped for good. A missing
  timestamp now leaves the order unknown; files from before keep the timestamp they stored.
- On a device whose clock was set back by more than `maximumClockDrift`, newer edits from other
  devices were moved below the device's own older edit, and last write wins pushed the older
  edit over them; without sequences, all remote timestamps ended at the same limit. The limit
  now counts from the newest timestamp the store holds when that is later than the device
  clock, and server versions are ordered only by timestamps within the limit.
- After a server restart, a page from a stale replica or cache could roll records back. Epochs
  now have an order (a longer one is later; of two as long, the greater byte by byte): a page
  of another epoch than the store's counts only when two requests of one sync report that
  epoch, so one page from another deployment behind the same URL or a stale replica does not
  move the store. An earlier epoch the store never held that both requests report in eight
  syncs in a row is taken, so a server whose epochs do not grow is still followed. What a push answer tells about a record (an accepted
  write, or the version a conflict answer brought) moves into a later epoch until a pull
  brings that version: the push may have been answered after a restart the store had not
  seen, and a page of the new epoch from before it no longer rolls the write back or makes the
  next edit meet the device's own write as a conflict.
- A push that failed while the device clock was far ahead waited for a retry date that far
  ahead after the clock was set right, unreported; the circuit breaker's pause and the wait
  after a failed file write did the same. A wait longer than the policy allows now counts as
  passed.
- While the store file could not be written (a full disk, file protection, another instance), a
  change in doubt went out again on every sync, and automatic sync sent it every second. After a
  failed write, syncs now wait with the retry policy's backoff, and automatic sync waits after
  failed syncs.
- With `maximumPullPages` set to 1, a server restart stopped the pull for good: the page that
  reported the new epoch used the sync's only page, so the pull from the beginning that confirms
  the epoch never came, and every sync reported success with `hasMoreChanges`. A shared cache
  that answered the pull from the beginning with an older page made each sync spend all its
  pages without progress, and a cached page of an even earlier epoch was taken after eight
  syncs, rolling every record back. Both requests that confirm an epoch now belong to one step
  of the pull; when they disagree, the sync fails without a change to the store.
- After `resetChangeToken()` a stale page of a later epoch rolled the device's accepted write
  back with every policy, and one page of an earlier epoch from a lagging replica was taken at
  once, bringing back deleted records. Epochs keep their order after a reset, and a later one
  keeps what push answers told.
- A device whose clock ran ahead won last write wins over edits other devices made up to as much
  later as its clock was ahead (ten minutes, a day), since the servers kept pushed timestamps as
  sent; one moment of a clock a year ahead stamped every later write a year ahead. The servers bound timestamps by
  their clock again, and the store's clock goes on from the drift limit once the device clock is
  back.
- One change nested deeper than 512 levels, in its record or in a field the app ignores, made
  `JSONDecoder` refuse the whole page, so the token never moved and no later change arrived; one
  such conflict answer made the whole push answer unreadable. `HTTPSyncTransport` now reads each
  change and each outcome on its own and sets such a change aside. Reading them on its own also
  made a page or push answer that starts with a UTF-8 byte order mark fail as a whole; the mark
  is skipped again, and a body in UTF-16 or UTF-32 fails with an error that names the encoding.
- A record nested a few hundred levels deep, such as an outline 180 blocks deep in a page of
  5 KB, ended the process with a stack overflow when the store file was written, on every sync
  and in debug and release builds alike, whatever server or transport delivered it. Records are
  now limited to 64 levels (`OfflineStore.maximumRecordDepth`), as the reference server limits
  them: a deeper one from a page or a push answer is set aside before it is decoded or stored,
  a merge that makes one keeps the server's version, and `save(_:)` refuses one.
- A 16 MiB page of elements that are not changes, `{"changes":[0,0,...]}`, took gigabytes of
  memory and seconds of work on every sync, which iOS ends, so every launch crashed again. A page
  now lists at most 100 changes it sets aside, is refused beyond 1,000 that cannot be read, and
  stops being read when the sync is cancelled or passes its deadline.
- Records within the reference server's limits added up to a first page larger than the 16 MiB
  the transport reads (68 records of 250 KiB made 17 MB), so every device that pulled from the
  beginning, a new one, one after `resetChangeToken()` and all of them after a server restart,
  failed on that page for good. The reference server cuts its pages at 8 MiB; the transport sends
  `limit`, asks for half as many changes while a page is too large, and sets aside a single
  change that is larger than the limit, moving past it.
- A few large records made a push larger than the reference server's 1 MiB body limit, so every
  change of the batch failed with status 413 until it was parked. The transport splits a push
  into requests of at most `maximumRequestSize` and halves a request the server refuses with
  413; a single change the server refuses so stays in doubt and is retried, then parked.
- After one failed write of its data file (a full disk, a missing permission), the reference
  server never wrote the file again, and pages showed a push whose write had failed: a device
  that pulled it took its own write for applied, and a restart lost the write on the server
  only. Writes now go on after a failure, and pages show a push only once the file holds it.
- A server that ignored `limit` could send a 16 MiB page of half a million small, valid changes:
  the transport read them all and the store applied them in one step of seconds and more than a
  gigabyte that no deadline stopped, on every launch. A page with more changes than its pull
  asked for is now refused, by `HTTPSyncTransport` as soon as the change after the limit starts,
  and by the store from any transport beyond 1,000.
- Setting aside a change larger than the response limit read the page without a limit: a change
  that never ended was read until the sync's deadline, and a page that ignored `limit=1` was
  read to its end. That read now stops when a second change starts and after four times
  `maximumResponseSize`, or before it starts when the page announces more.
- Conflict answers bring the server's version of each record, so a device that pushed 70
  offline edits of records another device had grown to 250 KiB, within the reference server's
  limits, got an answer of about 17.5 MiB, more than the 16 MiB the transport reads. Every
  push failed with `responseTooLarge`, the edits were parked, `retryFailedChanges()` met the
  same answer, and the device never got the other device's versions while the server never
  got its edits. The transport now sends a request whose answer is too long again as two
  halves, which the server answers from its memory of change IDs; a single change whose
  answer alone is longer than the limit stays in doubt and is retried with backoff, and the
  rest of the push and the sync go on.
- A 503 or 504 of an overloaded proxy that announced a body of 17 MiB, or a 502 error page that
  streamed without end, was taken for a push answer too long to read: the transport sent the
  request again in halves down to single changes, 2n - 1 requests to a server that was already
  failing, read up to 16 MiB of each error page, and parked every change of the sync as
  rejected. Of an answer outside 2xx the transport now reads the first 4 KiB and throws
  `unexpectedStatus`: one failed attempt with backoff. Halving adds at most 16 requests to a
  push, and only 413 or a 2xx answer longer than the limit halves a request.
- A change whose answer nobody read (a 504 or a long 200 from a proxy after the server had
  applied the push, or a single conflict answer longer than the limit) was rejected as not
  applied, which dropped its in-doubt mark. Another device's later edit then met it as a
  conflict, and with `.clientWins` `retryFailedChanges()` put the old edit back over that edit
  on the server and every device. Only an answer that was read settles a change now: such a
  change stays in doubt, keeps the newer version a pull brings, and learns its fate from its
  next push under the same change ID.
- After `resetChangeToken()`, a lagging replica or a shared cache that answered both requests
  of the epoch check with the epoch the store had left at a server restart was taken at once:
  every record went back to the replica's copy, and a pending edit the server never saw met
  the device's own older write in the resolver, so `.serverWins` dropped it on the device and
  the server. Epochs now go one way: the store retires an epoch it leaves for a later one,
  keeps the last 32 in its file through resets and refuses them in every sync.
- A replica that answered eight syncs in a row with an epoch the store never held decided
  pending edits from its stale pages. A change made on an earlier server history now meets the
  new one through its push's answer only; records without a pending change still follow the
  new history until the server's own later epoch answers again.

### Added

- `RemoteChange.sequence`, `PullResponse.epoch`, `PullResponse.quarantined`,
  `SyncTransport.serverIdentity` (default `nil`) and `QuarantinedChange`.
- `OfflineStore.resetChangeToken()`, `quarantinedChanges()`, `SyncReport.quarantined`,
  `Configuration.syncTimeout` (5 minutes) and `Configuration.maximumTombstones` (10,000).
- `InMemorySyncServer.restart()` and `InMemorySyncServer.maximumClockDrift`.
- `RemoteChange.changeID`: the ID of the pushed change that wrote a version, by which the store
  recognises its own writes; without it, the store compares the timestamps it pushed.
- `OfflineStore.maximumRecordDepth`, `OfflineFirstError.recordNestedTooDeeply(limit:)`,
  `PullResponse.quarantinedCount`, and the `pageSize` and `maximumRequestSize` parameters of
  `HTTPSyncTransport`.
- `OfflineStore.maximumChangesPerPage` (1,000).
- `StorageBackend.claimIdentity` (default `nil`), `HTTPSyncTransport.errorBodyLimit` (4 KiB)
  and `HTTPSyncTransport.maximumSplitRequests` (16).

### Changed

- The circuit breaker now pauses pulls only; changes that are due are still pushed, and
  `SyncReport.skipped` means the pull was skipped.
- `OfflineFirstError` has the new cases `storeChangedElsewhere(name:)` and
  `recordNestedTooDeeply(limit:)`; a `switch` over it without `default` needs them.
- `HTTPSyncTransport.Failure.unknownOutcome` is no longer thrown.
- While a sync waits after a failed write of the store file, `sync()` throws that error without
  a request; the next write that succeeds ends the wait.
- `SyncReport.conflicts` no longer counts a conflict with the device's own earlier write.
- The reference server starts a new epoch on every start, also with `--data`, so each client
  pulls everything once after a restart, and it saves the answers to change IDs with its data.
- Servers must report epochs that only move to later ones: longer, or as long and greater byte
  by byte, and keep counting sequences across a restart that keeps the data. Both reference
  servers make each epoch from the time in microseconds (16 hexadecimal digits), and at least
  one more than the last epoch they handed out in the process or, with `--data`, saved.
- Servers should send back the change ID that wrote each version and may bound pushed
  timestamps by their clock; a server without change IDs has to keep timestamps as they were
  pushed. The reference servers do the first and bound timestamps to five minutes ahead.
- A single page of an earlier epoch than the store's no longer fails the sync when the pull from
  the beginning names the store's epoch; two requests that name different epochs fail it with
  `OfflineFirstError.invalidServerResponse`.
- The Node reference server rejects a record nested deeper than 64 levels or larger than 256 KiB
  of JSON, with a reason, and applies the other changes of the push.
- `HTTPSyncTransport` sends `limit` with every pull and pushes in requests of at most 1 MiB.
  Servers must keep every page within the client's response limit: at most `limit` changes, cut
  by bytes, at least one change per page. The reference server cuts pages at 8 MiB.
- The answer to a single pushed change must fit in the client's response limit; with a longer
  one the change stays in doubt and is retried, then parked. A push answer that is too long as
  a whole no longer fails the push.
- `HTTPSyncTransport` throws `Failure.unexpectedStatus` for every status outside 2xx, whatever
  length the answer announces, with at most its first 4 KiB as `body` (500 bytes before), and
  `Failure.responseTooLarge` for 2xx answers only. Only a 2xx answer that was read settles a
  pushed change.
- `resetChangeToken()` forgets the token only; it no longer takes an earlier epoch at once. A
  store never takes back an epoch it left for a later one, so servers must never report an
  epoch again once they reported a later one. A store that followed another deployment behind
  the same URL returns to the first server once that server reports a new epoch.
- A page may hold at most the `limit` its pull asked for and, from any transport, 1,000 changes;
  `InMemorySyncServer.pageSize` is at most 1,000. A page beyond `limit` fails with a
  `DecodingError` instead of `HTTPSyncTransport.Failure.responseTooLarge`, and a single change
  larger than four times `maximumResponseSize` is no longer set aside.
- The Node reference server's `Collection.push` takes `{ publish: false }` and `publish()`, and
  `createSyncServer` runs the saves one after another itself: a push is answered and shown in
  pages once its save succeeded.

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
