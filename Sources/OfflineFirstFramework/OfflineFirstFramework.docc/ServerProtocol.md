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
      "revision": "9f2c41d07ab35e18.43",
      "sequence": 43,
      "timestamp": {
        "wallTime": 1760000005000,
        "counter": 0,
        "nodeID": "F0E1..."
      }
    }
  ],
  "token": "9f2c41d07ab35e18.43",
  "hasMore": false,
  "epoch": "9f2c41d07ab35e18"
}
```

A change without `record` is a deletion. `timestamp`, `sequence` and `epoch` are optional.
Return changes oldest first, at most one per record, and a `token` the server understands as
"after these". While `hasMore` is `true` the store asks again right away, up to
``OfflineStore/Configuration/maximumPullPages`` pages per sync; the token of such a page must
differ from every token the store pulled with in this sync, or the sync fails. The token is
sent percent-encoded, `+` as `%2B`.

| Field       | Meaning                                                                                                                                     |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| `revision`  | Names this version. Never give it to another version of the record, also after a restart or a restore.                                      |
| `sequence`  | Grows with every write the server stores; orders versions within one epoch. Lets the store skip stale pages.                                |
| `epoch`     | Names the server's history. Change it whenever the data may have been lost or replaced; never go back to an old one.                        |
| `timestamp` | The timestamp the change was pushed with, unchanged: the store knows its own writes by it. Over five minutes ahead counts as at that limit. |

When the server cannot continue after a token, because it lost its data, was restored from a
backup or the token belongs to another database, return changes from the beginning rather than
an empty page, and report a new epoch: the store then pulls everything again, skips records
whose revision it already has, and keeps its pending changes. The reference server creates a
new epoch on every start and puts it in front of its revisions and tokens
(`"9f2c41d07ab35e18.43"`).

A change the app cannot decode, for example a field of another type, is set aside in
``OfflineStore/quarantinedChanges()``; the rest of the page is used and the token moves on. A
push outcome that cannot be read leaves only its own change unanswered.

## Errors and limits

Any status outside 200–299 counts as a failed attempt and the store retries with its
``RetryPolicy``. The transport reads at most ``HTTPSyncTransport/maximumResponseSize`` bytes.
The reference server in `Examples/SyncServer` additionally caps request bodies at 1 MiB and
pushes at 500 changes, accepts only timestamps that a JavaScript number holds exactly, stores a
pushed timestamp more than five minutes ahead of its clock at that limit, and saves the answers
to the last 10,000 change IDs with its data.
