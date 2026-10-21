# Resolving conflicts

Decide what happens when a record changed on the device and on the server since the last sync.

## Overview

A conflict happens only when a record changed on the device and on the server: the device pushes
a change based on an old server revision, or a pull brings a newer server version of a record
that still has a local change waiting. Both changes can be deletions. A server version older
than the one the store holds (a page out of order, a lagging replica, an earlier version of a
deleted record) is not a conflict: the store skips it, whatever the resolver, and a record
without a local change simply takes the server's newer version. Neither is a version the device
wrote itself, such as a push the server applied although its answer was lost: the change made
on top of it goes out again on its revision without asking the resolver. The store tells older
from newer only by the server's ``RemoteChange/sequence`` (see <doc:ServerProtocol>), never by
timestamps, which device clocks write, and keeps deletions as tombstones, the newest
``OfflineStore/Configuration/maximumTombstones`` of them, so an older version of a deleted
record does not bring it back. From a server without sequences a pull cannot tell a newer
version from a stale copy: it leaves a waiting local change to its push, and the resolver meets
the version the server names in its conflict answer. The store hands both versions to its
``ConflictResolver`` as a ``Conflict`` and acts on the ``ConflictResolution``:

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
every timestamp it receives within its drift limit, and orders writes from the same millisecond
by a counter and the device ID, so all devices agree on which of two timestamps is newer. A
server timestamp more than ``OfflineStore/Configuration/maximumClockDrift`` ahead of the device
clock does not move the clock, and the store weighs it against local writes as if it were at
that limit, so one wrong timestamp cannot win every later conflict. The limit counts from the
newest timestamp the store holds when that is later than the device clock: on a device whose
clock was set back, a newer edit from another device stays newer than the device's own older
edit. A device whose own clock runs ahead still stamps its writes with that time and wins the
conflicts it resolves itself, and one whose clock is behind stamps its edits before the newer
ones it received from correct clocks, so with last write wins its concurrent edits lose to
those until its clock catches up. If devices with wrong clocks are a concern, use
``ConflictResolver/serverWins`` or a merge.

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
A push the server answers with a conflict counts as a failed attempt of the
``OfflineStore/Configuration/retryPolicy``. The resolved version goes out again right away once
per sync; if that push conflicts too, it waits for its retry date, and after the last attempt
it is parked in ``OfflineStore/failedChanges()``. So a server that answers every push with a
conflict, or two devices that both keep their own version with
``ConflictResolver/clientWins``, cannot keep the store pushing.
