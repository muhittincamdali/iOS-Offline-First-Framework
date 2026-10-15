<!-- i18n-source: README.md@10258518fc1ec3336336d25288bb44d80a78fc2f status=reviewed -->
<!-- brand:start -->

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-ru-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-ru-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-ru-light.svg" alt="Offline-First Framework: Локальное хранилище для Swift-приложений: работает без сети и синхронизируется с вашим сервером."></picture></p>

<!-- lang-selector:start -->
<p align="center"><a href="README.md">English</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a></p>
<!-- lang-selector:end -->

<p align="center">
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml"><img src="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml/badge.svg" alt="Статус CI"></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/releases"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg" alt="Последняя версия: v1.0.0"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg" alt="Поддерживаемые платформы: iOS 17+ · macOS 14+ · tvOS 17+ · watchOS 10+ · visionOS 1+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg" alt="Версия языка: Swift 6.2+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/LICENSE"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg" alt="Лицензия: MIT"></picture></a>
</p>

<p align="center">
<a href="#быстрый-старт"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-ru-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-ru-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-ru-light.svg" alt="Начать"></picture></a>
<a href="https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-ru-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-ru-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-ru-light.svg" alt="Документация"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/tree/master/Examples"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-ru-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-ru-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-ru-light.svg" alt="Примеры"></picture></a>
</p>

> Это перевод README на английском языке. Если они расходятся, актуальна английская версия.

<!-- brand:end -->
Swift-пакет, который хранит записи вашего приложения в файле на устройстве, ставит каждое изменение
в очередь и синхронизируется с вашим сервером, когда есть соединение. Сохранение никогда не ждёт
сеть, поэтому приложение одинаково работает в самолёте, в подвале и на нестабильном соединении в
поезде. Если одна и та же запись изменилась на двух устройствах, то, что сохранится, решает
выбранная вами политика разрешения конфликтов. Пакет работает с любым бэкендом: небольшим
HTTP-протоколом с эталонным сервером, вашим собственным API через протокол из двух функций или
серверной частью в памяти для тестов и превью. У пакета нет зависимостей.

## Основные возможности

- **Запись, которая никогда не ждёт** — `save` и `delete` попадают в атомарно записываемый файл и в
  надёжную очередь ожидающих изменений, которая переживает перезапуски; неудачные отправки
  повторяются с экспоненциальной задержкой (exponential backoff) и джиттером (jitter), а после
  последней попытки откладываются, а не теряются.
- **Конфликты, решаемые осознанно** — побеждает последняя запись по меткам времени гибридных
  логических часов (они никогда не идут назад и дают всем устройствам одинаковый порядок),
  побеждает сервер, побеждает клиент, ваше собственное слияние или поля без конфликтов:
  `LWWRegister`, `LWWMap`, `GCounter`, `PNCounter` и `ORSet`.
- **Любой бэкенд** — `HTTPSyncTransport` использует документированный JSON-протокол, который
  эталонный сервер из [`Examples/SyncServer`](Examples/SyncServer) реализует примерно в 280 строках
  JavaScript; любой другой API помещается за `SyncTransport`, например REST API с ETag.
- **Создан для SwiftUI** — `SyncedCollection` — это `@Observable`-модель хранилища; автоматическая
  синхронизация запускается, когда устройство выходит в сеть, и вскоре после локальных правок, а один
  вызов синхронизирует из фоновой задачи обновления.
- **Данные в покое защищены** — шифрование файлов AES-GCM с ключом в Keychain, классы защиты данных,
  миграции схемы записей и политика для повреждённых файлов.
- **Проверено на настоящем сервере** — 122 теста Swift Testing на macOS и в симуляторе iPhone, 15
  тестов Node для сервера и набор сквозных тестов в CI, который синхронизирует два хранилища через
  сервер по HTTP.

### Что входит

| Область                   | Типы                                                                                                                 |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Хранилище                 | `OfflineStore`, `SyncableRecord`, `SyncStatus`, `SyncReport`, `StoreState`, `PendingChange`                          |
| Подключение к серверу     | `SyncTransport`, `HTTPSyncTransport`, `InMemorySyncServer`, `OutgoingChange`, `RemoteChange`, `PushOutcome`          |
| Конфликты                 | `ConflictResolver`, `Conflict`, `ConflictResolution`, `Mergeable`                                                    |
| Поля без конфликтов       | `LWWRegister`, `LWWMap`, `GCounter`, `PNCounter`, `ORSet`                                                            |
| Управление синхронизацией | `RetryPolicy`, `CircuitBreaker`, `ConnectivityMonitor`, `NetworkConnectivityMonitor`, `SimulatedConnectivity`        |
| Хранение данных           | `FileStore`, `InMemoryStorage`, `StorageBackend`, `StoreEncryption`, `KeychainStore`, `RecordMigration`, `JSONValue` |
| Часы                      | `HybridLogicalClock`, `HLCTimestamp`, `VectorClock`                                                                  |
| SwiftUI                   | `SyncedCollection`                                                                                                   |

## Быстрый старт

**1. Добавьте пакет**

В Xcode выберите **File › Add Package Dependencies…** и введите адрес репозитория:

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

Вставьте его в поле поиска в правом верхнем углу окна. Оставьте **Dependency Rule** равным **Up to
Next Major Version** от `2.0.0` и нажмите **Add Package**. В следующем окне выберите цель вашего
приложения рядом с **OfflineFirstFramework** и снова нажмите **Add Package**.

**2. Импортируйте модуль**

```swift
import OfflineFirstFramework
```

Поместите эту строку в начало Swift-файла, где вы используете хранилище, рядом с `import SwiftUI`.

**3. Используйте**

В новом приложении Xcode (**File › New › Project… › App**, iOS 17 или новее) замените всё содержимое
`ContentView.swift` на:

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

Нажмите **Run** (⌘R). Введите задачу и нажмите Return: она сразу появится и сохранится на
устройстве, а на панели инструментов будет надпись **1 to sync**. Потяните список вниз, чтобы
синхронизировать; счётчик вернётся к 0. Закройте приложение и откройте снова: задачи на месте.
`InMemorySyncServer` заменяет ваш бэкенд, пока вы его не подключите (см. [Использование](#использование)).

## Установка

### Swift Package Manager

В Xcode выберите **File › Add Package Dependencies…** и введите адрес репозитория:

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

Или добавьте его в `dependencies` вашего `Package.swift`:

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

Версия 2.0 заменяет API версии 1.0.0, которую нельзя было подключить как зависимость; что изменилось,
перечислено в [журнале изменений](CHANGELOG.md).

## Использование

Каждый пример ниже скопирован из
[`ReadmeSamples.swift`](Examples/OfflineTodos/OfflineTodos/ReadmeSamples.swift); пример приложения
собирает этот файл, а набор тестов его выполняет.

### Синхронизация с вашим сервером по HTTP

Если ваш сервер реализует две конечные точки
[протокола сервера](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)
(`POST <base>/push` и `GET <base>/changes?since=<token>`), используйте HTTP-транспорт. Замыкание
`headers` выполняется перед каждым запросом, поэтому может получать свежий токен доступа:

```swift
let transport = HTTPSyncTransport<Todo>(
    baseURL: URL(string: "http://localhost:8080/sync/todos")!,
    headers: { ["Authorization": "Bearer \(try await token())"] }
)
let store = try OfflineStore<Todo>(name: "todos", transport: transport)
```

`http://localhost:8080` — это адрес, на котором слушает эталонный сервер, если запустить его командой
`node Examples/SyncServer/server.mjs`; замените его адресом вашего сервера.

### Подключение существующего API

Любой API помещается за `SyncTransport`: одна функция отправляет локальные изменения и сообщает
результат по каждому, другая возвращает изменения сервера после токена изменений. Этот пример
отображает хранилище на REST API, который версионирует записи с помощью ETag:

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

Правила, которым должен следовать транспорт (ревизии, повторные попытки, идемпотентность, удаления,
токены изменений), описаны в статье
[Подключение к вашему серверу](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md).

### Разрешение конфликтов

По умолчанию побеждает последняя запись. Чтобы сохранить части обеих версий, объедините их:

```swift
/// A to-do counts as done if either device ticked it; the server's title wins.
static let keepTicks = ConflictResolver<Todo>.merge { local, remote in
    var merged = remote
    merged.isDone = local.isDone || remote.isDone
    return merged
}
```

Передайте это как `configuration.conflictResolver` (см. следующий пример). Статья
[Разрешение конфликтов](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)
охватывает остальные политики и типы полей без конфликтов.

### Шифрование файла и миграция старых записей

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

### Автоматическая синхронизация

```swift
await TodoStore.shared.startAutomaticSync()
```

После этого хранилище синхронизируется, когда устройство выходит в сеть, через две секунды после
локальных изменений, когда подходит время повторить неудавшееся изменение, и каждые пять минут, пока
есть сеть. Ошибки отображаются в `SyncedCollection.status` и `lastError`. О синхронизации, пока
приложение работает в фоне, см.
[Синхронизация в фоне](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md).

### Тестирование без бэкенда

`InMemorySyncServer` ведёт себя как сервер (ревизии, конфликты, постраничное получение, переключатель
офлайн-режима), поэтому два хранилища могут играть роль двух устройств в модульном тесте:

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

## Демо

| Синхронизировано                                                                       | Офлайн, два изменения ждут                                                  |
| -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| ![Синхронизированный список задач, светлая тема](docs/images/example-synced-light.png) | ![Список задач офлайн, светлая тема](docs/images/example-offline-light.png) |
| ![Синхронизированный список задач, тёмная тема](docs/images/example-synced-dark.png)   | ![Список задач офлайн, тёмная тема](docs/images/example-offline-dark.png)   |

На скриншотах — пример приложения [OfflineTodos](Examples/OfflineTodos) в симуляторе iPhone, снятые
с помощью [`scripts/capture-example-screens.sh`](scripts/capture-example-screens.sh). В приложении
выключите **Online**, измените несколько задач и снова включите его, чтобы увидеть, как изменения
синхронизируются; **Edit on another device** меняет задачу из второго хранилища на том же сервере.
Откройте `Examples/OfflineTodos/OfflineTodos.xcodeproj`, выберите симулятор iPhone или **My Mac** и
нажмите **Run**; подробности — в [Examples/README.md](Examples/README.md).

## Документация

Справочник API и статьи:

- [Справочник API](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/)
  (DocC, публикуется на GitHub Pages из ветки `master`)
- Соберите его локально в Xcode через **Product › Build Documentation** или из командной строки:

```sh
xcodebuild docbuild -scheme OfflineFirstFramework -destination 'generic/platform=macOS'
```

## Руководства

- [Быстрое знакомство](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/gettingstarted)
  — добавить пакет, описать запись, открыть хранилище, показать его в SwiftUI
  ([исходник](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/GettingStarted.md)).
- [Подключение к вашему серверу](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/connectingtoyourserver)
  — HTTP-транспорт, правила для собственного транспорта, сервер в памяти
  ([исходник](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md)).
- [Протокол сервера](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/serverprotocol)
  — каждое поле запросов push и pull, для разработчиков бэкенда
  ([исходник](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)).
- [Разрешение конфликтов](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/resolvingconflicts)
  — политики, гибридные логические часы, слияние полей и типы без конфликтов
  ([исходник](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)).
- [Синхронизация в фоне](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/syncinginthebackground)
  — автоматическая синхронизация, повторные попытки, circuit breaker и фоновые задачи обновления
  ([исходник](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md)).
- [Защита и миграция данных](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/protectingandmigratingdata)
  — где лежат файлы, шифрование, миграции схемы и повреждённые файлы
  ([исходник](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ProtectingAndMigratingData.md)).

## Требования

| Платформа | Минимальная версия |
| --------- | ------------------ |
| iOS       | 17                 |
| macOS     | 14                 |
| tvOS      | 17                 |
| watchOS   | 10                 |
| visionOS  | 1                  |
| | Инструменты | Swift 6.2 · Xcode 26+ |  |

Для эталонного сервера нужен Node 24 или новее.

## Архитектура

- `OfflineStore` — это actor, которому принадлежит одна коллекция. Его состояние (записи, ожидающие
  изменения, токен изменений, часы) записывается в один JSON-файл; каждое изменение выполняется над
  копией, которая становится текущей только после успешной записи, поэтому сбой или переполненный
  диск никогда не оставят наполовину применённое изменение. Каждая запись несёт свою ревизию на
  сервере, свою последнюю метку времени и, пока не синхронизирована, одно ожидающее изменение с ID,
  который меняется при каждой локальной правке.
- Синхронизация отправляет ожидающие изменения пакетами (сначала самые старые, с той ревизией, на
  которой они основаны), применяет каждый результат, а затем получает страницы изменений сервера
  после сохранённого токена изменений. Конфликты с любой стороны передаются в `ConflictResolver`.
  Правки, сделанные во время отправки, сохраняются и отправляются следующими.
- `Sync/` содержит протокол транспорта, HTTP-транспорт и транспорт в памяти, политику повторных
  попыток, circuit breaker и отслеживание соединения; `Storage/` — файловое хранилище и хранилище в
  Keychain, шифрование и миграции; `Clock/` и `CRDT/` — типы-значения для упорядочивания и слияния;
  `SwiftUI/` — наблюдаемую модель. Ссылочными типами являются только `OfflineStore`,
  `InMemorySyncServer` и `SyncedCollection`.
- Хранилище защищается от некорректно ведущих себя серверов и повреждённых файлов: ограниченные
  размеры очереди, страниц, ответов, ревизий и токенов изменений, токен изменений, который обязан
  продвигаться, не более трёх отправок на запись и синхронизацию, игнорируемые записи с несовпавшим
  ID, метки времени за пределами допустимого расхождения часов и имена файлов, которые не могут
  выйти за пределы своего каталога. Тесты покрывают каждый из этих случаев.
- Весь файл переписывается при каждом изменении, что подходит для коллекций до десятков тысяч записей
  на хранилище.

Запустите тесты локально:

```sh
swift test                                          # macOS
xcodebuild test -scheme OfflineFirstFramework \
  -destination 'platform=iOS Simulator,name=iPhone 17'
(cd Examples/SyncServer && npm test)                # reference server
node Examples/SyncServer/server.mjs &               # end to end, against the server
OFFLINE_FIRST_SERVER_URL=http://localhost:8080 swift test --filter EndToEnd
```

## План развития

- Бэкенд хранения на SQLite для коллекций, слишком больших, чтобы переписывать их при каждом
  изменении.
- Транспорт на CloudKit (`CKSyncEngine`) для приложений без собственного сервера.
- Получение только части коллекции (например, записей одного проекта).
- Размещение пакета в Swift Package Index; `.spi.yml` уже есть в репозитории.

## Участие в разработке

Мы рады вашему участию. Перед открытием pull request прочитайте [руководство для участников](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/CONTRIBUTING.md) и [кодекс поведения](https://github.com/muhittincamdali/.github/blob/main/CODE_OF_CONDUCT.md). О проблемах безопасности сообщайте конфиденциально, как описано в [политике безопасности](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/SECURITY.md).

## Лицензия

Распространяется по лицензии MIT. Подробнее — в файле [LICENSE](LICENSE).
