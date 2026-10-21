import Foundation
import Testing
@testable import OfflineFirstFramework

private let restartPhase = ProcessInfo.processInfo.environment["OFFLINE_FIRST_E2E_RESTART_PHASE"]
private let restartDirectory = ProcessInfo.processInfo.environment["OFFLINE_FIRST_E2E_STORE_DIR"].map { URL(filePath: $0) }

/// Large records against the reference server across a restart that keeps its data (`--data`).
/// Every start has a new epoch, so after the restart every device pulls everything again from
/// the beginning; with 68 records of 250 KiB that first page is larger than the transport reads
/// unless the server cuts it by bytes.
///
/// Run in two phases, with the server restarted between them on the same data file, as the
/// "Examples" workflow does:
///
/// ```sh
/// node Examples/SyncServer/server.mjs --port 8081 --data /tmp/e2e.json &
/// OFFLINE_FIRST_SERVER_URL=http://localhost:8081 OFFLINE_FIRST_E2E_STORE_DIR=/tmp/e2e-stores \
///   OFFLINE_FIRST_E2E_RESTART_PHASE=before swift test --filter EndToEndRestartTests
/// # stop the server and start it again with the same --data, then the same with =after
/// ```
@Suite("End to end across a server restart",
       .enabled(if: referenceServerURL != nil && restartPhase != nil && restartDirectory != nil,
                "Set OFFLINE_FIRST_SERVER_URL, OFFLINE_FIRST_E2E_STORE_DIR and OFFLINE_FIRST_E2E_RESTART_PHASE."))
struct EndToEndRestartTests {
    private static let ids = (0..<68).map { "big-\($0)" }

    private func directory() throws -> URL { try #require(restartDirectory) }

    private func collection() throws -> String {
        let file = try directory().appending(path: "collection.txt")
        if let name = try? String(contentsOf: file, encoding: .utf8) { return name }
        let name = "e2e-restart-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(at: try directory(), withIntermediateDirectories: true)
        try name.write(to: file, atomically: true, encoding: .utf8)
        return name
    }

    /// A device whose store file lives in the shared directory, or in memory when `kept` is false.
    private func device(_ name: String, kept: Bool = true) throws -> OfflineStore<Note> {
        let url = try #require(referenceServerURL).appending(path: "sync/\(try collection())")
        let storage: any StorageBackend = kept ? try FileStore(directory: try directory().appending(path: name)) : InMemoryStorage()
        return try OfflineStore<Note>(name: name, storage: storage, transport: HTTPSyncTransport<Note>(baseURL: url))
    }

    private func epochFile() throws -> URL { try directory().appending(path: "epoch.txt") }

    @Test(.enabled(if: restartPhase == "before"))
    func beforeTheRestart() async throws {
        let phone = try device("phone")
        let text = String(repeating: "x", count: 250 * 1024)
        try await phone.save(contentsOf: Self.ids.map { Note(id: $0, text: text) })
        #expect(try await phone.sync().pushed == 68)
        let tablet = try device("tablet")
        #expect(try await tablet.sync().pulled == 68)
        try #require(await tablet.state.serverEpoch).write(to: try epochFile(), atomically: true, encoding: .utf8)
    }

    @Test(.enabled(if: restartPhase == "after"))
    func afterTheRestart() async throws {
        let before = try String(contentsOf: try epochFile(), encoding: .utf8)
        // The tablet holds every record; the new epoch makes it pull them all again.
        let tablet = try device("tablet")
        try await tablet.sync()
        let epoch = try #require(await tablet.state.serverEpoch)
        #expect(epoch != before)
        #expect(await tablet.records().map(\.id) == Self.ids)
        #expect(await tablet.quarantinedChanges().isEmpty)
        #expect(await tablet.state.token == "\(epoch).68")
        // A device that never synced pulls everything from the beginning too.
        let laptop = try device("laptop", kept: false)
        #expect(try await laptop.sync().pulled == 68)
        #expect(await laptop.records().map(\.id) == Self.ids)
        // An edit after the restart goes out on the record's revision, without a conflict.
        let phone = try device("phone")
        try await phone.save(Note(id: "big-0", text: "edited after the restart"))
        let report = try await phone.sync()
        #expect(report.pushed == 1)
        #expect(report.conflicts == 0)
    }
}
