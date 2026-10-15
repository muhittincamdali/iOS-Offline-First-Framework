import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// Answers requests for one host with a handler, so the transport runs its real HTTP code.
final class StubURLProtocol: URLProtocol {
    typealias Handler = @Sendable (URLRequest, Data) throws -> (status: Int, body: Data)

    private static let handlers = OSAllocatedUnfairLock<[String: Handler]>(initialState: [:])

    /// A session whose requests to `host` go to `handler`.
    static func session(host: String, handler: @escaping Handler) -> URLSession {
        handlers.withLock { $0[host] = handler }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host() ?? ""
        guard let handler = Self.handlers.withLock({ $0[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        do {
            let (status, body) = try handler(request, Self.body(of: request))
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

@Suite("HTTP transport")
struct HTTPSyncTransportTests {
    private func transport(host: String = UUID().uuidString.lowercased(), maximumResponseSize: Int = 1 << 20,
                           handler: @escaping StubURLProtocol.Handler) -> HTTPSyncTransport<Note> {
        HTTPSyncTransport<Note>(
            baseURL: URL(string: "https://\(host).example/sync/notes")!,
            session: StubURLProtocol.session(host: "\(host).example", handler: handler),
            maximumResponseSize: maximumResponseSize,
            headers: { ["Authorization": "Bearer token-1"] }
        )
    }

    private let timestamp = HLCTimestamp(wallTime: 1_700_000_000_000, counter: 2, nodeID: "phone")

    @Test func pushSendsTheChangesAndReadsEveryOutcome() async throws {
        let accepted = UUID(), conflicted = UUID(), rejected = UUID()
        let transport = transport { request, body in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path() == "/sync/notes/push")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
            let json = try JSONDecoder().decode(JSONValue.self, from: body)
            guard case .array(let changes)? = json["changes"] else { throw URLError(.badServerResponse) }
            #expect(changes.count == 3)
            #expect(changes[0]["operation"] == "upsert")
            #expect(changes[0]["record"]?["text"] == "Hello")
            #expect(changes[0]["timestamp"]?["nodeID"] == "phone")
            #expect(changes[1]["operation"] == "delete")
            #expect(changes[1]["record"] == nil)
            #expect(changes[1]["baseRevision"] == "4")
            let answer = """
            {"outcomes": {
              "\(accepted.uuidString)": {"status": "accepted", "revision": "5"},
              "\(conflicted.uuidString)": {"status": "conflict", "current": {"recordID": "b", "record": {"id": "b", "text": "Server"}, "revision": "6"}},
              "\(rejected.uuidString)": {"status": "rejected", "reason": "Too long"},
              "not-a-uuid": {"status": "accepted", "revision": "1"}
            }}
            """
            return (200, Data(answer.utf8))
        }
        let outcomes = try await transport.push([
            OutgoingChange(id: accepted, recordID: "a", operation: .upsert(Note(id: "a", text: "Hello")), timestamp: timestamp, baseRevision: nil),
            OutgoingChange(id: conflicted, recordID: "b", operation: .delete, timestamp: timestamp, baseRevision: "4"),
            OutgoingChange(id: rejected, recordID: "c", operation: .upsert(Note(id: "c", text: "x")), timestamp: timestamp, baseRevision: nil)
        ])
        #expect(outcomes.count == 3)
        guard case .accepted(let revision)? = outcomes[accepted] else { Issue.record("accepted"); return }
        #expect(revision == "5")
        guard case .conflict(let current)? = outcomes[conflicted] else { Issue.record("conflict"); return }
        #expect(current.record == Note(id: "b", text: "Server"))
        #expect(current.timestamp == nil)
        guard case .rejected(let reason, nil)? = outcomes[rejected] else { Issue.record("rejected"); return }
        #expect(reason == "Too long")
    }

    @Test func pullSendsTheTokenAndReadsThePage() async throws {
        let transport = transport { request, _ in
            let query = request.url?.query() ?? ""
            let answer = query == "since=7"
                ? #"{"changes": [{"recordID": "a", "revision": "8"}], "token": "8", "hasMore": false}"#
                : #"{"changes": [{"recordID": "a", "record": {"id": "a", "text": "A"}, "revision": "7", "timestamp": {"wallTime": 5, "counter": 0, "nodeID": "x"}}], "token": "7", "hasMore": true}"#
            return (200, Data(answer.utf8))
        }
        let first = try await transport.pull(since: nil)
        #expect(first.changes.first?.record == Note(id: "a", text: "A"))
        #expect(first.token == "7")
        #expect(first.hasMore)
        let second = try await transport.pull(since: "7")
        #expect(second.changes.first?.record == nil)
        #expect(second.token == "8")
    }

    @Test func errorStatusesThrowWithTheStartOfTheBody() async {
        let transport = transport { _, _ in (503, Data(String(repeating: "busy ", count: 300).utf8)) }
        do {
            _ = try await transport.pull(since: nil)
            Issue.record("expected an error")
        } catch let HTTPSyncTransport<Note>.Failure.unexpectedStatus(code, body) {
            #expect(code == 503)
            #expect(body.count == 500)
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }

    @Test func oversizedResponsesAreNotLoaded() async {
        let transport = transport(maximumResponseSize: 64) { _, _ in (200, Data(repeating: UInt8(ascii: " "), count: 10_000)) }
        await #expect(throws: HTTPSyncTransport<Note>.Failure.responseTooLarge(limit: 64)) {
            try await transport.pull(since: nil)
        }
    }

    /// An outcome that cannot be read leaves its own change unanswered; the others are settled.
    @Test func anUnreadableOutcomeLeavesOnlyItsChangeUnanswered() async throws {
        let unknown = UUID(), malformed = UUID(), accepted = UUID()
        let transport = transport { _, _ in
            let answer = """
            {"outcomes": {
              "\(unknown.uuidString)": {"status": "maybe"},
              "\(malformed.uuidString)": {"status": "conflict", "current": {"recordID": "b", "record": {"id": "b", "text": 42}, "revision": "7"}},
              "\(accepted.uuidString)": {"status": "accepted", "revision": "5"}
            }}
            """
            return (200, Data(answer.utf8))
        }
        let outcomes = try await transport.push([
            OutgoingChange(id: unknown, recordID: "a", operation: .delete, timestamp: timestamp, baseRevision: "1"),
            OutgoingChange(id: malformed, recordID: "b", operation: .delete, timestamp: timestamp, baseRevision: "1"),
            OutgoingChange(id: accepted, recordID: "c", operation: .delete, timestamp: timestamp, baseRevision: "1")
        ])
        #expect(outcomes.count == 1)
        guard case .accepted(let revision)? = outcomes[accepted] else { Issue.record("accepted"); return }
        #expect(revision == "5")
    }

    /// One record the app cannot decode is set aside; the rest of the page is used and the
    /// token moves on, so the pull does not stop for good.
    @Test func aRecordThatDoesNotDecodeIsQuarantined() async throws {
        let transport = transport { _, _ in
            let page = #"{"changes":[{"recordID":"ok","record":{"id":"ok","text":"fine"},"revision":"1"},{"recordID":"bad","record":{"id":"bad","text":42},"revision":"2"}],"token":"t9","hasMore":false}"#
            return (200, Data(page.utf8))
        }
        let response = try await transport.pull(since: nil)
        #expect(response.changes.map(\.recordID) == ["ok"])
        let entry = try #require(response.quarantined.first)
        #expect(entry.recordID == #""bad""#)
        #expect(entry.revision == "2")
        #expect(entry.reason.contains("text"))

        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: TestClock()))
        let report = try await store.sync()
        #expect(report.pulled == 1)
        #expect(report.quarantined == 1)
        #expect(await store.record("ok") == Note(id: "ok", text: "fine"))
        #expect(await store.state.token == "t9")
        #expect(await store.quarantinedChanges() == [entry])
    }

    /// A server whose pulls keep failing opens the circuit breaker, but local edits are still
    /// pushed: the breaker pauses pulls only.
    @Test func failingPullsDoNotStopPushes() async throws {
        let pushes = OSAllocatedUnfairLock(initialState: 0)
        let transport = transport { request, body in
            guard request.httpMethod == "POST" else { return (500, Data()) }
            pushes.withLock { $0 += 1 }
            let json = try JSONDecoder().decode(JSONValue.self, from: body)
            guard case .array(let changes)? = json["changes"] else { throw URLError(.badServerResponse) }
            var outcomes: [String: JSONValue] = [:]
            for change in changes {
                if case .string(let id)? = change["id"] { outcomes[id] = ["status": "accepted", "revision": "1"] }
            }
            return (200, try JSONEncoder().encode(JSONValue.object(["outcomes": .object(outcomes)])))
        }
        let clock = TestClock()
        var configuration = makeConfiguration(clock: clock)
        configuration.circuitBreaker = CircuitBreaker(failureThreshold: 2, cooldown: .seconds(60))
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport, configuration: configuration)
        for _ in 0..<2 {
            await #expect(throws: HTTPSyncTransport<Note>.Failure.self) { try await store.sync() }
        }
        #expect(try await store.sync().skipped)

        try await store.save(Note(id: "new", text: "local"))
        let report = try await store.sync()
        #expect(report.pushed == 1)
        #expect(report.skipped)
        #expect(pushes.withLock { $0 } == 1)
        #expect(await store.pendingChanges().isEmpty)
        #expect(await store.status == .paused(until: clock.now.addingTimeInterval(60)))
    }

    @Test func cancellingASyncOverHTTPIsNotAFailedAttempt() async throws {
        let started = OSAllocatedUnfairLock(initialState: false)
        let transport = transport { _, _ in
            started.withLock { $0 = true }
            // Answers late, so the sync is cancelled while the request is open.
            Thread.sleep(forTimeInterval: 1)
            return (200, Data(#"{"outcomes": {}}"#.utf8))
        }
        let clock = TestClock()
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock))
        try await store.save(Note(id: "a", text: "A"))
        let caller = Task { try await store.sync() }
        #expect(await eventually { started.withLock { $0 } })
        caller.cancel()

        await #expect(throws: CancellationError.self) { try await caller.value }
        let pending = try #require(await store.pendingChanges().first)
        #expect(pending.attempts == 0)
        #expect(pending.lastError == nil)
        #expect(await store.status == .idle)
    }

    @Test func storeSyncsThroughTheHTTPTransport() async throws {
        let server = InMemorySyncServer<Note>()
        // The stub forwards to the in-memory server, so the whole HTTP path runs.
        let transport = transport { request, body in
            let semaphore = DispatchSemaphore(value: 0)
            let result = OSAllocatedUnfairLock<Data?>(initialState: nil)
            Task {
                let data = try? await Self.forward(request, body: body, to: server)
                result.withLock { $0 = data }
                semaphore.signal()
            }
            semaphore.wait()
            guard let data = result.withLock({ $0 }) else { throw URLError(.badServerResponse) }
            return (200, data)
        }
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport)
        try await store.save(Note(id: "a", text: "Over HTTP"))
        let report = try await store.sync()
        #expect(report.pushed == 1)
        #expect(await server.record("a") == Note(id: "a", text: "Over HTTP"))
        // The page names the server's epoch, and the token belongs to the transport's URL.
        #expect(await store.state.serverEpoch != nil)
        #expect(await store.state.serverIdentity == transport.baseURL.absoluteString)
    }

    /// Translates the wire format to the in-memory server and back.
    private static func forward(_ request: URLRequest, body: Data, to server: InMemorySyncServer<Note>) async throws -> Data {
        struct Change: Decodable { let id: UUID; let recordID: String; let operation: String; let record: Note?; let timestamp: HLCTimestamp; let baseRevision: String? }
        struct Push: Decodable { let changes: [Change] }
        if request.httpMethod == "POST" {
            let push = try JSONDecoder().decode(Push.self, from: body)
            let outcomes = try await server.push(push.changes.map {
                OutgoingChange(id: $0.id, recordID: $0.recordID, operation: $0.record.map { .upsert($0) } ?? .delete, timestamp: $0.timestamp, baseRevision: $0.baseRevision)
            })
            var answer: [String: JSONValue] = [:]
            for (id, outcome) in outcomes {
                if case .accepted(let revision) = outcome { answer[id.uuidString] = ["status": "accepted", "revision": .string(revision)] }
            }
            return try JSONEncoder().encode(JSONValue.object(["outcomes": .object(answer)]))
        }
        let since = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "since" }?.value
        let page = try await server.pull(since: since)
        struct Page: Encodable { let changes: [RemoteChange<Note>]; let token: String?; let hasMore: Bool; let epoch: String? }
        return try JSONEncoder().encode(Page(changes: page.changes, token: page.token, hasMore: page.hasMore, epoch: page.epoch))
    }
}
