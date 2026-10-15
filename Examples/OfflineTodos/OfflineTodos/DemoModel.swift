import Foundation
import Observation
import OfflineFirstFramework

/// A transport that fails like a real one while the demo's "offline" switch is on.
struct SwitchableTransport: SyncTransport {
    let base: any SyncTransport<Todo>
    let connectivity: SimulatedConnectivity

    func push(_ changes: [OutgoingChange<Todo>]) async throws -> [UUID: PushOutcome<Todo>] {
        guard connectivity.isOnline else { throw URLError(.notConnectedToInternet) }
        return try await base.push(changes)
    }

    func pull(since token: String?) async throws -> PullResponse<Todo> {
        guard connectivity.isOnline else { throw URLError(.notConnectedToInternet) }
        return try await base.pull(since: token)
    }
}

/// The demo: this device's store, a second device on the same server, and an offline switch.
///
/// Launch arguments:
/// - `-serverURL http://localhost:8080/sync/todos` syncs with Examples/SyncServer instead of the
///   in-memory server.
/// - `-sample offline|synced|conflict` opens a prepared state (used for the README screenshots).
@MainActor
@Observable
final class DemoModel {
    let store: OfflineStore<Todo>
    let todos: SyncedCollection<Todo>
    private let otherDevice: OfflineStore<Todo>
    private let connectivity: SimulatedConnectivity
    private(set) var isOnline = true
    private(set) var otherDeviceMessage: String?

    init(arguments: UserDefaults = .standard) {
        let connectivity = SimulatedConnectivity()
        let server: any SyncTransport<Todo>
        if let url = arguments.string(forKey: "serverURL").flatMap(URL.init(string:)) {
            server = HTTPSyncTransport<Todo>(baseURL: url)
        } else {
            server = InMemorySyncServer<Todo>(latency: .milliseconds(400))
        }
        let transport = SwitchableTransport(base: server, connectivity: connectivity)
        // Screenshots start from a clean state; the normal demo keeps its data in a file.
        let isSample = arguments.string(forKey: "sample") != nil
        let storage: any StorageBackend = isSample ? InMemoryStorage() : ((try? FileStore.applicationSupport(subdirectory: "OfflineTodos")) ?? InMemoryStorage())
        do {
            store = try OfflineStore<Todo>(name: "todos", storage: storage, transport: transport)
            otherDevice = try OfflineStore<Todo>(name: "other-device", storage: InMemoryStorage(), transport: server)
        } catch {
            fatalError("The demo store could not be opened: \(error)")
        }
        self.connectivity = connectivity
        todos = SyncedCollection(store: store)
    }

    /// Seeds the server on first launch and starts automatic sync.
    func start(sample: String?) async {
        if await store.count == 0 {
            try? await otherDevice.save(contentsOf: [
                Todo(title: "Pack the charger"),
                Todo(title: "Download the boarding pass", isDone: true),
                Todo(title: "Book a table for Friday")
            ])
            _ = try? await otherDevice.sync()
        }
        await store.startAutomaticSync(monitor: connectivity, interval: .seconds(30), debounce: .seconds(1))
        _ = try? await store.sync()
        await prepare(sample: sample)
    }

    func setOnline(_ online: Bool) {
        isOnline = online
        connectivity.setOnline(online)
    }

    func add(_ title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await todos.save(Todo(title: trimmed))
    }

    func toggle(_ todo: Todo) async {
        var changed = todo
        changed.isDone.toggle()
        await todos.save(changed)
    }

    func delete(_ todo: Todo) async {
        await todos.delete(todo.id)
    }

    /// Renames the first to-do on the second device, as if someone edited it on another phone.
    func editOnOtherDevice() async {
        do {
            try await otherDevice.sync()
            guard var todo = await otherDevice.records().first else { return }
            todo.title = todo.title.hasSuffix("(edited on iPad)") ? todo.title : "\(todo.title) (edited on iPad)"
            try await otherDevice.save(todo)
            try await otherDevice.sync()
            otherDeviceMessage = "The iPad renamed “\(todo.title)”."
        } catch {
            otherDeviceMessage = "The iPad could not reach the server: \(error.localizedDescription)"
        }
    }

    private func prepare(sample: String?) async {
        switch sample {
        case "offline":
            setOnline(false)
            await add("Buy sunscreen")
            if let first = await store.records().first { await toggle(first) }
        case "conflict":
            await editOnOtherDevice()
            await todos.sync()
        default:
            break
        }
    }
}
