<!-- brand:start -->

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-light.svg" alt="Offline-First Framework: A local store for Swift apps that keeps working offline and syncs with your server."></picture></p>

<!-- lang-selector:start -->
<p align="center"><a href="README.md">English</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a></p>
<!-- lang-selector:end -->

<p align="center">
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml"><img src="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/releases"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg" alt="Latest version: v1.0.0"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg" alt="Supported platforms: iOS 17+ · macOS 14+ · tvOS 17+ · watchOS 10+ · visionOS 1+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg" alt="Language version: Swift 6.2+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/LICENSE"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg" alt="License: MIT"></picture></a>
</p>

<p align="center">
<a href="#quick-start"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-en-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-en-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-en-light.svg" alt="Get started"></picture></a>
<a href="https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-en-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-en-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-en-light.svg" alt="Documentation"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/tree/master/Examples"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-en-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-en-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-en-light.svg" alt="Examples"></picture></a>
</p>

<!-- brand:end -->

A Swift package that keeps your app's records in a file on the device, queues every change,
and syncs with your server whenever there is a connection. Saving never waits for the network,
so the app works the same on a plane, in a basement or on a flaky train connection. When the
same record changed on two devices, a conflict policy you choose decides what is kept. It works
with any backend: a small HTTP protocol with a reference server, your own API through a
two-function protocol, or an in-memory server for tests and previews. The package has no
dependencies.

## Highlights

- **Writes that never wait** — `save` and `delete` go to an atomically written file and a
  durable queue of pending changes that survives restarts; failed pushes are retried with
  exponential backoff and jitter, and parked after the last attempt instead of being lost.
- **Conflicts decided on purpose** — last write wins on hybrid logical clock timestamps (they
  never go backwards and give every device the same order), server wins, client wins, your own
  merge, or conflict-free fields: `LWWRegister`, `LWWMap`, `GCounter`, `PNCounter` and `ORSet`.
- **Any backend** — `HTTPSyncTransport` speaks a documented JSON protocol that the reference
  server in [`Examples/SyncServer`](Examples/SyncServer) implements in about 280 lines of
  JavaScript; any other API fits behind `SyncTransport`, for example a REST API with ETags.
- **Made for SwiftUI** — `SyncedCollection` is an `@Observable` model of a store; automatic
  sync runs when the device comes online and shortly after local edits, and one call syncs from
  a background refresh task.
- **Data at rest protected** — AES-GCM file encryption with a key kept in the Keychain, data
  protection classes, record schema migrations, and a policy for damaged files.
- **Tested against a real server** — 122 Swift Testing tests on macOS and an iPhone simulator,
  15 Node tests for the server, and an end-to-end suite in CI that syncs two stores through the
  server over HTTP.

### What's included

| Area                 | Types                                                                                                   |
| -------------------- | ------------------------------------------------------------------------------------------------------- |
| Store                | `OfflineStore`, `SyncableRecord`, `SyncStatus`, `SyncReport`, `StoreState`, `PendingChange`              |
| Server connection    | `SyncTransport`, `HTTPSyncTransport`, `InMemorySyncServer`, `OutgoingChange`, `RemoteChange`, `PushOutcome` |
| Conflicts            | `ConflictResolver`, `Conflict`, `ConflictResolution`, `Mergeable`                                       |
| Conflict-free fields | `LWWRegister`, `LWWMap`, `GCounter`, `PNCounter`, `ORSet`                                               |
| Sync control         | `RetryPolicy`, `CircuitBreaker`, `ConnectivityMonitor`, `NetworkConnectivityMonitor`, `SimulatedConnectivity` |
| Storage              | `FileStore`, `InMemoryStorage`, `StorageBackend`, `StoreEncryption`, `KeychainStore`, `RecordMigration`, `JSONValue` |
| Clocks               | `HybridLogicalClock`, `HLCTimestamp`, `VectorClock`                                                     |
| SwiftUI              | `SyncedCollection`                                                                                      |

## Quick start

**1. Add the package**

In Xcode, choose **File › Add Package Dependencies…** and enter the repository URL:

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

Paste it into the search field at the top right of the window. Leave **Dependency Rule** at
**Up to Next Major Version** from `2.0.0`, then click **Add Package**. In the next window,
choose your app target next to **OfflineFirstFramework** and click **Add Package** again.

**2. Import the module**

```swift
import OfflineFirstFramework
```

Put this line at the top of the Swift file where you use the store, next to `import SwiftUI`.

**3. Use it**

In a new Xcode app (**File › New › Project… › App**, iOS 17 or later), replace everything in
`ContentView.swift` with:

```swift
import OfflineFirstFramework
import SwiftUI

/// A to-do item. Any `Codable` struct with an `id` can be a record.
struct Todo: SyncableRecord, Hashable {
    var id = UUID()
    var title: String
    var isDone = false
}

enum TodoStore {
    // InMemorySyncServer stands in for a backend; swap in HTTPSyncTransport or your own
    // SyncTransport when you have one. The initializer throws only for an invalid name or a
    // store file it cannot read.
    static let shared = try! OfflineStore<Todo>(name: "todos", transport: InMemorySyncServer<Todo>())
}

struct ContentView: View {
    @State private var todos = SyncedCollection(store: TodoStore.shared)
    @State private var newTitle = ""

    var body: some View {
        NavigationStack {
            List {
                TextField("New to-do", text: $newTitle)
                    .onSubmit {
                        let todo = Todo(title: newTitle)
                        newTitle = ""
                        Task { await todos.save(todo) }
                    }
                ForEach(todos.records) { todo in
                    Text(todo.title)
                }
            }
            .navigationTitle("To-dos")
            .toolbar {
                Text("\(todos.pendingCount) to sync")
            }
            .refreshable { await todos.sync() }
        }
    }
}
```

Press **Run** (⌘R). Type a to-do and press Return: it appears at once and is saved on the
device, and the toolbar shows **1 to sync**. Pull the list down to sync; the counter goes back
to 0. Quit and reopen the app: the to-dos are still there. `InMemorySyncServer` stands in for
your backend until you connect one (see [Usage](#usage)).

## Installation

### Swift Package Manager

In Xcode, choose **File › Add Package Dependencies…** and enter the repository URL:

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

Or add it to the `dependencies` in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/muhittincamdali/iOS-Offline-First-Framework.git", from: "2.0.0")
],
targets: [
    .target(name: "YourApp", dependencies: [
        .product(name: "OfflineFirstFramework", package: "iOS-Offline-First-Framework")
    ])
]
```

Version 2.0 replaces the API of 1.0.0, which could not be resolved as a dependency; the
[changelog](CHANGELOG.md) lists what changed.

## Usage

Every sample below is copied from
[`ReadmeSamples.swift`](Examples/OfflineTodos/OfflineTodos/ReadmeSamples.swift), which the
example app builds and the test suite runs.

### Sync with your server over HTTP

If your server implements the two endpoints of the
[server protocol](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)
(`POST <base>/push` and `GET <base>/changes?since=<token>`), use the HTTP transport. The
`headers` closure runs before every request, so it can fetch a fresh access token:

```swift
let transport = HTTPSyncTransport<Todo>(
    baseURL: URL(string: "http://localhost:8080/sync/todos")!,
    headers: { ["Authorization": "Bearer \(try await token())"] }
)
let store = try OfflineStore<Todo>(name: "todos", transport: transport)
```

`http://localhost:8080` is where the reference server listens when you start it with
`node Examples/SyncServer/server.mjs`; replace it with your server's URL.

### Connect an existing API

Any API fits behind `SyncTransport`: one function sends local changes and reports an outcome
for each, the other returns server changes after a change token. This one maps the store onto
a REST API that versions records with ETags:

```swift
/// A transport for an existing REST API that versions records with ETags:
/// `PUT /todos/<id>` and `DELETE /todos/<id>` with `If-Match`, `GET /todos?since=<token>`.
struct TodoAPI: SyncTransport {
    var baseURL: URL
    var session = URLSession.shared

    func push(_ changes: [OutgoingChange<Todo>]) async throws -> [UUID: PushOutcome<Todo>] {
        var outcomes: [UUID: PushOutcome<Todo>] = [:]
        for change in changes {
            var request = URLRequest(url: baseURL.appending(path: "todos/\(change.recordID)"))
            request.httpMethod = change.record == nil ? "DELETE" : "PUT"
            request.httpBody = try change.record.map { try JSONEncoder().encode($0) }
            request.setValue(change.baseRevision ?? "*", forHTTPHeaderField: change.baseRevision == nil ? "If-None-Match" : "If-Match")
            let (data, response) = try await session.data(for: request)
            let http = response as? HTTPURLResponse
            let etag = http?.value(forHTTPHeaderField: "ETag") ?? ""
            switch http?.statusCode ?? 0 {
            case 200...204:
                outcomes[change.id] = .accepted(revision: etag)
            case 412:
                // The server sends its current version with the failed precondition.
                let current = data.isEmpty ? nil : try JSONDecoder().decode(Todo.self, from: data)
                outcomes[change.id] = .conflict(current: RemoteChange(recordID: change.recordID, record: current, revision: etag, timestamp: nil))
            case 422:
                outcomes[change.id] = .rejected(reason: String(decoding: data, as: UTF8.self), current: nil)
            default:
                // No outcome: the store counts a failed attempt and retries later.
                continue
            }
        }
        return outcomes
    }

    func pull(since token: String?) async throws -> PullResponse<Todo> {
        struct Page: Decodable {
            struct Item: Decodable { var id: UUID; var etag: String; var todo: Todo? }
            var items: [Item]
            var next: String
            var more: Bool
        }
        var url = baseURL.appending(path: "todos")
        if let token { url.append(queryItems: [URLQueryItem(name: "since", value: token)]) }
        let (data, _) = try await session.data(from: url)
        let page = try JSONDecoder().decode(Page.self, from: data)
        let changes = page.items.map { RemoteChange(recordID: $0.id, record: $0.todo, revision: $0.etag, timestamp: nil) }
        return PullResponse(changes: changes, token: page.next, hasMore: page.more)
    }
}
```

The rules a transport has to follow (revisions, retries, idempotency, deletions, change tokens)
are in the article
[Connecting to your server](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md).

### Decide conflicts

The default is last write wins. To keep parts of both versions, merge them:

```swift
/// A to-do counts as done if either device ticked it; the server's title wins.
static let keepTicks = ConflictResolver<Todo>.merge { local, remote in
    var merged = remote
    merged.isDone = local.isDone || remote.isDone
    return merged
}
```

Pass it as `configuration.conflictResolver` (see the next sample). The article
[Resolving conflicts](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)
covers the other policies and the conflict-free field types.

### Encrypt the file and migrate old records

```swift
/// A store with an encrypted file, a custom conflict policy and a schema migration.
static func makeSecureStore(transport: some SyncTransport<Todo>, storage: (any StorageBackend)? = nil) throws -> OfflineStore<Todo> {
    var configuration = OfflineStore<Todo>.Configuration()
    configuration.conflictResolver = keepTicks
    configuration.encryption = try .keychain(account: "todos-key", keychain: KeychainStore(service: "com.example.todos"))
    configuration.schemaVersion = 2
    configuration.migrations = [
        // Version 2 renamed `done` to `isDone`.
        RecordMigration(to: 2) { record in
            record["isDone"] = record["done"] ?? false
            record["done"] = nil
        }
    ]
    return try OfflineStore<Todo>(name: "secure-todos", storage: storage, transport: transport, configuration: configuration)
}
```

### Sync automatically

```swift
await TodoStore.shared.startAutomaticSync()
```

The store then syncs when the device comes online, two seconds after local changes, when a
failed change is due again, and every five minutes while online. Errors show up in
`SyncedCollection.status` and `lastError`. For sync while the app is in the background, see
[Syncing in the background](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md).

### Test without a backend

`InMemorySyncServer` behaves like a server (revisions, conflicts, paged pulls, an offline
switch), so two stores can play two devices in a unit test:

```swift
/// Two devices, one server: the phone writes, the laptop receives the to-do.
static func twoDevices() async throws -> (phone: [Todo], laptop: [Todo]) {
    let server = InMemorySyncServer<Todo>()
    let phone = try OfflineStore<Todo>(name: "phone", storage: InMemoryStorage(), transport: server)
    let laptop = try OfflineStore<Todo>(name: "laptop", storage: InMemoryStorage(), transport: server)

    try await phone.save(Todo(title: "Buy milk"))
    try await phone.sync()
    try await laptop.sync()
    return (await phone.records(), await laptop.records())
}
```

## Demo

| Synced                                                      | Offline, two changes waiting                                   |
| ----------------------------------------------------------- | -------------------------------------------------------------- |
| ![Synced to-do list, light](docs/images/example-synced-light.png) | ![Offline to-do list, light](docs/images/example-offline-light.png) |
| ![Synced to-do list, dark](docs/images/example-synced-dark.png)   | ![Offline to-do list, dark](docs/images/example-offline-dark.png)   |

The screenshots show the [OfflineTodos](Examples/OfflineTodos) example app on an iPhone
simulator, captured by
[`scripts/capture-example-screens.sh`](scripts/capture-example-screens.sh). In the app, switch
**Online** off, edit a few to-dos, and switch it back on to watch the changes sync; **Edit on
another device** changes a to-do from a second store on the same server. Open
`Examples/OfflineTodos/OfflineTodos.xcodeproj`, choose an iPhone simulator or **My Mac**, and
press **Run**; [Examples/README.md](Examples/README.md) has the details.

## Documentation

Reference documentation and articles:

- [API reference](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/)
  (DocC, published to GitHub Pages from `master`)
- Build it locally in Xcode with **Product › Build Documentation**, or from the command line:

```sh
xcodebuild docbuild -scheme OfflineFirstFramework -destination 'generic/platform=macOS'
```

## Guides

- [Getting started](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/gettingstarted)
  — add the package, define a record, open a store, show it in SwiftUI
  ([source](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/GettingStarted.md)).
- [Connecting to your server](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/connectingtoyourserver)
  — the HTTP transport, the rules for your own transport, the in-memory server
  ([source](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md)).
- [Server protocol](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/serverprotocol)
  — every field of the push and pull requests, for backend developers
  ([source](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)).
- [Resolving conflicts](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/resolvingconflicts)
  — policies, hybrid logical clocks, field merges and conflict-free types
  ([source](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)).
- [Syncing in the background](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/syncinginthebackground)
  — automatic sync, retries, the circuit breaker and background refresh tasks
  ([source](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md)).
- [Protecting and migrating data](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/protectingandmigratingdata)
  — where files live, encryption, schema migrations and damaged files
  ([source](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ProtectingAndMigratingData.md)).

## Requirements

| Platform  | Minimum version       |
| --------- | --------------------- |
| iOS       | 17                    |
| macOS     | 14                    |
| tvOS      | 17                    |
| watchOS   | 10                    |
| visionOS  | 1                     |
| Toolchain | Swift 6.2 · Xcode 26+ |

The reference server needs Node 24 or later.

## Architecture

- `OfflineStore` is an actor that owns one collection. Its state (records, pending changes,
  change token, clock) is written as one JSON file; every change runs on a copy that becomes
  current only after the write succeeded, so a crash or a full disk never leaves a half-applied
  change. Each record carries its server revision, its last timestamp and, while unsynced, one
  pending change with an ID that changes with every local edit.
- A sync pushes pending changes in batches (oldest first, with the revision they were based on),
  applies each outcome, then pulls pages of server changes after the saved change token.
  Conflicts from either side go to the `ConflictResolver`. Edits made while a push is on its way
  are kept and pushed next.
- `Sync/` holds the transport protocol, the HTTP and in-memory transports, retry policy,
  circuit breaker and connectivity; `Storage/` the file and Keychain stores, encryption and
  migrations; `Clock/` and `CRDT/` the value types for ordering and merging; `SwiftUI/` the
  observable model. Only `OfflineStore`, `InMemorySyncServer` and `SyncedCollection` are
  reference types.
- The store guards against misbehaving servers and damaged files: bounded queue, page,
  response, revision and change token sizes, a change token that must move, at most three pushes per record and sync,
  ignored records whose ID does not match, timestamps beyond the allowed clock drift, and file
  names that cannot leave their directory. The tests cover each of these.
- The whole file is rewritten on every change, which suits collections up to tens of thousands
  of records per store.

Run the tests locally:

```sh
swift test                                          # macOS
xcodebuild test -scheme OfflineFirstFramework \
  -destination 'platform=iOS Simulator,name=iPhone 17'
(cd Examples/SyncServer && npm test)                # reference server
node Examples/SyncServer/server.mjs &               # end to end, against the server
OFFLINE_FIRST_SERVER_URL=http://localhost:8080 swift test --filter EndToEnd
```

## Roadmap

- A storage backend on SQLite for collections that are too large to rewrite on every change.
- A transport on CloudKit (`CKSyncEngine`) for apps without their own server.
- Pulling only part of a collection (for example one project's records).
- Listing the package on the Swift Package Index; `.spi.yml` is already in the repository.

## Contributing

Contributions are welcome. Read the [contributing guide](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/CONTRIBUTING.md) and the [code of conduct](https://github.com/muhittincamdali/.github/blob/main/CODE_OF_CONDUCT.md) before opening a pull request. Report security issues privately as described in the [security policy](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/SECURITY.md).

## License

Released under the MIT license. See [LICENSE](LICENSE).
