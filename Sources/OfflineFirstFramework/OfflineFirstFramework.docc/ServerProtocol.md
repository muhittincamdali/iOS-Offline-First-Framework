# Server protocol

The two HTTP endpoints that ``HTTPSyncTransport`` calls, with every field.

## Overview

The transport is created with the URL of one collection, for example
`https://api.example.com/sync/todos`, and adds `/push` and `/changes` to it. Bodies are JSON in
UTF-8. Record IDs and records are encoded with the record type's own `Codable` conformance and
the default `JSONEncoder` settings.

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

## Pull

`GET <base>/changes` on the first sync, then `GET <base>/changes?since=<token>`.

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
optional. Conflict and rejection answers name the server's version in the same form.
Return changes oldest first, at most one per record, and a `token` the server understands as
"after these". While `hasMore` is `true` the store asks again right away, up to
``OfflineStore/Configuration/maximumPullPages`` pages per sync; the token of such a page must
differ from every token the store pulled with in this sync, or the sync fails. The token is
sent percent-encoded, `+` as `%2B`.

| Field       | Meaning                                                                                                                                                  |
| ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `revision`  | Names this version. Never give it to another version of the record, also after a restart or a restore.                                                   |
| `sequence`  | Grows with every write the server stores, also across a restart that keeps the data; orders versions within one epoch. Lets the store skip stale pages.  |
| `epoch`     | Names the server's history. Change it to a later one whenever the data may have been lost or replaced: longer, or as long and greater byte by byte.      |
| `timestamp` | The timestamp the change was pushed with; a wall time more than a few minutes ahead of the server's clock moved back to that limit.                   |
| `changeID`  | The `id` of the pushed change that wrote this version. The store knows its own writes by it; without it, by the exact timestamp it pushed.            |

When the server cannot continue after a token, because it lost its data, was restored from a
backup or the token belongs to another database, return changes from the beginning rather than
an empty page, and report a new epoch: the store then pulls everything again, skips records
whose revision it already has, and keeps its pending changes. The reference server creates a
later epoch on every start, 16 hexadecimal digits of the time in microseconds, and puts it in
front of its revisions and tokens (`"00064a1f3c2b9e18.43"`). The store believes another epoch
than its own only when two requests of one sync report it: the pull with its token and the
pull from the beginning, or, without a token, the pull from the beginning and the pull after
that page's token. A later epoch then starts a new history; an earlier one, as a stale replica
or cache sends, is refused until eight syncs in a row confirmed it, or taken at once after
``OfflineStore/resetChangeToken()``. When the two requests disagree, the sync fails without a
change to the store. So serve the pull from the beginning (`GET <base>/changes` without
`since`) from a cache only for a short time: every device asks for the same URL.

A change the app cannot decode, for example a field of another type or one nested deeper than
`JSONDecoder` reads (512 levels), is set aside in ``OfflineStore/quarantinedChanges()``; the
rest of the page is used and the token moves on. A push outcome that cannot be read leaves only
its own change unanswered.

## Errors and limits

Any status outside 200–299 counts as a failed attempt and the store retries with its
``RetryPolicy``. The transport reads at most ``HTTPSyncTransport/maximumResponseSize`` bytes.
The reference server in `Examples/SyncServer` additionally caps request bodies at 1 MiB and
pushes at 500 changes, rejects records nested deeper than 64 levels or larger than 256 KiB,
accepts only timestamps that a JavaScript number holds exactly, moves a pushed wall time more
than five minutes ahead of its clock back to that limit, sends back the change ID with every
version, and saves the answers to the last 10,000 change IDs with its data.
