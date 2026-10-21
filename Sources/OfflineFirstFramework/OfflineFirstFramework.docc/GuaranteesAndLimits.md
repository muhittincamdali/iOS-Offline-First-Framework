# Guarantees and limits

What the store promises about your data, what it needs from the server for that, and where its limits are.

## Overview

The guarantees below hold for every ``ConflictResolver``, for a server that follows
<doc:ServerProtocol>, and through lost requests, lost answers, app restarts, server restarts and
pages answered from a stale replica or cache. A property test checks them: two devices make
random saves, deletes, syncs (also two at once), restarts and calls of
``OfflineStore/resetChangeToken()`` against an ``InMemorySyncServer`` that restarts and answers
some pulls with stale pages, from a cache of each device or one cache both devices share, with
pages of two, three or a hundred changes and one to a hundred pages per sync, for last write
wins, server wins, client wins and a merge. It
checks the end state, that no accepted write is applied again after a later one, that no device
goes back to an older server version of a record, and that no resolver is asked about a
device's own write. Further tests send the HTTP transport pages of junk, deeply nested records,
pages larger than its limit and pages with more changes than it asked for, in debug and release
builds, stream pages that never end over a real socket, measure the memory a 16 MiB page costs,
and run 68 records of 250 KiB against the reference server, also across its restart, 70
conflict answers of 250 KiB that together exceed the response limit, and a write whose save
failed across a restart of the reference server.

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
  restart too, also after ``OfflineStore/resetChangeToken()``: a sync pushes before it pulls, so
  a push may be answered after a restart the store has not seen yet, and what a push answer
  told about a record (an accepted write, or the version a conflict answer brought) moves into
  the later epoch until a pull brings that version.
- **Deleted records stay deleted.** Deletions are kept as tombstones, also for records the store
  never held, so an older version that arrives later does not bring a record back.
- **A server that lost or replaced its data starts a new history.** A later
  ``PullResponse/epoch``, or a transport with another ``SyncTransport/serverIdentity``, makes the
  store pull everything again from the beginning, and the server's versions replace the ones of
  the earlier history, except those a push answer brought as described above (never from
  another server). Pending changes stay and are pushed against the server's current versions.
- **Another epoch counts only when two requests report it.** A page that names another epoch
  than the store's is used only when a second request of the same step reports that epoch too:
  the pull from the beginning after the pull with the token, or, without a token, the pull
  after the first page's token. One page from another deployment behind the same URL, a lagging
  replica or a stale cache therefore does not move the store or roll it back, and since both
  requests belong to one step, a sync that fetches a single page
  (``OfflineStore/Configuration/maximumPullPages``) still follows a restart.
- **A refused epoch does not stop the store for good.** When the server keeps answering both
  requests with an earlier epoch than the store's, eight syncs in a row, the store takes it as
  the server's history; after ``OfflineStore/resetChangeToken()`` the next sync in which both
  requests report it takes it.
- **A pull either moves forward or fails visibly.** A page is checked before it is stored: a
  token that does not move or goes round in a circle fails the sync, and the token never moves
  past a page that was not stored. When the two requests that check an epoch disagree (a cache
  answers the pull from the beginning with an older page), the sync fails without a change to
  the store instead of spending its pages and reporting success; it checks one epoch at most. A
  change the app cannot read, also one nested too deeply, is set aside in
  ``OfflineStore/quarantinedChanges()`` and the rest of the page is used; a push outcome that
  cannot be read leaves only its own change unanswered.
- **A server's answers have a bounded cost.** ``HTTPSyncTransport`` walks every page and push
  answer once, without copying it, before it decodes any part, and stops when the sync is
  cancelled or passes its deadline. A change or outcome nested deeper than
  ``OfflineStore/maximumRecordDepth`` (64 levels, the record counting as one) is set aside
  without being decoded, and no record that deep enters the store from a page, a push answer, a
  merge or a save, from any transport: decoding, storing and encoding a record recurses once per
  level on the 512 KiB stack of the task that syncs, and a few hundred levels ended the process
  on every sync. A page holds at most the `limit` its pull asked for, readable or not, and
  1,000 changes (``OfflineStore/maximumChangesPerPage``) from any transport: the transport
  cancels the download as soon as the change after the limit starts, and the store refuses a
  longer page before it stores any of it, so a 16 MiB page of junk or of half a million small
  valid changes costs milliseconds and kilobytes, not seconds and gigabytes. A page lists at
  most 100 changes it sets aside. An answer is read up to
  ``HTTPSyncTransport/maximumResponseSize`` and cancelled before it is read when it announces
  more. A page larger than the limit makes the pull ask for half as many changes, down to one,
  and a single change larger than the limit is set aside while the pull moves past it, reading
  four times the limit at most, so no first page can lock out a device that pulls from the
  beginning. A push is sent in requests of at most ``HTTPSyncTransport/maximumRequestSize``,
  halved when the server answers 413 or with more than the response limit, as 70 conflicts
  that each bring a version of 250 KiB do; the server answers a change it already applied from
  its memory of change IDs. A single change whose answer alone is longer than the limit is
  parked with ``HTTPSyncTransport/answerTooLarge`` and the sync goes on; a push of n changes
  takes at most 2n − 1 requests. A body may start with a UTF-8 byte order mark.
- **A wrong clock has a bounded effect.** The reference servers move a pushed timestamp more
  than five minutes ahead of their clock back to that limit and send back the change ID that
  wrote each version (``RemoteChange/changeID``), by which the device recognises its own write.
  A write from a device whose clock runs ahead therefore beats later edits on other devices for
  five minutes at most; on that device itself, the edits it makes while its clock is ahead still
  win the conflicts it resolves. When last write wins weighs a server version against a local
  write, a timestamp more than ``OfflineStore/Configuration/maximumClockDrift`` ahead of the
  device clock, or of the local write when that is later, counts as if it were at that limit,
  so a device whose clock was set back still takes a newer edit from another device as newer
  than its own older one. A device clock that showed a time far ahead only for a moment does not
  stamp later writes: the store's clock goes on from the drift limit once the device clock is
  back. Server versions are never ordered by a timestamp beyond the limit, so one stamped far
  ahead does not hide later versions.
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
  fixed-width digits, as the reference servers do), and serve the pull from the beginning from
  a shared cache for a short time at most. Report a ``RemoteChange/sequence`` that grows with
  every write, also across a restart that keeps the data. Without a sequence the store orders
  versions by their timestamps, which matches the server's order only while the devices
  resolve conflicts by last write wins or a merge.
- Send back the ``RemoteChange/timestamp`` a change was pushed with, a wall time far ahead of the
  server's clock moved back to a limit of a few minutes, and the ``RemoteChange/changeID`` that
  wrote each version. The store recognises a write of its own whose answer was lost by the
  change ID, or, from a server without change IDs, by the exact timestamp, which such a server
  has to keep as it was pushed; otherwise a change made after a lost answer is taken for a
  conflict with the device's own earlier write.
- Remember the answers to change IDs for as long as a device may retry them, also across
  restarts; the reference servers keep the last 10,000.
- Answer a push, and show its writes in pages, only once they are stored durably. A device that
  pulled a write the server then lost in a crash or restart takes it for applied and keeps it,
  and no other device gets it. The reference server writes its data file before it answers a
  push or shows it; when the write fails it answers status 500, the device pushes again, and
  the next write of the file that succeeds keeps the changes of both pushes.
- Keep every page within the transport's response limit (16 MiB by default): return at most
  `limit` changes (a longer page is refused), cut pages by bytes too, and put at least one
  change in each, as the reference server does with 8 MiB. Answer a push body larger than you
  accept with status 413, and keep the answer to a single change within the response limit:
  a conflict or rejection brings at most one version of one record, so keeping records well
  below the limit is enough (the reference server allows 256 KiB).
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
- **A save right after a discard has no base.** ``OfflineStore/discardChange(for:)`` removes the
  local version and pulls everything again. A record saved again before that pull brings the
  server's copy back is pushed as new, so the server's copy, also a version the device wrote
  itself, meets the resolver as a conflict.
- **One instance per file.** With the built-in backends, ``FileStore`` and
  ``InMemoryStorage``, and with a custom backend that reports a
  ``StorageBackend/claimIdentity`` (a backend that wraps a built-in one can forward its
  identity), a second ``OfflineStore`` on the same file in the same process cannot write once
  the first one did (``OfflineFirstError/storeChangedElsewhere(name:)``). A custom backend
  without an identity, the default, is not protected: two instances on one file each write
  their own state, and the one that writes last drops the records the other one saved.
  Separate processes, such as an app and its extension, are not coordinated.
- **The whole file is written on every change.** That suits tens of thousands of records per
  store. The file cannot grow beyond ``FileStore/maximumFileSize``: a pull that would make it
  larger fails with ``OfflineFirstError/fileTooLarge(name:size:limit:)``.
- **Policies decide, not the store.** With ``ConflictResolver/serverWins`` or
  ``ConflictResolver/clientWins`` the device that syncs first or last wins, by design. A
  deletion that met an edit on another device follows the resolver like any edit.
- **Old deletions are forgotten.** Beyond ``OfflineStore/Configuration/maximumTombstones``
  (10,000 by default) the oldest tombstones are dropped; a version of such a record that
  arrives late can bring it back.
- **Quarantined changes wait.** A change the app cannot read, also one nested too deeply or
  larger than the response limit on its own, is skipped until a newer version of the record
  arrives or ``OfflineStore/resetChangeToken()`` pulls everything again.
- **Records nest at most 64 levels.** ``OfflineStore/save(_:)`` refuses a deeper record with
  ``OfflineFirstError/recordNestedTooDeeply(limit:)``, and a merge that makes one keeps the
  server's version. A custom ``SyncTransport`` that decodes pages itself has to limit the depth
  its decoder reads: the store measures the records it is handed, but the transport's decoder
  runs first.
- **A broken page stops the pull until the server changes it.** A page with more changes than
  its pull asked for (more than 1,000 from a custom transport), a page whose structure is
  broken, and a single change larger than four times the response limit fail every sync,
  without a change to the store. Finding such a change costs up to four times the response
  limit per sync; raise ``HTTPSyncTransport/maximumResponseSize`` for records that large.
- **A change whose push answer alone exceeds the response limit is parked.** Its answer is
  not read, so the change waits in ``OfflineStore/failedChanges()`` with
  ``HTTPSyncTransport/answerTooLarge``; ``OfflineStore/retryFailedChanges()`` meets the same
  answer until the server's version of the record is smaller or
  ``HTTPSyncTransport/maximumResponseSize`` is raised, and ``OfflineStore/discardChange(for:)``
  drops the change.
- **A server without sequences and timestamps cannot be checked for order.** The store then
  takes every server version as the newest, so a stale page can roll a record back until the
  next change of it. The same holds without sequences for a version whose timestamp is missing
  or beyond the drift limit; on a device whose clock is far behind, that can be every timestamp
  from a correct clock.
- **A copied store file shares its node ID.** A file restored onto a second device, or moved
  with a migration while the first device stays in use, stamps its writes with the same node
  ID. The store neither orders versions nor recognises its own writes by the node ID alone,
  but from a server without change IDs two of their timestamps can be equal; the store then
  keeps the server's version.
- **A device whose clock is behind loses concurrent edits.** Its clock does not move to
  timestamps from correct clocks that are beyond the drift limit, so its edits carry earlier
  timestamps until its clock catches up. An edit it makes on top of a version it received
  still replaces that version (there is no conflict); with last write wins, an edit made at the
  same time as one on a correct clock loses.
