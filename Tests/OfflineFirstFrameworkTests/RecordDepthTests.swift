import Foundation
import Testing
@testable import OfflineFirstFramework

/// A block of an outline, the plain recursive shape of record that ended the process: an outline
/// 180 blocks deep (363 levels of JSON) overflowed the 512 KiB stack of the task that wrote the
/// store file, in debug and release builds.
struct OutlineBlock: Codable, Sendable, Equatable {
    var title: String
    var children: [OutlineBlock]
}

struct Outline: SyncableRecord, Equatable {
    var id: String
    var root: OutlineBlock

    /// An outline with `levels` blocks below its root: 3 + 2 × `levels` levels of JSON, the
    /// leaf's empty list of children included.
    static func nested(_ levels: Int, id: String = "x") -> Outline {
        var block = OutlineBlock(title: "leaf", children: [])
        for _ in 0..<levels { block = OutlineBlock(title: "b", children: [block]) }
        return Outline(id: id, root: block)
    }

    /// The JSON of ``nested(_:id:)``, built without encoding it.
    static func json(_ levels: Int, id: String = "x") -> String {
        let open = String(repeating: #"{"title":"b","children":["#, count: levels)
        let close = String(repeating: "]}", count: levels)
        return #"{"id":"\#(id)","root":"# + open + #"{"title":"leaf","children":[]}"# + close + "}"
    }
}

/// A record whose body nests exactly as deep as a test needs: 1 + the depth of the body.
struct Document: SyncableRecord, Equatable {
    var id: String
    var body: JSONValue

    /// `depth` arrays around a number.
    static func arrays(_ depth: Int) -> JSONValue {
        var value = JSONValue.integer(1)
        for _ in 0..<depth { value = .array([value]) }
        return value
    }
}

/// Hands over Swift values, as a custom transport or a server SDK does: nothing limits how deep
/// they nest before they reach the store.
actor ValueTransport<Record: SyncableRecord>: SyncTransport {
    typealias Answer = @Sendable ([OutgoingChange<Record>]) throws -> [UUID: PushOutcome<Record>]

    private var page: PullResponse<Record>
    private var answer: Answer

    init(page: PullResponse<Record> = PullResponse(changes: [], token: "t0", hasMore: false),
         answer: @escaping Answer = { changes in Dictionary(uniqueKeysWithValues: changes.map { ($0.id, .accepted(revision: "r-\($0.id)")) }) }) {
        self.page = page
        self.answer = answer
    }

    func setPage(_ page: PullResponse<Record>) { self.page = page }
    func setAnswer(_ answer: @escaping Answer) { self.answer = answer }

    func push(_ changes: [OutgoingChange<Record>]) async throws -> [UUID: PushOutcome<Record>] { try answer(changes) }
    func pull(since token: String?) async throws -> PullResponse<Record> { page }
}

/// A record nested deeper than ``OfflineStore/maximumRecordDepth`` never enters the store, from
/// any side; one at the limit is stored and read back. Run these in a release build too
/// (`swift test -c release -Xswiftc -enable-testing --filter RecordDepth`): without the limit
/// the first one ends the process in both builds.
@Suite("Records nested too deeply")
struct RecordDepthTests {
    private static let retry = RetryPolicy(maximumAttempts: 3, initialDelay: .seconds(10), maximumDelay: .seconds(60), jitter: 0)

    private func httpStore<Record: SyncableRecord>(_ type: Record.Type, page: String,
                                                   storage: InMemoryStorage = InMemoryStorage()) throws -> OfflineStore<Record> {
        let host = "depth-\(UUID().uuidString.lowercased()).example"
        let body = Data(page.utf8)
        let session = StubURLProtocol.session(host: host) { request, _ in
            request.httpMethod == "POST" ? (200, Data(#"{"outcomes":{}}"#.utf8)) : (200, body)
        }
        let transport = HTTPSyncTransport<Record>(baseURL: URL(string: "https://\(host)/sync/records")!, session: session)
        return try OfflineStore<Record>(name: "records", storage: storage, transport: transport)
    }

    private static func page(_ records: [(json: String, revision: String)]) -> String {
        let changes = records.enumerated().map { index, record in
            #"{"recordID":"# + Self.id(of: record.json) + #","record":"# + record.json
                + #","revision":"\#(record.revision)","sequence":\#(index + 1)}"#
        }
        return #"{"changes":["# + changes.joined(separator: ",") + #"],"token":"t1","hasMore":false,"epoch":"e1"}"#
    }

    private static func id(of json: String) -> String {
        let start = json.range(of: #""id":""#)!.upperBound
        return "\"" + json[start...].prefix { $0 != "\"" } + "\""
    }

    @Test(arguments: [180, 1_000])
    func anOutlineNestedTooDeeplyInAPageIsSetAsideBeforeItIsDecoded(levels: Int) async throws {
        let storage = InMemoryStorage()
        let store = try httpStore(Outline.self, page: Self.page([(Outline.json(levels), "1"), (Outline.json(3, id: "y"), "2")]),
                                  storage: storage)
        let report = try await store.sync()
        #expect(report.quarantined == 1)
        #expect(await store.record("x") == nil)
        #expect(await store.record("y") == Outline.nested(3, id: "y"))
        let entry = try #require(await store.quarantinedChanges().first)
        #expect(entry.recordID == #""x""#)
        #expect(entry.revision == "1")
        #expect(entry.reason.contains("64 levels"))
        #expect(await store.state.token == "t1")
        let reopened = try OfflineStore<Outline>(name: "records", storage: storage)
        #expect(await reopened.record("y") == Outline.nested(3, id: "y"))
        try await store.sync()
    }

    /// The record's own object counts as one level, as the reference server counts.
    @Test func aRecordAtTheLimitIsStoredAndOneLevelDeeperIsSetAside() async throws {
        func json(_ id: String, _ depth: Int) throws -> String {
            String(decoding: try JSONEncoder().encode(Document(id: id, body: Document.arrays(depth))), as: UTF8.self)
        }
        let storage = InMemoryStorage()
        let store = try httpStore(Document.self, page: Self.page([(try json("limit", 63), "1"), (try json("over", 64), "2")]),
                                  storage: storage)
        let report = try await store.sync()
        #expect(report.quarantined == 1)
        #expect(await store.quarantinedChanges().map(\.recordID) == [#""over""#])
        #expect(await store.record("limit")?.body == Document.arrays(63))
        let reopened = try OfflineStore<Document>(name: "records", storage: storage)
        #expect(await reopened.record("limit")?.body == Document.arrays(63))
    }

    @Test func aDeepRecordFromATransportOfValuesIsSetAside() async throws {
        let page = PullResponse(changes: [RemoteChange(recordID: "x", record: Outline.nested(600), revision: "1", timestamp: nil, sequence: 1),
                                          RemoteChange(recordID: "y", record: Outline.nested(2, id: "y"), revision: "2", timestamp: nil, sequence: 2)],
                                token: "t1", hasMore: false, epoch: "e1")
        let storage = InMemoryStorage()
        let store = try OfflineStore<Outline>(name: "values", storage: storage, transport: ValueTransport(page: page))
        let report = try await store.sync()
        #expect(report.quarantined == 1)
        #expect(await store.record("x") == nil)
        #expect(await store.record("y") == Outline.nested(2, id: "y"))
        #expect(await store.quarantinedChanges().first?.reason.contains("64 levels") == true)
        _ = try OfflineStore<Outline>(name: "values", storage: storage)
    }

    private struct Mixed: Codable {
        enum Choice: Codable {
            case one(Int)
            case two(names: [String])
        }

        var data = Data([1, 2, 3])
        var url = URL(string: "https://example.com/a")!
        var decimal = Decimal(string: "1.25")!
        var date = Date(timeIntervalSince1970: 0)
        var map: [String: [Int]] = ["a": [1]]
        var missing: [String]? = nil
        var choice = Choice.two(names: ["x"])
    }

    /// The store measures a record as deep as the JSON it encodes to nests, as the transport and
    /// the reference server count: values `JSONEncoder` writes as strings or numbers are leaves.
    @Test func theStoreCountsLevelsAsTheEncodedJSONNests() throws {
        let values: [any Encodable] = [Outline.nested(0), Outline.nested(7), Document(id: "a", body: Document.arrays(10)), Mixed(),
                                       [Mixed()], ["k": Mixed()]]
        for value in values {
            let depth = try JSONLayout.read(try JSONEncoder().encode(value)) { try $0.value(at: 0).depth }
            let fits = NestingDepth.exceeds(value, limit: depth) == false
            let oneLevelLess = NestingDepth.exceeds(value, limit: depth - 1)
            #expect(fits && oneLevelLess, "\(type(of: value)) nests \(depth) levels")
        }
    }

    @Test func aSaveNestedTooDeeplyThrowsAndChangesNothing() async throws {
        let store = try OfflineStore<Outline>(name: "local", storage: InMemoryStorage())
        await #expect(throws: OfflineFirstError.recordNestedTooDeeply(limit: 64)) {
            try await store.save(Outline.nested(31)) // 65 levels of JSON
        }
        #expect(await store.records().isEmpty)
        #expect(await store.pendingChanges().isEmpty)
        try await store.save(Outline.nested(30)) // 63 levels
        #expect(await store.record("x") == Outline.nested(30))
    }

    /// The store cannot keep the version a conflict answer names, so the change stays unanswered
    /// and is retried, as with an answer that cannot be read.
    @Test func aConflictAnswerNestedTooDeeplyLeavesItsChangeUnanswered() async throws {
        let current = RemoteChange(recordID: "x", record: Outline.nested(600), revision: "9", timestamp: nil, sequence: 9)
        let transport = ValueTransport<Outline>(answer: { changes in
            Dictionary(uniqueKeysWithValues: changes.map { ($0.id, .conflict(current: current)) })
        })
        let clock = TestClock()
        let store = try OfflineStore<Outline>(name: "conflict", storage: InMemoryStorage(), transport: transport,
                                              configuration: .init(retryPolicy: Self.retry, now: { clock.now }, random: { 0 }))
        try await store.save(Outline.nested(1))
        try await store.sync()
        let pending = try #require(await store.pendingChanges().first)
        #expect(pending.attempts == 1)
        #expect(pending.isParked == false)
        #expect(await store.record("x") == Outline.nested(1))
    }

    @Test func aMergeNestedTooDeeplyKeepsTheServerVersion() async throws {
        let transport = ValueTransport<Outline>(answer: { _ in throw URLError(.notConnectedToInternet) })
        let clock = TestClock()
        let configuration = OfflineStore<Outline>.Configuration(conflictResolver: .merge { _, _ in Outline.nested(40) },
                                                                retryPolicy: Self.retry, now: { clock.now }, random: { 0 })
        let store = try OfflineStore<Outline>(name: "merge", storage: InMemoryStorage(), transport: transport, configuration: configuration)
        try await store.save(Outline.nested(1))
        await #expect(throws: URLError.self) { try await store.sync() }
        let server = Outline(id: "x", root: OutlineBlock(title: "server", children: []))
        await transport.setPage(PullResponse(changes: [RemoteChange(recordID: "x", record: server, revision: "1", timestamp: nil, sequence: 1)],
                                             token: "t1", hasMore: false, epoch: "e1"))
        let report = try await store.sync() // the change waits for its retry date; the pull meets it
        #expect(report.conflicts == 1)
        #expect(await store.record("x") == server)
        #expect(await store.pendingChanges().isEmpty)
    }

    /// The transport measures each outcome: one whose current version nests too deeply is not
    /// decoded, and the other changes of the push are settled.
    @Test func aConflictAnswerOverHTTPNestedTooDeeplyLeavesOnlyItsChangeUnanswered() async throws {
        let host = "depth-\(UUID().uuidString.lowercased()).example"
        let session = StubURLProtocol.session(host: host) { request, body in
            guard request.httpMethod == "POST" else { return (200, Data(#"{"changes":[],"token":"t","hasMore":false}"#.utf8)) }
            let sent = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            let outcomes = (sent?["changes"] as? [[String: Any]] ?? []).map { change -> String in
                let id = change["id"] as? String ?? ""
                guard change["recordID"] as? String == "x" else { return #""\#(id)":{"status":"accepted","revision":"r-\#(id)"}"# }
                return #""\#(id)":{"status":"conflict","current":{"recordID":"x","record":\#(Outline.json(100)),"revision":"9"}}"#
            }
            return (200, Data(("{\"outcomes\":{" + outcomes.joined(separator: ",") + "}}").utf8))
        }
        let transport = HTTPSyncTransport<Outline>(baseURL: URL(string: "https://\(host)/sync/outlines")!, session: session)
        let store = try OfflineStore<Outline>(name: "outlines", storage: InMemoryStorage(), transport: transport)
        try await store.save(contentsOf: [Outline.nested(1), Outline.nested(1, id: "y")])
        let report = try await store.sync()
        #expect(report.pushed == 1)
        #expect(await store.pendingChanges().map(\.recordID) == ["x"])
    }
}
