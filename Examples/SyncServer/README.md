# Reference sync server

A small HTTP server that speaks the protocol of `HTTPSyncTransport`. Use it to try the
framework against a real network connection, to run the end-to-end tests, or as a starting
point for the sync endpoints of your own backend. It needs Node 24 or later and has no
dependencies.

```sh
cd Examples/SyncServer
node server.mjs --port 8080                       # data in memory
node server.mjs --port 8080 --data sync-data.json # data kept in a file
npm test                                          # the server's own tests
```

Point a store at it:

```swift
let transport = HTTPSyncTransport<Note>(baseURL: URL(string: "http://localhost:8080/sync/notes")!)
let store = try OfflineStore<Note>(name: "notes", transport: transport)
```

`notes` is the collection name: 1 to 64 letters, digits, `_` or `-`. Each collection has its own
records and revisions.

## Endpoints

| Request                                                  | Body / answer                                                            |
| -------------------------------------------------------- | ------------------------------------------------------------------------ |
| `POST /sync/<collection>/push`                           | `{"changes": [...]}` → `{"outcomes": {"<change ID>": {...}}}`            |
| `GET /sync/<collection>/changes?since=<token>&limit=<n>` | → `{"changes": [...], "token": "...", "hasMore": false, "epoch": "..."}` |

A change is
`{"id": "<UUID>", "recordID": "a", "operation": "upsert" | "delete", "record": {...},
"timestamp": {"wallTime": 1760000000000, "counter": 0, "nodeID": "..."}, "baseRevision": "4"}`.
An outcome is `{"status": "accepted", "revision": "5"}`,
`{"status": "conflict", "current": {...}}` or
`{"status": "rejected", "reason": "...", "current": {...}}`. The documentation article
"Server protocol" describes every field.

## Behaviour

- Every accepted write gets the revision `<epoch>.<n>`, where `n` counts the collection's
  writes; deletions keep their revision, so other devices learn about them. Each version is
  sent with the `changeID` of the push that wrote it, by which a device recognises its own
  write after a lost answer.
- A pushed timestamp whose wall time is more than five minutes ahead of the server's clock is
  stored at that limit, so a device whose clock runs ahead wins over later edits on other
  devices for five minutes at most.
- The epoch is new every time the server starts, also with `--data`: the file may be an older
  backup, and the writes after it would otherwise get revisions that devices already hold for
  other versions. So a revision is never handed out twice, and a push based on a revision from
  before the restart is checked against the record's current revision.
- Each epoch is later than the ones before: 16 hexadecimal digits of the start time in
  microseconds, or one more than the last epoch (also the one saved with `--data`) when that is
  later, so the server never reports an epoch again after a later one. Devices refuse a page
  that names an earlier epoch than the one they know in every sync, also after
  `resetChangeToken()`, as a stale replica or cache sends one. Without `--data`, a start with
  the clock set back before the previous start reports an earlier epoch, which devices refuse
  for as long as that run lasts; run with `--data` where the clock may go back.
- A change whose `baseRevision` is not the record's current revision gets a conflict with the
  current record.
- The answers to the last 10,000 change IDs are remembered, and saved with `--data`, so a push
  that is repeated after a lost answer or a restart is not applied twice.
- With `--data`, the file is written after every push, one write after the other. A push is
  answered, and its writes appear in pages, only once the file holds them: a write that a
  device pulled and a restart then lost would stay on that device alone. A failed write
  answers the push with status 500 (the device pushes again), and the next push that is saved
  keeps the changes of the failed one too.
- A change token is `<epoch>.<n>`, and every page names the epoch. A token of another epoch or
  past the newest write starts the pull from the beginning, so after a restart each client
  pulls every record once instead of waiting for writes that never come.
- A page holds at most `limit` changes (100 by default, 1,000 at most) and at most 8 MiB of
  them, but always at least one, so it fits in the client's response limit (16 MiB by
  default) however large the records are.
- A push answer brings at most one version of one record per change, 256 KiB at most, so the
  answer to one change fits in the client's response limit. When the answers of one request
  add up to more (70 conflicts on records of 250 KiB make 17.5 MiB), the client sends the
  request again in halves (16 more requests at most), and the server answers those changes from
  its memory of change IDs. Only such a 2xx answer or a 413 halves a request; an error status,
  of the server or of a proxy in front of it, is a failed attempt the device retries later.
- Limits: 1 MiB per request body, 500 changes per push, 1,000 changes per page, 100
  collections, 100,000 records per collection (deleted ones included), record IDs of at most
  256 characters, timestamps that a JavaScript number holds exactly. Requests outside them get
  status 400, 413 or 507. A record nested deeper than 64 levels or larger than 256 KiB of JSON
  is rejected with a reason; the other changes of the push are applied.

The server has no authentication or rate limiting. Put it behind your own before you expose it.
