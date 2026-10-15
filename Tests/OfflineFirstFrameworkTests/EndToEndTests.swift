import Foundation
import Testing
@testable import OfflineFirstFramework

let referenceServerURL = ProcessInfo.processInfo.environment["OFFLINE_FIRST_SERVER_URL"].flatMap(URL.init(string:))

/// Runs two stores against the reference server in `Examples/SyncServer`.
///
/// Start the server (`node Examples/SyncServer/server.mjs --port 8080`) and run
/// `OFFLINE_FIRST_SERVER_URL=http://localhost:8080 swift test --filter EndToEnd`.
/// Without the variable the suite is skipped; the "Example server" workflow runs it in CI.
@Suite("End to end with the reference server", .enabled(if: referenceServerURL != nil, "Set OFFLINE_FIRST_SERVER_URL to run against Examples/SyncServer."))
struct EndToEndTests {
    static var serverURL: URL? { referenceServerURL }

    private let collection = "e2e-\(UUID().uuidString.prefix(8))"

    private func device(_ name: String) throws -> OfflineStore<Note> {
        let transport = HTTPSyncTransport<Note>(baseURL: try #require(Self.serverURL).appending(path: "sync/\(collection)"))
        return try OfflineStore<Note>(name: name, storage: InMemoryStorage(), transport: transport)
    }

    @Test func twoDevicesShareEditsDeletesAndConflicts() async throws {
        let phone = try device("phone")
        let laptop = try device("laptop")

        try await phone.save(contentsOf: [Note(id: "milk", text: "Buy milk"), Note(id: "call", text: "Call Ana")])
        #expect(try await phone.sync().pushed == 2)
        #expect(try await laptop.sync().pulled == 2)
        #expect(await laptop.records().map(\.id) == ["milk", "call"])

        // Both devices edit the same note; the laptop writes last and wins.
        try await phone.save(Note(id: "milk", text: "Buy oat milk"))
        try await Task.sleep(for: .milliseconds(20))
        try await laptop.save(Note(id: "milk", text: "Buy milk and bread"))
        try await phone.sync()
        let report = try await laptop.sync()
        #expect(report.conflicts == 1)
        try await phone.sync()
        #expect(await phone.record("milk")?.text == "Buy milk and bread")
        #expect(await laptop.record("milk")?.text == "Buy milk and bread")

        try await laptop.delete("call")
        try await laptop.sync()
        try await phone.sync()
        #expect(await phone.records().map(\.id) == ["milk"])
        #expect(await phone.pendingChanges().isEmpty)
        #expect(await laptop.pendingChanges().isEmpty)
    }
}
