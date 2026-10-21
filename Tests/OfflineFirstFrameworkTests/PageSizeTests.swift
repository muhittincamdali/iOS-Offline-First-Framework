import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A page must fit in the transport's response limit. Records within a server's limits could
/// add up to a first page larger than that, and every device that pulls from the beginning (a
/// new device, after resetChangeToken(), after every server restart) failed on that page for
/// good. The transport asks for fewer changes while the page is too large, and sets aside a
/// change that is too large on its own.
@Suite("HTTP transport: pages larger than the response limit", .heapExclusive)
struct PageSizeTests {
    /// Serves `records` (ID and text) in order, honouring `since` (an index) and `limit`, or
    /// sending every record when `ignoresLimit`. Records the `limit` of every request.
    final class Feed: Sendable {
        let records: [(id: String, text: String)]
        let ignoresLimit: Bool
        private let seen = OSAllocatedUnfairLock<[Int]>(initialState: [])

        init(records: [(id: String, text: String)], ignoresLimit: Bool = false) {
            self.records = records
            self.ignoresLimit = ignoresLimit
        }

        var limits: [Int] { seen.withLock { $0 } }

        func answer(_ request: URLRequest) -> (status: Int, body: Data) {
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let since = items.first { $0.name == "since" }?.value.flatMap(Int.init) ?? 0
            let limit = items.first { $0.name == "limit" }?.value.flatMap(Int.init) ?? 100
            seen.withLock { $0.append(limit) }
            let end = ignoresLimit ? records.count : min(records.count, since + limit)
            let changes = records[since..<end].enumerated().map { offset, record in
                #"{"recordID":"\#(record.id)","record":{"id":"\#(record.id)","text":"\#(record.text)"},"revision":"r\#(since + offset + 1)","sequence":\#(since + offset + 1),"timestamp":{"wallTime":1,"counter":0,"nodeID":"server"}}"#
            }
            let body = #"{"changes":["# + changes.joined(separator: ",") + #"],"token":"\#(end)","hasMore":\#(end < records.count),"epoch":"e1"}"#
            return (200, Data(body.utf8))
        }
    }

    private func store(_ feed: Feed, maximumResponseSize: Int = 1 << 20) throws -> OfflineStore<Note> {
        let host = "pages-\(UUID().uuidString.lowercased()).example"
        let session = StubURLProtocol.session(host: host) { request, _ in feed.answer(request) }
        let transport = HTTPSyncTransport<Note>(baseURL: URL(string: "https://\(host)/sync/notes")!, session: session,
                                                maximumResponseSize: maximumResponseSize)
        return try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport)
    }

    private static func text(kibibytes: Int) -> String { String(repeating: "x", count: kibibytes * 1024) }

    @Test func aPullAsksForHalfAsManyChangesWhileThePageIsTooLarge() async throws {
        let feed = Feed(records: (0..<20).map { ("n\($0)", Self.text(kibibytes: 300)) })
        let store = try store(feed)
        let report = try await store.sync()
        #expect(report.pulled == 20)
        #expect(await store.records().count == 20)
        #expect(await store.state.token == "20")
        #expect(Array(feed.limits.prefix(6)) == [100, 50, 25, 12, 6, 3])
    }

    @Test func aChangeLargerThanTheLimitOnItsOwnIsSetAsideAndThePullMovesOn() async throws {
        let feed = Feed(records: [("big", Self.text(kibibytes: 2_048)), ("small", "fine")])
        let store = try store(feed)
        let report = try await store.sync()
        #expect(report.quarantined == 1)
        let entry = try #require(await store.quarantinedChanges().first)
        #expect(entry.recordID == #""big""#)
        #expect(entry.revision == "r1")
        #expect(entry.reason.contains("maximumResponseSize"))
        #expect(await store.record("big") == nil)
        #expect(await store.record("small")?.text == "fine")
        #expect(await store.state.token == "2")
        #expect(feed.limits == [100, 50, 25, 12, 6, 3, 1, 1, 100])
    }

    @Test func aServerThatIgnoresTheLimitStillFailsAndNothingChanges() async throws {
        let feed = Feed(records: [("a", Self.text(kibibytes: 600)), ("b", Self.text(kibibytes: 600))], ignoresLimit: true)
        let store = try store(feed)
        await #expect(throws: DecodingError.self) { try await store.sync() }
        #expect(await store.records().isEmpty)
        #expect(await store.quarantinedChanges().isEmpty)
        #expect(await store.state.token == nil)
    }

    @Test func theOutlineKeepsAChangesOwnFieldsAndLeavesOutWhatItHolds() throws {
        let page = #"{"changes":[{"recordID":"a","record":{"id":"a","text":"}]\"{[","list":[[1],{"x":[]}]},"revision":"9","timestamp":{"wallTime":1}}],"token":"t\"}","hasMore":true}"#
        var outline = PageOutline()
        var kept = Data()
        for byte in page.utf8 { outline.append(byte, to: &kept) }
        #expect(String(decoding: kept, as: UTF8.self)
            == #"{"changes":[{"recordID":"a","record":null,"revision":"9","timestamp":null}],"token":"t\"}","hasMore":true}"#)
    }
}
