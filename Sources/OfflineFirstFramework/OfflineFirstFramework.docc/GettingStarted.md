# Getting started

Add the package, define a record, open a store and show it in SwiftUI.

## Add the package

In Xcode, choose **File › Add Package Dependencies…**, enter
`https://github.com/muhittincamdali/iOS-Offline-First-Framework.git`, and add the
**OfflineFirstFramework** library to your app target. In a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/muhittincamdali/iOS-Offline-First-Framework.git", from: "2.1.0")
],
targets: [
    .target(name: "MyApp", dependencies: [
        .product(name: "OfflineFirstFramework", package: "iOS-Offline-First-Framework")
    ])
]
```

## Define a record

A record is any `Codable` struct with a stable `id`. Conform it to ``SyncableRecord``:

```swift
import OfflineFirstFramework

struct Todo: SyncableRecord, Hashable {
    var id = UUID()
    var title: String
    var isDone = false
}
```

The `id` must not change, and two records must never share one. `UUID`, `String` and `Int`
identifiers all work.

## Open a store

Create one ``OfflineStore`` per collection and keep it for the life of the app, for example in
a static property:

```swift
enum TodoStore {
    static let shared = try! OfflineStore<Todo>(name: "todos", transport: InMemorySyncServer<Todo>())
}
```

The store keeps its file in `Application Support/OfflineFirst/todos.store`. The initializer
throws only for an invalid name or a file it cannot read (see ``CorruptionPolicy``).
``InMemorySyncServer`` stands in for a backend while you build the app; replace it with
``HTTPSyncTransport`` or your own ``SyncTransport`` later (see <doc:ConnectingToYourServer>).

## Read and write

All store methods are `async` because the store is an actor:

```swift
try await TodoStore.shared.save(Todo(title: "Buy milk"))
let todos = await TodoStore.shared.records()
try await TodoStore.shared.delete(todos[0].id)
```

``OfflineStore/save(_:)`` and ``OfflineStore/delete(_:)`` return as soon as the change is in
the file. ``OfflineStore/pendingChanges()`` lists what still has to reach the server.

## Show it in SwiftUI

``SyncedCollection`` is an observable model that follows the store, including changes that a
sync brings in:

```swift
struct ContentView: View {
    @State private var todos = SyncedCollection(store: TodoStore.shared)

    var body: some View {
        List(todos.records, id: \.id) { todo in
            Text(todo.title)
        }
        .refreshable { await todos.sync() }
    }
}
```

## Sync

Call ``OfflineStore/sync()`` yourself, or let the store do it:

```swift
await TodoStore.shared.startAutomaticSync()
```

Automatic sync runs when the device comes online, two seconds after local changes, when a
failed change is due again, and every five minutes while online. For sync while the app is in
the background, see <doc:SyncingInTheBackground>.
