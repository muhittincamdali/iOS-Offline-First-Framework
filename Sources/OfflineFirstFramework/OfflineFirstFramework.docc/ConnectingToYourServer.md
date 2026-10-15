# Connecting to your server

Use the HTTP transport with a server that speaks its protocol, or write a transport for the API you already have.

## Overview

The store talks to the network only through a ``SyncTransport``: one call sends local changes,
one fetches server changes. You have three options:

- ``HTTPSyncTransport`` for a server that implements the two endpoints in <doc:ServerProtocol>.
  `Examples/SyncServer` in the repository is a working server for Node 24.
- Your own type that conforms to ``SyncTransport``, for an existing REST, GraphQL or database
  API.
- ``InMemorySyncServer`` for tests, previews and prototypes.

## Use the HTTP transport

```swift
let transport = HTTPSyncTransport<Todo>(
    baseURL: URL(string: "https://api.example.com/sync/todos")!,
    headers: { ["Authorization": "Bearer \(try await Auth.shared.validToken())"] }
)
let store = try OfflineStore<Todo>(name: "todos", transport: transport)
```

The `headers` closure runs before every request, so it can refresh an expired token. A status
outside 200–299 throws ``HTTPSyncTransport/Failure/unexpectedStatus(code:body:)`` and the store
retries the changes later. Responses longer than
``HTTPSyncTransport/maximumResponseSize`` are not read.

## Write your own transport

Map your API onto two functions:

```swift
struct TodoAPI: SyncTransport {
    func push(_ changes: [OutgoingChange<Todo>]) async throws -> [UUID: PushOutcome<Todo>] {
        // Send each change; answer .accepted, .conflict or .rejected per change ID.
    }

    func pull(since token: String?) async throws -> PullResponse<Todo> {
        // Return changes after the token, the next token and whether more follow.
    }
}
```

The rules that keep sync correct:

- **Revisions.** Every server write needs a new revision string (a version number, an ETag,
  an update timestamp), and a revision must never name two versions of a record, also after a
  restart or a restore from a backup: put an ID of the server's run in front of a counter, as
  the reference servers do. ``OutgoingChange/baseRevision`` is the revision the device last
  saw; if the server's revision differs, answer ``PushOutcome/conflict(current:)`` with the
  server's record instead of overwriting it.
- **Order and history.** Send ``RemoteChange/sequence``, a number that grows with every write,
  so the store recognises older versions that arrive late without trusting device clocks, and
  ``PullResponse/epoch``, which changes when the server lost or replaced its data, so the store
  pulls everything again. Give the transport a ``SyncTransport/serverIdentity`` (the HTTP
  transport uses its URL), so a store opened with another server does not send it the old
  server's token.
- **Failures.** Throw for anything worth retrying (no connection, timeouts, 5xx). Leave a
  change out of the answer to retry only that change. Answer
  ``PushOutcome/rejected(reason:current:)`` only when the change can never succeed.
- **Idempotency.** ``OutgoingChange/id`` stays the same when the store retries the same version
  of a change. If the answer to a push is lost, the store sends it again; a server that
  remembers change IDs can answer from memory instead of applying the change twice. Keep that
  memory across restarts: until the answer arrives the store treats the change as in doubt and
  learns from it whether the server applied the change.
- **Deletions.** ``RemoteChange/record`` is `nil` for a deleted record. Keep deleted records
  (or their IDs and revisions) on the server, so pulls can tell other devices about them.
- **Change tokens.** ``PullResponse/token`` must move forward while ``PullResponse/hasMore`` is
  `true`; a token that stays the same makes the sync fail with
  ``OfflineFirstError/pullTokenDidNotAdvance(token:)`` instead of looping.
- **Timestamps.** Send ``RemoteChange/timestamp`` back if you store it; without it,
  ``ConflictResolver/lastWriteWins`` lets the server's version win. Store a timestamp far ahead
  of the server's clock at a limit, as the reference servers do with five minutes.
- **Cancellation.** Stop both calls when their task is cancelled. The store cancels a request
  when every caller gave up and when the sync runs past
  ``OfflineStore/Configuration/syncTimeout``.

<doc:GuaranteesAndLimits> lists what the store guarantees when a server follows these rules.

The example app's `ReadmeSamples.swift` contains a complete transport for an ETag-based REST
API (`PUT` and `DELETE` with `If-Match`, `412` for conflicts, `422` for rejections), and the
package's tests run it against stubbed HTTP answers.

## Test with the in-memory server

``InMemorySyncServer`` behaves like a backend: revisions, conflicts, paged pulls, remembered
change IDs, validation and an offline switch. Write as another device would to create
conflicts:

```swift
let server = InMemorySyncServer<Todo>()
let store = try OfflineStore<Todo>(name: "todos", storage: InMemoryStorage(), transport: server)
await server.write(Todo(title: "Written on the iPad"))
await server.setOnline(false)   // the next sync throws URLError(.notConnectedToInternet)
```
