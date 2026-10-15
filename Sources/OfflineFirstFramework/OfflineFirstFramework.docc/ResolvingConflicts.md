# Resolving conflicts

Decide what happens when a record changed on the device and on the server since the last sync.

## Overview

A conflict happens when the device pushes a change based on an old server revision, or when a
pull brings a server change for a record that still has a local change waiting. The store hands
both versions to its ``ConflictResolver`` as a ``Conflict`` and acts on the
``ConflictResolution``:

- ``ConflictResolution/keepRemote``: the server's version replaces the local one, and the local
  change is dropped.
- ``ConflictResolution/keepLocal``: the local version stays and is pushed again on top of the
  server's revision.
- ``ConflictResolution/merged(_:)``: the combined record is stored and pushed.

Set the resolver in the configuration:

```swift
var configuration = OfflineStore<Todo>.Configuration()
configuration.conflictResolver = .serverWins
let store = try OfflineStore<Todo>(name: "todos", transport: transport, configuration: configuration)
```

## Built-in policies

| Resolver                         | Result                                                                        |
| -------------------------------- | ----------------------------------------------------------------------------- |
| ``ConflictResolver/lastWriteWins`` | The newer ``HLCTimestamp`` wins. The default.                                   |
| ``ConflictResolver/serverWins``    | The server's version always wins.                                             |
| ``ConflictResolver/clientWins``    | The device's version always wins.                                             |
| ``ConflictResolver/merge(_:)``     | Your function combines both versions; deletions fall back to last write wins. |
| ``ConflictResolver/mergeable``     | The record's own ``Mergeable/merged(with:)``.                                   |

Last write wins compares hybrid logical clock timestamps, not plain dates. A
``HybridLogicalClock`` never goes backwards when the user changes the device time, moves past
every timestamp it receives, and orders writes from the same millisecond by a counter and the
device ID, so all devices agree on the winner. A server timestamp more than
``OfflineStore/Configuration/maximumClockDrift`` ahead of the device clock does not move the
clock, so one device with a wrong clock cannot make its edits win forever.

## Merging fields

When different fields of a record change on different devices, merge them:

```swift
let keepTicks = ConflictResolver<Todo>.merge { local, remote in
    var merged = remote
    merged.isDone = local.isDone || remote.isDone
    return merged
}
```

For values that many devices change at the same time, use the conflict-free types as fields:
``LWWRegister`` (newest write per field), ``LWWMap`` (newest write per key), ``GCounter`` and
``PNCounter`` (counts from every device add up), and ``ORSet`` (adds and removes from every
device survive). Their merge is commutative, associative and idempotent, so every device ends up
with the same value whatever order the changes arrive in:

```swift
struct Checklist: SyncableRecord, Mergeable {
    var id: UUID
    var items: ORSet<String>
    var views: GCounter

    func merged(with other: Checklist) -> Checklist {
        Checklist(id: id, items: items.merged(with: other.items), views: views.merged(with: other.views))
    }
}

configuration.conflictResolver = .mergeable
```

## Limits

A resolver that returns a record with another ID is ignored and the server's version is kept.
If the server answers every push of a record with a new conflict, the store stops pushing that
record after three attempts in one sync and tries again in the next one.
