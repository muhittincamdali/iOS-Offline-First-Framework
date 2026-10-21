import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A page of `count` small, valid changes with distinct record IDs: deletions, or upserts of
/// empty notes.
func floodPage(count: Int, deletions: Bool) -> Data {
    var body = Data(#"{"changes":["#.utf8)
    for index in 0..<count {
        if index > 0 { body.append(UInt8(ascii: ",")) }
        let change = deletions
            ? #"{"recordID":"\#(index)","revision":"1"}"#
            : #"{"recordID":"\#(index)","revision":"1","record":{"id":"\#(index)","text":""}}"#
        body.append(contentsOf: Array(change.utf8))
    }
    body.append(contentsOf: Array(#"],"token":"t1","hasMore":false}"#.utf8))
    return body
}

/// A page holds at most the `limit` its pull asked for. A server that ignores `limit` could send
/// a 16 MiB page of 456,436 small deletions, each one valid: the transport read them all (144 MiB
/// more heap) and the store applied them in one synchronous step that took seconds and a
/// gigabyte, which no deadline could stop. On iOS the app was ended before the token moved, and
/// automatic sync met the same page on every launch.
@Suite("Pages with more changes than the pull asked for", .heapExclusive)
struct PageLimitTests {
    private func transport(serving body: Data, pageSize: Int = 100, limits: LimitLog? = nil) -> HTTPSyncTransport<Note> {
        let host = "limit-\(UUID().uuidString.lowercased()).example"
        let session = StubURLProtocol.session(host: host) { request, _ in
            // A push is left unanswered, so the store pulls.
            guard request.httpMethod == "GET" else { return (200, Data(#"{"outcomes":{}}"#.utf8)) }
            limits?.record(request)
            return (200, onePageAnswer(request, holding: body))
        }
        return HTTPSyncTransport<Note>(baseURL: URL(string: "https://\(host)/sync/notes")!, session: session,
                                       maximumResponseSize: 16 * 1024 * 1024, pageSize: pageSize)
    }

    @Test(arguments: [true, false])
    func aPageOfValidChangesBeyondTheLimitIsRefusedAndNothingChanges(deletions: Bool) async throws {
        let limits = LimitLog()
        let store = try OfflineStore<Note>(name: "n", storage: InMemoryStorage(),
                                           transport: transport(serving: floodPage(count: 5_000, deletions: deletions), limits: limits))
        try await store.save(Note(id: "mine", text: "kept"))
        await #expect(throws: DecodingError.self) { try await store.sync() }
        #expect(await store.records().map(\.id) == ["mine"])
        #expect(await store.state.entries.count == 1)
        #expect(await store.state.token == nil)
        // Asking for fewer changes would not help a server that ignores `limit`.
        #expect(limits.values == [100])
    }

    @Test func aPageOfExactlyTheLimitIsUsed() async throws {
        let store = try OfflineStore<Note>(name: "n", storage: InMemoryStorage(),
                                           transport: transport(serving: floodPage(count: 100, deletions: false)))
        #expect(try await store.sync().pulled == 100)
        #expect(await store.state.token == "t1")
    }

    /// The flood of the audit, 16 MiB of distinct valid changes, read by the transport: refused
    /// at its 101st change, in milliseconds and with a few kilobytes.
    @Test(arguments: [true, false])
    func sixteenMebibytesOfValidChangesCostLittle(deletions: Bool) throws {
        let count = deletions ? 456_436 : 236_101
        let body = floodPage(count: count, deletions: deletions)
        var failure: (any Error)?
        let start = ContinuousClock.now
        // The least growth of three runs, as in PageBudgetTests.
        let growth = (0..<3).map { _ in
            peakHeapGrowth {
                do { _ = try HTTPSyncTransport<Note>.page(from: body, limit: 100) } catch { failure = error }
            }
        }.min() ?? 0
        let elapsed = (ContinuousClock.now - start) / 3
        guard case DecodingError.dataCorrupted(let context)? = failure else {
            Issue.record("expected the page to be refused, got \(String(describing: failure))")
            return
        }
        #expect(context.debugDescription.contains("more changes than the 100"))
        #expect(growth <= 1_048_576, "grew by \(growth) bytes")
        #expect(elapsed < .milliseconds(500), "took \(elapsed)")
    }

    /// A custom transport is held to the same bound: the store applies a page in one step that
    /// nothing interrupts, so it refuses a page of more than 1,000 changes before it stores any.
    @Test(arguments: [1_001, 236_101])
    func theStoreRefusesAPageOfMoreThanAThousandChangesFromAnyTransport(count: Int) async throws {
        let changes = (0..<count).map { RemoteChange<Note>(recordID: "\($0)", record: Note(id: "\($0)", text: ""), revision: "1", timestamp: nil) }
        let page = PullResponse(changes: changes, token: "t1", hasMore: false)
        let store = try OfflineStore<Note>(name: "n", storage: InMemoryStorage(), transport: ScriptedTransport(pull: { _ in page }))
        let start = ContinuousClock.now
        await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        #expect(ContinuousClock.now - start < .seconds(1))
        #expect(await store.records().isEmpty)
        #expect(await store.state.token == nil)
    }

    @Test func aPageOfAThousandChangesAndSetAsideOnesIsStored() async throws {
        let changes = (0..<900).map { RemoteChange<Note>(recordID: "\($0)", record: Note(id: "\($0)", text: ""), revision: "1", timestamp: nil) }
        let unreadable = (0..<100).map { QuarantinedChange(recordID: "bad\($0)", revision: "1", reason: "test") }
        let page = PullResponse(changes: changes, token: "t1", hasMore: false, quarantined: unreadable, quarantinedCount: 5_000)
        let store = try OfflineStore<Note>(name: "n", storage: InMemoryStorage(), transport: ScriptedTransport(pull: servingOnePage(page)))
        let report = try await store.sync()
        #expect(report.pulled == 900)
        #expect(report.quarantined == 5_000)
        #expect(await store.state.token == "t1")
        #expect(await InMemorySyncServer<Note>(pageSize: 5_000).pageSize == 1_000)
    }
}

/// The `limit` of every pull request.
final class LimitLog: Sendable {
    private let seen = OSAllocatedUnfairLock<[Int]>(initialState: [])

    var values: [Int] { seen.withLock { $0 } }

    func record(_ request: URLRequest) {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let limit = items.first(where: { $0.name == "limit" })?.value.flatMap(Int.init) {
            seen.withLock { $0.append(limit) }
        }
    }
}
