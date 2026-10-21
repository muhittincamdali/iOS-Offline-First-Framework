<!-- i18n-source: README.md@dda00c8524eaba424ab0bb3aa2216dc80dbca2ef status=reviewed -->
<!-- brand:start -->

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-pt-BR-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-pt-BR-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-pt-BR-light.svg" alt="Offline-First Framework: Um armazenamento local para apps em Swift que continua funcionando offline e sincroniza com o seu servidor."></picture></p>

<!-- lang-selector:start -->
<p align="center"><a href="README.md">English</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a></p>
<!-- lang-selector:end -->

<p align="center">
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml"><img src="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml/badge.svg" alt="Status da CI"></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/releases"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg" alt="Versão mais recente: v2.0.0"></picture></a>
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
- **Testado contra um servidor real** — 331 testes de Swift Testing no macOS e em um simulador de
  iPhone, entre eles dois testes de propriedades que submetem cada política de conflito a
  solicitações perdidas, reinícios, redefinições do token, sincronizações simultâneas, limites de
  páginas pequenos, páginas desatualizadas, operações simultâneas e falhas, também contra um
  servidor sem sequências, testes de cenários com uma réplica que responde a um dispositivo
  durante muitas sincronizações, com uma falha em cada gravação de uma sincronização e com
  relógios de dispositivo que saltam para a frente, e testes que enviam páginas de dados inúteis,
  registros aninhados muito fundo, páginas maiores que o limite de resposta e páginas com mais
  alterações do que o pedido, também transmitidas sem fim por um socket; 28 testes de Node para o
  servidor; e uma suíte de testes de ponta a ponta na CI que sincroniza stores por meio do
  servidor via HTTP, também com 68 registros de 250 KiB através de um reinício do servidor, com 70
  respostas de conflito de 250 KiB que juntas passam do limite de resposta, com uma gravação cujo
  salvamento falhou antes de um reinício, com um envio que o servidor aplicou atrás de um proxy
  que responde 504 e com uma réplica que serve páginas de antes de um reinício depois de redefinir
  o token.

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

## Garantias e limites

O store cumpre estas promessas com qualquer política de conflito, diante de solicitações perdidas,
respostas perdidas, reinícios do app e do servidor e páginas desatualizadas, desde que o servidor
siga o [protocolo](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md):

- Um salvamento ou uma exclusão está no arquivo antes de a chamada retornar, e uma alteração na
  fila é enviada até o servidor respondê-la. Uma nova tentativa mantém o ID da alteração, então o
  servidor a aplica uma única vez. Só uma resposta que foi lida decide uma alteração: depois de um
  status de erro, de uma conexão perdida ou de uma resposta longa demais para ler, a alteração
  fica em dúvida até o próximo envio.
- Uma cópia desatualizada nunca substitui uma gravação que o servidor aceitou: o resolvedor só é
  consultado quando um registro mudou no dispositivo e em outro dispositivo, e uma versão mais
  antiga do servidor é ignorada pelo `sequence` do servidor, também logo depois de o servidor
  aceitar a gravação do próprio dispositivo, mesmo depois de um reinício do servidor que o
  dispositivo ainda não viu e depois de `resetChangeToken()`. Uma versão que o próprio dispositivo
  gravou nunca é um conflito, nem quando uma página desatualizada fez o registro voltar atrás e o
  usuário editou em cima dela, ou uma página lista uma gravação mais antiga do próprio dispositivo
  antes de uma versão cuja resposta se perdeu. Sem sequências, uma leitura deixa uma alteração
  pendente para o seu envio, cuja resposta de conflito nomeia a versão atual do servidor.
- Outro epoch do servidor só conta quando duas solicitações da mesma sincronização o informam, a
  leitura com o token e a leitura desde o início, então um cache desatualizado ou outra
  implantação atrás da mesma URL não consegue fazer o store voltar atrás. Uma sincronização que lê
  uma única página ainda acompanha um reinício do servidor, e quando as duas solicitações não
  concordam a sincronização falha em vez de informar sucesso. Os epochs seguem um único sentido:
  um epoch anterior ao do store, um que ele deixou ou um que nunca teve, nunca é aceito, nem
  depois de `resetChangeToken()`, então uma réplica ou um cache desatualizado que responde às duas
  solicitações, por quantas sincronizações seguidas for, também não consegue fazer o store voltar
  atrás.
- Registros excluídos continuam excluídos. Um servidor que perdeu seus dados, ou outro servidor,
  faz o store ler tudo de novo, mantendo suas alterações pendentes, que encontram a nova história
  pela resposta ao seu envio, não por uma página. Um registro que o app não consegue decodificar,
  ou um aninhado em mais de 64 níveis, é separado em `quarantinedChanges()` em vez de interromper
  a leitura.
- As respostas de um servidor têm custo limitado. Um registro aninhado em mais de 64 níveis nunca
  entra no store, então gravar o arquivo não consegue estourar a pilha; uma página de dados
  inúteis, ou com mais alterações do que a leitura pediu (no máximo 1.000), é recusada em
  milissegundos em vez de ocupar gigabytes, e seu download é cancelado; uma página maior que o
  limite de resposta faz a leitura pedir menos alterações, e uma única alteração que sozinha passa
  do limite, até quatro vezes ele, é separada; um envio é dividido em solicitações que o limite de
  corpo do servidor aceita e enviado de novo em metades, com no máximo 16 solicitações a mais,
  enquanto o servidor responder 413 ou uma resposta 2xx passar do limite de resposta, e uma
  alteração cuja resposta sozinha passa dele fica em dúvida; de um status de erro só os primeiros
  4 KiB são lidos, então um gateway com problemas custa uma tentativa com falha; uma marca de
  ordem de bytes UTF-8 é lida.
- Um relógio adiantado ou atrasado à mão, um servidor que responde a cada envio com um conflito,
  um servidor que nunca responde e um arquivo que não pode ser gravado têm efeito limitado: os
  servidores de referência guardam um carimbo de data/hora recebido no máximo cinco minutos além
  do próprio relógio, um instante de relógio errado no dispositivo não passa para as gravações
  seguintes, as versões do servidor nunca são ordenadas por carimbos de data/hora (um relógio
  adiantado não esconde nenhuma versão posterior nem estaciona nenhuma alteração), as novas
  tentativas esperam e são estacionadas, uma sincronização termina após `syncTimeout` e as
  sincronizações esperam enquanto o arquivo não puder ser gravado.

O servidor nunca deve dar a mesma revisão a duas versões de um registro, deveria enviar um `epoch`
que só avança para outros posteriores (mais longos, ou maiores byte a byte) e nunca volta, um
`sequence` que continua contando entre reinícios (a única ordem que o store usa), os carimbos de
data/hora recebidos (com uma hora muito à frente do seu relógio trazida a um limite) e o
`changeID` que gravou cada versão, e precisa lembrar os IDs de alteração entre reinícios, mostrar
uma gravação nas páginas só depois de armazená-la e manter cada página e a resposta a cada
alteração enviada dentro do limite de resposta do cliente (uma página tem no máximo `limit`
alterações, cortada também por bytes, pelo menos uma alteração por página). Limites: gravações que
um servidor perdeu em uma restauração não são enviadas de novo, um servidor sem `sequence` não tem
garantia de ordem (uma página desatualizada pode fazer um registro voltar atrás até ele mudar de
novo, embora nenhuma gravação se perca), um registro salvo de novo logo depois de
`discardChange(for:)` encontra a cópia do servidor como um conflito, uma única instância do store
por arquivo (garantido com `FileStore`, `InMemoryStorage` e backends próprios que informam um
`claimIdentity`), o arquivo inteiro é gravado a cada alteração, registros se aninham em no máximo
64 níveis, uma página tem no máximo 1.000 alterações, uma única alteração maior que quatro vezes o
limite de resposta interrompe a leitura, uma alteração cuja resposta de envio sozinha passa do
limite de resposta fica em dúvida e é estacionada depois da última tentativa, um epoch anterior
continua recusado até o servidor informar um posterior ao do store, e exclusões além de 10.000 são
esquecidas. [Garantias e
limites](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/GuaranteesAndLimits.md) traz a
lista completa.

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
  posteriores ao token de alteração salvo. Um registro que mudou no dispositivo e no servidor vai
  para o `ConflictResolver`; uma versão mais antiga do servidor é ignorada. As edições feitas
  enquanto um envio está a caminho são mantidas e enviadas em seguida.
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
OFFLINE_FIRST_NODE=$(command -v node) swift test --filter ServerSaveTests  # a failed save, a restart
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
