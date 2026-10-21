import Darwin
import Dispatch
import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// Bytes the process holds in malloc'd memory, summed over all zones. Unlike the physical
/// footprint, it does not hide an allocation that reuses pages freed before.
func heapBytesInUse() -> Int {
    var statistics = malloc_statistics_t()
    malloc_zone_statistics(nil, &statistics)
    return Int(statistics.size_in_use)
}

/// How far the heap grew above its size before `body` while `body` ran, sampled every 200 µs on
/// another thread that starts sampling before `body` does, and once more after it.
func peakHeapGrowth(of body: () -> Void) -> Int {
    let baseline = heapBytesInUse()
    let peak = OSAllocatedUnfairLock(initialState: baseline)
    let running = OSAllocatedUnfairLock(initialState: true)
    let sampling = DispatchSemaphore(value: 0)
    let sampler = Thread {
        sampling.signal()
        while running.withLock({ $0 }) {
            let now = heapBytesInUse()
            peak.withLock { $0 = max($0, now) }
            usleep(200)
        }
    }
    sampler.start()
    sampling.wait()
    body()
    running.withLock { $0 = false }
    let end = heapBytesInUse()
    return peak.withLock { max($0, end) } - baseline
}

/// A page of the given elements, `{"changes":[e,e,…],"token":"t1","hasMore":false}`, of about
/// `size` bytes, built in large pieces.
func junkPage(repeating element: String, size: Int) -> Data {
    let piece = Data(String(repeating: element + ",", count: max(1, 65_536 / (element.utf8.count + 1))).utf8)
    var body = Data(#"{"changes":["#.utf8)
    body.reserveCapacity(size + piece.count + 64)
    while body.count + piece.count < size { body.append(piece) }
    body.append(Data((element + #"],"token":"t1","hasMore":false}"#).utf8))
    return body
}

/// What an untrusted page may cost. A server, a proxy or a client that wrote junk could send
/// 16 MiB of elements, changes or not: hundreds of thousands to millions of entries, gigabytes of
/// memory and seconds of work, on every sync, since the page never moves the token. iOS ends an
/// app that uses that much memory, so every launch would end the same way.
@Suite("HTTP transport: what a page may cost", .serialized, .heapExclusive)
struct PageBudgetTests {
    private static let pageSize = 16 * 1024 * 1024 - 64

    @Test(arguments: ["0", "{}", "[]", #""x""#, #"{"recordID":"a","revision":"1","record":0}"#, #"{"recordID":"a","revision":"1"}"#,
                      #"{"recordID":"a","revision":"1","record":{"id":"a","text":""}}"#])
    func aPageOfMillionsOfChangesIsRefusedQuicklyAndWithLittleMemory(element: String) throws {
        let body = junkPage(repeating: element, size: Self.pageSize)
        var growths: [Int] = []
        var failure: (any Error)?
        let start = ContinuousClock.now
        for _ in 0..<3 {
            growths.append(peakHeapGrowth {
                do {
                    _ = try HTTPSyncTransport<Note>.page(from: body, limit: 100)
                } catch {
                    failure = error
                }
            })
        }
        let elapsed = (ContinuousClock.now - start) / 3
        guard case DecodingError.dataCorrupted(let context)? = failure else {
            Issue.record("expected the page to be refused, got \(String(describing: failure))")
            return
        }
        #expect(context.debugDescription.contains("more changes than the 100"))
        // The least growth of three runs, so another test's allocation at the same moment does
        // not count; the bound of the design is four times the page. Before the budget, these
        // pages grew the heap by 90 MiB to 1.4 GiB and took 1 to 17 s in a debug build; pages of
        // valid changes were read in full, 144 MiB for half a million deletions.
        let growth = growths.min() ?? 0
        #expect(growth <= 4 * body.count, "grew by \(growth / 1_048_576) MiB for a \(body.count / 1_048_576) MiB page")
        #expect(elapsed < .seconds(2), "took \(elapsed)")
    }

    /// A page of large changes that can be read: each record is decoded from its own bytes. The
    /// decoded page is kept until the last sample, so its records count.
    @Test func aFullPageOfLargeChangesStaysWithinFourTimesItsSize() throws {
        let text = String(repeating: "x", count: 250 * 1024)
        let changes = (0..<64).map { #"{"recordID":"n\#($0)","record":{"id":"n\#($0)","text":"\#(text)"},"revision":"\#($0)"}"# }
        let body = Data((#"{"changes":["# + changes.joined(separator: ",") + #"],"token":"t1","hasMore":false}"#).utf8)
        var page: PullResponse<Note>?
        let growth = (0..<3).map { _ in
            page = nil
            return peakHeapGrowth { page = try? HTTPSyncTransport<Note>.page(from: body, limit: 100) }
        }.min() ?? 0
        #expect(page?.changes.count == 64)
        #expect(growth >= body.count / 2, "the records of the page were not seen: grew by \(growth) bytes")
        #expect(growth <= 4 * body.count, "grew by \(growth / 1_048_576) MiB for a \(body.count / 1_048_576) MiB page")
    }

    /// Up to the limit, every unreadable change is set aside and counted, the first 100 listed,
    /// and the readable ones are used.
    @Test func aPageOfAThousandChangesSetsAsideTheUnreadableAndListsTheFirstHundred() async throws {
        let unreadable = (0..<999).map { #"{"recordID":"bad\#($0)","revision":"\#($0)","record":0}"# }
        let readable = #"{"recordID":"good","record":{"id":"good","text":"fine"},"revision":"g"}"#
        let body = Data((#"{"changes":["# + (unreadable + [readable]).joined(separator: ",") + #"],"token":"t1","hasMore":false}"#).utf8)
        let page = try HTTPSyncTransport<Note>.page(from: body, limit: 1_000)
        #expect(page.quarantined.count == 100)
        #expect(page.quarantinedCount == 999)
        #expect(page.quarantined.first?.recordID == #""bad0""#)
        #expect(page.changes.map(\.recordID) == ["good"])
        let store = try OfflineStore<Note>(name: "n", storage: InMemoryStorage(), transport: ScriptedTransport(pull: { _ in page }))
        let report = try await store.sync()
        #expect(report.quarantined == 999)
        #expect(await store.quarantinedChanges().count == 100)
        #expect(await store.record("good")?.text == "fine")
        #expect(await store.state.token == "t1")
    }

    @Test func onePastTheLimitTheSyncFailsAndNothingChanges() async throws {
        let unreadable = (0..<1_000).map { #"{"recordID":"bad\#($0)","revision":"\#($0)","record":0}"# }
        let readable = #"{"recordID":"good","record":{"id":"good","text":"fine"},"revision":"g"}"#
        let body = Data((#"{"changes":["# + ([readable] + unreadable).joined(separator: ",") + #"],"token":"t1","hasMore":false}"#).utf8)
        let host = "budget-\(UUID().uuidString.lowercased()).example"
        let session = StubURLProtocol.session(host: host) { _, _ in (200, body) }
        let transport = HTTPSyncTransport<Note>(baseURL: URL(string: "https://\(host)/sync/notes")!, session: session,
                                                maximumResponseSize: 16 * 1024 * 1024, pageSize: 1_000)
        let store = try OfflineStore<Note>(name: "n", storage: InMemoryStorage(), transport: transport)
        await #expect(throws: DecodingError.self) { try await store.sync() }
        #expect(await store.record("good") == nil)
        #expect(await store.state.token == nil)
        #expect(await store.quarantinedChanges().isEmpty)
    }

    /// The walk is synchronous, so it checks for cancellation itself: the store cancels it when
    /// the sync passes its deadline or every caller gave up.
    @Test func aCancelledTaskStopsReadingThePage() async throws {
        let body = junkPage(repeating: #"{"recordID":"a","record":{"id":"a","text":"t"},"revision":"1"}"#, size: 4 * 1024 * 1024)
        let result = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return Result { try HTTPSyncTransport<Note>.page(from: body, limit: 1_000) }
        }.value
        #expect(throws: CancellationError.self) { try result.get() }
    }

    /// Outcomes for change IDs that were not pushed are skipped without being decoded, so a push
    /// answer cannot grow the result beyond the changes sent.
    @Test func outcomesForChangesThatWereNotSentAreSkipped() throws {
        let sent = UUID()
        var answer = #"{"outcomes":{"#
        for _ in 0..<100_000 { answer += #""\#(UUID().uuidString)":{"status":"accepted","revision":"r"},"# }
        answer += #""\#(sent.uuidString)":{"status":"accepted","revision":"mine"}}}"#
        let outcomes = try HTTPSyncTransport<Note>.outcomes(from: Data(answer.utf8), for: [sent])
        #expect(outcomes.count == 1)
        guard case .accepted(let revision)? = outcomes[sent] else { Issue.record("no outcome for the sent change"); return }
        #expect(revision == "mine")
    }
}
