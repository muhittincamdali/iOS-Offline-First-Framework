import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A push must fit in the server's request limit (1 MiB for the reference server). The store
/// pushes up to 100 changes at once, so a few large records made every push of the batch fail
/// with status 413 until all of them were parked, although each one was within the limits.
@Suite("HTTP transport: pushes larger than the server's request limit")
struct PushSizeTests {
    /// Accepts a push body up to `limit` bytes, answers 413 to a larger one, and 503 to the
    /// request numbered `failing`. Records the size of every body.
    final class Endpoint: Sendable {
        let limit: Int
        let failing: Int?
        private let sizes = OSAllocatedUnfairLock<[Int]>(initialState: [])

        init(limit: Int, failing: Int? = nil) {
            self.limit = limit
            self.failing = failing
        }

        var bodies: [Int] { sizes.withLock { $0 } }

        func answer(_ request: URLRequest, _ body: Data) throws -> (status: Int, body: Data) {
            guard request.httpMethod == "POST" else { return (200, Data(#"{"changes":[],"token":"t","hasMore":false}"#.utf8)) }
            let number = sizes.withLock { $0.append(body.count); return $0.count }
            if number == failing { return (503, Data()) }
            guard body.count <= limit else { return (413, Data("the body is larger than \(limit) bytes".utf8)) }
            let changes = (try JSONSerialization.jsonObject(with: body) as? [String: Any])?["changes"] as? [[String: Any]] ?? []
            let outcomes = changes.map { #""\#($0["id"] as? String ?? "")":{"status":"accepted","revision":"r-\#($0["recordID"] as? String ?? "")"}"# }
            return (200, Data(("{\"outcomes\":{" + outcomes.joined(separator: ",") + "}}").utf8))
        }
    }

    private func store(_ endpoint: Endpoint, clock: TestClock = TestClock()) throws -> OfflineStore<Note> {
        let host = "push-\(UUID().uuidString.lowercased()).example"
        let session = StubURLProtocol.session(host: host) { request, body in try endpoint.answer(request, body) }
        let transport = HTTPSyncTransport<Note>(baseURL: URL(string: "https://\(host)/sync/notes")!, session: session)
        return try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                      configuration: makeConfiguration(clock: clock))
    }

    private static func notes(_ count: Int, kibibytes: Int) -> [Note] {
        (0..<count).map { Note(id: "n\($0)", text: String(repeating: "x", count: kibibytes * 1024)) }
    }

    @Test func aPushIsSplitIntoRequestsTheServerTakes() async throws {
        let endpoint = Endpoint(limit: 1 << 20)
        let store = try store(endpoint)
        try await store.save(contentsOf: Self.notes(10, kibibytes: 300))
        let report = try await store.sync()
        #expect(report.pushed == 10)
        #expect(await store.pendingChanges().isEmpty)
        #expect(endpoint.bodies.count == 4)
        #expect(endpoint.bodies.allSatisfy { $0 <= 1 << 20 })
    }

    @Test func aServerWithASmallerLimitGetsTheRequestInHalves() async throws {
        let endpoint = Endpoint(limit: 400 * 1024)
        let store = try store(endpoint)
        try await store.save(contentsOf: Self.notes(6, kibibytes: 300))
        let report = try await store.sync()
        #expect(report.pushed == 6)
        #expect(await store.pendingChanges().isEmpty)
    }

    /// A change the server refuses as too large on its own gets no outcome, since only a 2xx
    /// answer settles a change: it waits for its retry date and is parked after its last
    /// attempt, as the retry policy says. The other change goes through.
    @Test func aChangeTooLargeForTheServerIsRetriedAndParkedAndTheOthersGoThrough() async throws {
        let endpoint = Endpoint(limit: 1 << 20)
        let clock = TestClock()
        let store = try store(endpoint, clock: clock)
        try await store.save(contentsOf: [Note(id: "huge", text: String(repeating: "y", count: 2 << 20)), Note(id: "small", text: "s")])
        let report = try await store.sync()
        #expect(report.pushed == 1)
        #expect(report.rejected == 0)
        let waiting = try #require(await store.pendingChanges().first)
        #expect(waiting.recordID == "huge")
        #expect(waiting.attempts == 1)
        #expect(!waiting.isParked)
        for _ in 0..<2 {
            clock.advance(by: 3_600)
            _ = try? await store.sync()
        }
        let failed = try #require(await store.failedChanges().first)
        #expect(failed.recordID == "huge")
        #expect(failed.lastError?.contains("413") == true)
        #expect(await store.pendingChanges().map(\.recordID) == ["huge"])
    }

    @Test func answersOfEarlierRequestsCountWhenALaterOneFails() async throws {
        let endpoint = Endpoint(limit: 1 << 20, failing: 2)
        let store = try store(endpoint)
        try await store.save(contentsOf: Self.notes(6, kibibytes: 300))
        try await store.sync()
        let pending = await store.pendingChanges()
        #expect(pending.map(\.recordID).sorted() == ["n3", "n4", "n5"])
        #expect(pending.allSatisfy { $0.attempts == 1 })
    }
}
