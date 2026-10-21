import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// The answer to a push must fit in the transport's response limit. Conflict answers bring the
/// server's version of each record, so 70 conflicts on records of 250 KiB, each within the
/// reference server's limits, made an answer of 17.5 MiB: every push failed with
/// `responseTooLarge`, the changes were parked, `retryFailedChanges()` met the same answer, and
/// the device never got the other device's versions nor the server the device's edits.
@Suite("HTTP transport: push answers larger than the response limit")
struct PushAnswerSizeTests {
    /// Answers each pushed change with a conflict that brings a version of `conflictSize` bytes
    /// of text, or accepts it when its record is in `accepted`. Pulls get an empty page.
    final class Endpoint: Sendable {
        let conflictSize: Int
        let accepted: Set<String>
        private let pushed = OSAllocatedUnfairLock<[[String]]>(initialState: [])

        init(conflictSize: Int, accepted: Set<String> = []) {
            self.conflictSize = conflictSize
            self.accepted = accepted
        }

        /// The record IDs of every push request, in order.
        var requests: [[String]] { pushed.withLock { $0 } }

        func answer(_ request: URLRequest, _ body: Data) throws -> (status: Int, body: Data) {
            guard request.httpMethod == "POST" else { return (200, Data(#"{"changes":[],"token":"t","hasMore":false}"#.utf8)) }
            let changes = (try JSONSerialization.jsonObject(with: body) as? [String: Any])?["changes"] as? [[String: Any]] ?? []
            let ids = changes.map { ($0["id"] as? String ?? "", $0["recordID"] as? String ?? "") }
            pushed.withLock { $0.append(ids.map(\.1)) }
            let text = String(repeating: "s", count: conflictSize)
            let outcomes = ids.map { id, recordID in
                guard !accepted.contains(recordID) else { return #""\#(id)":{"status":"accepted","revision":"r-\#(recordID)"}"# }
                let current = #"{"recordID":"\#(recordID)","record":{"id":"\#(recordID)","text":"\#(text)"},"revision":"s-\#(recordID)","#
                    + #""timestamp":{"wallTime":1700000060000,"counter":0,"nodeID":"server"}}"#
                return #""\#(id)":{"status":"conflict","current":\#(current)}"#
            }
            return (200, Data(("{\"outcomes\":{" + outcomes.joined(separator: ",") + "}}").utf8))
        }
    }

    private func store(_ endpoint: Endpoint, maximumResponseSize: Int) throws -> OfflineStore<Note> {
        let host = "answer-\(UUID().uuidString.lowercased()).example"
        let session = StubURLProtocol.session(host: host) { request, body in try endpoint.answer(request, body) }
        let transport = HTTPSyncTransport<Note>(baseURL: URL(string: "https://\(host)/sync/notes")!, session: session,
                                                maximumResponseSize: maximumResponseSize)
        return try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                      configuration: makeConfiguration(clock: TestClock()))
    }

    /// Eight conflicts of 12 KiB do not fit in 64 KiB; four do. The changes go out again in two
    /// halves, and the server's newer versions replace the device's.
    @Test func aPushWhoseAnswerIsTooLargeIsSentAgainInHalves() async throws {
        let endpoint = Endpoint(conflictSize: 12 * 1024)
        let store = try store(endpoint, maximumResponseSize: 64 * 1024)
        let ids = (0..<8).map { "n\($0)" }
        try await store.save(contentsOf: ids.map { Note(id: $0, text: "device") })
        let report = try await store.sync()
        #expect(report.conflicts == 8)
        #expect(report.parked == 0)
        #expect(await store.pendingChanges().isEmpty)
        #expect(await store.records().map(\.text) == Array(repeating: String(repeating: "s", count: 12 * 1024), count: 8))
        #expect(endpoint.requests == [ids, Array(ids[..<4]), Array(ids[4...])])
    }

    /// A conflict of 40 KiB never fits in 16 KiB. That change is parked with `answerTooLarge`,
    /// the other change of the request is accepted, and the sync goes on to pull.
    @Test func aChangeWhoseAnswerAloneIsTooLargeIsParkedAndTheSyncGoesOn() async throws {
        let endpoint = Endpoint(conflictSize: 40 * 1024, accepted: ["small"])
        let store = try store(endpoint, maximumResponseSize: 16 * 1024)
        try await store.save(contentsOf: [Note(id: "huge", text: "device"), Note(id: "small", text: "device")])
        let report = try await store.sync()
        #expect(report.pushed == 1)
        #expect(report.rejected == 1)
        let failed = try #require(await store.failedChanges().first)
        #expect(failed.recordID == "huge")
        #expect(failed.lastError?.hasPrefix(HTTPSyncTransport<Note>.answerTooLarge) == true)
        #expect(await store.pendingChanges().map(\.recordID) == ["huge"])
        #expect(await store.record("huge")?.text == "device")
        #expect(await store.state.token == "t")
        #expect(endpoint.requests == [["huge", "small"], ["huge"], ["small"]])
    }
}
