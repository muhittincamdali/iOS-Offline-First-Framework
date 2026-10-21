import Foundation
import Testing
@testable import OfflineFirstFramework

/// A server or gateway in trouble answers a push with a 5xx whose body the transport has no use
/// for: a 503 that announces 17 MiB and never sends it, a 502 error page that streams without
/// end. The transport took such an answer for one longer than its response limit: it sent the
/// push again in halves down to single changes, 2n − 1 requests to a server that was already
/// failing, read up to 16 MiB of each error page, and parked every change as `answerTooLarge`
/// in one sync, although the server never saw them.
@Suite("HTTP transport: error answers of a gateway in trouble")
struct GatewayErrorTests {
    private func store(_ proxy: RogueProxy) throws -> OfflineStore<Note> {
        let transport = HTTPSyncTransport<Note>(baseURL: proxy.url.appending(path: "sync/notes"),
                                                session: URLSession(configuration: .ephemeral))
        return try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                      configuration: makeConfiguration(clock: TestClock()))
    }

    /// One failed attempt: one request, every change waits for its retry date and none is parked.
    @Test func aServerErrorThatAnnouncesALongBodyIsOneFailedAttempt() async throws {
        let proxy = try await RogueProxy.start(mode: .overloaded)
        defer { proxy.stop() }
        let store = try store(proxy)
        try await store.save(contentsOf: (0..<10).map { Note(id: "n\($0)", text: "t\($0)") })
        await #expect(throws: HTTPSyncTransport<Note>.Failure.unexpectedStatus(code: 503, body: "")) { try await store.sync() }
        #expect(proxy.counts.pushes == 1)
        let pending = await store.pendingChanges()
        #expect(pending.count == 10)
        #expect(pending.allSatisfy { !$0.isParked && $0.attempts == 1 && $0.lastError?.contains("503") == true })
        #expect(await store.failedChanges().isEmpty)
    }

    /// The error page is read up to its first bytes, and the request is not sent again.
    @Test func anErrorPageThatNeverEndsIsReadOnlyAtItsStart() async throws {
        let proxy = try await RogueProxy.start(mode: .streamingError)
        defer { proxy.stop() }
        let store = try store(proxy)
        try await store.save(contentsOf: (0..<4).map { Note(id: "n\($0)", text: "t\($0)") })
        do {
            try await store.sync()
            Issue.record("expected the sync to fail")
        } catch let HTTPSyncTransport<Note>.Failure.unexpectedStatus(code, body) {
            #expect(code == 502)
            #expect(body.utf8.count == HTTPSyncTransport<Note>.errorBodyLimit)
        }
        #expect(proxy.counts.pushes == 1)
        // What the socket's buffers took before the transport cancelled: far less than the
        // 16 MiB response limit the transport used to read of every request.
        #expect(proxy.counts.errorBytesSent < 8 << 20, "sent \(proxy.counts.errorBytesSent >> 10) KiB")
        #expect(await store.failedChanges().isEmpty)
    }
}
