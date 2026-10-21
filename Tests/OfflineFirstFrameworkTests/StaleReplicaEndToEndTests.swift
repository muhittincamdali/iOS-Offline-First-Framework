#if os(macOS)
import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// `StaleReplicaAfterResetTests` against the real reference server: it restarts with `--data`
/// and a later epoch, and a proxy serves the pages a replica kept from before the restart,
/// as the raw bodies the server sent then, to both requests of the sync after
/// `resetChangeToken()`.
///
/// Runs where `OFFLINE_FIRST_NODE` names a Node 24 binary, as the "Examples" workflow does:
/// `OFFLINE_FIRST_NODE=$(command -v node) swift test --filter StaleReplicaEndToEndTests`.
@Suite("Reference server: a stale replica after resetChangeToken()", .serialized,
       .enabled(if: referenceServerNode != nil, "Set OFFLINE_FIRST_NODE to the path of node."))
struct StaleReplicaEndToEndTests {
    /// Pushes through `base`, or fail as on a device without a connection.
    private struct Device: SyncTransport {
        let http: HTTPSyncTransport<Note>
        let offline: OSAllocatedUnfairLock<Bool>
        var serverIdentity: String? { http.serverIdentity }

        func push(_ changes: [OutgoingChange<Note>]) async throws -> [UUID: PushOutcome<Note>] {
            if offline.withLock({ $0 }) { throw URLError(.notConnectedToInternet) }
            return try await http.push(changes)
        }

        func pull(since token: String?) async throws -> PullResponse<Note> {
            try await http.pull(since: token)
        }
    }

    @Test(arguments: ConvergenceTests.Policy.allCases)
    func aReplicaThatAnswersBothRequestsCannotTakeTheStoreBack(policy: ConvergenceTests.Policy) async throws {
        let node = try #require(referenceServerNode)
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: "stale-replica-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = directory.appending(path: "data.json")
        var server = try ReferenceServerProcess(node: node, data: data)
        let address = OSAllocatedUnfairLock(initialState: server.url)
        let proxy = try await RogueProxy.start(upstream: { address.withLock { $0 } }, mode: .pass)
        defer { proxy.stop() }
        let collection = "replica-\(UUID().uuidString.prefix(8))"
        let clock = TestClock()
        let asked = OSAllocatedUnfairLock<[String]>(initialState: [])
        let offline = OSAllocatedUnfairLock(initialState: false)
        let resolver = ConflictResolver<Note> { conflict in
            if let remote = conflict.remoteTimestamp, remote.nodeID == conflict.localTimestamp.nodeID {
                asked.withLock { $0.append("\(conflict.recordID): \(conflict.local?.text ?? "nil") vs \(conflict.remote?.text ?? "nil")") }
            }
            return policy.resolver.resolve(conflict)
        }
        let transport = Device(http: HTTPSyncTransport<Note>(baseURL: proxy.url.appending(path: "sync/\(collection)"),
                                                             session: URLSession(configuration: .ephemeral)), offline: offline)
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock, resolver: resolver))

        try await store.save(contentsOf: [Note(id: "c", text: "v1"), Note(id: "d", text: "d1")])
        try await store.sync()
        // The replica's copy, from before the restart: the page from the beginning and the
        // page after its token.
        let changes = server.url.appending(path: "sync/\(collection)/changes")
        let (first, _) = try await URLSession.shared.data(from: changes)
        let token = try #require(try JSONDecoder().decode(JSONValue.self, from: first)["token"].flatMap { value -> String? in
            if case .string(let text) = value { return text }
            return nil
        })
        var components = try #require(URLComponents(url: changes, resolvingAgainstBaseURL: false))
        components.queryItems = [URLQueryItem(name: "since", value: token)]
        let (second, _) = try await URLSession.shared.data(from: try #require(components.url))

        server.kill()
        server = try ReferenceServerProcess(node: node, data: data)
        let restarted = server.url
        address.withLock { $0 = restarted }
        defer { server.kill() }
        clock.advance(by: 5)
        try await store.save(contentsOf: [Note(id: "d", text: "d2"), Note(id: "c", text: "v1b")])
        try await store.sync()
        let epoch = try #require(await store.state.serverEpoch)
        #expect(await store.state.retiredEpochs.count == 1)

        clock.advance(by: 5)
        try await store.save(Note(id: "c", text: "v2, never pushed"))
        offline.withLock { $0 = true }
        await #expect(throws: URLError.self) { try await store.sync() }

        try await store.resetChangeToken()
        proxy.serveStalePages(RogueProxy.StalePages(first: first, second: second))
        await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        #expect(await store.state.serverEpoch == epoch, "\(policy)")
        #expect(await store.record("d")?.text == "d2", "\(policy)")

        proxy.serveStalePages(nil)
        offline.withLock { $0 = false }
        clock.advance(by: 3_600)
        try await store.retryFailedChanges()
        try await store.sync()
        try await store.sync()
        let fresh = try OfflineStore<Note>(name: "fresh", storage: InMemoryStorage(),
                                           transport: HTTPSyncTransport<Note>(baseURL: restarted.appending(path: "sync/\(collection)")),
                                           configuration: makeConfiguration(clock: clock))
        try await fresh.sync()
        #expect(asked.withLock { $0 }.isEmpty, "\(policy): \(asked.withLock { $0 })")
        #expect(await fresh.record("c")?.text == "v2, never pushed", "\(policy)")
        #expect(await fresh.record("d")?.text == "d2", "\(policy)")
        #expect(await store.record("c")?.text == "v2, never pushed", "\(policy)")
        #expect(await store.record("d")?.text == "d2", "\(policy)")
        #expect(await store.pendingChanges().isEmpty, "\(policy)")
    }
}
#endif
