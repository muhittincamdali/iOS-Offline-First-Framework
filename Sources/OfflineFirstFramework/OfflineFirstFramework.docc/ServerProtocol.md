# Server protocol

The two HTTP endpoints that ``HTTPSyncTransport`` calls, with every field.

## Overview

The transport is created with the URL of one collection, for example
`https://api.example.com/sync/todos`, and adds `/push` and `/changes` to it. Bodies are JSON in
UTF-8, with or without a byte order mark; an answer in UTF-16 or UTF-32 fails with a
`DecodingError` that says so. Record IDs and records are encoded with the record type's own
`Codable` conformance and the default `JSONEncoder` settings. A record nests objects and arrays
at most ``OfflineStore/maximumRecordDepth`` (64) levels deep, its own object counting as one.

## Push

`POST <base>/push`

```json
{
  "changes": [
    {
      "id": "6F9619FF-8B86-D011-B42D-00C04FC964FF",
      "recordID": "C2D6...",
      "operation": "upsert",
      "record": { "id": "C2D6...", "title": "Buy milk", "isDone": false },
      "timestamp": {
        "wallTime": 1760000000000,
        "counter": 0,
        "nodeID": "A1B2..."
      },
      "baseRevision": "41"
    }
  ]
}
```

| Field          | Meaning                                                                                  |
| -------------- | ---------------------------------------------------------------------------------------- |
| `id`           | Change ID. The same for every retry of this version of the change.                       |
| `recordID`     | The record's ID.                                                                         |
| `operation`    | `upsert` (create or replace) or `delete`.                                                |
| `record`       | The full record for an upsert; absent for a delete.                                      |
| `timestamp`    | Hybrid logical clock time of the change (milliseconds since 1970, counter, device ID).   |
| `baseRevision` | The server revision the device last saw; absent for a record the server never confirmed. |

The answer has one outcome per change ID. A change without an outcome is retried later.

The transport sends a push in requests of at most ``HTTPSyncTransport/maximumRequestSize``
bytes (1 MiB by default), one after the other, and reads in each answer only the outcomes of
that request's changes. Answer a request body that is larger than you accept with status 413:
the transport sends it again as two halves. When a later request fails, the outcomes of the
earlier ones still count.

An answer must fit in ``HTTPSyncTransport/maximumResponseSize`` (16 MiB by default). A longer
one, such as conflicts that each bring a large version of their record, makes the transport
send the request again as two halves; answer a change ID you already applied with the outcome
you gave it, as the reference server does from its memory of the last 10,000 change IDs.
Keep that memory across restarts, and restore it with the data: after a restore from a backup,
keep only the answers the backup holds, or none. An answer kept from after the backup names a
version of a history the server left; the store takes it for an older version than it holds
and holds the change back until it parks.
Halving adds at most ``HTTPSyncTransport/maximumSplitRequests`` (16) requests to a push, and
only status 413 or a 2xx answer longer than the limit halves a request. **The answer to a single
change must not be longer than ``HTTPSyncTransport/maximumResponseSize``**: only an answer the
transport read settles a change, so such a change, like a single change answered with 413,
gets no outcome. It stays in doubt, is retried with backoff and parked after the retry policy's
last attempt, and the rest of the push goes on. A conflict or a rejection brings at most one
version of one record, so records well below the limit keep every answer within it.

```json
{
  "outcomes": {
    "6F9619FF-8B86-D011-B42D-00C04FC964FF": {
      "status": "accepted",
      "revision": "42"
    }
  }
}
```

| Outcome                                                        | When                                                                            |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `{"status": "accepted", "revision": "42"}`                     | The server stored the change as this revision.                                  |
| `{"status": "conflict", "current": <change>}`                  | The record's revision is not `baseRevision`; `current` is the server's version. |
| `{"status": "rejected", "reason": "...", "current": <change>}` | The change can never succeed; `current` is optional.                            |

Store a change only while the record's revision is its `baseRevision`, and a change without one
only while you hold no version of the record, a deletion included. The store takes an accepted
change as written on top of that version: with `sequence`, a version later than that one came
after the change.

## Pull

`GET <base>/changes?limit=<n>` on the first sync, then `GET <base>/changes?since=<token>&limit=<n>`.

```json
{
  "changes": [
    {
      "recordID": "C2D6...",
      "record": { "id": "C2D6...", "title": "Buy oat milk", "isDone": false },
      "revision": "00064a1f3c2b9e18.43",
      "sequence": 43,
      "timestamp": {
        "wallTime": 1760000005000,
        "counter": 0,
        "nodeID": "F0E1..."
      },
      "changeID": "0C2B1A9E-4D3C-4B2A-9F8E-7D6C5B4A3F2E"
    }
  ],
  "token": "00064a1f3c2b9e18.43",
  "hasMore": false,
  "epoch": "00064a1f3c2b9e18"
}
```

A change without `record` is a deletion. `timestamp`, `sequence`, `changeID` and `epoch` are
optional, but a server that reports an epoch reports it on every page. Conflict and rejection
answers name the server's version in the same form.

A page must fit in ``HTTPSyncTransport/maximumResponseSize`` (16 MiB by default). Return at most
`limit` changes (``HTTPSyncTransport/pageSize``, 100 by default, 1,000 at most), cut the page by
bytes as well, and put at least one change in every page; the reference server cuts its pages at
8 MiB. Send `Content-Length`, so a page that is too large is refused before it is read. While a
page is larger than the limit, the transport asks for half as many changes, down to one. A
single change that is larger on its own is read as it streams in, without what it holds, set
aside in ``OfflineStore/quarantinedChanges()``, and the token moves past it; that read stops
after four times the limit, so a larger change fails every sync with
``HTTPSyncTransport/Failure/responseTooLarge(limit:)``. A page with more changes than `limit`
is cancelled as soon as the change after the limit starts and refused with a `DecodingError`,
so a server that ignores `limit` fails every sync.
Return changes oldest first, at most one per record, and a `token` the server understands as
"after these". While `hasMore` is `true` the store asks again right away, up to
``OfflineStore/Configuration/maximumPullPages`` pages per sync; the token of such a page must
differ from every token the store pulled with in this sync, or the sync fails. The token is
sent percent-encoded, `+` as `%2B`.

| Field       | Meaning                                                                                                                                                                                               |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `revision`  | Names this version. Never give it to another version of the record, also after a restart or a restore.                                                                                                |
| `sequence`  | Grows with every write the server stores, also across a restart that keeps the data; orders versions within one epoch. The only order the store uses: without it a stale page can roll a record back. |
| `epoch`     | Names the server's history. Change it to a later one whenever the data may have been lost or replaced: longer, or as long and greater byte by byte.                                                   |
| `timestamp` | The timestamp the change was pushed with; a wall time more than a few minutes ahead of the server's clock moved back to that limit.                                                                   |
| `changeID`  | The `id` of the pushed change that wrote this version. The store knows its own writes by it; without it, by the exact timestamp it pushed.                                                            |

When the server cannot continue after a token, because it lost its data, was restored from a
backup or the token belongs to another database, return changes from the beginning rather than
an empty page, and report a new epoch: the store then pulls everything again, skips records
whose revision it already has, and keeps its pending changes. The reference server creates a
later epoch on every start, 16 hexadecimal digits of the time in microseconds, and puts it in
front of its revisions and tokens (`"00064a1f3c2b9e18.43"`). The store believes another epoch
than its own only when two requests of one sync report it: the pull with its token and the pull
from the beginning, or, without a token, the pull from the beginning and the pull after that
page's token. A later epoch then starts a new history. The first epoch a store hears of, from a
server that starts to report epochs, is checked the same way; once both requests report it, the
pull goes on after the token, without a new history. A new store checks its first page the same
way, with or without an epoch, by a pull after that page's token; when the two disagree, a third
pull, from the beginning, decides which of them came from the server. **Never report an earlier
epoch, and never report an epoch again once you reported a later one**: the store refuses a page
that names an earlier epoch than its own in every sync, however many requests or syncs report
it, as it comes from a stale replica or cache. That holds for an epoch the store left for a
later one (it keeps the last 32 of them) and for one it never held, such as the epoch between
two restarts. A server restored from a backup reports a new, later epoch; a server whose clock
may go back keeps its last epoch and counts on from it, as the reference server does with
`--data`. A page without an epoch, once two requests reported the store's, is refused the same
way: it comes from no history the store knows, such as another deployment behind the same URL,
so a server that stops reporting epochs is refused until it reports one again. One page from
another deployment can therefore neither lock a store out of a server without epochs nor a new
store out of its server. ``OfflineStore/resetChangeToken()`` forgets the token only: the next
sync pulls from the beginning, and earlier epochs stay refused. When the two requests disagree
and a third one does not settle it, the sync fails without a change to the store. So serve the
pull from the beginning (`GET <base>/changes` without `since`) from a cache only for a short
time: every device asks for the same URL, and right after a reset both requests of the check are
such URLs.

A change the app cannot decode, for example a field of another type, is set aside in
``OfflineStore/quarantinedChanges()``; the rest of the page is used and the token moves on. The
transport walks each page once and measures every change before it decodes it: a change that is
not an object, has no `recordID` or `revision`, or nests deeper than a record may is set aside
without being decoded. A page lists the first 100 changes it sets aside and counts the others
(``PullResponse/quarantinedCount``). A push outcome that cannot be read, also one
that nests deeper than the outcome, its current change and a record allow, leaves only its own
change unanswered.

## Errors and limits

Any status outside 200–299 counts as a failed attempt and the store retries with its
``RetryPolicy``; it settles none of the request's changes. The transport reads at most the
first ``HTTPSyncTransport/errorBodyLimit`` (4 KiB) of such an answer, whatever length it
announces, and never halves a request after it, except after 413. Of a 2xx answer it reads at
most ``HTTPSyncTransport/maximumResponseSize`` bytes, and four times as many to set a single
change aside.

Answer a push, and show its writes in pages, only once they are stored durably. A device that
pulls a write the server then loses, in a crash or a restart, takes it for applied (its own
write, by the change ID) and keeps it, and no other device ever gets it.
The reference server in `Examples/SyncServer` additionally caps request bodies at 1 MiB (status
413), pushes at 500 changes and pages at `limit` changes (1,000 at most) and 8 MiB, rejects
records nested deeper than 64 levels or larger than 256 KiB,
accepts only timestamps that a JavaScript number holds exactly, moves a pushed wall time more
than five minutes ahead of its clock back to that limit, sends back the change ID with every
version, and saves the answers to the last 10,000 change IDs with its data. With `--data` it
writes its data file after every push and answers the push, and shows its writes in pages, only
once the file holds them; a failed write answers status 500 and keeps the writes out of pages
until a later write of the file succeeds.
