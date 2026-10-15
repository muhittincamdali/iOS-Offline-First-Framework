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
      "revision": "43",
      "timestamp": {
        "wallTime": 1760000005000,
        "counter": 0,
        "nodeID": "F0E1..."
      }
    }
  ],
  "token": "43",
  "hasMore": false
}
```

A change without `record` is a deletion; `timestamp` is optional. Return changes oldest first,
at most one per record, and a `token` the server understands as "after these". While
`hasMore` is `true` the store asks again right away, up to
``OfflineStore/Configuration/maximumPullPages`` pages per sync.

When the server cannot continue after a token, because it lost its data, was restored from a
backup or the token belongs to another database, return changes from the beginning rather than
an empty page: the store skips records whose revision it already has. The reference server puts
an epoch in front of the revision (`"9f2c41d07ab35e18.43"`) to recognise such tokens.

## Errors and limits

Any status outside 200–299 counts as a failed attempt and the store retries with its
``RetryPolicy``. The transport reads at most ``HTTPSyncTransport/maximumResponseSize`` bytes.
The reference server in `Examples/SyncServer` additionally caps request bodies at 1 MiB and
pushes at 500 changes, and accepts only timestamps that a JavaScript number holds exactly.
