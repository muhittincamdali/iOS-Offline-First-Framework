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

    /// A conflict of 40 KiB never fits in 16 KiB. That answer was never read, so the change was
    /// not settled: it used to be rejected and parked as not applied, which dropped its in-doubt
    /// mark although the server may have applied it. It now stays in doubt and waits for its
    /// retry date; the other change of the request is accepted, and the sync goes on to pull.
    @Test func aChangeWhoseAnswerAloneIsTooLargeStaysInDoubtAndTheSyncGoesOn() async throws {
        let endpoint = Endpoint(conflictSize: 40 * 1024, accepted: ["small"])
        let store = try store(endpoint, maximumResponseSize: 16 * 1024)
        try await store.save(contentsOf: [Note(id: "huge", text: "device"), Note(id: "small", text: "device")])
        let report = try await store.sync()
        #expect(report.pushed == 1)
        #expect(report.rejected == 0)
        #expect(await store.failedChanges().isEmpty)
        let pending = try #require(await store.pendingChanges().first)
        #expect(pending.recordID == "huge")
        #expect(pending.attempts == 1)
        #expect(await store.state.entries["huge"]?.pending?.isInDoubt == true)
        #expect(await store.record("huge")?.text == "device")
        #expect(await store.state.token == "t")
        #expect(endpoint.requests == [["huge", "small"], ["huge"], ["small"]])
    }

    /// Forty conflicts of 12 KiB fit in 16 KiB one by one only. Halving them all took 79
    /// requests; it stops after `maximumSplitRequests` more, and the changes it did not reach
    /// wait for their retry date in doubt.
    @Test func halvingAPushAddsABoundedNumberOfRequests() async throws {
        let endpoint = Endpoint(conflictSize: 12 * 1024)
        let store = try store(endpoint, maximumResponseSize: 16 * 1024)
        try await store.save(contentsOf: (0..<40).map { Note(id: "n\($0)", text: "device") })
        let report = try await store.sync()
        #expect(endpoint.requests.count == 1 + HTTPSyncTransport<Note>.maximumSplitRequests)
        #expect(report.conflicts > 0)
        let waiting = await store.pendingChanges().filter { $0.lastError == "The server did not answer this change." }
        #expect(!waiting.isEmpty)
        #expect(waiting.allSatisfy { !$0.isParked && $0.attempts == 1 })
        #expect(await store.failedChanges().isEmpty)
    }
}
