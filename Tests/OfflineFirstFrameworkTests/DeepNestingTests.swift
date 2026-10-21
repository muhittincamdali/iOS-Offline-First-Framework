import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// JSONDecoder refuses a whole document that nests deeper than 512 levels anywhere. One such
/// change in a page, or one such conflict answer in a push answer, must cost only that change:
/// the rest of the page is used and the token moves on, the other outcomes are settled.
@Suite("HTTP transport: changes nested deeper than the decoder reads")
struct DeepNestingTests {
    static func deep(_ depth: Int) -> String {
        String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
    }

    private func store(answering page: @escaping @Sendable () -> Data,
                       push: @escaping @Sendable (Data) throws -> Data = { _ in Data(#"{"outcomes":{}}"#.utf8) },
                       retry: RetryPolicy? = nil) throws -> OfflineStore<Note> {
        let host = "deep-\(UUID().uuidString.lowercased()).example"
        let session = StubURLProtocol.session(host: host) { request, body in
            request.httpMethod == "POST" ? (200, try push(body)) : (200, page())
        }
        let transport = HTTPSyncTransport<Note>(baseURL: URL(string: "https://\(host)/sync/notes")!, session: session)
        let clock = TestClock()
        let configuration = retry.map { makeConfiguration(clock: clock, retry: $0) } ?? makeConfiguration(clock: clock)
        return try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport, configuration: configuration)
    }

    @Test(arguments: [
        #""text":"# + deep(513),
        #""text":"x","extra":"# + deep(600),
        #""text":"# + deep(100_000),
    ])
    func aChangeNestedTooDeeplyIsSetAsideAndThePageIsUsed(fragment: String) async throws {
        let page = Data((#"{"changes":[{"recordID":"x","record":{"id":"x","# + fragment
            + #"},"revision":"1","sequence":1},{"recordID":"y","record":{"id":"y","text":"normal"},"revision":"2","sequence":2}],"#
            + #""token":"t1","hasMore":false,"epoch":"e1"}"#).utf8)
        let store = try store(answering: { page })
        let report = try await store.sync()
        #expect(report.quarantined == 1)
        #expect(await store.record("y")?.text == "normal")
        #expect(await store.record("x") == nil)
        #expect(await store.quarantinedChanges().map(\.recordID) == [#""x""#])
        #expect(await store.quarantinedChanges().first?.revision == "1")
        #expect(await store.state.token == "t1")
        try await store.sync()
    }

    /// Strings that hold brackets, quotes and backslashes, and whitespace between the parts,
    /// do not confuse the layout.
    @Test func bracketsInsideStringsAndWhitespaceAreRead() async throws {
        let page = Data(#"""
         { "token" : "t\"1]" ,
           "changes" : [ { "recordID" : "a" , "record" : { "id" : "a" , "text" : "]}[{\\\"," } , "revision" : "1" } ,
                         { "recordID" : "b" , "record" : { "id" : "b" , "text" : "]" } , "revision" : "2" } ] ,
           "hasMore" : false }
        """#.utf8)
        let store = try store(answering: { page })
        try await store.sync()
        #expect(await store.record("a")?.text == #"]}[{\","#)
        #expect(await store.record("b")?.text == "]")
        #expect(await store.state.token == #"t"1]"#)
    }

    @Test func aBrokenPageStillFailsTheSync() async throws {
        let page = Data(#"{"changes":[{"recordID":"a","revision":"1"}"#.utf8)
        let store = try store(answering: { page })
        await #expect(throws: DecodingError.self) { try await store.sync() }
    }

    /// The server accepts y and z and answers x with a conflict whose current version nests too
    /// deeply. y and z are settled; only x has no answer and is pushed again later.
    @Test func aConflictAnswerNestedTooDeeplyLeavesOnlyItsChangeUnanswered() async throws {
        let store = try store(answering: { Data(#"{"changes":[],"token":"t","hasMore":false}"#.utf8) }, push: { body in
            let sent = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let changes = sent?["changes"] as? [[String: Any]] ?? []
            let outcomes = changes.map { change -> String in
                let id = change["id"] as? String ?? ""
                if change["recordID"] as? String == "x" {
                    return #""\#(id)":{"status":"conflict","current":{"recordID":"x","record":{"id":"x","text":"t","extra":\#(Self.deep(600))},"revision":"9","sequence":9}}"#
                }
                return #""\#(id)":{"status":"accepted","revision":"r-\#(id)"}"#
            }
            return Data(("{\"outcomes\":{" + outcomes.joined(separator: ",") + "}}").utf8)
        }, retry: .default)
        try await store.save(contentsOf: [Note(id: "x", text: "mine"), Note(id: "y", text: "fine"), Note(id: "z", text: "fine")])
        let report = try await store.sync()
        #expect(report.pushed == 2)
        let pending = await store.pendingChanges()
        #expect(pending.map(\.recordID) == ["x"])
        #expect(pending.first?.attempts == 1)
        #expect(pending.first?.isParked == false)
    }
}
