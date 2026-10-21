<!-- i18n-source: README.md@f0650e0435dcbdd107b34be82133d1fd3898bd38 status=reviewed -->
<!-- brand:start -->

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-de-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-de-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-de-light.svg" alt="Offline-First Framework: Ein lokaler Speicher für Swift-Apps, der offline weiterarbeitet und mit deinem Server synchronisiert."></picture></p>

<!-- lang-selector:start -->
<p align="center"><a href="README.md">English</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a></p>
<!-- lang-selector:end -->

<p align="center">
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml"><img src="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml/badge.svg" alt="CI-Status"></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/releases"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg" alt="Aktuelle Version: v2.0.0"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg" alt="Unterstützte Plattformen: iOS 17+ · macOS 14+ · tvOS 17+ · watchOS 10+ · visionOS 1+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg" alt="Sprachversion: Swift 6.2+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/LICENSE"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg" alt="Lizenz: MIT"></picture></a>
</p>

<p align="center">
<a href="#schnellstart"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-de-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-de-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-de-light.svg" alt="Loslegen"></picture></a>
<a href="https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-de-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-de-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-de-light.svg" alt="Dokumentation"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/tree/master/Examples"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-de-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-de-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-de-light.svg" alt="Beispiele"></picture></a>
</p>

> Dies ist eine Übersetzung der englischen README. Bei Abweichungen gilt die englische Fassung.

<!-- brand:end -->
Ein Swift-Paket, das die Datensätze deiner App in einer Datei auf dem Gerät speichert, jede Änderung
in eine Warteschlange legt und mit deinem Server abgleicht, sobald eine Verbindung besteht. Das
Speichern wartet nie auf das Netzwerk, die App funktioniert also im Flugzeug, im Keller oder bei
einer wackeligen Zugverbindung genauso. Wurde derselbe Datensatz auf zwei Geräten geändert,
entscheidet eine Konfliktrichtlinie, die du wählst, was behalten wird. Das Paket funktioniert mit
jedem Backend: einem kleinen HTTP-Protokoll mit Referenzserver, deiner eigenen API über ein
Protokoll mit zwei Funktionen oder einem In-Memory-Server für Tests und Vorschauen. Das Paket hat
keine Abhängigkeiten.

## Highlights

- **Schreibvorgänge, die nie warten** — `save` und `delete` gehen in eine atomar geschriebene Datei
  und in eine dauerhafte Warteschlange ausstehender Änderungen, die Neustarts übersteht;
  fehlgeschlagene Übertragungen werden mit exponentiellem Backoff und Jitter wiederholt und nach dem
  letzten Versuch zurückgestellt, statt verloren zu gehen.
- **Konflikte bewusst entschieden** — Last Write Wins auf Basis von Zeitstempeln einer hybriden
  logischen Uhr (sie gehen nie zurück und geben jedem Gerät dieselbe Reihenfolge), Server gewinnt,
  Client gewinnt, dein eigenes Zusammenführen oder konfliktfreie Felder: `LWWRegister`, `LWWMap`,
  `GCounter`, `PNCounter` und `ORSet`.
- **Jedes Backend** — `HTTPSyncTransport` spricht ein dokumentiertes JSON-Protokoll, das der
  Referenzserver in [`Examples/SyncServer`](Examples/SyncServer) in etwa 280 Zeilen JavaScript
  umsetzt; jede andere API passt hinter `SyncTransport`, zum Beispiel eine REST-API mit ETags.
- **Gemacht für SwiftUI** — `SyncedCollection` ist ein `@Observable`-Modell eines Stores; die
  automatische Synchronisierung läuft, wenn das Gerät online geht und kurz nach lokalen
  Änderungen, und ein einziger Aufruf synchronisiert aus einer Hintergrundaktualisierung heraus.
- **Gespeicherte Daten geschützt** — AES-GCM-Dateiverschlüsselung mit einem Schlüssel im Keychain,
  Datenschutzklassen, Schemamigrationen für Datensätze und eine Richtlinie für beschädigte Dateien.
- **Gegen einen echten Server getestet** — 324 Swift-Testing-Tests auf macOS und in einem
  iPhone-Simulator, darunter zwei Eigenschaftstests, die jede Konfliktrichtlinie durch verlorene
  Anfragen, Neustarts, zurückgesetzte Tokens, überlappende Synchronisierungen, kleine
  Seitengrenzen, veraltete Seiten, gleichzeitige Operationen und Abstürze schicken, Szenariotests
  mit einem Replikat, das einem Gerät viele Synchronisierungen lang antwortet, und mit einem
  Absturz bei jedem Schreibvorgang einer Synchronisierung, und Tests, die Seiten voller
  unbrauchbarer Daten, sehr tief verschachtelte Datensätze, Seiten über dem Antwortlimit und
  Seiten mit mehr Änderungen als angefordert senden, auch endlos über einen Socket gestreamt; 28
  Node-Tests für den Server; und eine End-to-End-Testsuite in der CI, die Stores über HTTP durch
  den Server synchronisiert, auch mit 68 Datensätzen zu 250 KiB über einen Serverneustart hinweg,
  mit 70 Konfliktantworten zu 250 KiB, die zusammen das Antwortlimit überschreiten, mit einem
  Schreibvorgang, dessen Speichern vor einem Neustart fehlschlug, mit einer Übertragung, die der
  Server hinter einem Proxy angewandt hat, der mit 504 antwortet, und mit einem Replikat, das nach
  dem Zurücksetzen des Tokens Seiten von vor einem Neustart liefert.

### Was enthalten ist

| Bereich                    | Typen                                                                                                                |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Store                      | `OfflineStore`, `SyncableRecord`, `SyncStatus`, `SyncReport`, `StoreState`, `PendingChange`                          |
| Serververbindung           | `SyncTransport`, `HTTPSyncTransport`, `InMemorySyncServer`, `OutgoingChange`, `RemoteChange`, `PushOutcome`          |
| Konflikte                  | `ConflictResolver`, `Conflict`, `ConflictResolution`, `Mergeable`                                                    |
| Konfliktfreie Felder       | `LWWRegister`, `LWWMap`, `GCounter`, `PNCounter`, `ORSet`                                                            |
| Synchronisierungssteuerung | `RetryPolicy`, `CircuitBreaker`, `ConnectivityMonitor`, `NetworkConnectivityMonitor`, `SimulatedConnectivity`        |
| Speicherung                | `FileStore`, `InMemoryStorage`, `StorageBackend`, `StoreEncryption`, `KeychainStore`, `RecordMigration`, `JSONValue` |
| Uhren                      | `HybridLogicalClock`, `HLCTimestamp`, `VectorClock`                                                                  |
| SwiftUI                    | `SyncedCollection`                                                                                                   |

## Schnellstart

**1. Paket hinzufügen**

Wähle in Xcode **File › Add Package Dependencies…** und gib die Repository-URL ein:

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

Füge sie in das Suchfeld oben rechts im Fenster ein. Lass **Dependency Rule** auf **Up to Next Major
Version** ab `2.0.0` stehen und klicke auf **Add Package**. Wähle im nächsten Fenster neben
**OfflineFirstFramework** dein App-Target aus und klicke noch einmal auf **Add Package**.

**2. Modul importieren**

```swift
import OfflineFirstFramework
```

Setze diese Zeile an den Anfang der Swift-Datei, in der du den Store verwendest, neben
`import SwiftUI`.

**3. Verwenden**

Ersetze in einer neuen Xcode-App (**File › New › Project… › App**, iOS 17 oder neuer) den gesamten
Inhalt von `ContentView.swift` durch:

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

Drücke **Run** (⌘R). Tippe eine Aufgabe ein und drücke Return: Sie erscheint sofort und wird auf dem
Gerät gespeichert, und die Symbolleiste zeigt **1 to sync**. Ziehe die Liste nach unten, um zu
synchronisieren; der Zähler springt zurück auf 0. Beende die App und öffne sie erneut: Die Aufgaben
sind noch da. `InMemorySyncServer` steht für dein Backend, bis du eines anbindest (siehe
[Verwendung](#verwendung)).

## Installation

### Swift Package Manager

Wähle in Xcode **File › Add Package Dependencies…** und gib die Repository-URL ein:

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

Oder füge es zu den `dependencies` in deiner `Package.swift` hinzu:

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

Version 2.0 ersetzt die API von 1.0.0, die sich nicht als Abhängigkeit auflösen ließ; das
[Änderungsprotokoll](CHANGELOG.md) listet auf, was sich geändert hat.

## Verwendung

Jedes Beispiel unten stammt aus
[`ReadmeSamples.swift`](Examples/OfflineTodos/OfflineTodos/ReadmeSamples.swift); die Beispiel-App
baut diese Datei, und die Testsuite führt sie aus.

### Über HTTP mit deinem Server synchronisieren

Wenn dein Server die beiden Endpunkte des
[Serverprotokolls](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)
(`POST <base>/push` und `GET <base>/changes?since=<token>`) umsetzt, verwende den HTTP-Transport.
Die `headers`-Closure läuft vor jeder Anfrage und kann daher ein frisches Zugriffstoken holen:

```swift
let transport = HTTPSyncTransport<Todo>(
    baseURL: URL(string: "http://localhost:8080/sync/todos")!,
    headers: { ["Authorization": "Bearer \(try await token())"] }
)
let store = try OfflineStore<Todo>(name: "todos", transport: transport)
```

`http://localhost:8080` ist die Adresse, auf der der Referenzserver lauscht, wenn du ihn mit
`node Examples/SyncServer/server.mjs` startest; ersetze sie durch die URL deines Servers.

### Eine bestehende API anbinden

Jede API passt hinter `SyncTransport`: Eine Funktion sendet lokale Änderungen und meldet für jede
ein Ergebnis, die andere liefert Serveränderungen nach einem Änderungstoken. Dieses Beispiel bildet
den Store auf eine REST-API ab, die Datensätze mit ETags versioniert:

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

Die Regeln, die ein Transport einhalten muss (Revisionen, Wiederholungen, Idempotenz, Löschungen,
Änderungstokens), stehen im Artikel
[Mit deinem Server verbinden](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md).

### Konflikte entscheiden

Standard ist Last Write Wins. Um Teile beider Versionen zu behalten, führe sie zusammen:

```swift
/// A to-do counts as done if either device ticked it; the server's title wins.
static let keepTicks = ConflictResolver<Todo>.merge { local, remote in
    var merged = remote
    merged.isDone = local.isDone || remote.isDone
    return merged
}
```

Übergib es als `configuration.conflictResolver` (siehe das nächste Beispiel). Der Artikel
[Konflikte lösen](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)
behandelt die anderen Richtlinien und die konfliktfreien Feldtypen.

### Die Datei verschlüsseln und alte Datensätze migrieren

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

### Automatisch synchronisieren

```swift
await TodoStore.shared.startAutomaticSync()
```

Danach synchronisiert der Store, wenn das Gerät online geht, zwei Sekunden nach lokalen
Änderungen, wenn eine fehlgeschlagene Änderung wieder an der Reihe ist, und solange das Gerät online
ist alle fünf Minuten. Fehler erscheinen in `SyncedCollection.status` und `lastError`. Zur
Synchronisierung, während die App im Hintergrund ist, siehe
[Im Hintergrund synchronisieren](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md).

### Ohne Backend testen

`InMemorySyncServer` verhält sich wie ein Server (Revisionen, Konflikte, seitenweises Abrufen, ein
Offline-Schalter), sodass zwei Stores in einem Unit-Test zwei Geräte spielen können:

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

## Garantien und Grenzen

Der Store hält diese Zusagen bei jeder Konfliktrichtlinie ein, auch bei verlorenen Anfragen,
verlorenen Antworten, Neustarts von App und Server und veralteten Seiten, solange der Server dem
[Protokoll](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md) folgt:

- Ein Speichern oder Löschen steht in der Datei, bevor der Aufruf zurückkehrt, und eine
  ausstehende Änderung wird übertragen, bis der Server sie beantwortet. Eine Wiederholung behält
  die Änderungs-ID, sodass der Server sie nur einmal anwendet. Nur eine gelesene Antwort
  entscheidet über eine Änderung: Nach einem Fehlerstatus, einer abgebrochenen Verbindung oder
  einer Antwort, die zu lang zum Lesen ist, bleibt die Änderung bis zu ihrer nächsten Übertragung
  ungewiss.
- Eine veraltete Kopie ersetzt nie einen Schreibvorgang, den der Server angenommen hat: Der
  Resolver wird nur gefragt, wenn sich ein Datensatz auf dem Gerät und auf einem anderen Gerät
  geändert hat, und eine ältere Serverversion wird übersprungen, auch direkt nachdem der Server
  den eigenen Schreibvorgang des Geräts angenommen hat, selbst über einen Serverneustart hinweg,
  den das Gerät noch nicht gesehen hat, und nach `resetChangeToken()`. Eine Version, die das Gerät
  selbst geschrieben hat, ist nie ein Konflikt, auch wenn eine veraltete Seite den Datensatz
  zurückgesetzt und der Nutzer darauf weiterbearbeitet hat.
- Eine andere Server-Epoch zählt nur, wenn zwei Anfragen derselben Synchronisierung sie melden,
  der Abruf mit dem Token und der Abruf von Anfang an. Ein veralteter Cache oder ein anderes
  Deployment hinter derselben URL kann den Store also nicht zurücksetzen. Eine Synchronisierung,
  die nur eine Seite abruft, folgt trotzdem einem Serverneustart, und wenn die beiden Anfragen
  nicht übereinstimmen, schlägt die Synchronisierung fehl, statt Erfolg zu melden. Epochs laufen
  nur in eine Richtung: Eine frühere Epoch als die des Stores, ob er sie verlassen oder nie gehabt
  hat, wird nie übernommen, auch nicht nach `resetChangeToken()`, sodass auch ein veraltetes
  Replikat oder ein Cache, das beide Anfragen beantwortet, wie viele Synchronisierungen in Folge
  auch immer, den Store nicht zurücksetzen kann.
- Gelöschte Datensätze bleiben gelöscht. Ein Server, der seine Daten verloren hat, oder ein
  anderer Server lässt den Store alles neu abrufen, wobei ausstehende Änderungen erhalten bleiben;
  sie treffen auf die neue Historie über die Antwort auf ihre Übertragung, nicht über eine Seite.
  Ein Datensatz, den die App nicht dekodieren kann oder der tiefer als 64 Ebenen verschachtelt
  ist, wird in `quarantinedChanges()` zurückgestellt, statt den Abruf anzuhalten.
- Die Antworten eines Servers kosten nur begrenzt. Ein Datensatz, der tiefer als 64 Ebenen
  verschachtelt ist, gelangt nie in den Store, sodass das Schreiben der Datei den Stack nicht
  überlaufen lassen kann; eine Seite voller unbrauchbarer Daten oder mit mehr Änderungen, als der
  Abruf angefordert hat (höchstens 1.000), wird in Millisekunden abgewiesen, statt Gigabytes zu
  belegen, und ihr Download abgebrochen; eine Seite, die größer als das Antwortlimit ist, lässt
  den Abruf weniger Änderungen anfordern, und eine einzelne Änderung, die allein größer als das
  Limit ist, wird bis zum Vierfachen des Limits zurückgestellt; eine Übertragung wird in Anfragen
  aufgeteilt, die das Body-Limit des Servers annimmt, und in Hälften erneut gesendet, mit
  höchstens 16 zusätzlichen Anfragen, solange der Server 413 antwortet oder eine 2xx-Antwort
  länger als das Antwortlimit ist, und eine Änderung, deren Antwort allein länger ist, bleibt
  ungewiss; von einem Fehlerstatus werden nur die ersten 4 KiB gelesen, sodass ein Gateway in
  Schwierigkeiten einen fehlgeschlagenen Versuch kostet; eine UTF-8-Byte-Order-Mark wird gelesen.
- Eine vorgehende oder zurückgestellte Uhr, ein Server, der jede Übertragung mit einem Konflikt
  beantwortet, ein Server, der nie antwortet, und eine Datei, die sich nicht schreiben lässt,
  wirken nur begrenzt: Die Referenzserver speichern einen übertragenen Zeitstempel höchstens fünf
  Minuten nach ihrer eigenen Uhr, ein kurzer Moment einer falschen Geräteuhr geht nicht auf
  spätere Schreibvorgänge über, Wiederholungen warten und werden geparkt, eine Synchronisierung
  endet nach `syncTimeout`, und Synchronisierungen warten, solange die Datei nicht geschrieben
  werden kann.

Der Server darf dieselbe Revision nie zwei Versionen eines Datensatzes geben, sollte eine `epoch`,
die nur zu späteren wechselt (länger oder Byte für Byte größer) und nie zurückkehrt, eine
`sequence`, die über Neustarts weiterzählt, die übertragenen Zeitstempel (eine Zeit, die seiner
Uhr weit vorausliegt, auf eine Grenze zurückgesetzt) und die `changeID`, die jede Version
geschrieben hat, senden, muss sich Änderungs-IDs über Neustarts hinweg merken, einen
Schreibvorgang erst in Seiten zeigen, wenn er gespeichert ist, und jede Seite sowie die Antwort
auf jede übertragene Änderung innerhalb des Antwortlimits des Clients halten (eine Seite enthält
höchstens `limit` Änderungen, auch nach Bytes begrenzt, mindestens eine Änderung pro Seite).
Grenzen: Schreibvorgänge, die ein Server bei einer Wiederherstellung verloren hat, werden nicht
erneut hochgeladen, ein Datensatz, der direkt nach `discardChange(for:)` erneut gespeichert wird,
trifft die Kopie des Servers als Konflikt, eine Store-Instanz pro Datei (durchgesetzt für
`FileStore`, `InMemoryStorage` und eigene Backends, die eine `claimIdentity` melden), die ganze
Datei wird bei jeder Änderung geschrieben, Datensätze sind höchstens 64 Ebenen tief verschachtelt,
eine Seite enthält höchstens 1.000 Änderungen, eine einzelne Änderung, die größer als das
Vierfache des Antwortlimits ist, hält den Abruf an, eine Änderung, deren Übertragungsantwort
allein größer als das Antwortlimit ist, bleibt ungewiss und wird nach ihrem letzten Versuch
geparkt, eine frühere Epoch bleibt abgewiesen, bis der Server eine spätere als die des Stores
meldet, und Löschungen jenseits von 10.000 werden vergessen. [Garantien und
Grenzen](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/GuaranteesAndLimits.md) enthält
die vollständige Liste.

## Demo

| Synchronisiert                                                                | Offline, zwei Änderungen warten                                        |
| ----------------------------------------------------------------------------- | ---------------------------------------------------------------------- |
| ![Synchronisierte Aufgabenliste, hell](docs/images/example-synced-light.png)  | ![Aufgabenliste offline, hell](docs/images/example-offline-light.png)  |
| ![Synchronisierte Aufgabenliste, dunkel](docs/images/example-synced-dark.png) | ![Aufgabenliste offline, dunkel](docs/images/example-offline-dark.png) |

Die Screenshots zeigen die Beispiel-App [OfflineTodos](Examples/OfflineTodos) in einem
iPhone-Simulator, aufgenommen mit
[`scripts/capture-example-screens.sh`](scripts/capture-example-screens.sh). Schalte in der App
**Online** aus, bearbeite ein paar Aufgaben und schalte es wieder ein, um zu sehen, wie die
Änderungen synchronisiert werden; **Edit on another device** ändert eine Aufgabe aus einem zweiten
Store auf demselben Server. Öffne `Examples/OfflineTodos/OfflineTodos.xcodeproj`, wähle einen
iPhone-Simulator oder **My Mac** und drücke **Run**; Details stehen in
[Examples/README.md](Examples/README.md).

## Dokumentation

API-Referenz und Artikel:

- [API-Referenz](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/)
  (DocC, von `master` auf GitHub Pages veröffentlicht)
- Baue sie lokal in Xcode mit **Product › Build Documentation** oder über die Kommandozeile:

```sh
xcodebuild docbuild -scheme OfflineFirstFramework -destination 'generic/platform=macOS'
```

## Anleitungen

- [Erste Schritte](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/gettingstarted)
  — das Paket hinzufügen, einen Datensatz definieren, einen Store öffnen, ihn in SwiftUI anzeigen
  ([Quelle](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/GettingStarted.md)).
- [Mit deinem Server verbinden](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/connectingtoyourserver)
  — der HTTP-Transport, die Regeln für deinen eigenen Transport, der In-Memory-Server
  ([Quelle](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md)).
- [Serverprotokoll](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/serverprotocol)
  — jedes Feld der Push- und Pull-Anfragen, für Backend-Entwickler
  ([Quelle](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)).
- [Konflikte lösen](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/resolvingconflicts)
  — Richtlinien, hybride logische Uhren, Feldzusammenführungen und konfliktfreie Typen
  ([Quelle](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)).
- [Im Hintergrund synchronisieren](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/syncinginthebackground)
  — automatische Synchronisierung, Wiederholungen, der Circuit Breaker und Hintergrundaktualisierungen
  ([Quelle](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md)).
- [Daten schützen und migrieren](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/protectingandmigratingdata)
  — wo die Dateien liegen, Verschlüsselung, Schemamigrationen und beschädigte Dateien
  ([Quelle](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ProtectingAndMigratingData.md)).

## Voraussetzungen

| Plattform | Mindestversion |
| --------- | -------------- |
| iOS       | 17             |
| macOS     | 14             |
| tvOS      | 17             |
| watchOS   | 10             |
| visionOS  | 1              |
| | Toolchain | Swift 6.2 · Xcode 26+ |  |

Der Referenzserver benötigt Node 24 oder neuer.

## Architektur

- `OfflineStore` ist ein Actor, dem eine Collection gehört. Sein Zustand (Datensätze, ausstehende
  Änderungen, Änderungstoken, Uhr) wird als eine JSON-Datei geschrieben; jede Änderung läuft auf einer
  Kopie, die erst nach erfolgreichem Schreiben aktuell wird, sodass ein Absturz oder ein volles
  Laufwerk nie eine halb angewendete Änderung hinterlässt. Jeder Datensatz trägt seine
  Serverrevision, seinen letzten Zeitstempel und, solange er nicht synchronisiert ist, eine
  ausstehende Änderung mit einer ID, die sich bei jeder lokalen Bearbeitung ändert.
- Eine Synchronisierung überträgt ausstehende Änderungen in Stapeln (die ältesten zuerst, mit der
  Revision, auf der sie beruhten), wendet jedes Ergebnis an und ruft dann Seiten mit
  Serveränderungen nach dem gespeicherten Änderungstoken ab. Ein Datensatz, der sich auf dem Gerät
  und auf dem Server geändert hat, geht an den `ConflictResolver`; eine ältere Serverversion wird
  übersprungen. Bearbeitungen, die während einer laufenden Übertragung erfolgen, bleiben erhalten
  und werden als Nächstes übertragen.
- `Sync/` enthält das Transport-Protokoll, die HTTP- und In-Memory-Transporte, die
  Wiederholungsrichtlinie, den Circuit Breaker und die Konnektivität; `Storage/` die Datei- und
  Keychain-Stores, die Verschlüsselung und die Migrationen; `Clock/` und `CRDT/` die Werttypen zum
  Ordnen und Zusammenführen; `SwiftUI/` das beobachtbare Modell. Nur `OfflineStore`,
  `InMemorySyncServer` und `SyncedCollection` sind Referenztypen.
- Der Store schützt sich vor fehlerhaft arbeitenden Servern und beschädigten Dateien: begrenzte
  Größen von Warteschlange, Seiten, Antworten, Revisionen und Änderungstokens, ein Änderungstoken,
  das sich weiterbewegen muss, höchstens drei Übertragungen pro Datensatz und Synchronisierung,
  ignorierte Datensätze, deren ID nicht passt, Zeitstempel jenseits der erlaubten Uhrenabweichung und
  Dateinamen, die ihr Verzeichnis nicht verlassen können. Die Tests decken jeden dieser Punkte ab.
- Bei jeder Änderung wird die ganze Datei neu geschrieben, was zu Collections mit bis zu zehntausenden
  Datensätzen pro Store passt.

Führe die Tests lokal aus:

```sh
swift test                                          # macOS
xcodebuild test -scheme OfflineFirstFramework \
  -destination 'platform=iOS Simulator,name=iPhone 17'
(cd Examples/SyncServer && npm test)                # reference server
node Examples/SyncServer/server.mjs &               # end to end, against the server
OFFLINE_FIRST_SERVER_URL=http://localhost:8080 swift test --filter EndToEnd
OFFLINE_FIRST_NODE=$(command -v node) swift test --filter ServerSaveTests  # a failed save, a restart
```

## Roadmap

- Ein Speicher-Backend auf SQLite für Collections, die zu groß sind, um sie bei jeder Änderung neu
  zu schreiben.
- Ein Transport auf CloudKit (`CKSyncEngine`) für Apps ohne eigenen Server.
- Nur einen Teil einer Collection abrufen (zum Beispiel die Datensätze eines Projekts).
- Das Paket im Swift Package Index listen; `.spi.yml` liegt bereits im Repository.

## Mitwirken

Beiträge sind willkommen. Lies vor einem Pull Request den [Leitfaden für Beiträge](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/CONTRIBUTING.md) und den [Verhaltenskodex](https://github.com/muhittincamdali/.github/blob/main/CODE_OF_CONDUCT.md). Sicherheitsprobleme meldest du vertraulich, wie in der [Sicherheitsrichtlinie](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/SECURITY.md) beschrieben.

## Lizenz

Veröffentlicht unter der MIT-Lizenz. Siehe [LICENSE](LICENSE).
