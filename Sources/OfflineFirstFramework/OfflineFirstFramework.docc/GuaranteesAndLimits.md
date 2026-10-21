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
wins, server wins, client wins and a merge. It checks the end state, that no accepted write is
applied again after a later one, that no device goes back to an older server version of a
record, and that no resolver is asked about a device's own write. A second property test runs
one to three operations of three devices at once, with resets, server restarts between a push
and its pull, a lagging replica of earlier epochs and storage that dies at random writes,
against a server written apart from the store, with and without sequences and change IDs, and
checks the same, except that a device may go back without sequences (see the limits). Further
tests send the HTTP transport pages of junk, deeply nested records, pages larger than its limit
and pages with more changes than it asked for, in debug and release builds, stream pages that
never end over a real socket, measure the memory a 16 MiB page costs, and run 68 records of 250
KiB against the reference server, also across its restart, 70 conflict answers of 250 KiB that
together exceed the response limit, a write whose save failed across a restart of the reference
server, a push the server applied behind a proxy that answers 504 or a 200 too long to read, and
a replica that serves pages from before a restart after ``OfflineStore/resetChangeToken()``.
Scenario tests run, for every policy, a replica of the epoch between two server restarts that
answers a device for many syncs in a row, a change made during a pull, two syncs at once, a
crash at every write of a sync, a page after a restart that lists an older own write before a
version whose answer was lost, a lagging replica that brings an older own write back while an
edit of a newer version waits, and a version a pull kept back for a change in doubt, stale or
newer, against a conflict or an accepted push answer from the server's memory of change IDs.
Further tests give a store of a server without epochs one page with an epoch from another
deployment, and a new store a first page from another deployment, with an earlier, a later or
no epoch and a record the server never held. A third property test makes three devices append
to records only they write, through the same faults, another deployment that answers one
request and a server that starts to report epochs, and checks that each record ends as its last
save. Device clocks a year ahead for a moment, or an hour ahead for good, run against servers
without sequences.

## Guarantees

- **A write is on disk before it returns.** ``OfflineStore/save(_:)`` and
  ``OfflineStore/delete(_:)`` return after the file was written atomically; when the write fails
  they throw and the store is unchanged.
- **A queued change is pushed until the server answers it.** Pending changes survive restarts.
  A retry of the same version keeps its change ID, so a server that remembers change IDs
  applies it once. Only an answer the transport read settles a change: after a lost answer,
  an error status or an answer too long to read, the change is in doubt, and no pull resolves
  it again until its next push tells whether the server applied it, or a pull brings that very
  change.
- **A stale copy never replaces an acknowledged write.** A push names the revision it is based
  on, and the server applies it only while that revision is current. The resolver is asked only
  when a record changed on the device and, by another device, on the server: a version the
  device wrote itself is not a conflict, and the change made on top of it goes out again on its
  revision. That holds for a push applied although its answer was lost, and for a write the
  server accepted even when a page the store could not order took the record back afterwards and
  the user edited on top of that: the store keeps the change IDs and timestamps of the last 16
  writes of each record the server holds or held. The versions of a change that were in doubt
  stay known until a push answer settles them, also when a page lists an older own write before
  them, as the first page after a server restart can. From a server that sends
  ``RemoteChange/sequence``, a server version older than the one the store holds (a page out of
  order, a lagging replica, a stale cache) is skipped and never pushed back, also right after
  the store's own write was accepted: until its echo arrives, the store knows the write is newer
  than every version up to the one it replaced, its own earlier accepted writes included, and
  keeps that in its file. That holds across a server restart too, also after
  ``OfflineStore/resetChangeToken()``: a sync pushes before it pulls, so a push may be answered
  after a restart the store has not seen yet, and what a push answer told about a record (an
  accepted write, or the version a conflict answer brought) moves into the later epoch until a
  pull brings that version. From a server without sequences a pull cannot tell a newer version
  from a stale copy: it leaves a pending change to its push, also when the page brings an older
  write of the device itself, and the resolver meets the version the server names in its
  conflict answer, never a stale page. The push's answer decides over a version a pull kept back
  while the change was in doubt, by one rule for every answer: the kept-back version takes the
  place of the version the answer names only when the server's sequences show it is newer, for
  an accepted write when it came after the version the write was based on. An answer that names
  or accepts the device's own write settles the change on that write. When the sequences cannot
  tell, the answer may come from the server's memory of change IDs and the kept-back version
  from a stale page: a conflict with another device's version sends the change once more under a
  new change ID, and the server answers with its current version; any other answer stands, an
  accepted write included, and the next sync pulls from the beginning, which brings the server's
  current version if it is a newer one.
- **Deleted records stay deleted.** Deletions are kept as tombstones, also for records the store
  never held, so an older version that arrives later from a server that sends sequences does
  not bring a record back.
- **A server that lost or replaced its data starts a new history.** A later
  ``PullResponse/epoch``, or a transport with another ``SyncTransport/serverIdentity``, makes the
  store pull everything again from the beginning, and the server's versions replace the ones of
  the earlier history, except those a push answer brought as described above (never from
  another server). Pending changes stay and are pushed against the server's current versions:
  a change made on the earlier history meets the new one through its push's answer, never
  through a page, so a page from a stale source cannot decide it.
- **Another epoch counts only when two requests report it.** A page that names another epoch
  than the store's is used only when a second request of the same step reports that epoch too:
  the pull from the beginning after the pull with the token, or, without a token, the pull after
  the first page's token. One page from another deployment behind the same URL, a lagging
  replica or a stale cache therefore does not move the store or roll it back. The first epoch a
  store hears of (a server that starts to report epochs, or another one) counts the same way: it
  is taken once a second request reports it too, and the pull goes on after the token. So does a
  new store's first page, with an epoch or without: when the second request disagrees, a third
  one, from the beginning, decides, and the first page is dropped, so one page from another
  deployment brings a new store neither records the server never held, nor a token, nor
  sequences, nor an epoch that would lock it out. A page that names no epoch, once two requests
  reported the store's, is checked the same way and never taken, since a server that reports
  epochs reports one on every page: one such page from another deployment cannot bring its
  revisions and sequences into the store, where a sequence from elsewhere would make the
  server's own answers look older and park every later edit of the record. So one page with an
  epoch from another deployment cannot lock a store out of a server without epochs either. A
  store file that holds an epoch only one request reported, as one written before this check
  can, checks it on its next sync; when two requests report an earlier epoch or none instead,
  that starts a new history, and the records without a pending change that the unchecked history
  brought go. And since both requests belong to one step, a sync that fetches a single page
  (``OfflineStore/Configuration/maximumPullPages``) still follows a restart.
- **Epochs go one way.** An earlier epoch than the store's is never taken, however many
  requests or syncs report it: an epoch the store left for a later one (the store keeps the
  last 32 it left in its file, and ``OfflineStore/resetChangeToken()`` keeps them), and an
  epoch the store never held, such as the one between two server restarts. A stale replica or
  a shared cache that answers both requests with one is refused in every sync, also one that
  sticks to a device for many syncs. After a reset both requests go to URLs that are the same
  for every device, so a cache answers them easily.
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
  most 100 changes it sets aside. A 2xx answer is read up to
  ``HTTPSyncTransport/maximumResponseSize`` and cancelled before it is read when it announces
  more; of an answer with any other status only the first ``HTTPSyncTransport/errorBodyLimit``
  (4 KiB) is read, whatever length it announces, so a 502 page that never ends or a 503 that
  announces 17 MiB costs one request and one failed attempt. A page larger than the limit makes
  the pull ask for half as many changes, down to one,
  and a single change larger than the limit is set aside while the pull moves past it, reading
  four times the limit at most, so no first page can lock out a device that pulls from the
  beginning. A push is sent in requests of at most ``HTTPSyncTransport/maximumRequestSize``,
  halved when the server answers 413 or with a 2xx answer longer than the response limit, as
  70 conflicts that each bring a version of 250 KiB do, and never after another status; the
  server answers a change it already applied from its memory of change IDs. Halving adds at
  most ``HTTPSyncTransport/maximumSplitRequests`` (16) requests to a push. A request that stays
  too large, a single change or one past that bound, settles none of its changes: they stay in
  doubt, wait for their retry date, and the rest of the push goes on. A body may start with a
  UTF-8 byte order mark.
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
  back. Server versions are never ordered by timestamps, also not by those within the limit, so
  a clock that ran ahead, for a moment or for good, hides no later version of a record and makes
  no conflict answer of the server look older: no change is parked for it.
- **Retries are bounded.** Failed pushes and pushes answered with a conflict wait with
  exponential backoff and jitter (``RetryPolicy``) and are parked after the last attempt; a sync
  ends after ``OfflineStore/Configuration/syncTimeout``; the ``CircuitBreaker`` pauses pulls but
  never the pushes that are due. While the store file cannot be written (a full disk, file
  protection, another instance), syncs wait with the same backoff instead of sending requests
  whose answers they could not store, and automatic sync waits after every failed sync.
- **Devices converge.** Once the network is quiet and every device has synced, every device
  holds the server's records and nothing is queued; from a server without sequences, unless a
  stale page answered after the last change of a record (see the limits). With
  ``ConflictResolver/lastWriteWins`` every record ends as its newest write on any device.

## What the server must do

- Never give the same revision to two versions of a record, also after a restart or a restore
  from a backup. The reference servers put an epoch that is new on every start in front of a
  counter.
- Report an ``PullResponse/epoch`` that changes whenever its history may have changed, to a
  later one: longer, or as long and greater byte by byte (a counter, or the start time in
  fixed-width digits, as the reference servers do). Never report an earlier epoch, also not
  after a restore or with a clock set back: the store refuses it in every sync. Once you report
  an epoch, report one on every page: the store refuses a page without one. Never report an
  epoch again once you reported a later one, and serve the pull from the beginning from a shared
  cache for a short time at most. Report a ``RemoteChange/sequence`` that grows with every
  write, also across a restart that keeps the data: a server that sends it gets the order
  guarantees above. Without it the store has no order of the server's versions, since it does
  not take one from timestamps, which device clocks write.
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
  below the limit is enough (the reference server allows 256 KiB). Only a 2xx answer settles a
  change; any other status, also from a gateway, counts as a failed attempt.
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
  itself, meets the resolver as a conflict. The store forgets the device's writes of the record
  with the discard, so the same holds when a stale page brings an older copy back and the user
  edits that.
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
- **A change whose push answer alone exceeds the response limit stays in doubt.** Its answer
  is not read, so the change is retried as the ``RetryPolicy`` says and then waits in
  ``OfflineStore/failedChanges()``, still in doubt: a pull keeps the server's newer version of
  the record back for it. ``OfflineStore/retryFailedChanges()`` meets the same answer until the
  server's version of the record is smaller or ``HTTPSyncTransport/maximumResponseSize`` is
  raised, and ``OfflineStore/discardChange(for:)`` drops the change. The same holds for a single
  change the server refuses with status 413.
- **An earlier epoch stays refused.** A store that took a later epoch from another deployment
  behind the same URL, from two requests of one sync it answered, a new store's first sync too,
  refuses the real server's earlier one in every sync, also after
  ``OfflineStore/resetChangeToken()``, and keeps its records and pending changes; it follows that
  server again once the server reports an epoch later than the one the store holds. A server whose epoch went back, after a restart with its clock set back and
  without its saved epoch, is refused the same way until it reports one later than the store's.
  So is a page without an epoch once two requests reported the store's: a server that stops
  reporting epochs is refused in every sync until it reports one again, its last one or a later
  one; its pushes still go out.
- **A server without sequences gets no order guarantee.** The store does not order versions by
  timestamps, which device clocks write, so it takes every server version a page brings as the
  newest: a stale page (out of order, from a lagging replica or a cache) can roll a record
  without a local change back, also to a version from before its deletion, until the record
  changes again, and devices then differ until it does. No write is lost and no change is parked
  for it: a pull leaves a pending change to its push. The device's own write knows the version
  it replaced as older, whether an accepted answer, a page or a conflict answer showed it
  applied, so a stale page with that version is skipped; when a stale page brings an older
  version still in place of the device's own accepted write, an edit made on the stale copy
  replaces that write without a conflict. When a push answer stands over a version a pull kept
  back meanwhile because nothing orders the two, the device shows the answer's version, its own
  accepted write included, until the next sync, whose pull from the beginning brings a newer
  version the server holds.
- **A copied store file shares its node ID.** A file restored onto a second device, or moved
  with a migration while the first device stays in use, stamps its writes with the same node
  ID. The store neither orders versions nor recognises its own writes by the node ID alone,
  but from a server without change IDs two of their timestamps can be equal, and the store then
  takes the other copy's write for its own: a version with the timestamp of its pending change
  replaces that change, and a pending change goes out over a version with the timestamp of one
  of its accepted writes without the resolver. Writes from before the copy belong to both.
- **A device whose clock is behind loses concurrent edits.** Its clock does not move to
  timestamps from correct clocks that are beyond the drift limit, so its edits carry earlier
  timestamps until its clock catches up. An edit it makes on top of a version it received
  still replaces that version (there is no conflict); with last write wins, an edit made at the
  same time as one on a correct clock loses.

## Known limitations: answers from another deployment

The epoch check covers pages: one page from another deployment behind the same URL, a stale
replica or a cache never counts. Answers that reach another deployment in other ways, or a
deployment that is all a new store ever hears, are not covered, and the store cannot tell them
from the real server's. They come from a load balancer, DNS or proxy that sends requests to the
wrong deployment (staging and production, two regions with separate data), or from a replica
that still serves the history from before a data loss. A setup that never sends a device's
requests anywhere but one deployment with one history is not affected.

- **A new store's first sync answered only by another history.** When both requests of a new
  store's first sync reach another deployment, the store takes that deployment's state as the
  server's. Without an epoch, it goes on after that deployment's token; a server whose tokens
  are positions, unlike the reference servers, then never sends the records before that
  position, while every sync succeeds. With a later epoch than the server's, every later sync
  fails as from an earlier history, until the server reports a later epoch still. A copy of a
  record from that deployment with a sequence beyond the server's stays on the device, and an
  edit of it meets the server's version as a conflict that names an older version and parks.
  When both pulls of the first sync reach a replica that serves the history from before the
  server lost its data, while the push goes to the server, the replica's version of a record
  replaces the device's own accepted write on the device, and the next edit replaces that write
  on the server.
- **One push answer from another deployment.** A conflict or rejected answer that names that
  deployment's copy of a record, with a sequence beyond the server's, makes the device show
  that copy and skip the server's later versions of the record as older, without an error. With
  ``ConflictResolver/lastWriteWins`` and ``ConflictResolver/serverWins`` the resolver decides the
  device's edit against that copy, so the edit can go; with ``ConflictResolver/clientWins`` and a
  merge the edit parks in ``OfflineStore/failedChanges()``. An accepted answer from another
  deployment, after a first sync it answered too, counts as the server accepting the write: the
  server never gets it, and the device keeps its copy while other devices' edits of the record
  do not arrive.

Recovery: ``OfflineStore/resetChangeToken()`` brings back the records a token without an epoch
skipped. The other cases do not end by themselves, also not after a server restart: read
``OfflineStore/records()``, ``OfflineStore/pendingChanges()`` and
``OfflineStore/failedChanges()``, release the store, move `<name>.store` aside with the
``StorageBackend`` (``StorageBackend/move(_:to:)``), open a new store, sync, and save again what
the user still needs. The new store checks its first page with a second request.
