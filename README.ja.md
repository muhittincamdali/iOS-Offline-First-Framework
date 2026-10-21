<!-- i18n-source: README.md@17ca3fe66e195ea475a0b15e41fc1d8962c24ea6 status=reviewed -->
<!-- brand:start -->

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-ja-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-ja-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-ja-light.svg" alt="Offline-First Framework: オフラインでも動き続け、サーバーと同期する Swift アプリ向けのローカルストア。"></picture></p>

<!-- lang-selector:start -->
<p align="center"><a href="README.md">English</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a></p>
<!-- lang-selector:end -->

<p align="center">
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml"><img src="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml/badge.svg" alt="CI ステータス"></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/releases"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg" alt="最新バージョン: v2.0.0"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg" alt="対応プラットフォーム: iOS 17+ · macOS 14+ · tvOS 17+ · watchOS 10+ · visionOS 1+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg" alt="言語バージョン: Swift 6.2+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/LICENSE"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg" alt="ライセンス: MIT"></picture></a>
</p>

<p align="center">
<a href="#クイックスタート"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-ja-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-ja-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-ja-light.svg" alt="はじめる"></picture></a>
<a href="https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-ja-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-ja-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-ja-light.svg" alt="ドキュメント"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/tree/master/Examples"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-ja-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-ja-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-ja-light.svg" alt="サンプル"></picture></a>
</p>

> このドキュメントは英語版 README の翻訳です。内容が異なる場合は英語版が最新です。

<!-- brand:end -->
アプリのレコードをデバイス上のファイルに保存し、すべての変更をキューに積み、接続できるときにサーバーと同期する Swift パッケージです。保存はネットワークを待たないため、飛行機の中でも、地下室でも、接続が不安定な電車の中でも、アプリは同じように動作します。同じレコードが 2 台のデバイスで変更された場合は、選択した競合ポリシーに従って、どちらを残すかが決まります。どのバックエンドとも連携できます。リファレンスサーバーのある小さな HTTP プロトコル、2 つの関数からなるプロトコルを介した独自の API、テストやプレビュー用のインメモリサーバーのいずれかを使えます。このパッケージに依存関係はありません。

## 主な特長

- **待たされない書き込み** — `save` と `delete` は、アトミックに書き込まれるファイルと、再起動後も残る永続的な保留中の変更キューに書き込まれます。失敗したプッシュは指数バックオフ（exponential backoff）とジッター（jitter）で再試行され、最後の試行のあとも失われることなく保留として退避されます。
- **意図して決める競合解決** — ハイブリッド論理クロックのタイムスタンプによる後勝ち（タイムスタンプは決して逆戻りせず、すべてのデバイスに同じ順序を与えます）、サーバー優先、クライアント優先、独自のマージ、または競合の起きないフィールド（`LWWRegister`、`LWWMap`、`GCounter`、`PNCounter`、`ORSet`）から選べます。
- **任意のバックエンド** — `HTTPSyncTransport` は、文書化された JSON プロトコルを使います。[`Examples/SyncServer`](Examples/SyncServer) のリファレンスサーバーは、約 280 行の JavaScript でこのプロトコルを実装しています。ほかの API も `SyncTransport` の背後に置けます。たとえば ETag を使う REST API です。
- **SwiftUI 向けに設計** — `SyncedCollection` はストアの `@Observable` モデルです。自動同期は、デバイスがオンラインになったときとローカルでの編集の直後に実行され、バックグラウンドリフレッシュのタスクからは 1 回の呼び出しで同期できます。
- **保存データを保護** — Keychain に保管したキーによる AES-GCM のファイル暗号化、データ保護クラス、レコードスキーマのマイグレーション、破損したファイルに対するポリシーを備えています。
- **実際のサーバーに対してテスト済み** — macOS と iPhone シミュレータで 311 件の Swift Testing テスト（すべての競合ポリシーをリクエストの消失、再起動、トークンのリセット、重なった同期、小さなページ上限、古いページ、同時に走る操作、クラッシュにさらす 2 つのプロパティテストと、使えないデータばかりのページ、非常に深く入れ子になったレコード、応答の上限より大きいページ、要求より多くの変更を含むページを、ソケット経由で終わりなく流すものも含めて送るテストを含む）、サーバー用の 28 件の Node テスト、そして CI ではストアを HTTP 経由でサーバーを通して同期し、250 KiB のレコード 68 件をサーバーの再起動をまたいでも扱い、合計で応答の上限を超える 250 KiB の競合応答 70 件も扱い、保存に失敗した書き込みを再起動後にも確かめ、504 を返すプロキシの背後でサーバーが適用したプッシュや、トークンのリセット後に再起動前のページを返すレプリカも扱うエンドツーエンドのテストスイートを実行しています。

### 含まれるもの

| 分類                 | 型                                                                                                                   |
| -------------------- | -------------------------------------------------------------------------------------------------------------------- |
| ストア               | `OfflineStore`, `SyncableRecord`, `SyncStatus`, `SyncReport`, `StoreState`, `PendingChange`                          |
| サーバー接続         | `SyncTransport`, `HTTPSyncTransport`, `InMemorySyncServer`, `OutgoingChange`, `RemoteChange`, `PushOutcome`          |
| 競合                 | `ConflictResolver`, `Conflict`, `ConflictResolution`, `Mergeable`                                                    |
| 競合しないフィールド | `LWWRegister`, `LWWMap`, `GCounter`, `PNCounter`, `ORSet`                                                            |
| 同期の制御           | `RetryPolicy`, `CircuitBreaker`, `ConnectivityMonitor`, `NetworkConnectivityMonitor`, `SimulatedConnectivity`        |
| 保存                 | `FileStore`, `InMemoryStorage`, `StorageBackend`, `StoreEncryption`, `KeychainStore`, `RecordMigration`, `JSONValue` |
| クロック             | `HybridLogicalClock`, `HLCTimestamp`, `VectorClock`                                                                  |
| SwiftUI              | `SyncedCollection`                                                                                                   |

## クイックスタート

**1. パッケージを追加する**

Xcode で **File › Add Package Dependencies…** を選び、リポジトリの URL を入力します。

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

ウィンドウ右上の検索欄に貼り付けます。**Dependency Rule** は `2.0.0` からの **Up to Next Major Version** のままにして、**Add Package** をクリックします。次のウィンドウで、**OfflineFirstFramework** の横にあるアプリのターゲットを選び、もう一度 **Add Package** をクリックします。

**2. モジュールをインポートする**

```swift
import OfflineFirstFramework
```

この行は、ストアを使う Swift ファイルの先頭、`import SwiftUI` の隣に置きます。

**3. 使ってみる**

新しい Xcode アプリ（**File › New › Project… › App**、iOS 17 以降）で、`ContentView.swift` の内容をすべて次のものに置き換えます。

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

**Run**（⌘R）を押します。To-Do を入力して Return を押すと、すぐに表示されてデバイスに保存され、ツールバーに **1 to sync** と表示されます。リストを下に引っ張って同期すると、カウンターは 0 に戻ります。アプリを終了して開き直しても、To-Do はそのまま残っています。`InMemorySyncServer` は、バックエンドを接続するまでの代わりを務めます（[使い方](#使い方)を参照）。

## インストール

### Swift Package Manager

Xcode で **File › Add Package Dependencies…** を選び、リポジトリの URL を入力します。

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

または `Package.swift` の `dependencies` に追加します。

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

バージョン 2.0 は、依存関係として解決できなかった 1.0.0 の API を置き換えるものです。変更点は[変更履歴](CHANGELOG.md)にまとめています。

## 使い方

以下のサンプルはすべて、[`ReadmeSamples.swift`](Examples/OfflineTodos/OfflineTodos/ReadmeSamples.swift) からコピーしたものです。このファイルはサンプルアプリがビルドし、テストスイートが実行します。

### HTTP でサーバーと同期する

サーバーが[サーバープロトコル](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)の 2 つのエンドポイント（`POST <base>/push` と `GET <base>/changes?since=<token>`）を実装している場合は、HTTP transport を使います。`headers` クロージャはリクエストごとに実行されるため、新しいアクセストークンを取得できます。

```swift
let transport = HTTPSyncTransport<Todo>(
    baseURL: URL(string: "http://localhost:8080/sync/todos")!,
    headers: { ["Authorization": "Bearer \(try await token())"] }
)
let store = try OfflineStore<Todo>(name: "todos", transport: transport)
```

`http://localhost:8080` は、`node Examples/SyncServer/server.mjs` でリファレンスサーバーを起動したときに待ち受けるアドレスです。ご自身のサーバーの URL に置き換えてください。

### 既存の API に接続する

どの API も `SyncTransport` の背後に置けます。1 つの関数がローカルの変更を送信して変更ごとの結果を返し、もう 1 つの関数が変更トークン以降のサーバーの変更を返します。次の例は、ETag でレコードのバージョンを管理する REST API にストアを対応させたものです。

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

transport が従うべきルール（revision、再試行、冪等性、削除、変更トークン）は、記事[サーバーに接続する](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md)にまとめています。

### 競合を解決する

デフォルトは後勝ちです。両方のバージョンの一部を残したい場合は、マージします。

```swift
/// A to-do counts as done if either device ticked it; the server's title wins.
static let keepTicks = ConflictResolver<Todo>.merge { local, remote in
    var merged = remote
    merged.isDone = local.isDone || remote.isDone
    return merged
}
```

これを `configuration.conflictResolver` として渡します（次のサンプルを参照）。ほかのポリシーと競合しないフィールド型は、記事[競合を解決する](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)で説明しています。

### ファイルを暗号化して古いレコードをマイグレーションする

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

### 自動で同期する

```swift
await TodoStore.shared.startAutomaticSync()
```

これ以降、ストアはデバイスがオンラインになったとき、ローカルの変更から 2 秒後、失敗した変更の再試行時刻になったとき、そしてオンライン中は 5 分ごとに同期します。エラーは `SyncedCollection.status` と `lastError` に表示されます。アプリがバックグラウンドにあるときの同期については、[バックグラウンドで同期する](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md)を参照してください。

### バックエンドなしでテストする

`InMemorySyncServer` はサーバーと同じように動作します（revision、競合、ページ分割されたプル、オフラインスイッチ）。そのため、ユニットテストでは 2 つのストアを 2 台のデバイスに見立てられます。

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

## 保証と制限

サーバーが[プロトコル](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)に従っている限り、ストアはどの競合ポリシーでも、リクエストの消失、応答の消失、アプリとサーバーの再起動、古いページがあっても、次の約束を守ります。

- 保存や削除は呼び出しが戻る前にファイルに書き込まれ、キューに入った変更はサーバーが応答するまでプッシュされます。再試行では変更 ID が変わらないため、サーバーはそれを一度だけ適用します。変更を確定させるのは読み取れた応答だけです。エラーステータス、切れた接続、読み取れないほど長い応答の後は、変更は次のプッシュまで未確定（in doubt）のままです。
- 古いコピーが、サーバーが受け入れた書き込みを置き換えることはありません。リゾルバーが呼ばれるのはレコードがこのデバイスと別のデバイスの両方で変更された場合だけで、サーバーの古いバージョンは、デバイス自身の書き込みが受け入れられた直後でも、デバイスがまだ気づいていないサーバーの再起動をまたいでも、`resetChangeToken()` の後でもスキップされます。
- サーバーの別の epoch は、1 回の同期の 2 つのリクエスト、つまりトークン付きの取得と最初からの取得の両方が報告したときだけ有効になります。そのため、古いキャッシュや同じ URL の背後にある別のデプロイがストアを巻き戻すことはできません。1 ページだけ取得する同期でもサーバーの再起動に追従し、2 つのリクエストが食い違うときは成功を報告せずに同期が失敗します。epoch は一方向にしか進みません。ストアがより後の epoch のために離れた epoch は、`resetChangeToken()` の後でも二度と受け入れられないため、両方のリクエストに応答する古いレプリカやキャッシュもストアを巻き戻せません。
- 削除されたレコードは削除されたままです。データを失ったサーバーや別のサーバーに対しては、ストアが保留中の変更を残したまますべてを最初から取得し直し、保留中の変更はページではなく自分のプッシュへの応答を通じて新しい履歴と出会います。アプリがデコードできないレコードや 64 階層より深く入れ子になったレコードは、取得を止めず、`quarantinedChanges()` に取り分けられます。
- サーバーの応答にかかるコストは限られます。64 階層より深く入れ子になったレコードはストアに入らないため、ファイルの書き込みでスタックがあふれることはありません。使えないデータばかりのページや、取得が求めたより多くの変更（最大 1,000 件）を含むページは、ギガバイト単位のメモリを使う代わりに数ミリ秒で拒否され、ダウンロードも中止されます。応答の上限より大きいページでは取得がより少ない変更を求め、単独で上限を超える変更は上限の 4 倍まで取り分けられます。プッシュはサーバーのボディ上限に収まるリクエストに分割され、サーバーが 413 を返すか 2xx の応答が応答の上限より長い間は、追加のリクエスト 16 件までで半分ずつ送り直され、単独の応答が上限より長い変更は未確定のまま残り、エラーステータスの応答は最初の 4 KiB だけが読まれるので、不調なゲートウェイは失敗した 1 回の試行で済み、UTF-8 のバイトオーダーマークも読み取られます。
- 進んだ時計や戻された時計、すべてのプッシュに競合で応答するサーバー、まったく応答しないサーバー、書き込めないファイルの影響は限られます。リファレンスサーバーはプッシュされたタイムスタンプを自分の時計より最大でも 5 分先までに抑え、デバイスの時計が一瞬だけずれてもその時刻は後の書き込みに引き継がれず、再試行は間隔を空けたうえで保留され、同期は `syncTimeout` が過ぎると終了し、ファイルに書き込めない間は同期が待機します。

サーバーは同じ revision をレコードの 2 つのバージョンに与えてはならず、より後のものにだけ進み、決して戻らない `epoch`（より長いか、同じ長さならバイト単位で大きいもの）、再起動後も数え続ける `sequence`、プッシュされたタイムスタンプ（自分の時計より大きく先の時刻は上限まで戻したもの）と各バージョンを書き込んだ `changeID` を送るべきで、変更 ID を再起動後も覚えておき、書き込みは保存してからページに出し、各ページとプッシュした各変更への応答をクライアントの応答上限に収める（1 ページは最大 `limit` 件の変更、バイト数でも区切り、1 ページに少なくとも 1 件）必要があります。制限: サーバーがバックアップからの復元で失った書き込みは再アップロードされない、`discardChange(for:)` の直後に保存し直したレコードはサーバーのコピーと競合として出会う、1 つのファイルにつきストアのインスタンスは 1 つ（`FileStore`、`InMemoryStorage`、`claimIdentity` を返す独自のバックエンドでは強制される）、変更のたびにファイル全体が書き込まれる、レコードの入れ子は 64 階層まで、1 ページの変更は最大 1,000 件、応答上限の 4 倍を超える単独の変更は取得を止める、プッシュへの応答が単独で応答上限を超える変更は未確定のまま残り、最後の試行の後に保留される、ストアが離れた epoch はサーバーが新しい epoch を報告するまで拒否され続ける、ストアが一度も持たなかった epoch で 8 回続けて同期に応答するレプリカは、サーバーが再び応答するまでその古いレコードを見せる、10,000 件を超える削除は忘れられる。完全な一覧は[保証と制限](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/GuaranteesAndLimits.md)にあります。

## デモ

| 同期済み                                                                   | オフライン、2 件の変更が待機中                                                |
| -------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| ![同期済みの To-Do リスト（ライト）](docs/images/example-synced-light.png) | ![オフラインの To-Do リスト（ライト）](docs/images/example-offline-light.png) |
| ![同期済みの To-Do リスト（ダーク）](docs/images/example-synced-dark.png)  | ![オフラインの To-Do リスト（ダーク）](docs/images/example-offline-dark.png)  |

スクリーンショットは、iPhone シミュレータ上の [OfflineTodos](Examples/OfflineTodos) サンプルアプリを [`scripts/capture-example-screens.sh`](scripts/capture-example-screens.sh) で撮影したものです。アプリで **Online** をオフにして To-Do をいくつか編集し、再びオンにすると、変更が同期される様子を確認できます。**Edit on another device** は、同じサーバーにつながるもう 1 つのストアから To-Do を変更します。`Examples/OfflineTodos/OfflineTodos.xcodeproj` を開き、iPhone シミュレータまたは **My Mac** を選んで **Run** を押してください。詳細は [Examples/README.md](Examples/README.md) を参照してください。

## ドキュメント

API リファレンスと解説記事：

- [API リファレンス](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/)
  （DocC。`master` から GitHub Pages に公開されます）
- Xcode では **Product › Build Documentation** で、またはコマンドラインからローカルでビルドできます。

```sh
xcodebuild docbuild -scheme OfflineFirstFramework -destination 'generic/platform=macOS'
```

## ガイド

- [はじめに](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/gettingstarted)
  — パッケージの追加、レコードの定義、ストアのオープン、SwiftUI での表示
  （[ソース](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/GettingStarted.md)）。
- [サーバーに接続する](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/connectingtoyourserver)
  — HTTP transport、独自 transport のルール、インメモリサーバー
  （[ソース](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md)）。
- [サーバープロトコル](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/serverprotocol)
  — バックエンド開発者向けに、push と pull のリクエストの全フィールドを解説
  （[ソース](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)）。
- [競合を解決する](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/resolvingconflicts)
  — ポリシー、ハイブリッド論理クロック、フィールドのマージ、競合しない型
  （[ソース](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)）。
- [バックグラウンドで同期する](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/syncinginthebackground)
  — 自動同期、再試行、サーキットブレーカー（circuit breaker）、バックグラウンドリフレッシュのタスク
  （[ソース](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md)）。
- [データの保護とマイグレーション](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/protectingandmigratingdata)
  — ファイルの保存場所、暗号化、スキーマのマイグレーション、破損したファイル
  （[ソース](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ProtectingAndMigratingData.md)）。

## 動作要件

| プラットフォーム | 最小バージョン |
| ---------------- | -------------- |
| iOS              | 17             |
| macOS            | 14             |
| tvOS             | 17             |
| watchOS          | 10             |
| visionOS         | 1              |
| | ツールチェーン | Swift 6.2 · Xcode 26+ |         |

リファレンスサーバーには Node 24 以降が必要です。

## アーキテクチャ

- `OfflineStore` は 1 つのコレクションを所有する actor です。その状態（レコード、保留中の変更、変更トークン、クロック）は 1 つの JSON ファイルとして書き込まれます。すべての変更はコピーに対して実行され、書き込みが成功した後にはじめてコピーが現在の状態になるため、クラッシュやディスクの空き容量不足で、変更が中途半端に適用された状態が残ることはありません。各レコードは、サーバーの revision、最後のタイムスタンプ、そして未同期の間は、ローカルで編集するたびに変わる ID を持つ保留中の変更を 1 件保持します。
- 同期では、保留中の変更を（古いものから順に、基にした revision とともに）バッチで送信し、それぞれの結果を適用してから、保存された変更トークン以降のサーバーの変更をページ単位で取得します。デバイスとサーバーの両方で変更されたレコードが `ConflictResolver` に渡され、サーバーの古いバージョンはスキップされます。プッシュの実行中に行われた編集は保持され、次回にプッシュされます。
- `Sync/` には transport プロトコル、HTTP とインメモリの transport、再試行ポリシー、サーキットブレーカー（circuit breaker）、接続監視が、`Storage/` にはファイルと Keychain のストア、暗号化、マイグレーションが、`Clock/` と `CRDT/` には順序付けとマージのための値型が、`SwiftUI/` には observable なモデルがあります。参照型は `OfflineStore`、`InMemorySyncServer`、`SyncedCollection` だけです。
- ストアは、不正な動作をするサーバーや破損したファイルから身を守ります。キュー、ページ、レスポンス、revision、変更トークンのサイズの上限、必ず進まなければならない変更トークン、1 レコード・1 回の同期あたり最大 3 回のプッシュ、ID が一致せず無視されるレコード、許容されるクロックのずれを超えるタイムスタンプ、ディレクトリの外に出られないファイル名がそれにあたります。テストはこれらのそれぞれをカバーしています。
- 変更のたびにファイル全体を書き直すため、ストアあたり数万件までのレコードを持つコレクションに向いています。

テストをローカルで実行します。

```sh
swift test                                          # macOS
xcodebuild test -scheme OfflineFirstFramework \
  -destination 'platform=iOS Simulator,name=iPhone 17'
(cd Examples/SyncServer && npm test)                # reference server
node Examples/SyncServer/server.mjs &               # end to end, against the server
OFFLINE_FIRST_SERVER_URL=http://localhost:8080 swift test --filter EndToEnd
OFFLINE_FIRST_NODE=$(command -v node) swift test --filter ServerSaveTests  # a failed save, a restart
```

## ロードマップ

- 変更のたびに書き直すには大きすぎるコレクション向けの、SQLite を使うストレージバックエンド。
- 独自のサーバーを持たないアプリ向けの、CloudKit（`CKSyncEngine`）を使う transport。
- コレクションの一部だけ（たとえば 1 つのプロジェクトのレコード）のプル。
- Swift Package Index へのパッケージの登録。`.spi.yml` はすでにリポジトリにあります。

## コントリビューション

コントリビューションを歓迎します。pull request を作成する前に[コントリビューションガイド](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/CONTRIBUTING.md)と[行動規範](https://github.com/muhittincamdali/.github/blob/main/CODE_OF_CONDUCT.md)をお読みください。セキュリティ上の問題は[セキュリティポリシー](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/SECURITY.md)に従って非公開で報告してください。

## ライセンス

MIT ライセンスで公開しています。詳細は [LICENSE](LICENSE) を参照してください。
