<!-- i18n-source: README.md@4d9df4dc8e348cf5ca7a61c8d85e9e33ecc98ae0 status=reviewed -->
<!-- brand:start -->

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-es-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-es-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-es-light.svg" alt="Offline-First Framework: Un almacén local para apps en Swift que sigue funcionando sin conexión y se sincroniza con tu servidor."></picture></p>

<!-- lang-selector:start -->
<p align="center"><a href="README.md">English</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a></p>
<!-- lang-selector:end -->

<p align="center">
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml"><img src="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml/badge.svg" alt="Estado de CI"></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/releases"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg" alt="Última versión: v2.0.0"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg" alt="Plataformas compatibles: iOS 17+ · macOS 14+ · tvOS 17+ · watchOS 10+ · visionOS 1+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg" alt="Versión del lenguaje: Swift 6.2+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/LICENSE"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg" alt="Licencia: MIT"></picture></a>
</p>

<p align="center">
<a href="#inicio-rápido"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-es-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-es-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-es-light.svg" alt="Empezar"></picture></a>
<a href="https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-es-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-es-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-es-light.svg" alt="Documentación"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/tree/master/Examples"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-es-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-es-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-es-light.svg" alt="Ejemplos"></picture></a>
</p>

> Esta es una traducción del README en inglés. Si hay diferencias, la versión en inglés es la vigente.

<!-- brand:end -->
Un paquete de Swift que guarda los registros de tu app en un archivo del dispositivo, pone en cola
cada cambio y se sincroniza con tu servidor cuando hay conexión. Guardar nunca espera a la red,
así que la app funciona igual en un avión, en un sótano o con la conexión intermitente de un tren.
Cuando el mismo registro cambió en dos dispositivos, una política de conflictos que tú eliges
decide qué se conserva. Funciona con cualquier backend: un pequeño protocolo HTTP con un servidor
de referencia, tu propia API a través de un protocolo de dos funciones, o un servidor en memoria
para pruebas y previsualizaciones. El paquete no tiene dependencias.

## Lo más destacado

- **Escrituras que nunca esperan** — `save` y `delete` van a un archivo escrito de forma atómica y
  a una cola duradera de cambios pendientes que sobrevive a los reinicios; los envíos fallidos se
  reintentan con retroceso exponencial (exponential backoff) y jitter, y tras el último intento se
  aparcan en lugar de perderse.
- **Conflictos decididos a propósito** — gana la última escritura según marcas de tiempo de reloj
  lógico híbrido (nunca retroceden y dan a todos los dispositivos el mismo orden), gana el
  servidor, gana el cliente, tu propia combinación, o campos sin conflictos: `LWWRegister`,
  `LWWMap`, `GCounter`, `PNCounter` y `ORSet`.
- **Cualquier backend** — `HTTPSyncTransport` habla un protocolo JSON documentado que el servidor
  de referencia de [`Examples/SyncServer`](Examples/SyncServer) implementa en unas 280 líneas de
  JavaScript; cualquier otra API cabe detrás de `SyncTransport`, por ejemplo una API REST con ETags.
- **Hecho para SwiftUI** — `SyncedCollection` es un modelo `@Observable` de un almacén; la
  sincronización automática se ejecuta cuando el dispositivo se conecta y poco después de las
  ediciones locales, y una sola llamada sincroniza desde una tarea de actualización en segundo plano.
- **Datos en reposo protegidos** — cifrado de archivos AES-GCM con una clave guardada en el Keychain,
  clases de protección de datos, migraciones del esquema de los registros y una política para los
  archivos dañados.
- **Probado contra un servidor real** — 369 pruebas de Swift Testing en macOS y en un simulador de
  iPhone, entre ellas tres pruebas de propiedades que someten cada política de conflictos a
  solicitudes perdidas, reinicios, restablecimientos del token, sincronizaciones solapadas,
  límites de páginas pequeños, páginas obsoletas, operaciones simultáneas y caídas, también contra
  un servidor sin secuencias, pruebas de escenarios con una réplica que responde a un dispositivo
  durante muchas sincronizaciones, con una página obsoleta que trae de vuelta una escritura propia
  más antigua o se encuentra con un envío aceptado, con una caída en cada escritura de una
  sincronización y con relojes de dispositivo que saltan hacia adelante, y pruebas que envían
  páginas de datos inservibles, registros anidados a gran profundidad, páginas mayores que el
  límite de respuesta y páginas con más cambios de los pedidos, también transmitidas sin fin por
  un socket; 28 pruebas de Node para el servidor; y un conjunto de pruebas de extremo a extremo en
  CI que sincroniza almacenes a través del servidor por HTTP, también con 68 registros de 250 KiB
  a través de un reinicio del servidor, con 70 respuestas de conflicto de 250 KiB que juntas
  superan el límite de respuesta, con una escritura cuyo guardado falló antes de un reinicio, con
  un envío que el servidor aplicó detrás de un proxy que responde 504 y con una réplica que sirve
  páginas de antes de un reinicio tras restablecer el token.

### Qué incluye

| Área                      | Tipos                                                                                                                |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Almacén                   | `OfflineStore`, `SyncableRecord`, `SyncStatus`, `SyncReport`, `StoreState`, `PendingChange`                          |
| Conexión con el servidor  | `SyncTransport`, `HTTPSyncTransport`, `InMemorySyncServer`, `OutgoingChange`, `RemoteChange`, `PushOutcome`          |
| Conflictos                | `ConflictResolver`, `Conflict`, `ConflictResolution`, `Mergeable`                                                    |
| Campos sin conflictos     | `LWWRegister`, `LWWMap`, `GCounter`, `PNCounter`, `ORSet`                                                            |
| Control de sincronización | `RetryPolicy`, `CircuitBreaker`, `ConnectivityMonitor`, `NetworkConnectivityMonitor`, `SimulatedConnectivity`        |
| Almacenamiento            | `FileStore`, `InMemoryStorage`, `StorageBackend`, `StoreEncryption`, `KeychainStore`, `RecordMigration`, `JSONValue` |
| Relojes                   | `HybridLogicalClock`, `HLCTimestamp`, `VectorClock`                                                                  |
| SwiftUI                   | `SyncedCollection`                                                                                                   |

## Inicio rápido

**1. Añade el paquete**

En Xcode, elige **File › Add Package Dependencies…** e introduce la URL del repositorio:

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

Pégala en el campo de búsqueda de la parte superior derecha de la ventana. Deja **Dependency Rule**
en **Up to Next Major Version** desde `2.0.0` y haz clic en **Add Package**. En la ventana siguiente,
elige el target de tu app junto a **OfflineFirstFramework** y vuelve a hacer clic en **Add Package**.

**2. Importa el módulo**

```swift
import OfflineFirstFramework
```

Pon esta línea al principio del archivo Swift donde uses el almacén, junto a `import SwiftUI`.

**3. Úsalo**

En una app nueva de Xcode (**File › New › Project… › App**, iOS 17 o posterior), sustituye todo el
contenido de `ContentView.swift` por:

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

Pulsa **Run** (⌘R). Escribe una tarea y pulsa Return: aparece al instante y se guarda en el
dispositivo, y la barra de herramientas muestra **1 to sync**. Tira de la lista hacia abajo para
sincronizar; el contador vuelve a 0. Cierra la app y vuelve a abrirla: las tareas siguen ahí.
`InMemorySyncServer` hace las veces de tu backend hasta que conectes uno (consulta [Uso](#uso)).

## Instalación

### Swift Package Manager

En Xcode, elige **File › Add Package Dependencies…** e introduce la URL del repositorio:

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

O añádelo a las `dependencies` de tu `Package.swift`:

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

La versión 2.0 sustituye la API de la 1.0.0, que no se podía resolver como dependencia; el
[registro de cambios](CHANGELOG.md) enumera qué cambió.

## Uso

Cada ejemplo de abajo está copiado de
[`ReadmeSamples.swift`](Examples/OfflineTodos/OfflineTodos/ReadmeSamples.swift), que la app de
ejemplo compila y el conjunto de pruebas ejecuta.

### Sincronizar con tu servidor por HTTP

Si tu servidor implementa los dos endpoints del
[protocolo del servidor](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)
(`POST <base>/push` y `GET <base>/changes?since=<token>`), usa el transport HTTP. El closure
`headers` se ejecuta antes de cada petición, así que puede obtener un token de acceso nuevo:

```swift
let transport = HTTPSyncTransport<Todo>(
    baseURL: URL(string: "http://localhost:8080/sync/todos")!,
    headers: { ["Authorization": "Bearer \(try await token())"] }
)
let store = try OfflineStore<Todo>(name: "todos", transport: transport)
```

`http://localhost:8080` es la dirección en la que escucha el servidor de referencia cuando lo
inicias con `node Examples/SyncServer/server.mjs`; sustitúyela por la URL de tu servidor.

### Conectar una API existente

Cualquier API cabe detrás de `SyncTransport`: una función envía los cambios locales e informa de un
resultado para cada uno, y la otra devuelve los cambios del servidor posteriores a un token de
cambios. Este ejemplo asigna el almacén a una API REST que versiona los registros con ETags:

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

Las reglas que debe seguir un transport (revisiones, reintentos, idempotencia, borrados, tokens de
cambios) están en el artículo
[Conectar con tu servidor](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md).

### Decidir los conflictos

Por defecto gana la última escritura. Para conservar partes de ambas versiones, combínalas:

```swift
/// A to-do counts as done if either device ticked it; the server's title wins.
static let keepTicks = ConflictResolver<Todo>.merge { local, remote in
    var merged = remote
    merged.isDone = local.isDone || remote.isDone
    return merged
}
```

Pásala como `configuration.conflictResolver` (consulta el ejemplo siguiente). El artículo
[Resolver conflictos](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)
trata las demás políticas y los tipos de campos sin conflictos.

### Cifrar el archivo y migrar registros antiguos

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

### Sincronizar automáticamente

```swift
await TodoStore.shared.startAutomaticSync()
```

A partir de ahí, el almacén se sincroniza cuando el dispositivo se conecta, dos segundos después de
los cambios locales, cuando toca reintentar un cambio fallido y cada cinco minutos mientras haya
conexión. Los errores aparecen en `SyncedCollection.status` y `lastError`. Para sincronizar mientras
la app está en segundo plano, consulta
[Sincronizar en segundo plano](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md).

### Probar sin un backend

`InMemorySyncServer` se comporta como un servidor (revisiones, conflictos, descargas paginadas, un
interruptor de modo sin conexión), de modo que dos almacenes pueden hacer de dos dispositivos en una
prueba unitaria:

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

## Garantías y límites

El almacén cumple estas promesas con cualquier política de conflictos, ante solicitudes perdidas,
respuestas perdidas, reinicios de la app y del servidor y páginas obsoletas, siempre que el
servidor siga el [protocolo](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md):

- Un guardado o un borrado está en el archivo antes de que la llamada vuelva, y un cambio en cola
  se envía hasta que el servidor lo responde. Un reintento conserva el ID del cambio, así que el
  servidor lo aplica una sola vez. Solo una respuesta que se leyó decide un cambio: tras un estado
  de error, una conexión perdida o una respuesta demasiado larga para leerla, el cambio queda en
  duda hasta su próximo envío.
- Una copia obsoleta nunca reemplaza una escritura que el servidor aceptó: al resolutor solo se le
  pregunta cuando un registro cambió en el dispositivo y en otro dispositivo, y una versión más
  antigua del servidor se omite por el `sequence` del servidor, también justo después de que se
  aceptara la escritura del propio dispositivo, incluso tras un reinicio del servidor que el
  dispositivo aún no ha visto y tras `resetChangeToken()`. Una versión que escribió el propio
  dispositivo nunca es un conflicto, tampoco cuando una página obsoleta hizo retroceder el
  registro y el usuario editó sobre ella, o una página lista una escritura propia más antigua
  antes de una versión cuya respuesta se perdió. Sin secuencias, una descarga deja un cambio
  pendiente a su envío, también cuando la página trae una escritura más antigua del propio
  dispositivo, y decide la respuesta del envío, aceptada o no: una versión que una descarga retuvo
  entretanto solo ocupa su lugar cuando el `sequence` del servidor muestra que es más nueva.
  Cuando nada lo indica, un conflicto hace que el cambio salga una vez más para obtener una
  respuesta nueva, y cualquier otra respuesta se mantiene mientras la siguiente sincronización
  descarga desde el principio.
- Otro epoch del servidor, y el primero del que se entera un almacén, también en la primera página
  de un almacén nuevo, solo cuenta cuando lo informan dos solicitudes de la misma sincronización,
  la descarga con el token y la descarga desde el principio, así que una sola página de una caché
  obsoleta o de otro despliegue detrás de la misma URL no puede hacer retroceder el almacén, traer
  a un almacén nuevo registros que el servidor nunca tuvo ni dejar fuera a un almacén. Una página
  sin epoch, una vez que dos solicitudes informaron uno, tampoco se toma nunca. Una sincronización
  que descarga una sola página sigue igualmente un reinicio del servidor, y cuando las dos
  solicitudes no coinciden la sincronización falla en lugar de informar de un éxito. Los epochs
  van en un solo sentido: un epoch anterior al del almacén, uno que dejó o uno que nunca tuvo,
  nunca se toma, tampoco tras `resetChangeToken()`, así que una réplica o caché obsoleta que
  responde ambas solicitudes, durante cuantas sincronizaciones seguidas sea, tampoco puede hacer
  retroceder el almacén.
- Los registros borrados siguen borrados. Un servidor que perdió sus datos, u otro servidor, hace
  que el almacén vuelva a descargarlo todo y conserve sus cambios pendientes, que se encuentran
  con la nueva historia a través de la respuesta a su envío, no de una página. Un registro que la
  app no puede decodificar, o uno anidado a más de 64 niveles, se aparta en `quarantinedChanges()`
  en lugar de detener la descarga.
- Las respuestas de un servidor tienen un coste acotado. Un registro anidado a más de 64 niveles
  nunca entra en el almacén, así que escribir el archivo no puede desbordar la pila; una página de
  datos inservibles, o con más cambios de los que pidió la descarga (1.000 como mucho), se rechaza
  en milisegundos en lugar de ocupar gigabytes, y su descarga se cancela; una página mayor que el
  límite de respuesta hace que la descarga pida menos cambios, y un único cambio que por sí solo
  supera el límite, hasta cuatro veces este, se aparta; un envío se divide en solicitudes que el
  límite de cuerpo del servidor acepta y se vuelve a enviar en mitades, con 16 solicitudes más
  como mucho, mientras el servidor responda 413 o una respuesta 2xx supere el límite de respuesta,
  y un cambio cuya respuesta por sí sola lo supera queda en duda; de un estado de error solo se
  leen los primeros 4 KiB, así que una pasarela con problemas cuesta un intento fallido; se lee
  una marca de orden de bytes UTF-8.
- Un reloj adelantado o retrasado a mano, un servidor que responde cada envío con un conflicto, un
  servidor que nunca responde y un archivo que no se puede escribir tienen un efecto acotado: los
  servidores de referencia guardan una marca de tiempo recibida como mucho cinco minutos por
  delante de su propio reloj, un instante de un reloj del dispositivo equivocado no pasa a las
  escrituras posteriores, las versiones del servidor nunca se ordenan por marcas de tiempo (un
  reloj adelantado no oculta ninguna versión posterior ni aparca ningún cambio), los reintentos
  esperan y se aparcan, una sincronización termina tras `syncTimeout` y las sincronizaciones
  esperan mientras no se pueda escribir el archivo.

El servidor nunca debe dar la misma revisión a dos versiones de un registro, debería enviar en
cada página un `epoch` que solo avance a otros posteriores (más largos, o mayores byte a byte) y
nunca vuelva, un `sequence` que siga contando tras los reinicios (el único orden que usa el
almacén), las marcas de tiempo recibidas (con una hora muy por delante de su reloj llevada a un
límite) y el `changeID` que escribió cada versión, y debe recordar los IDs de cambio a través de
los reinicios, mostrar una escritura en las páginas solo cuando esté guardada y mantener cada
página y la respuesta a cada cambio enviado dentro del límite de respuesta del cliente (una página
contiene como mucho `limit` cambios, cortada también por bytes, al menos un cambio por página).
Límites: las escrituras que un servidor perdió en una restauración no se vuelven a subir, un
servidor sin `sequence` no tiene garantía de orden (una página obsoleta puede hacer retroceder un
registro hasta que vuelva a cambiar, aunque no se pierde ninguna escritura), un registro guardado
de nuevo justo después de `discardChange(for:)` encuentra la copia del servidor como un conflicto,
una sola instancia del almacén por archivo (garantizado con `FileStore`, `InMemoryStorage` y los
backends propios que informan un `claimIdentity`), el archivo entero se escribe en cada cambio,
los registros se anidan como mucho 64 niveles, una página contiene como mucho 1.000 cambios, un
único cambio mayor que cuatro veces el límite de respuesta detiene la descarga, un cambio cuya
respuesta de envío por sí sola supera el límite de respuesta queda en duda y se aparca tras su
último intento, un epoch anterior sigue rechazado hasta que el servidor informe uno posterior al
del almacén, una página sin epoch hasta que vuelva a informar uno, y los borrados más allá de
10.000 se olvidan. [Garantías y
límites](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/GuaranteesAndLimits.md) tiene la
lista completa.

## Demo

| Sincronizado                                                                 | Sin conexión, dos cambios en espera                                           |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| ![Lista de tareas sincronizada, claro](docs/images/example-synced-light.png) | ![Lista de tareas sin conexión, claro](docs/images/example-offline-light.png) |
| ![Lista de tareas sincronizada, oscuro](docs/images/example-synced-dark.png) | ![Lista de tareas sin conexión, oscuro](docs/images/example-offline-dark.png) |

Las capturas muestran la app de ejemplo [OfflineTodos](Examples/OfflineTodos) en un simulador de
iPhone, tomadas con
[`scripts/capture-example-screens.sh`](scripts/capture-example-screens.sh). En la app, desactiva
**Online**, edita algunas tareas y vuelve a activarlo para ver cómo se sincronizan los cambios;
**Edit on another device** cambia una tarea desde un segundo almacén en el mismo servidor. Abre
`Examples/OfflineTodos/OfflineTodos.xcodeproj`, elige un simulador de iPhone o **My Mac** y pulsa
**Run**; [Examples/README.md](Examples/README.md) tiene los detalles.

## Documentación

Referencia de la API y artículos:

- [Referencia de la API](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/)
  (DocC, publicada en GitHub Pages desde `master`)
- Compílala en local en Xcode con **Product › Build Documentation**, o desde la línea de comandos:

```sh
xcodebuild docbuild -scheme OfflineFirstFramework -destination 'generic/platform=macOS'
```

## Guías

- [Primeros pasos](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/gettingstarted)
  — añade el paquete, define un registro, abre un almacén y muéstralo en SwiftUI
  ([código fuente](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/GettingStarted.md)).
- [Conectar con tu servidor](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/connectingtoyourserver)
  — el transport HTTP, las reglas para tu propio transport, el servidor en memoria
  ([código fuente](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md)).
- [Protocolo del servidor](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/serverprotocol)
  — cada campo de las peticiones push y pull, para desarrolladores de backend
  ([código fuente](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)).
- [Resolver conflictos](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/resolvingconflicts)
  — políticas, relojes lógicos híbridos, combinaciones de campos y tipos sin conflictos
  ([código fuente](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)).
- [Sincronizar en segundo plano](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/syncinginthebackground)
  — sincronización automática, reintentos, el circuit breaker y las tareas de actualización en segundo plano
  ([código fuente](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md)).
- [Proteger y migrar datos](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/protectingandmigratingdata)
  — dónde están los archivos, el cifrado, las migraciones del esquema y los archivos dañados
  ([código fuente](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ProtectingAndMigratingData.md)).

## Requisitos

| Plataforma | Versión mínima |
| ---------- | -------------- |
| iOS        | 17             |
| macOS      | 14             |
| tvOS       | 17             |
| watchOS    | 10             |
| visionOS   | 1              |
| | Herramientas | Swift 6.2 · Xcode 26+ |   |

El servidor de referencia necesita Node 24 o posterior.

## Arquitectura

- `OfflineStore` es un actor que posee una colección. Su estado (registros, cambios pendientes,
  token de cambios, reloj) se escribe como un único archivo JSON; cada cambio se ejecuta sobre una
  copia que pasa a ser la actual solo después de que la escritura haya tenido éxito, de modo que un
  fallo o un disco lleno nunca dejan un cambio aplicado a medias. Cada registro lleva su revisión del
  servidor, su última marca de tiempo y, mientras no está sincronizado, un cambio pendiente con un
  ID que cambia con cada edición local.
- Una sincronización envía los cambios pendientes por lotes (primero los más antiguos, con la
  revisión en la que se basaron), aplica cada resultado y después descarga páginas de cambios del
  servidor posteriores al token de cambios guardado. Un registro que cambió en el dispositivo y en
  el servidor va al `ConflictResolver`; una versión más antigua del servidor se omite. Las ediciones
  hechas mientras un envío está en camino se conservan y se envían a continuación.
- `Sync/` contiene el protocolo de transport, los transports HTTP y en memoria, la política de
  reintentos, el circuit breaker y la conectividad; `Storage/` los almacenes de archivos y del
  Keychain, el cifrado y las migraciones; `Clock/` y `CRDT/` los tipos de valor para ordenar y
  combinar; `SwiftUI/` el modelo observable. Solo `OfflineStore`, `InMemorySyncServer` y
  `SyncedCollection` son tipos de referencia.
- El almacén se protege de servidores que se comportan mal y de archivos dañados: tamaños limitados
  de la cola, las páginas, las respuestas, las revisiones y los tokens de cambios, un token de
  cambios que debe avanzar, como máximo tres envíos por registro y sincronización, registros
  ignorados cuyo ID no coincide, marcas de tiempo más allá de la desviación de reloj permitida y
  nombres de archivo que no pueden salir de su directorio. Las pruebas cubren cada uno de estos casos.
- El archivo completo se reescribe en cada cambio, lo que conviene a colecciones de hasta decenas de
  miles de registros por almacén.

Ejecuta las pruebas en local:

```sh
swift test                                          # macOS
xcodebuild test -scheme OfflineFirstFramework \
  -destination 'platform=iOS Simulator,name=iPhone 17'
(cd Examples/SyncServer && npm test)                # reference server
node Examples/SyncServer/server.mjs &               # end to end, against the server
OFFLINE_FIRST_SERVER_URL=http://localhost:8080 swift test --filter EndToEnd
OFFLINE_FIRST_NODE=$(command -v node) swift test --filter ServerSaveTests  # a failed save, a restart
```

## Hoja de ruta

- Un backend de almacenamiento sobre SQLite para colecciones demasiado grandes para reescribirlas en
  cada cambio.
- Un transport sobre CloudKit (`CKSyncEngine`) para apps sin servidor propio.
- Descargar solo una parte de una colección (por ejemplo, los registros de un proyecto).
- Publicar el paquete en el Swift Package Index; `.spi.yml` ya está en el repositorio.

## Contribuir

Las contribuciones son bienvenidas. Lee la [guía de contribución](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/CONTRIBUTING.md) y el [código de conducta](https://github.com/muhittincamdali/.github/blob/main/CODE_OF_CONDUCT.md) antes de abrir una pull request. Informa de los problemas de seguridad de forma privada, como se describe en la [política de seguridad](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/SECURITY.md).

## Licencia

Publicado bajo la licencia MIT. Consulta [LICENSE](LICENSE).
