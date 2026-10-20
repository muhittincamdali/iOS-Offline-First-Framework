# Guarantees and limits

What the store promises about your data, what it needs from the server for that, and where its limits are.

## Overview

The guarantees below hold for every ``ConflictResolver``, for a server that follows
<doc:ServerProtocol>, and through lost requests, lost answers, app restarts, server restarts and
pages answered from a stale replica or cache. A property test checks them: two devices make
random saves, deletes, syncs and restarts against an ``InMemorySyncServer`` that restarts and
answers some pulls with stale pages, from a cache of each device or one cache both devices
share, for last write wins, server wins, client wins and a merge. It
checks the end state, that no accepted write is applied again after a later one, that no device
goes back to an older server version of a record, and that no resolver is asked about a
device's own write.

## Guarantees

- **A write is on disk before it returns.** ``OfflineStore/save(_:)`` and
  ``OfflineStore/delete(_:)`` return after the file was written atomically; when the write fails
  they throw and the store is unchanged.
- **A queued change is pushed until the server answers it.** Pending changes survive restarts.
  A retry of the same version keeps its change ID, so a server that remembers change IDs
  applies it once. A change whose answer was lost is in doubt: no pull resolves it again until
  its next push tells whether the server applied it, or a pull brings that very change.
- **A stale copy never replaces an acknowledged write.** A push names the revision it is based
  on, and the server applies it only while that revision is current. The resolver is asked only
  when a record changed on the device and, by another device, on the server: a version the
  device wrote itself (a push applied although its answer was lost) is not a conflict, and the
  change made on top of it goes out again on its revision. A server version older than the one
  the store holds (a page out of order, a lagging replica, a stale cache) is skipped and never
  pushed back, also right after the store's own write was accepted: until its echo arrives,
  the store knows the write is newer than every version up to the one it replaced, its own
  earlier accepted writes included, and keeps that in its file. That holds across a server
  restart too: a sync pushes before it pulls, so a push may be answered after a restart the
  store has not seen yet, and what a push answer told about a record (an accepted write, or the
  version a conflict answer brought) moves into the later epoch until a pull brings that
  version. A page that names an earlier server epoch than the store's is refused.
- **Deleted records stay deleted.** Deletions are kept as tombstones, also for records the store
  never held, so an older version that arrives later does not bring a record back.
- **A server that lost or replaced its data starts a new history.** A later
  ``PullResponse/epoch``, or a transport with another ``SyncTransport/serverIdentity``, makes the
  store pull everything again from the beginning, and the server's versions replace the ones of
  the earlier history, except those a push answer brought as described above (never from
  another server). Pending changes stay and are pushed against the server's current versions.
  A later epoch counts once the pull from the beginning reports it too, so one page from
  another deployment behind the same URL does not move the store.
- **A refused epoch does not stop the store for good.** When the server keeps answering with an
  earlier epoch than the store's, eight syncs in a row, the store takes it as the server's
  history; ``OfflineStore/resetChangeToken()`` takes the next epoch at once.
- **A pull either moves forward or fails visibly.** A page is checked before it is stored: a
  token that does not move or goes round in a circle fails the sync, and the token never moves
  past a page that was not stored. A change the app cannot read is set aside in
  ``OfflineStore/quarantinedChanges()`` and the rest of the page is used.
- **A wrong clock has a bounded effect.** When last write wins weighs a server version against a
  local write, a timestamp more than ``OfflineStore/Configuration/maximumClockDrift`` ahead of
  the device clock counts as if it were at that limit; the server keeps the timestamp as it was
  pushed, so the device that wrote it still recognises it. A write from a device whose clock
  runs ahead therefore beats later edits on other devices for at most that long; on that device
  itself, its own edits still win the conflicts it resolves. The limit counts from the newest timestamp the store holds when
  that is later than the device clock, so a device whose clock was set back still takes a newer
  edit from another device as newer than its own older one. Server versions are never ordered
  by a timestamp beyond the limit, so one stamped far ahead does not hide later versions.
- **Retries are bounded.** Failed pushes and pushes answered with a conflict wait with
  exponential backoff and jitter (``RetryPolicy``) and are parked after the last attempt; a sync
  ends after ``OfflineStore/Configuration/syncTimeout``; the ``CircuitBreaker`` pauses pulls but
  never the pushes that are due. While the store file cannot be written (a full disk, file
  protection, another instance), syncs wait with the same backoff instead of sending requests
  whose answers they could not store, and automatic sync waits after every failed sync.
- **Devices converge.** Once the network is quiet and every device has synced, every device
  holds the server's records and nothing is queued. With ``ConflictResolver/lastWriteWins``
  every record ends as its newest write on any device.

## What the server must do

- Never give the same revision to two versions of a record, also after a restart or a restore
  from a backup. The reference servers put an epoch that is new on every start in front of a
  counter.
- Report an ``PullResponse/epoch`` that changes whenever its history may have changed, to a
  later one: longer, or as long and greater byte by byte (a counter, or the start time in
  fixed-width digits, as the reference servers do). Report a ``RemoteChange/sequence`` that
  grows with every write, also across a restart that keeps the data. Without a sequence the
  store orders versions by their timestamps,
  which matches the server's order only while the devices resolve conflicts by last write wins
  or a merge.
- Send back the ``RemoteChange/timestamp`` a change was pushed with. The store recognises a
  write of its own whose answer was lost by that timestamp; without it, a change made after a
  lost answer is taken for a conflict with the device's own earlier write.
- Remember the answers to change IDs for as long as a device may retry them, also across
  restarts; the reference servers keep the last 10,000.
- In a custom ``SyncTransport``, stop when the task is cancelled, so the deadline and
  cancellation can end a request.

## Limits

- **Data the server lost stays lost.** After a restore from a backup the store follows the
  server: it does not upload again the writes the server no longer has, and records the server
  lost stay on the device until they change again. A record whose last push the server
  answered before the store saw the new epoch keeps what that answer told, since a pull cannot
  tell the restored version from a stale page: after a restore that set the server's sequence
  back, the device keeps its version until the record changes on the device (the server's
  version then meets the edit as a conflict) or changes on the server once the sequence has
  passed where it stood before.
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
  next change of it. The same holds without sequences for a version whose timestamp is missing
  or beyond the drift limit; on a device whose clock is far behind, that can be every timestamp
  from a correct clock.
- **A copied store file shares its node ID.** A file restored onto a second device, or moved
  with a migration while the first device stays in use, stamps its writes with the same node
  ID. The store neither orders versions nor recognises its own writes by the node ID alone,
  but two of their timestamps can be equal; the store then keeps the server's version.
- **A device whose clock is behind loses concurrent edits.** Its clock does not move to
  timestamps from correct clocks that are beyond the drift limit, so its edits carry earlier
  timestamps until its clock catches up. An edit it makes on top of a version it received
  still replaces that version (there is no conflict); with last write wins, an edit made at the
  same time as one on a correct clock loses.
