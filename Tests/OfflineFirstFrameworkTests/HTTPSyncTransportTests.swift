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

    @Test func unknownOutcomesAreErrors() async {
        let id = UUID()
        let transport = transport { _, _ in (200, Data(#"{"outcomes": {"\#(id.uuidString)": {"status": "maybe"}}}"#.utf8)) }
        await #expect(throws: HTTPSyncTransport<Note>.Failure.unknownOutcome("maybe")) {
            try await transport.push([OutgoingChange(id: id, recordID: "a", operation: .delete, timestamp: timestamp, baseRevision: "1")])
        }
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
        struct Page: Encodable { let changes: [RemoteChange<Note>]; let token: String?; let hasMore: Bool }
        return try JSONEncoder().encode(Page(changes: page.changes, token: page.token, hasMore: page.hasMore))
    }
}
