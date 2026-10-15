# Guarantees and limits

What the store promises about your data, what it needs from the server for that, and where its limits are.

## Overview

The guarantees below hold for every ``ConflictResolver``, for a server that follows
<doc:ServerProtocol>, and through lost requests, lost answers, app restarts, server restarts and
pages answered from a stale replica. A property test checks them: two devices make random
saves, deletes, syncs and restarts against an ``InMemorySyncServer`` that restarts and answers
some pulls with stale pages, for last write wins, server wins, client wins and a merge.

## Guarantees

- **A write is on disk before it returns.** ``OfflineStore/save(_:)`` and
  ``OfflineStore/delete(_:)`` return after the file was written atomically; when the write fails
  they throw and the store is unchanged.
- **A queued change is pushed until the server answers it.** Pending changes survive restarts.
  A retry of the same version keeps its change ID, so a server that remembers change IDs
  applies it once. A change whose answer was lost is in doubt: no pull resolves it again until
  its next push tells whether the server applied it.
- **A stale copy never replaces an acknowledged write.** A push names the revision it is based
  on, and the server applies it only while that revision is current. The resolver is asked only
  when a record changed on the device and on the server; a server version older than the one
  the store holds (a page out of order, a lagging replica, a stale cache) is skipped and never
  pushed back.
- **Deleted records stay deleted.** Deletions are kept as tombstones, also for records the store
  never held, so an older version that arrives later does not bring a record back.
- **A server that lost or replaced its data does not mix histories.** A new
  ``PullResponse/epoch``, or a transport with another ``SyncTransport/serverIdentity``, makes the
  store pull everything again from the beginning. Pending changes stay and are pushed against
  the server's current versions.
- **A pull either moves forward or fails visibly.** A page is checked before it is stored: a
  token that does not move or goes round in a circle fails the sync, and the token never moves
  past a page that was not stored. A change the app cannot read is set aside in
  ``OfflineStore/quarantinedChanges()`` and the rest of the page is used.
- **A wrong clock has a bounded effect.** A server timestamp more than
  ``OfflineStore/Configuration/maximumClockDrift`` ahead of the device clock counts as if it
  were at that limit, and the reference servers store pushed timestamps the same way. A write
  from a device whose clock runs ahead therefore beats later edits on other devices for at most
  that long; on that device itself, its own edits still win the conflicts it resolves.
- **Retries are bounded.** Failed pushes and pushes answered with a conflict wait with
  exponential backoff and jitter (``RetryPolicy``) and are parked after the last attempt; a sync
  ends after ``OfflineStore/Configuration/syncTimeout``; the ``CircuitBreaker`` pauses pulls but
  never the pushes that are due.
- **Devices converge.** Once the network is quiet and every device has synced, every device
  holds the server's records and nothing is queued. With ``ConflictResolver/lastWriteWins``
  every record ends as its newest write on any device.

## What the server must do

- Never give the same revision to two versions of a record, also after a restart or a restore
  from a backup. The reference servers put an epoch that is new on every start in front of a
  counter.
- Report an ``PullResponse/epoch`` that changes whenever its history may have changed, and a
  ``RemoteChange/sequence`` that grows with every write. Without a sequence the store orders
  versions by their timestamps, which matches the server's order only while the devices
  resolve conflicts by last write wins or a merge.
- Remember the answers to change IDs for as long as a device may retry them, also across
  restarts; the reference servers keep the last 10,000.
- In a custom ``SyncTransport``, stop when the task is cancelled, so the deadline and
  cancellation can end a request.

## Limits

- **Data the server lost stays lost.** After a restore from a backup the store follows the
  server: it does not upload again the writes the server no longer has, and records the server
  lost stay on the device until they change again.
- **One instance per file.** A second ``OfflineStore`` on the same file in the same process
  cannot write once the first one did
  (``OfflineFirstError/storeChangedElsewhere(name:)``); separate processes, such as an app and
  its extension, are not coordinated.
- **The whole file is written on every change.** That suits tens of thousands of records per
  store. The file cannot grow beyond ``FileStore/maximumFileSize``: a pull that would make it
  larger fails with ``OfflineFirstError/fileTooLarge(name:size:limit:)``.
- **Policies decide, not the store.** With ``ConflictResolver/serverWins`` or
  ``ConflictResolver/clientWins`` the device that syncs first or last wins, by design. A
  deletion that met an edit on another device follows the resolver like any edit.
- **Old deletions are forgotten.** Beyond ``OfflineStore/Configuration/maximumTombstones``
  (10,000 by default) the oldest tombstones are dropped; a version of such a record that
  arrives late can bring it back.
- **Quarantined changes wait.** A change the app cannot read is skipped until a newer version
  of the record arrives or ``OfflineStore/resetChangeToken()`` pulls everything again.
- **A server without sequences and timestamps cannot be checked for order.** The store then
  takes every server version as the newest, so a stale page can roll a record back until the
  next change of it.
