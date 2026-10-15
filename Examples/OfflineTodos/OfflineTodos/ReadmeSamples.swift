// The code samples of the README. The example app compiles this file, and the package's test
// target compiles and runs it through the symlink Tests/OfflineFirstFrameworkTests/ReadmeExamples.swift,
// so every sample in the README builds with the current API.
import Foundation
import OfflineFirstFramework
import SwiftUI

// MARK: - Quick start

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

// MARK: - Your server over HTTP

enum HTTPSample {
    /// A store that syncs with a server speaking the HTTP sync protocol, such as the reference
    /// server in Examples/SyncServer. `token` returns the current access token.
    static func makeStore(token: @escaping @Sendable () async throws -> String) throws -> OfflineStore<Todo> {
        let transport = HTTPSyncTransport<Todo>(
            baseURL: URL(string: "http://localhost:8080/sync/todos")!,
            headers: { ["Authorization": "Bearer \(try await token())"] }
        )
        let store = try OfflineStore<Todo>(name: "todos", transport: transport)
        return store
    }

    /// Turns on automatic sync for the quick start store.
    static func startSyncing() async {
        await TodoStore.shared.startAutomaticSync()
    }
}

// MARK: - Your own backend

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

// MARK: - Conflicts, encryption and migrations

enum ReadmeSamples {
    /// A to-do counts as done if either device ticked it; the server's title wins.
    static let keepTicks = ConflictResolver<Todo>.merge { local, remote in
        var merged = remote
        merged.isDone = local.isDone || remote.isDone
        return merged
    }

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
}
