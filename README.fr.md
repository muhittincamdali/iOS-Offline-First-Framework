<!-- i18n-source: README.md@f0650e0435dcbdd107b34be82133d1fd3898bd38 status=reviewed -->
<!-- brand:start -->

<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-fr-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-fr-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/banner-fr-light.svg" alt="Offline-First Framework: Un stockage local pour les apps Swift qui continue de fonctionner hors ligne et se synchronise avec votre serveur."></picture></p>

<!-- lang-selector:start -->
<p align="center"><a href="README.md">English</a> · <a href="README.tr.md">Türkçe</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · <a href="README.es.md">Español</a> · <a href="README.de.md">Deutsch</a> · <a href="README.fr.md">Français</a> · <a href="README.pt-BR.md">Português (Brasil)</a> · <a href="README.ru.md">Русский</a></p>
<!-- lang-selector:end -->

<p align="center">
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml"><img src="https://github.com/muhittincamdali/iOS-Offline-First-Framework/actions/workflows/ci.yml/badge.svg" alt="État de la CI"></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/releases"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-version-light.svg" alt="Dernière version: v2.0.0"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-platforms-light.svg" alt="Plateformes prises en charge: iOS 17+ · macOS 14+ · tvOS 17+ · watchOS 10+ · visionOS 1+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/Package.swift"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-language-light.svg" alt="Version du langage: Swift 6.2+"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/LICENSE"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/badge-license-light.svg" alt="Licence: MIT"></picture></a>
</p>

<p align="center">
<a href="#démarrage-rapide"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-fr-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-fr-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-start-fr-light.svg" alt="Commencer"></picture></a>
<a href="https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-fr-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-fr-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-docs-fr-light.svg" alt="Documentation"></picture></a>
<a href="https://github.com/muhittincamdali/iOS-Offline-First-Framework/tree/master/Examples"><picture><source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-fr-dark.svg"><source media="(prefers-color-scheme: light)" srcset="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-fr-light.svg"><img src="https://raw.githubusercontent.com/muhittincamdali/iOS-Offline-First-Framework/master/.github/brand/button-examples-fr-light.svg" alt="Exemples"></picture></a>
</p>

> Ceci est une traduction du README anglais. En cas de différence, la version anglaise fait foi.

<!-- brand:end -->
Un paquet Swift qui conserve les enregistrements de votre app dans un fichier sur l’appareil,
met chaque modification en file d’attente et se synchronise avec votre serveur dès qu’il y a une
connexion. L’enregistrement n’attend jamais le réseau : l’app fonctionne de la même façon dans un
avion, dans une cave ou sur une connexion de train instable. Quand le même enregistrement a changé
sur deux appareils, une politique de conflit que vous choisissez décide de ce qui est conservé. Il
fonctionne avec n’importe quel backend : un petit protocole HTTP avec un serveur de référence, votre
propre API via un protocole de deux fonctions, ou un serveur en mémoire pour les tests et les
aperçus. Le paquet n’a aucune dépendance.

## Points forts

- **Des écritures qui n’attendent jamais** — `save` et `delete` vont dans un fichier écrit de façon
  atomique et dans une file durable de modifications en attente qui survit aux redémarrages ; les
  envois qui échouent sont retentés avec un backoff exponentiel et du jitter, puis mis de côté après
  la dernière tentative au lieu d’être perdus.
- **Des conflits tranchés en connaissance de cause** — la dernière écriture l’emporte selon des
  horodatages d’horloge logique hybride (ils ne reculent jamais et donnent le même ordre à tous les
  appareils), le serveur l’emporte, le client l’emporte, votre propre fusion, ou des champs sans
  conflit : `LWWRegister`, `LWWMap`, `GCounter`, `PNCounter` et `ORSet`.
- **N’importe quel backend** — `HTTPSyncTransport` parle un protocole JSON documenté que le serveur
  de référence de [`Examples/SyncServer`](Examples/SyncServer) implémente en environ 280 lignes de
  JavaScript ; toute autre API se place derrière `SyncTransport`, par exemple une API REST avec des
  ETags.
- **Pensé pour SwiftUI** — `SyncedCollection` est un modèle `@Observable` d’un store ; la
  synchronisation automatique s’exécute quand l’appareil se connecte et peu après les modifications
  locales, et un seul appel synchronise depuis une tâche d’actualisation en arrière-plan.
- **Données au repos protégées** — chiffrement des fichiers en AES-GCM avec une clé conservée dans le
  Keychain, classes de protection des données, migrations de schéma des enregistrements et une
  politique pour les fichiers endommagés.
- **Testé contre un vrai serveur** — 324 tests Swift Testing sur macOS et sur un simulateur
  d’iPhone, dont deux tests de propriétés qui soumettent chaque politique de conflit à des
  requêtes perdues, des redémarrages, des réinitialisations du jeton, des synchronisations
  simultanées, de petites limites de pages, des pages périmées, des opérations simultanées et des
  plantages, des tests de scénarios avec une réplique qui répond à un appareil pendant de
  nombreuses synchronisations et avec un plantage à chaque écriture d’une synchronisation, et des
  tests qui envoient des pages de données inutilisables, des enregistrements très profondément
  imbriqués, des pages plus grandes que la limite de réponse et des pages avec plus de
  modifications que demandé, aussi diffusées sans fin sur un socket ; 28 tests Node pour le
  serveur ; et une suite de tests de bout en bout dans la CI qui synchronise des stores via le
  serveur en HTTP, aussi avec 68 enregistrements de 250 Kio à travers un redémarrage du serveur,
  avec 70 réponses de conflit de 250 Kio qui ensemble dépassent la limite de réponse, avec une
  écriture dont la sauvegarde a échoué avant un redémarrage, avec un envoi que le serveur a
  appliqué derrière un proxy qui répond 504, et avec une réplique qui sert des pages d’avant un
  redémarrage après une réinitialisation du jeton.

### Contenu

| Domaine                        | Types                                                                                                                |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------- |
| Store                          | `OfflineStore`, `SyncableRecord`, `SyncStatus`, `SyncReport`, `StoreState`, `PendingChange`                          |
| Connexion au serveur           | `SyncTransport`, `HTTPSyncTransport`, `InMemorySyncServer`, `OutgoingChange`, `RemoteChange`, `PushOutcome`          |
| Conflits                       | `ConflictResolver`, `Conflict`, `ConflictResolution`, `Mergeable`                                                    |
| Champs sans conflit            | `LWWRegister`, `LWWMap`, `GCounter`, `PNCounter`, `ORSet`                                                            |
| Contrôle de la synchronisation | `RetryPolicy`, `CircuitBreaker`, `ConnectivityMonitor`, `NetworkConnectivityMonitor`, `SimulatedConnectivity`        |
| Stockage                       | `FileStore`, `InMemoryStorage`, `StorageBackend`, `StoreEncryption`, `KeychainStore`, `RecordMigration`, `JSONValue` |
| Horloges                       | `HybridLogicalClock`, `HLCTimestamp`, `VectorClock`                                                                  |
| SwiftUI                        | `SyncedCollection`                                                                                                   |

## Démarrage rapide

**1. Ajouter le paquet**

Dans Xcode, choisissez **File › Add Package Dependencies…** et saisissez l’URL du dépôt :

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

Collez-la dans le champ de recherche en haut à droite de la fenêtre. Laissez **Dependency Rule** sur
**Up to Next Major Version** à partir de `2.0.0`, puis cliquez sur **Add Package**. Dans la fenêtre
suivante, choisissez la cible de votre app à côté de **OfflineFirstFramework** et cliquez de nouveau
sur **Add Package**.

**2. Importer le module**

```swift
import OfflineFirstFramework
```

Placez cette ligne en haut du fichier Swift où vous utilisez le store, à côté de `import SwiftUI`.

**3. L’utiliser**

Dans une nouvelle app Xcode (**File › New › Project… › App**, iOS 17 ou version ultérieure),
remplacez tout le contenu de `ContentView.swift` par :

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

Appuyez sur **Run** (⌘R). Saisissez une tâche et appuyez sur Entrée : elle apparaît aussitôt et est
enregistrée sur l’appareil, et la barre d’outils affiche **1 to sync**. Tirez la liste vers le bas
pour synchroniser ; le compteur retombe à 0. Quittez l’app et rouvrez-la : les tâches sont toujours
là. `InMemorySyncServer` tient lieu de backend tant que vous n’en connectez pas un (voir
[Utilisation](#utilisation)).

## Installation

### Swift Package Manager

Dans Xcode, choisissez **File › Add Package Dependencies…** et saisissez l’URL du dépôt :

```text
https://github.com/muhittincamdali/iOS-Offline-First-Framework.git
```

Ou ajoutez-le aux `dependencies` de votre `Package.swift` :

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

La version 2.0 remplace l’API de la 1.0.0, qui ne pouvait pas être résolue comme dépendance ; le
[journal des modifications](CHANGELOG.md) liste ce qui a changé.

## Utilisation

Chaque exemple ci-dessous est copié de
[`ReadmeSamples.swift`](Examples/OfflineTodos/OfflineTodos/ReadmeSamples.swift), que l’app
d’exemple compile et que la suite de tests exécute.

### Synchroniser avec votre serveur en HTTP

Si votre serveur implémente les deux endpoints du
[protocole du serveur](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)
(`POST <base>/push` et `GET <base>/changes?since=<token>`), utilisez le transport HTTP. La closure
`headers` s’exécute avant chaque requête et peut donc récupérer un jeton d’accès à jour :

```swift
let transport = HTTPSyncTransport<Todo>(
    baseURL: URL(string: "http://localhost:8080/sync/todos")!,
    headers: { ["Authorization": "Bearer \(try await token())"] }
)
let store = try OfflineStore<Todo>(name: "todos", transport: transport)
```

`http://localhost:8080` est l’adresse sur laquelle écoute le serveur de référence quand vous le
démarrez avec `node Examples/SyncServer/server.mjs` ; remplacez-la par l’URL de votre serveur.

### Connecter une API existante

Toute API se place derrière `SyncTransport` : une fonction envoie les modifications locales et
indique un résultat pour chacune, l’autre renvoie les modifications du serveur postérieures à un
jeton de modification. Cet exemple fait correspondre le store à une API REST qui versionne les
enregistrements avec des ETags :

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

Les règles qu’un transport doit respecter (révisions, nouvelles tentatives, idempotence,
suppressions, jetons de modification) sont décrites dans l’article
[Se connecter à votre serveur](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md).

### Trancher les conflits

Par défaut, la dernière écriture l’emporte. Pour conserver des parties des deux versions, fusionnez-les :

```swift
/// A to-do counts as done if either device ticked it; the server's title wins.
static let keepTicks = ConflictResolver<Todo>.merge { local, remote in
    var merged = remote
    merged.isDone = local.isDone || remote.isDone
    return merged
}
```

Passez-la en tant que `configuration.conflictResolver` (voir l’exemple suivant). L’article
[Résoudre les conflits](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)
présente les autres politiques et les types de champs sans conflit.

### Chiffrer le fichier et migrer les anciens enregistrements

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

### Synchroniser automatiquement

```swift
await TodoStore.shared.startAutomaticSync()
```

Le store se synchronise ensuite quand l’appareil se connecte, deux secondes après les modifications
locales, quand une modification en échec doit être retentée, et toutes les cinq minutes tant que
l’appareil est connecté. Les erreurs apparaissent dans `SyncedCollection.status` et `lastError`. Pour
synchroniser pendant que l’app est en arrière-plan, voir
[Synchroniser en arrière-plan](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md).

### Tester sans backend

`InMemorySyncServer` se comporte comme un serveur (révisions, conflits, récupération paginée,
interrupteur hors ligne), de sorte que deux stores peuvent jouer deux appareils dans un test
unitaire :

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

## Garanties et limites

Le store tient ces promesses avec toute politique de conflit, malgré les requêtes perdues, les
réponses perdues, les redémarrages de l’app et du serveur et les pages périmées, tant que le
serveur suit le [protocole](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md) :

- Un enregistrement ou une suppression est dans le fichier avant que l’appel ne rende la main, et
  une modification en attente est envoyée jusqu’à ce que le serveur y réponde. Une nouvelle
  tentative garde l’ID de la modification, si bien que le serveur ne l’applique qu’une fois. Seule
  une réponse lue règle une modification : après un statut d’erreur, une connexion perdue ou une
  réponse trop longue pour être lue, la modification reste incertaine jusqu’à son prochain envoi.
- Une copie périmée ne remplace jamais une écriture acceptée par le serveur : le résolveur n’est
  consulté que lorsqu’un enregistrement a changé sur l’appareil et sur un autre appareil, et une
  version plus ancienne du serveur est ignorée, y compris juste après l’acceptation d’une écriture
  de l’appareil lui-même, même après un redémarrage du serveur que l’appareil n’a pas encore vu et
  après `resetChangeToken()`. Une version que l’appareil a écrite lui-même n’est jamais un
  conflit, même quand une page périmée a fait revenir l’enregistrement en arrière et que
  l’utilisateur l’a modifié par-dessus.
- Un autre epoch du serveur ne compte que lorsque deux requêtes d’une même synchronisation le
  signalent, la récupération avec le jeton et la récupération depuis le début : un cache périmé ou
  un autre déploiement derrière la même URL ne peut donc pas faire revenir le store en arrière.
  Une synchronisation qui ne récupère qu’une page suit quand même un redémarrage du serveur, et
  quand les deux requêtes ne concordent pas, la synchronisation échoue au lieu de signaler un
  succès. Les epochs vont dans un seul sens : un epoch antérieur à celui du store, qu’il l’ait
  quitté ou ne l’ait jamais eu, n’est jamais pris, même après `resetChangeToken()`, si bien qu’une
  réplique ou un cache périmé qui répond aux deux requêtes, pendant autant de synchronisations de
  suite que ce soit, ne peut pas non plus faire revenir le store en arrière.
- Les enregistrements supprimés le restent. Un serveur qui a perdu ses données, ou un autre
  serveur, fait tout récupérer à nouveau au store, qui garde ses modifications en attente ; elles
  rencontrent le nouvel historique par la réponse à leur envoi, pas par une page. Un
  enregistrement que l’app ne sait pas décoder, ou imbriqué sur plus de 64 niveaux, est mis de
  côté dans `quarantinedChanges()` au lieu d’arrêter la récupération.
- Les réponses d’un serveur ont un coût borné. Un enregistrement imbriqué sur plus de 64 niveaux
  n’entre jamais dans le store, si bien qu’écrire le fichier ne peut pas faire déborder la pile ;
  une page de données inutilisables, ou de plus de modifications que la récupération n’en a
  demandé (1 000 au plus), est refusée en quelques millisecondes au lieu d’occuper des gigaoctets,
  et son téléchargement est annulé ; une page plus grande que la limite de réponse fait demander
  moins de modifications, et une modification qui dépasse seule la limite, jusqu’à quatre fois
  celle-ci, est mise de côté ; un envoi est découpé en requêtes que la limite de corps du serveur
  accepte et renvoyé par moitiés, avec 16 requêtes de plus au maximum, tant que le serveur répond
  413 ou qu’une réponse 2xx dépasse la limite de réponse, et une modification dont la réponse
  seule la dépasse reste incertaine ; d’un statut d’erreur, seuls les 4 premiers Kio sont lus, si
  bien qu’une passerelle en difficulté coûte une seule tentative échouée ; une marque d’ordre des
  octets UTF-8 est lue.
- Une horloge en avance ou reculée, un serveur qui répond à chaque envoi par un conflit, un
  serveur qui ne répond jamais et un fichier impossible à écrire ont un effet borné : les
  serveurs de référence gardent un horodatage reçu au plus cinq minutes au-delà de leur propre
  horloge, un instant d’horloge erronée sur l’appareil ne se reporte pas sur les écritures
  suivantes, les nouvelles tentatives patientent puis sont mises de côté, une synchronisation
  s’arrête après `syncTimeout`, et les synchronisations attendent tant que le fichier ne peut pas
  être écrit.

Le serveur ne doit jamais donner la même révision à deux versions d’un enregistrement, devrait
envoyer un `epoch` qui ne passe qu’à des epochs ultérieurs (plus longs, ou plus grands octet par
octet) et ne revient jamais, un `sequence` qui continue de compter après un redémarrage, les
horodatages reçus (une heure très en avance sur son horloge ramenée à une limite) et le `changeID`
qui a écrit chaque version, doit retenir les ID de modification d’un redémarrage à l’autre, ne
montrer une écriture dans les pages qu’une fois enregistrée et garder chaque page et la réponse à
chaque modification envoyée dans la limite de réponse du client (une page contient au plus `limit`
modifications, découpée aussi par octets, au moins une modification par page). Limites : les
écritures qu’un serveur a perdues lors d’une restauration ne sont pas renvoyées, un enregistrement
sauvegardé de nouveau juste après `discardChange(for:)` rencontre la copie du serveur comme un
conflit, une seule instance du store par fichier (garanti avec `FileStore`, `InMemoryStorage` et
les backends personnalisés qui fournissent une `claimIdentity`), le fichier entier est écrit à
chaque modification, les enregistrements s’imbriquent sur 64 niveaux au plus, une page contient au
plus 1 000 modifications, une modification seule plus grande que quatre fois la limite de réponse
arrête la récupération, une modification dont la réponse d’envoi seule dépasse la limite de
réponse reste incertaine et est mise en attente après sa dernière tentative, un epoch antérieur
reste refusé jusqu’à ce que le serveur en annonce un plus récent que celui du store, et les
suppressions au-delà de 10 000 sont oubliées. [Garanties et
limites](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/GuaranteesAndLimits.md) donne la
liste complète.

## Démo

| Synchronisé                                                                  | Hors ligne, deux modifications en attente                                   |
| ---------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| ![Liste de tâches synchronisée, clair](docs/images/example-synced-light.png) | ![Liste de tâches hors ligne, clair](docs/images/example-offline-light.png) |
| ![Liste de tâches synchronisée, sombre](docs/images/example-synced-dark.png) | ![Liste de tâches hors ligne, sombre](docs/images/example-offline-dark.png) |

Les captures d’écran montrent l’app d’exemple [OfflineTodos](Examples/OfflineTodos) sur un
simulateur d’iPhone, prises avec
[`scripts/capture-example-screens.sh`](scripts/capture-example-screens.sh). Dans l’app, désactivez
**Online**, modifiez quelques tâches et réactivez-le pour voir les modifications se synchroniser ;
**Edit on another device** modifie une tâche depuis un second store sur le même serveur. Ouvrez
`Examples/OfflineTodos/OfflineTodos.xcodeproj`, choisissez un simulateur d’iPhone ou **My Mac** et
appuyez sur **Run** ; [Examples/README.md](Examples/README.md) donne les détails.

## Documentation

Référence de l’API et articles :

- [Référence de l’API](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/)
  (DocC, publiée sur GitHub Pages depuis `master`)
- Générez-la en local dans Xcode avec **Product › Build Documentation**, ou en ligne de commande :

```sh
xcodebuild docbuild -scheme OfflineFirstFramework -destination 'generic/platform=macOS'
```

## Guides

- [Premiers pas](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/gettingstarted)
  — ajouter le paquet, définir un enregistrement, ouvrir un store, l’afficher dans SwiftUI
  ([source](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/GettingStarted.md)).
- [Se connecter à votre serveur](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/connectingtoyourserver)
  — le transport HTTP, les règles pour votre propre transport, le serveur en mémoire
  ([source](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ConnectingToYourServer.md)).
- [Protocole du serveur](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/serverprotocol)
  — chaque champ des requêtes push et pull, pour les développeurs backend
  ([source](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ServerProtocol.md)).
- [Résoudre les conflits](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/resolvingconflicts)
  — politiques, horloges logiques hybrides, fusions de champs et types sans conflit
  ([source](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ResolvingConflicts.md)).
- [Synchroniser en arrière-plan](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/syncinginthebackground)
  — synchronisation automatique, nouvelles tentatives, circuit breaker et tâches d’actualisation en arrière-plan
  ([source](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/SyncingInTheBackground.md)).
- [Protéger et migrer les données](https://muhittincamdali.github.io/iOS-Offline-First-Framework/documentation/offlinefirstframework/protectingandmigratingdata)
  — où se trouvent les fichiers, chiffrement, migrations de schéma et fichiers endommagés
  ([source](Sources/OfflineFirstFramework/OfflineFirstFramework.docc/ProtectingAndMigratingData.md)).

## Prérequis

| Plateforme | Version minimale |
| ---------- | ---------------- |
| iOS        | 17               |
| macOS      | 14               |
| tvOS       | 17               |
| watchOS    | 10               |
| visionOS   | 1                |
| | Chaîne d’outils | Swift 6.2 · Xcode 26+ |   |

Le serveur de référence nécessite Node 24 ou une version ultérieure.

## Architecture

- `OfflineStore` est un actor qui possède une collection. Son état (enregistrements, modifications
  en attente, jeton de modification, horloge) est écrit dans un seul fichier JSON ; chaque
  modification s’exécute sur une copie qui ne devient la copie courante qu’une fois l’écriture
  réussie, si bien qu’un plantage ou un disque plein ne laisse jamais une modification appliquée à
  moitié. Chaque enregistrement porte sa révision serveur, son dernier horodatage et, tant qu’il n’est
  pas synchronisé, une modification en attente avec un ID qui change à chaque modification locale.
- Une synchronisation envoie les modifications en attente par lots (les plus anciennes d’abord, avec
  la révision sur laquelle elles reposaient), applique chaque résultat, puis récupère des pages de
  modifications du serveur postérieures au jeton de modification enregistré. Un enregistrement qui a
  changé sur l’appareil et sur le serveur va au `ConflictResolver` ; une version plus ancienne du
  serveur est ignorée. Les modifications faites pendant qu’un envoi est en cours sont conservées et
  envoyées ensuite.
- `Sync/` contient le protocole de transport, les transports HTTP et en mémoire, la politique de
  nouvelles tentatives, le circuit breaker et la connectivité ; `Storage/` les stores de fichiers et
  du Keychain, le chiffrement et les migrations ; `Clock/` et `CRDT/` les types valeur pour ordonner
  et fusionner ; `SwiftUI/` le modèle observable. Seuls `OfflineStore`, `InMemorySyncServer` et
  `SyncedCollection` sont des types référence.
- Le store se protège des serveurs qui se comportent mal et des fichiers endommagés : tailles bornées
  de la file, des pages, des réponses, des révisions et des jetons de modification, un jeton de
  modification qui doit avancer, au plus trois envois par enregistrement et par synchronisation,
  enregistrements ignorés dont l’ID ne correspond pas, horodatages au-delà de la dérive d’horloge
  autorisée et noms de fichier qui ne peuvent pas sortir de leur dossier. Les tests couvrent chacun
  de ces points.
- Le fichier entier est réécrit à chaque modification, ce qui convient à des collections allant
  jusqu’à des dizaines de milliers d’enregistrements par store.

Exécutez les tests en local :

```sh
swift test                                          # macOS
xcodebuild test -scheme OfflineFirstFramework \
  -destination 'platform=iOS Simulator,name=iPhone 17'
(cd Examples/SyncServer && npm test)                # reference server
node Examples/SyncServer/server.mjs &               # end to end, against the server
OFFLINE_FIRST_SERVER_URL=http://localhost:8080 swift test --filter EndToEnd
OFFLINE_FIRST_NODE=$(command -v node) swift test --filter ServerSaveTests  # a failed save, a restart
```

## Feuille de route

- Un backend de stockage sur SQLite pour les collections trop volumineuses pour être réécrites à
  chaque modification.
- Un transport sur CloudKit (`CKSyncEngine`) pour les apps sans serveur propre.
- Ne récupérer qu’une partie d’une collection (par exemple les enregistrements d’un projet).
- Référencer le paquet sur le Swift Package Index ; `.spi.yml` est déjà dans le dépôt.

## Contribuer

Les contributions sont les bienvenues. Lisez le [guide de contribution](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/CONTRIBUTING.md) et le [code de conduite](https://github.com/muhittincamdali/.github/blob/main/CODE_OF_CONDUCT.md) avant d’ouvrir une pull request. Signalez les problèmes de sécurité en privé, comme indiqué dans la [politique de sécurité](https://github.com/muhittincamdali/iOS-Offline-First-Framework/blob/master/SECURITY.md).

## Licence

Publié sous licence MIT. Voir [LICENSE](LICENSE).
