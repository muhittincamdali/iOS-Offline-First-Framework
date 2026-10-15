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

| Request                                    | Body / answer                                                 |
| ------------------------------------------ | ------------------------------------------------------------- |
| `POST /sync/<collection>/push`             | `{"changes": [...]}` → `{"outcomes": {"<change ID>": {...}}}` |
| `GET /sync/<collection>/changes?after=<n>` | → `{"changes": [...], "cursor": "<n>", "hasMore": false}`     |

A change is
`{"id": "<UUID>", "recordID": "a", "operation": "upsert" | "delete", "record": {...},
"timestamp": {"wallTime": 1760000000000, "counter": 0, "nodeID": "..."}, "baseRevision": "4"}`.
An outcome is `{"status": "accepted", "revision": "5"}`,
`{"status": "conflict", "current": {...}}` or
`{"status": "rejected", "reason": "...", "current": {...}}`. The documentation article
"Server protocol" describes every field.

## Behaviour

- Every accepted write increments the collection's revision; deletions keep their revision, so
  other devices learn about them.
- A change whose `baseRevision` is not the record's current revision gets a conflict with the
  current record.
- The answers to the last 10,000 change IDs are remembered, so a push that is repeated after a
  lost answer is not applied twice.
- Limits: 1 MiB per request body, 500 changes per push, 1,000 changes per page, 100
  collections, record IDs of at most 256 characters, timestamps that a JavaScript number holds
  exactly. Requests outside them get status 400, 413 or 507.

The server has no authentication or rate limiting. Put it behind your own before you expose it.
