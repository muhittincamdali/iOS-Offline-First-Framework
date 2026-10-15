<!-- i18n-source: README.md@10258518fc1ec3336336d25288bb44d80a78fc2f status=reviewed -->
<!-- brand:start -->

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-zh-CN-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-zh-CN-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-zh-CN-light.svg" alt="Offline-First Framework: 面向 Swift 应用的本地存储：离线照常工作，联网后与你的服务器同步。"></picture></p>

<!-- lang-selector:start -->
<p align="center"><a href="README.md">English</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a></p>
<!-- lang-selector:end -->

<p align="center">
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml"><img src="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml/badge.svg" alt="CI 状态"></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/releases"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg" alt="最新版本: v1.0.0"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg" alt="支持的平台: iOS 17+ · macOS 14+ · tvOS 17+ · watchOS 10+ · visionOS 1+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg" alt="语言版本: Swift 6.2+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/LICENSE"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg" alt="许可证: MIT"></picture></a>
</p>

<p align="center">
<a href="#快速开始"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-zh-CN-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-zh-CN-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-zh-CN-light.svg" alt="开始使用"></picture></a>
<a href="https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-zh-CN-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-zh-CN-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-zh-CN-light.svg" alt="文档"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/tree/master/Examples"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-zh-CN-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-zh-CN-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-zh-CN-light.svg" alt="示例"></picture></a>
</p>

> 本文是英文 README 的译文。如两者内容不一致，以英文版为准。

<!-- brand:end -->
这是一个 Swift 软件包：它把应用的记录保存在设备上的文件里，将每次改动放入队列，并在有网络连接时与你的服务器同步。保存操作从不等待网络，因此应用在飞机上、地下室里或信号时断时续的火车上，表现完全一致。当同一条记录在两台设备上都被修改时，由你选择的冲突策略决定保留哪一份。它可以配合任何后端：带有参考服务器的轻量 HTTP 协议、通过两个函数的协议接入你自己的 API，或者用于测试和预览的内存服务器。该软件包没有任何依赖。

## 亮点

- **写入从不等待** — `save` 和 `delete` 会写入一个以原子方式写出的文件，以及一个重启后依然保留的持久化待同步队列；推送失败时按指数退避（exponential backoff）加抖动（jitter）重试，在最后一次尝试后会被搁置，而不是丢失。
- **有意识地决定冲突** — 基于混合逻辑时钟时间戳的最后写入者优先（时间戳不会倒退，并让每台设备得到相同的顺序）、服务器优先、客户端优先、你自己的合并逻辑，或者无冲突字段：`LWWRegister`、`LWWMap`、`GCounter`、`PNCounter` 和 `ORSet`。
- **任何后端** — `HTTPSyncTransport` 使用一套有文档的 JSON 协议，[`Examples/SyncServer`](Examples/SyncServer) 中的参考服务器用大约 280 行 JavaScript 实现了它；任何其他 API 都可以接在 `SyncTransport` 之后，例如使用 ETag 的 REST API。
- **为 SwiftUI 而生** — `SyncedCollection` 是存储的 `@Observable` 模型；设备联网时以及本地编辑之后不久会自动同步，也可以通过一次调用在后台刷新任务中同步。
- **静态数据受保护** — 使用保存在 Keychain 中的密钥进行 AES-GCM 文件加密、数据保护级别、记录架构迁移，以及针对损坏文件的处理策略。
- **针对真实服务器测试** — 在 macOS 和 iPhone 模拟器上运行 122 个 Swift Testing 测试，为服务器编写了 15 个 Node 测试，并在 CI 中有一套端到端测试，通过 HTTP 经由服务器同步两个存储。

### 内容一览

| 领域       | 类型                                                                                                                 |
| ---------- | -------------------------------------------------------------------------------------------------------------------- |
| 存储       | `OfflineStore`, `SyncableRecord`, `SyncStatus`, `SyncReport`, `StoreState`, `PendingChange`                          |
| 服务器连接 | `SyncTransport`, `HTTPSyncTransport`, `InMemorySyncServer`, `OutgoingChange`, `RemoteChange`, `PushOutcome`          |
| 冲突       | `ConflictResolver`, `Conflict`, `ConflictResolution`, `Mergeable`                                                    |
| 无冲突字段 | `LWWRegister`, `LWWMap`, `GCounter`, `PNCounter`, `ORSet`                                                            |
| 同步控制   | `RetryPolicy`, `CircuitBreaker`, `ConnectivityMonitor`, `NetworkConnectivityMonitor`, `SimulatedConnectivity`        |
| 持久化     | `FileStore`, `InMemoryStorage`, `StorageBackend`, `StoreEncryption`, `KeychainStore`, `RecordMigration`, `JSONValue` |
| 时钟       | `HybridLogicalClock`, `HLCTimestamp`, `VectorClock`                                                                  |
| SwiftUI    | `SyncedCollection`                                                                                                   |

## 快速开始

**1. 添加软件包**

在 Xcode 中选择 **File › Add Package Dependencies…**，然后输入仓库地址：

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

将其粘贴到窗口右上角的搜索框中。把 **Dependency Rule** 保持为从 `2.0.0` 开始的 **Up to Next Major Version**，然后点击 **Add Package**。在接下来的窗口中，在 **OfflineFirstFramework** 旁边选择你的应用 target，再次点击 **Add Package**。

**2. 导入模块**

```swift
import OfflineFirstFramework
```

把这一行放在你使用存储的 Swift 文件顶部，紧挨着 `import SwiftUI`。

**3. 开始使用**

在新建的 Xcode 应用中（**File › New › Project… › App**，iOS 17 或更高版本），将 `ContentView.swift` 中的全部内容替换为：

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

按 **Run**（⌘R）。输入一个待办事项并按回车：它会立刻出现并保存在设备上，工具栏显示 **1 to sync**。下拉列表即可同步，计数器回到 0。退出并重新打开应用：待办事项依然都在。在你连接真正的后端之前，`InMemorySyncServer` 会代替它（参见[使用方法](#使用方法)）。

## 安装

### Swift Package Manager

在 Xcode 中选择 **File › Add Package Dependencies…**，然后输入仓库地址：

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

或者将其添加到 `Package.swift` 的 `dependencies` 中：

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

2.0 版取代了 1.0.0 的 API，而 1.0.0 无法作为依赖被解析；具体改动请见[更新日志](CHANGELOG.md)。

## 使用方法

下面的每个示例都复制自 [`ReadmeSamples.swift`](Examples/OfflineTodos/OfflineTodos/ReadmeSamples.swift)，示例应用会编译它，测试套件也会运行它。

### 通过 HTTP 与你的服务器同步

如果你的服务器实现了[服务器协议](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)的两个端点（`POST <base>/push` 和 `GET <base>/changes?since=<token>`），就使用 HTTP transport。`headers` 闭包会在每次请求之前运行，因此可以获取新的访问令牌：

```swift
let transport = HTTPSyncTransport<Todo>(
    baseURL: URL(string: "http://localhost:8080/sync/todos")!,
    headers: { ["Authorization": "Bearer \(try await token())"] }
)
let store = try OfflineStore<Todo>(name: "todos", transport: transport)
```

`http://localhost:8080` 是你用 `node Examples/SyncServer/server.mjs` 启动参考服务器时它监听的地址；请把它替换为你自己服务器的 URL。

### 连接现有 API

任何 API 都可以接在 `SyncTransport` 之后：一个函数发送本地改动并为每条改动报告结果，另一个函数返回某个变更令牌之后的服务器改动。下面这个示例把存储映射到一个用 ETag 为记录做版本控制的 REST API 上：

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

transport 必须遵守的规则（revision、重试、幂等性、删除、变更令牌）见文章[连接到你的服务器](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md)。

### 决定冲突

默认策略是最后写入者优先。若要同时保留两个版本中的部分内容，请将它们合并：

```swift
/// A to-do counts as done if either device ticked it; the server's title wins.
static let keepTicks = ConflictResolver<Todo>.merge { local, remote in
    var merged = remote
    merged.isDone = local.isDone || remote.isDone
    return merged
}
```

把它作为 `configuration.conflictResolver` 传入（见下一个示例）。文章[解决冲突](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)介绍了其他策略和无冲突字段类型。

### 加密文件并迁移旧记录

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

### 自动同步

```swift
await TodoStore.shared.startAutomaticSync()
```

之后，存储会在设备联网时、本地改动两秒后、失败的改动到了重试时间时，以及联网期间每五分钟同步一次。错误会显示在 `SyncedCollection.status` 和 `lastError` 中。应用在后台时的同步，请参阅[在后台同步](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md)。

### 无需后端即可测试

`InMemorySyncServer` 的行为与真实服务器一致（revision、冲突、分页拉取、离线开关），因此在单元测试中，两个存储就可以扮演两台设备：

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

## 演示

| 已同步                                                          | 离线，有两处改动等待同步                                       |
| --------------------------------------------------------------- | -------------------------------------------------------------- |
| ![已同步的待办列表，浅色](docs/images/example-synced-light.png) | ![离线的待办列表，浅色](docs/images/example-offline-light.png) |
| ![已同步的待办列表，深色](docs/images/example-synced-dark.png)  | ![离线的待办列表，深色](docs/images/example-offline-dark.png)  |

这些截图展示的是 iPhone 模拟器上的 [OfflineTodos](Examples/OfflineTodos) 示例应用，由 [`scripts/capture-example-screens.sh`](scripts/capture-example-screens.sh) 截取。在应用中，关闭 **Online**，编辑几个待办事项，再重新打开它，即可观察改动同步；**Edit on another device** 会通过同一服务器上的第二个存储修改一个待办事项。打开 `Examples/OfflineTodos/OfflineTodos.xcodeproj`，选择一个 iPhone 模拟器或 **My Mac**，然后按 **Run**；详情见 [Examples/README.md](Examples/README.md)。

## 文档

API 参考文档与文章：

- [API 参考](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/)
  （DocC，从 `master` 发布到 GitHub Pages）
- 在 Xcode 中通过 **Product › Build Documentation** 在本地构建，或使用命令行：

```sh
xcodebuild docbuild -scheme OfflineFirstFramework -destination 'generic/platform=macOS'
```

## 指南

- [快速上手](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/gettingstarted)
  — 添加软件包、定义记录、打开存储，并在 SwiftUI 中显示
  （[源文件](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/GettingStarted.md)）。
- [连接到你的服务器](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/connectingtoyourserver)
  — HTTP transport、自定义 transport 的规则、内存服务器
  （[源文件](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md)）。
- [服务器协议](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/serverprotocol)
  — 面向后端开发者的 push 和 pull 请求的每个字段
  （[源文件](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)）。
- [解决冲突](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/resolvingconflicts)
  — 策略、混合逻辑时钟、字段合并和无冲突类型
  （[源文件](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)）。
- [在后台同步](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/syncinginthebackground)
  — 自动同步、重试、断路器（circuit breaker）和后台刷新任务
  （[源文件](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md)）。
- [保护与迁移数据](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/protectingandmigratingdata)
  — 文件存放位置、加密、架构迁移和损坏的文件
  （[源文件](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ProtectingAndMigratingData.md)）。

## 系统要求

| 平台     | 最低版本 |
| -------- | -------- |
| iOS      | 17       |
| macOS    | 14       |
| tvOS     | 17       |
| watchOS  | 10       |
| visionOS | 1        |
| | 工具链 | Swift 6.2 · Xcode 26+ | |

参考服务器需要 Node 24 或更高版本。

## 架构

- `OfflineStore` 是一个 actor，拥有一个集合。它的状态（记录、待同步改动、变更令牌、时钟）会写成一个 JSON 文件；每次改动都在一份副本上进行，只有写入成功后该副本才会成为当前状态，因此崩溃或磁盘写满都不会留下只应用了一半的改动。每条记录都带有它的服务器 revision、最后一个时间戳，并且在尚未同步时带有一条待同步改动，其 ID 会随每次本地编辑而改变。
- 一次同步会分批推送待同步改动（最旧的优先，并附上它们所基于的 revision），应用每个结果，然后在已保存的变更令牌之后分页拉取服务器改动。来自任一方的冲突都交给 `ConflictResolver`。推送进行期间所做的编辑会被保留，并在下一次推送。
- `Sync/` 包含 transport 协议、HTTP 与内存 transport、重试策略、断路器（circuit breaker）和连接状态；`Storage/` 包含文件与 Keychain 存储、加密和迁移；`Clock/` 与 `CRDT/` 是用于排序和合并的值类型；`SwiftUI/` 是可观察模型。只有 `OfflineStore`、`InMemorySyncServer` 和 `SyncedCollection` 是引用类型。
- 存储会防范行为异常的服务器和损坏的文件：队列、页面、响应、revision 和变更令牌的大小上限，必须前进的变更令牌，每条记录每次同步最多三次推送，ID 不匹配而被忽略的记录，超出允许时钟偏差的时间戳，以及无法跳出其目录的文件名。测试覆盖了其中的每一项。
- 每次改动都会重写整个文件，这适用于每个存储最多几万条记录的集合。

在本地运行测试：

```sh
swift test                                          # macOS
xcodebuild test -scheme OfflineFirstFramework \
  -destination 'platform=iOS Simulator,name=iPhone 17'
(cd Examples/SyncServer && npm test)                # reference server
node Examples/SyncServer/server.mjs &               # end to end, against the server
OFFLINE_FIRST_SERVER_URL=http://localhost:8080 swift test --filter EndToEnd
```

## 路线图

- 基于 SQLite 的存储后端，适用于大到无法每次改动都重写的集合。
- 基于 CloudKit（`CKSyncEngine`）的 transport，适用于没有自己服务器的应用。
- 只拉取集合的一部分（例如某个项目的记录）。
- 将软件包上架到 Swift Package Index；`.spi.yml` 已经在仓库中。

## 参与贡献

欢迎参与贡献。提交 pull request 之前，请先阅读[贡献指南](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/CONTRIBUTING.md)和[行为准则](https://github.com/muhittincamdali/.github/blob/main/CODE_OF_CONDUCT.md)。如发现安全问题，请按照[安全策略](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/SECURITY.md)私下报告。

## 许可证

基于 MIT 许可证发布。详见 [LICENSE](LICENSE)。
