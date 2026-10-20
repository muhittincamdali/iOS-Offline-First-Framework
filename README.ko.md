<!-- i18n-source: README.md@a2cfe83ca8ddfbb907d4765a50520b1442196ef0 status=reviewed -->
<!-- brand:start -->

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-ko-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-ko-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-ko-light.svg" alt="Offline-First Framework: 오프라인에서도 계속 동작하고 서버와 동기화되는 Swift 앱용 로컬 저장소."></picture></p>

<!-- lang-selector:start -->
<p align="center"><a href="README.md">English</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a></p>
<!-- lang-selector:end -->

<p align="center">
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml"><img src="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml/badge.svg" alt="CI 상태"></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/releases"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg" alt="최신 버전: v2.0.0"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg" alt="지원 플랫폼: iOS 17+ · macOS 14+ · tvOS 17+ · watchOS 10+ · visionOS 1+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg" alt="언어 버전: Swift 6.2+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/LICENSE"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg" alt="라이선스: MIT"></picture></a>
</p>

<p align="center">
<a href="#빠른-시작"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-ko-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-ko-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-ko-light.svg" alt="시작하기"></picture></a>
<a href="https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-ko-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-ko-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-ko-light.svg" alt="문서"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/tree/master/Examples"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-ko-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-ko-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-ko-light.svg" alt="예제"></picture></a>
</p>

> 이 문서는 영어 README의 번역본입니다. 내용이 다를 경우 영어 버전이 최신입니다.

<!-- brand:end -->
앱의 레코드를 기기의 파일에 보관하고, 모든 변경을 큐에 쌓아 두었다가 연결될 때마다 서버와 동기화하는 Swift 패키지입니다. 저장은 네트워크를 기다리지 않으므로 앱은 비행기 안에서도, 지하실에서도, 끊기는 기차 안에서도 똑같이 동작합니다. 같은 레코드가 두 기기에서 바뀌면 직접 고른 충돌 정책이 무엇을 남길지 결정합니다. 어떤 백엔드와도 쓸 수 있습니다. 참조 서버가 있는 작은 HTTP 프로토콜, 함수 두 개짜리 프로토콜로 연결하는 자체 API, 테스트와 미리 보기를 위한 인메모리 서버 중에서 고르면 됩니다. 이 패키지는 의존성이 없습니다.

## 주요 기능

- **기다리지 않는 쓰기** — `save`와 `delete`는 원자적으로 기록되는 파일과, 재시작 후에도 남는 영속적인 대기 중 변경 큐에 기록됩니다. 실패한 푸시는 지수 백오프(exponential backoff)와 지터(jitter)로 재시도하고, 마지막 시도 뒤에는 사라지지 않고 보류 상태로 남습니다.
- **의도에 따라 결정하는 충돌** — 하이브리드 논리 시계 타임스탬프 기준의 마지막 쓰기 우선(타임스탬프는 뒤로 가지 않으며 모든 기기에 같은 순서를 줍니다), 서버 우선, 클라이언트 우선, 직접 작성한 병합, 또는 충돌 없는 필드(`LWWRegister`, `LWWMap`, `GCounter`, `PNCounter`, `ORSet`) 중에서 선택합니다.
- **모든 백엔드** — `HTTPSyncTransport`는 문서화된 JSON 프로토콜을 사용하며, [`Examples/SyncServer`](Examples/SyncServer)의 참조 서버가 약 280줄의 JavaScript로 이를 구현합니다. 그 밖의 API도 `SyncTransport` 뒤에 둘 수 있습니다. 예를 들어 ETag를 쓰는 REST API가 그렇습니다.
- **SwiftUI를 위해 설계** — `SyncedCollection`은 스토어의 `@Observable` 모델입니다. 자동 동기화는 기기가 온라인이 될 때와 로컬 편집 직후에 실행되고, 호출 한 번으로 백그라운드 새로 고침 작업에서도 동기화할 수 있습니다.
- **저장된 데이터 보호** — Keychain에 보관한 키를 쓰는 AES-GCM 파일 암호화, 데이터 보호 클래스, 레코드 스키마 마이그레이션, 손상된 파일을 위한 정책을 제공합니다.
- **실제 서버로 테스트** — macOS와 iPhone 시뮬레이터에서 Swift Testing 테스트 237개(모든 충돌 정책을 요청 유실, 재시작, 오래된 페이지로 시험하는 속성 테스트 포함), 서버용 Node 테스트 20개, 그리고 CI에서 스토어 두 개를 HTTP로 서버를 거쳐 동기화하는 엔드투엔드 테스트 모음을 실행합니다.

### 포함된 항목

| 영역           | 타입                                                                                                                 |
| -------------- | -------------------------------------------------------------------------------------------------------------------- |
| 스토어         | `OfflineStore`, `SyncableRecord`, `SyncStatus`, `SyncReport`, `StoreState`, `PendingChange`                          |
| 서버 연결      | `SyncTransport`, `HTTPSyncTransport`, `InMemorySyncServer`, `OutgoingChange`, `RemoteChange`, `PushOutcome`          |
| 충돌           | `ConflictResolver`, `Conflict`, `ConflictResolution`, `Mergeable`                                                    |
| 충돌 없는 필드 | `LWWRegister`, `LWWMap`, `GCounter`, `PNCounter`, `ORSet`                                                            |
| 동기화 제어    | `RetryPolicy`, `CircuitBreaker`, `ConnectivityMonitor`, `NetworkConnectivityMonitor`, `SimulatedConnectivity`        |
| 저장소         | `FileStore`, `InMemoryStorage`, `StorageBackend`, `StoreEncryption`, `KeychainStore`, `RecordMigration`, `JSONValue` |
| 시계           | `HybridLogicalClock`, `HLCTimestamp`, `VectorClock`                                                                  |
| SwiftUI        | `SyncedCollection`                                                                                                   |

## 빠른 시작

**1. 패키지 추가**

Xcode에서 **File › Add Package Dependencies…**를 선택하고 저장소 URL을 입력하세요.

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

창 오른쪽 위의 검색란에 붙여 넣으세요. **Dependency Rule**은 `2.0.0` 부터의 **Up to Next Major Version**으로 그대로 두고 **Add Package**를 클릭합니다. 다음 창에서 **OfflineFirstFramework** 옆에서 앱 타깃을 고르고 **Add Package**를 다시 클릭하세요.

**2. 모듈 가져오기**

```swift
import OfflineFirstFramework
```

이 줄은 스토어를 사용하는 Swift 파일의 맨 위, `import SwiftUI` 옆에 넣으세요.

**3. 사용하기**

새 Xcode 앱(**File › New › Project… › App**, iOS 17 이상)에서 `ContentView.swift`의 내용을 모두 다음으로 바꾸세요.

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

**Run**(⌘R)을 누르세요. 할 일을 입력하고 Return을 누르면 곧바로 나타나고 기기에 저장되며, 툴바에 **1 to sync**가 표시됩니다. 목록을 아래로 당겨 동기화하면 카운터가 0으로 돌아갑니다. 앱을 종료했다가 다시 열어도 할 일은 그대로 남아 있습니다. `InMemorySyncServer`는 백엔드를 연결하기 전까지 그 자리를 대신합니다([사용법](#사용법) 참고).

## 설치

### Swift Package Manager

Xcode에서 **File › Add Package Dependencies…**를 선택하고 저장소 URL을 입력하세요.

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

또는 `Package.swift`의 `dependencies`에 추가하세요.

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

버전 2.0은 의존성으로 해석할 수 없었던 1.0.0의 API를 대체합니다. 무엇이 바뀌었는지는 [변경 기록](CHANGELOG.md)에 있습니다.

## 사용법

아래 예제는 모두 [`ReadmeSamples.swift`](Examples/OfflineTodos/OfflineTodos/ReadmeSamples.swift)에서 복사한 것으로, 이 파일은 예제 앱이 빌드하고 테스트 모음이 실행합니다.

### HTTP로 서버와 동기화하기

서버가 [서버 프로토콜](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)의 두 엔드포인트(`POST <base>/push`와 `GET <base>/changes?since=<token>`)를 구현했다면 HTTP transport를 사용하세요. `headers` 클로저는 요청마다 먼저 실행되므로 새 액세스 토큰을 가져올 수 있습니다.

```swift
let transport = HTTPSyncTransport<Todo>(
    baseURL: URL(string: "http://localhost:8080/sync/todos")!,
    headers: { ["Authorization": "Bearer \(try await token())"] }
)
let store = try OfflineStore<Todo>(name: "todos", transport: transport)
```

참조 서버를 `node Examples/SyncServer/server.mjs`로 시작하면 `http://localhost:8080` 주소에서 대기합니다. 이 주소는 사용하는 서버의 URL로 바꾸세요.

### 기존 API 연결하기

어떤 API 든 `SyncTransport` 뒤에 둘 수 있습니다. 한 함수는 로컬 변경을 보내고 각 변경의 결과를 알려 주며, 다른 함수는 변경 토큰 이후의 서버 변경을 반환합니다. 다음 예제는 스토어를 ETag로 레코드 버전을 관리하는 REST API에 대응시킵니다.

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

transport가 따라야 하는 규칙(revision, 재시도, 멱등성, 삭제, 변경 토큰)은 문서 [서버에 연결하기](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md)에 있습니다.

### 충돌 결정하기

기본값은 마지막 쓰기 우선입니다. 두 버전의 일부를 모두 남기려면 병합하세요.

```swift
/// A to-do counts as done if either device ticked it; the server's title wins.
static let keepTicks = ConflictResolver<Todo>.merge { local, remote in
    var merged = remote
    merged.isDone = local.isDone || remote.isDone
    return merged
}
```

이것을 `configuration.conflictResolver`로 전달하세요(다음 예제 참고). 다른 정책과 충돌 없는 필드 타입은 문서 [충돌 해결하기](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)에서 다룹니다.

### 파일 암호화와 이전 레코드 마이그레이션

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

### 자동으로 동기화하기

```swift
await TodoStore.shared.startAutomaticSync()
```

그러면 스토어는 기기가 온라인이 될 때, 로컬 변경 2초 뒤, 실패한 변경의 재시도 시각이 되었을 때, 그리고 온라인인 동안 5분마다 동기화합니다. 오류는 `SyncedCollection.status`와 `lastError`에 표시됩니다. 앱이 백그라운드에 있는 동안의 동기화는 [백그라운드에서 동기화하기](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md)를 참고하세요.

### 백엔드 없이 테스트하기

`InMemorySyncServer`는 서버처럼 동작하므로(revision, 충돌, 페이지 단위 가져오기, 오프라인 스위치), 단위 테스트에서 스토어 두 개가 기기 두 대 역할을 할 수 있습니다.

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

## 보장과 한계

서버가 [프로토콜](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)을 따르는 한, 스토어는 어떤 충돌 정책에서든 요청 유실, 응답 유실, 앱과 서버의 재시작, 오래된 페이지에도 다음 약속을 지킵니다.

- 저장이나 삭제는 호출이 반환되기 전에 파일에 기록되고, 큐에 있는 변경은 서버가 응답할 때까지 푸시됩니다. 재시도는 변경 ID를 그대로 쓰므로 서버는 변경을 한 번만 적용합니다.
- 오래된 사본이 서버가 받아들인 쓰기를 대체하는 일은 없습니다. 리졸버는 레코드가 이 기기와 다른 기기 양쪽에서 바뀐 경우에만 호출되고, 서버의 더 오래된 버전은 기기 자신의 쓰기가 받아들여진 직후에도, 기기가 아직 알지 못한 서버 재시작을 거친 뒤에도 건너뜁니다.
- 삭제된 레코드는 삭제된 상태로 남습니다. 데이터를 잃은 서버나 다른 서버를 만나면 스토어는 대기 중 변경을 유지한 채 모든 것을 처음부터 다시 가져옵니다. 앱이 디코딩할 수 없는 레코드는 가져오기를 멈추지 않고 `quarantinedChanges()`로 따로 둡니다.
- 앞서 가거나 뒤로 돌려진 시계, 모든 푸시에 충돌로 응답하는 서버, 전혀 응답하지 않는 서버, 쓸 수 없는 파일의 영향은 제한됩니다. 타임스탬프는 기기가 아는 가장 최근 시각보다 최대 5분 앞선 것으로만 계산되고, 재시도는 간격을 두다가 보류되며, 동기화는 `syncTimeout`이 지나면 끝나고, 파일을 쓸 수 없는 동안에는 동기화가 기다립니다.

서버는 같은 revision을 레코드의 두 버전에 절대 주면 안 되고, 더 나중 것으로만 바뀌는 `epoch`(더 길거나, 길이가 같으면 바이트 단위로 더 큰 것), 재시작 후에도 계속 세는 `sequence`, 푸시받은 타임스탬프를 그대로 보내야 하며, 변경 ID를 재시작 후에도 기억해야 합니다. 한계: 서버가 백업 복원으로 잃은 쓰기는 다시 업로드되지 않고, 파일 하나에 스토어 인스턴스는 하나이며, 변경할 때마다 파일 전체를 쓰고, 10,000건을 넘는 삭제는 잊힙니다. 전체 목록은 [보장과 한계](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/GuaranteesAndLimits.md)에 있습니다.

## 데모

| 동기화됨                                                             | 오프라인, 변경 2건 대기 중                                            |
| -------------------------------------------------------------------- | --------------------------------------------------------------------- |
| ![동기화된 할 일 목록, 라이트](docs/images/example-synced-light.png) | ![오프라인 할 일 목록, 라이트](docs/images/example-offline-light.png) |
| ![동기화된 할 일 목록, 다크](docs/images/example-synced-dark.png)    | ![오프라인 할 일 목록, 다크](docs/images/example-offline-dark.png)    |

스크린샷은 iPhone 시뮬레이터에서 실행한 [OfflineTodos](Examples/OfflineTodos) 예제 앱을 보여 주며, [`scripts/capture-example-screens.sh`](scripts/capture-example-screens.sh)로 캡처했습니다. 앱에서 **Online**을 끄고 할 일을 몇 개 편집한 다음 다시 켜면 변경이 동기화되는 모습을 볼 수 있습니다. **Edit on another device**는 같은 서버의 두 번째 스토어에서 할 일을 변경합니다. `Examples/OfflineTodos/OfflineTodos.xcodeproj` 파일을 열고 iPhone 시뮬레이터나 **My Mac**을 선택한 뒤 **Run**을 누르세요. 자세한 내용은 [Examples/README.md](Examples/README.md)에 있습니다.

## 문서

API 레퍼런스와 문서:

- [API 레퍼런스](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/)
  (DocC, `master`에서 GitHub Pages로 게시)
- Xcode에서 **Product › Build Documentation**으로 로컬에서 빌드하거나 명령줄에서 빌드할 수 있습니다.

```sh
xcodebuild docbuild -scheme OfflineFirstFramework -destination 'generic/platform=macOS'
```

## 가이드

- [시작하기](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/gettingstarted)
  — 패키지 추가, 레코드 정의, 스토어 열기, SwiftUI에 표시하기
  ([소스](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/GettingStarted.md)).
- [서버에 연결하기](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/connectingtoyourserver)
  — HTTP transport, 자체 transport를 위한 규칙, 인메모리 서버
  ([소스](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md)).
- [서버 프로토콜](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/serverprotocol)
  — 백엔드 개발자를 위한 push와 pull 요청의 모든 필드
  ([소스](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)).
- [충돌 해결하기](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/resolvingconflicts)
  — 정책, 하이브리드 논리 시계, 필드 병합, 충돌 없는 타입
  ([소스](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)).
- [백그라운드에서 동기화하기](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/syncinginthebackground)
  — 자동 동기화, 재시도, 서킷 브레이커(circuit breaker), 백그라운드 새로 고침 작업
  ([소스](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md)).
- [데이터 보호와 마이그레이션](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/protectingandmigratingdata)
  — 파일 위치, 암호화, 스키마 마이그레이션, 손상된 파일
  ([소스](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ProtectingAndMigratingData.md)).

## 요구 사항

| 플랫폼   | 최소 버전 |
| -------- | --------- |
| iOS      | 17        |
| macOS    | 14        |
| tvOS     | 17        |
| watchOS  | 10        |
| visionOS | 1         |
| | 툴체인 | Swift 6.2 · Xcode 26+ | |

참조 서버에는 Node 24 이상이 필요합니다.

## 아키텍처

- `OfflineStore`는 컬렉션 하나를 소유하는 actor 입니다. 상태(레코드, 대기 중 변경, 변경 토큰, 시계)는 JSON 파일 하나로 기록됩니다. 모든 변경은 복사본에서 실행되고 기록에 성공한 뒤에야 복사본이 현재 상태가 되므로, 충돌이나 디스크 가득 참으로 변경이 반쯤만 적용된 채 남는 일이 없습니다. 각 레코드는 서버 revision, 마지막 타임스탬프, 그리고 동기화되기 전까지는 로컬 편집마다 바뀌는 ID가 붙은 대기 중 변경 하나를 가집니다.
- 동기화는 대기 중 변경을 (오래된 것부터, 기반이 된 revision과 함께) 일괄로 푸시하고, 각 결과를 적용한 다음, 저장된 변경 토큰 이후의 서버 변경을 페이지 단위로 가져옵니다. 기기와 서버 양쪽에서 바뀐 레코드는 `ConflictResolver`로 넘어가고, 서버의 더 오래된 버전은 건너뜁니다. 푸시가 진행되는 동안 이루어진 편집은 보존되어 다음에 푸시됩니다.
- `Sync/` 에는 transport 프로토콜, HTTP와 인메모리 transport, 재시도 정책, 서킷 브레이커(circuit breaker), 연결 상태가 있고, `Storage/` 에는 파일과 Keychain 스토어, 암호화, 마이그레이션이, `Clock/`과 `CRDT/` 에는 순서 지정과 병합을 위한 값 타입이, `SwiftUI/` 에는 관찰 가능한 모델이 있습니다. 참조 타입은 `OfflineStore`, `InMemorySyncServer`, `SyncedCollection` 뿐입니다.
- 스토어는 오작동하는 서버와 손상된 파일로부터 스스로를 보호합니다. 큐, 페이지, 응답, revision, 변경 토큰 크기의 상한, 반드시 앞으로 나아가야 하는 변경 토큰, 레코드와 동기화당 최대 세 번의 푸시, ID가 일치하지 않아 무시되는 레코드, 허용된 시계 편차를 넘는 타임스탬프, 디렉터리를 벗어날 수 없는 파일 이름이 그 예입니다. 테스트가 이 각각을 다룹니다.
- 변경할 때마다 파일 전체를 다시 쓰므로, 스토어당 수만 개 레코드까지의 컬렉션에 적합합니다.

테스트를 로컬에서 실행하세요.

```sh
swift test                                          # macOS
xcodebuild test -scheme OfflineFirstFramework \
  -destination 'platform=iOS Simulator,name=iPhone 17'
(cd Examples/SyncServer && npm test)                # reference server
node Examples/SyncServer/server.mjs &               # end to end, against the server
OFFLINE_FIRST_SERVER_URL=http://localhost:8080 swift test --filter EndToEnd
```

## 로드맵

- 변경할 때마다 다시 쓰기에는 너무 큰 컬렉션을 위한 SQLite 기반 스토리지 백엔드.
- 자체 서버가 없는 앱을 위한 CloudKit(`CKSyncEngine`) 기반 transport.
- 컬렉션의 일부만 가져오기(예: 프로젝트 하나의 레코드).
- Swift Package Index에 패키지 등록. `.spi.yml`은 이미 저장소에 있습니다.

## 기여하기

기여를 환영합니다. pull request를 열기 전에 [기여 가이드](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/CONTRIBUTING.md)와 [행동 강령](https://github.com/muhittincamdali/.github/blob/main/CODE_OF_CONDUCT.md)을 읽어 주세요. 보안 문제는 [보안 정책](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/SECURITY.md)에 따라 비공개로 제보해 주세요.

## 라이선스

MIT 라이선스로 배포됩니다. 자세한 내용은 [LICENSE](LICENSE)를 참고하세요.
