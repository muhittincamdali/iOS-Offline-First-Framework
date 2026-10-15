<!-- i18n-source: README.md@10258518fc1ec3336336d25288bb44d80a78fc2f status=reviewed -->
<!-- brand:start -->

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-pt-BR-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-pt-BR-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-pt-BR-light.svg" alt="Offline-First Framework: Um armazenamento local para apps em Swift que continua funcionando offline e sincroniza com o seu servidor."></picture></p>

<!-- lang-selector:start -->
<p align="center"><a href="README.md">English</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a></p>
<!-- lang-selector:end -->

<p align="center">
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml"><img src="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml/badge.svg" alt="Status da CI"></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/releases"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg" alt="Versão mais recente: v1.0.0"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg" alt="Plataformas compatíveis: iOS 17+ · macOS 14+ · tvOS 17+ · watchOS 10+ · visionOS 1+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg" alt="Versão da linguagem: Swift 6.2+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/LICENSE"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg" alt="Licença: MIT"></picture></a>
</p>

<p align="center">
<a href="#início-rápido"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-pt-BR-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-pt-BR-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-pt-BR-light.svg" alt="Começar"></picture></a>
<a href="https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-pt-BR-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-pt-BR-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-pt-BR-light.svg" alt="Documentação"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/tree/master/Examples"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-pt-BR-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-pt-BR-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-pt-BR-light.svg" alt="Exemplos"></picture></a>
</p>

> Esta é uma tradução do README em inglês. Se houver diferença, vale a versão em inglês.

<!-- brand:end -->
Um pacote Swift que guarda os registros do seu app em um arquivo no dispositivo, coloca cada
alteração em uma fila e sincroniza com o seu servidor sempre que há conexão. Salvar nunca espera
pela rede, então o app funciona do mesmo jeito em um avião, em um porão ou em uma conexão instável
de trem. Quando o mesmo registro mudou em dois dispositivos, uma política de conflito que você
escolhe decide o que é mantido. Ele funciona com qualquer backend: um pequeno protocolo HTTP com um
servidor de referência, a sua própria API por meio de um protocolo de duas funções, ou um servidor
em memória para testes e pré-visualizações. O pacote não tem dependências.

## Destaques

- **Gravações que nunca esperam** — `save` e `delete` vão para um arquivo gravado de forma atômica e
  para uma fila durável de alterações pendentes que sobrevive a reinicializações; os envios que
  falham são repetidos com backoff exponencial e jitter e, depois da última tentativa, ficam
  guardados em vez de se perderem.
- **Conflitos decididos de propósito** — a última gravação vence com base em carimbos de data/hora de
  um relógio lógico híbrido (eles nunca voltam no tempo e dão a mesma ordem a todos os dispositivos),
  o servidor vence, o cliente vence, a sua própria mesclagem ou campos sem conflito: `LWWRegister`,
  `LWWMap`, `GCounter`, `PNCounter` e `ORSet`.
- **Qualquer backend** — `HTTPSyncTransport` fala um protocolo JSON documentado que o servidor de
  referência em [`Examples/SyncServer`](Examples/SyncServer) implementa em cerca de 280 linhas de
  JavaScript; qualquer outra API cabe atrás de `SyncTransport`, por exemplo uma API REST com ETags.
- **Feito para SwiftUI** — `SyncedCollection` é um modelo `@Observable` de um store; a sincronização
  automática roda quando o dispositivo fica online e logo após as edições locais, e uma única
  chamada sincroniza a partir de uma tarefa de atualização em segundo plano.
- **Dados em repouso protegidos** — criptografia de arquivos AES-GCM com uma chave guardada no
  Keychain, classes de proteção de dados, migrações de esquema dos registros e uma política para
  arquivos danificados.
- **Testado contra um servidor real** — 122 testes de Swift Testing no macOS e em um simulador de
  iPhone, 15 testes de Node para o servidor e uma suíte de testes de ponta a ponta na CI que
  sincroniza dois stores por meio do servidor via HTTP.

### O que está incluído

| Área                      | Tipos                                                                                                                |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Store                     | `OfflineStore`, `SyncableRecord`, `SyncStatus`, `SyncReport`, `StoreState`, `PendingChange`                          |
| Conexão com o servidor    | `SyncTransport`, `HTTPSyncTransport`, `InMemorySyncServer`, `OutgoingChange`, `RemoteChange`, `PushOutcome`          |
| Conflitos                 | `ConflictResolver`, `Conflict`, `ConflictResolution`, `Mergeable`                                                    |
| Campos sem conflito       | `LWWRegister`, `LWWMap`, `GCounter`, `PNCounter`, `ORSet`                                                            |
| Controle de sincronização | `RetryPolicy`, `CircuitBreaker`, `ConnectivityMonitor`, `NetworkConnectivityMonitor`, `SimulatedConnectivity`        |
| Armazenamento             | `FileStore`, `InMemoryStorage`, `StorageBackend`, `StoreEncryption`, `KeychainStore`, `RecordMigration`, `JSONValue` |
| Relógios                  | `HybridLogicalClock`, `HLCTimestamp`, `VectorClock`                                                                  |
| SwiftUI                   | `SyncedCollection`                                                                                                   |

## Início rápido

**1. Adicione o pacote**

No Xcode, escolha **File › Add Package Dependencies…** e informe a URL do repositório:

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

Cole no campo de busca no canto superior direito da janela. Deixe **Dependency Rule** em **Up to Next
Major Version** a partir de `2.0.0` e clique em **Add Package**. Na janela seguinte, escolha o target
do seu app ao lado de **OfflineFirstFramework** e clique em **Add Package** de novo.

**2. Importe o módulo**

```swift
import OfflineFirstFramework
```

Coloque esta linha no topo do arquivo Swift em que você usa o store, ao lado de `import SwiftUI`.

**3. Use**

Em um app novo do Xcode (**File › New › Project… › App**, iOS 17 ou posterior), substitua todo o
conteúdo de `ContentView.swift` por:

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

Pressione **Run** (⌘R). Digite uma tarefa e pressione Return: ela aparece na hora e é salva no
dispositivo, e a barra de ferramentas mostra **1 to sync**. Puxe a lista para baixo para
sincronizar; o contador volta a 0. Feche e abra o app de novo: as tarefas continuam lá.
`InMemorySyncServer` faz as vezes do seu backend até você conectar um (veja [Uso](#uso)).

## Instalação

### Swift Package Manager

No Xcode, escolha **File › Add Package Dependencies…** e informe a URL do repositório:

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

Ou adicione-o às `dependencies` do seu `Package.swift`:

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

A versão 2.0 substitui a API da 1.0.0, que não podia ser resolvida como dependência; o
[registro de alterações](CHANGELOG.md) lista o que mudou.

## Uso

Cada exemplo abaixo foi copiado de
[`ReadmeSamples.swift`](Examples/OfflineTodos/OfflineTodos/ReadmeSamples.swift), que o app de
exemplo compila e a suíte de testes executa.

### Sincronizar com o seu servidor via HTTP

Se o seu servidor implementa os dois endpoints do
[protocolo do servidor](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)
(`POST <base>/push` e `GET <base>/changes?since=<token>`), use o transport HTTP. O closure
`headers` roda antes de cada requisição, então pode buscar um token de acesso novo:

```swift
let transport = HTTPSyncTransport<Todo>(
    baseURL: URL(string: "http://localhost:8080/sync/todos")!,
    headers: { ["Authorization": "Bearer \(try await token())"] }
)
let store = try OfflineStore<Todo>(name: "todos", transport: transport)
```

`http://localhost:8080` é o endereço em que o servidor de referência escuta quando você o inicia
com `node Examples/SyncServer/server.mjs`; troque-o pela URL do seu servidor.

### Conectar uma API existente

Qualquer API cabe atrás de `SyncTransport`: uma função envia as alterações locais e informa um
resultado para cada uma, e a outra devolve as alterações do servidor posteriores a um token de
alteração. Este exemplo mapeia o store para uma API REST que versiona os registros com ETags:

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

As regras que um transport precisa seguir (revisões, novas tentativas, idempotência, exclusões,
tokens de alteração) estão no artigo
[Conectando ao seu servidor](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md).

### Decidir os conflitos

O padrão é a última gravação vencer. Para manter partes das duas versões, mescle-as:

```swift
/// A to-do counts as done if either device ticked it; the server's title wins.
static let keepTicks = ConflictResolver<Todo>.merge { local, remote in
    var merged = remote
    merged.isDone = local.isDone || remote.isDone
    return merged
}
```

Passe-a como `configuration.conflictResolver` (veja o próximo exemplo). O artigo
[Resolvendo conflitos](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)
trata das outras políticas e dos tipos de campos sem conflito.

### Criptografar o arquivo e migrar registros antigos

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

### Sincronizar automaticamente

```swift
await TodoStore.shared.startAutomaticSync()
```

Depois disso, o store sincroniza quando o dispositivo fica online, dois segundos após as alterações
locais, quando uma alteração que falhou está pronta para nova tentativa e a cada cinco minutos
enquanto estiver online. Os erros aparecem em `SyncedCollection.status` e `lastError`. Para
sincronizar com o app em segundo plano, veja
[Sincronizando em segundo plano](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md).

### Testar sem um backend

`InMemorySyncServer` se comporta como um servidor (revisões, conflitos, leituras paginadas, uma
chave de modo offline), de modo que dois stores podem fazer o papel de dois dispositivos em um teste
unitário:

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

## Demonstração

| Sincronizado                                                                  | Offline, duas alterações aguardando                                       |
| ----------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| ![Lista de tarefas sincronizada, claro](docs/images/example-synced-light.png) | ![Lista de tarefas offline, claro](docs/images/example-offline-light.png) |
| ![Lista de tarefas sincronizada, escuro](docs/images/example-synced-dark.png) | ![Lista de tarefas offline, escuro](docs/images/example-offline-dark.png) |

As capturas de tela mostram o app de exemplo [OfflineTodos](Examples/OfflineTodos) em um simulador de
iPhone, capturadas com
[`scripts/capture-example-screens.sh`](scripts/capture-example-screens.sh). No app, desligue
**Online**, edite algumas tarefas e ligue de novo para ver as alterações serem sincronizadas;
**Edit on another device** altera uma tarefa a partir de um segundo store no mesmo servidor. Abra
`Examples/OfflineTodos/OfflineTodos.xcodeproj`, escolha um simulador de iPhone ou **My Mac** e
pressione **Run**; [Examples/README.md](Examples/README.md) tem os detalhes.

## Documentação

Referência da API e artigos:

- [Referência da API](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/)
  (DocC, publicada no GitHub Pages a partir de `master`)
- Gere-a localmente no Xcode com **Product › Build Documentation**, ou pela linha de comando:

```sh
xcodebuild docbuild -scheme OfflineFirstFramework -destination 'generic/platform=macOS'
```

## Guias

- [Primeiros passos](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/gettingstarted)
  — adicionar o pacote, definir um registro, abrir um store, mostrá-lo no SwiftUI
  ([código-fonte](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/GettingStarted.md)).
- [Conectando ao seu servidor](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/connectingtoyourserver)
  — o transport HTTP, as regras para o seu próprio transport, o servidor em memória
  ([código-fonte](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md)).
- [Protocolo do servidor](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/serverprotocol)
  — cada campo das requisições push e pull, para quem desenvolve o backend
  ([código-fonte](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)).
- [Resolvendo conflitos](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/resolvingconflicts)
  — políticas, relógios lógicos híbridos, mesclagens de campos e tipos sem conflito
  ([código-fonte](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)).
- [Sincronizando em segundo plano](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/syncinginthebackground)
  — sincronização automática, novas tentativas, o circuit breaker e tarefas de atualização em segundo plano
  ([código-fonte](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md)).
- [Protegendo e migrando dados](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/protectingandmigratingdata)
  — onde ficam os arquivos, criptografia, migrações de esquema e arquivos danificados
  ([código-fonte](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ProtectingAndMigratingData.md)).

## Requisitos

| Plataforma | Versão mínima |
| ---------- | ------------- |
| iOS        | 17            |
| macOS      | 14            |
| tvOS       | 17            |
| watchOS    | 10            |
| visionOS   | 1             |
| | Ferramentas | Swift 6.2 · Xcode 26+ |   |

O servidor de referência precisa do Node 24 ou posterior.

## Arquitetura

- `OfflineStore` é um actor que possui uma coleção. O estado dele (registros, alterações pendentes,
  token de alteração, relógio) é gravado como um único arquivo JSON; cada alteração roda em uma cópia
  que só passa a valer depois que a gravação é bem-sucedida, de modo que uma falha ou um disco cheio
  nunca deixa uma alteração aplicada pela metade. Cada registro leva a sua revisão do servidor, o seu
  último carimbo de data/hora e, enquanto não sincronizado, uma alteração pendente com um ID que
  muda a cada edição local.
- Uma sincronização envia as alterações pendentes em lotes (as mais antigas primeiro, com a revisão
  em que se basearam), aplica cada resultado e então lê páginas de alterações do servidor
  posteriores ao token de alteração salvo. Os conflitos de qualquer um dos lados vão para o
  `ConflictResolver`. As edições feitas enquanto um envio está a caminho são mantidas e enviadas em
  seguida.
- `Sync/` contém o protocolo de transport, os transports HTTP e em memória, a política de novas
  tentativas, o circuit breaker e a conectividade; `Storage/` os stores de arquivo e do Keychain, a
  criptografia e as migrações; `Clock/` e `CRDT/` os tipos de valor para ordenar e mesclar;
  `SwiftUI/` o modelo observável. Apenas `OfflineStore`, `InMemorySyncServer` e `SyncedCollection`
  são tipos de referência.
- O store se protege de servidores que se comportam mal e de arquivos danificados: tamanhos limitados
  da fila, das páginas, das respostas, das revisões e dos tokens de alteração, um token de alteração
  que precisa avançar, no máximo três envios por registro e sincronização, registros ignorados cujo
  ID não corresponde, carimbos de data/hora além do desvio de relógio permitido e nomes de arquivo
  que não podem sair do seu diretório. Os testes cobrem cada um desses pontos.
- O arquivo inteiro é regravado a cada alteração, o que serve a coleções de até dezenas de milhares de
  registros por store.

Execute os testes localmente:

```sh
swift test                                          # macOS
xcodebuild test -scheme OfflineFirstFramework \
  -destination 'platform=iOS Simulator,name=iPhone 17'
(cd Examples/SyncServer && npm test)                # reference server
node Examples/SyncServer/server.mjs &               # end to end, against the server
OFFLINE_FIRST_SERVER_URL=http://localhost:8080 swift test --filter EndToEnd
```

## Roteiro

- Um backend de armazenamento em SQLite para coleções grandes demais para serem regravadas a cada
  alteração.
- Um transport em CloudKit (`CKSyncEngine`) para apps sem servidor próprio.
- Ler apenas parte de uma coleção (por exemplo, os registros de um projeto).
- Listar o pacote no Swift Package Index; o `.spi.yml` já está no repositório.

## Como contribuir

Contribuições são bem-vindas. Leia o [guia de contribuição](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/CONTRIBUTING.md) e o [código de conduta](https://github.com/muhittincamdali/.github/blob/main/CODE_OF_CONDUCT.md) antes de abrir um pull request. Relate problemas de segurança de forma privada, como descrito na [política de segurança](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/SECURITY.md).

## Licença

Publicado sob a licença MIT. Veja [LICENSE](LICENSE).
