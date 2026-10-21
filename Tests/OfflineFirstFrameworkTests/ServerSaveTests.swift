#if os(macOS)
import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A push whose save failed, followed by a restart of the reference server before any save
/// succeeded. The server used to apply the push in memory and show it in pages although it
/// answered 500: the device pulled its own write, took it for applied, and after the restart
/// kept a record that no other device ever got.
///
/// Runs where `OFFLINE_FIRST_NODE` names a Node 24 binary, as the "Examples" workflow does:
/// `OFFLINE_FIRST_NODE=$(command -v node) swift test --filter ServerSaveTests`.
@Suite("Reference server: a failed save and a restart", .enabled(if: referenceServerNode != nil, "Set OFFLINE_FIRST_NODE to the path of node."))
struct ServerSaveTests {
    @Test func aWriteWhoseSaveFailedReachesEveryDeviceAfterARestart() async throws {
        let node = try #require(referenceServerNode)
        let directory = URL(filePath: NSTemporaryDirectory()).appending(path: "server-save-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = directory.appending(path: "data.json")
        // A directory where the temporary file of a save goes makes every save fail.
        let blocker = directory.appending(path: "data.json.tmp")

        var server = try ReferenceServerProcess(node: node, data: data)
        // The server's port changes with every start; the collection stays.
        let address = OSAllocatedUnfairLock(initialState: server.url)
        let clock = TestClock()
        func device(_ name: String) throws -> OfflineStore<Note> {
            let transport = ReplaceableURLTransport(server: { address.withLock { $0 }.appending(path: "sync/notes") })
            return try OfflineStore<Note>(name: name, storage: InMemoryStorage(), transport: transport,
                                          configuration: makeConfiguration(clock: clock))
        }
        let phone = try device("phone")
        try await phone.save(Note(id: "a", text: "saved"))
        try await phone.sync()

        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: false)
        try await phone.save(Note(id: "b", text: "its save fails"))
        await #expect(throws: HTTPSyncTransport<Note>.Failure.self) { try await phone.sync() }
        // Before its retry date the next sync only pulls: it must not meet the write as applied.
        try await phone.sync()
        #expect(await phone.pendingChanges().map(\.recordID) == ["b"])

        server.kill()
        try FileManager.default.removeItem(at: blocker)
        server = try ReferenceServerProcess(node: node, data: data)
        let url = server.url
        address.withLock { $0 = url }
        defer { server.kill() }
        clock.advance(by: 60)
        try await phone.sync()
        let fresh = try device("fresh")
        try await fresh.sync()
        #expect(await phone.pendingChanges().isEmpty)
        #expect(await phone.records().map(\.id).sorted() == ["a", "b"])
        #expect(await fresh.records().map(\.id).sorted() == ["a", "b"])
    }
}

/// An HTTP transport whose base URL is looked up for every request, so a store follows the
/// server to the port of its next start.
private struct ReplaceableURLTransport: SyncTransport {
    let server: @Sendable () -> URL
    var serverIdentity: String? { "reference-server/notes" }

    func push(_ changes: [OutgoingChange<Note>]) async throws -> [UUID: PushOutcome<Note>] {
        try await HTTPSyncTransport<Note>(baseURL: server()).push(changes)
    }

    func pull(since token: String?) async throws -> PullResponse<Note> {
        try await HTTPSyncTransport<Note>(baseURL: server()).pull(since: token)
    }
}
#endif
