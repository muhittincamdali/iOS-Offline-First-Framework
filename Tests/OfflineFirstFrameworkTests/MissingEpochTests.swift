import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A page without an epoch once the store holds one that two requests reported: another
/// deployment behind the same URL, or a proxy that answers for the server. It was taken from a
/// single request, with its revision, sequence and token: the record went back to that copy, and
/// the forged sequence made every later conflict answer of the real server look older, so each
/// edit of the record was parked, also after `retryFailedChanges()` and `resetChangeToken()`.
/// (Against an epoch only a new store's first page reported, see `FirstEpochTests`.)
@Suite("Offline store: a page without an epoch")
struct MissingEpochTests {
    private static let forgedPage = PullResponse(
        changes: [RemoteChange(recordID: "n", record: Note(id: "n", text: "old copy"), revision: "legacy.99999",
                               timestamp: nil, sequence: 99_999)],
        token: "legacy.99999", hasMore: false, epoch: nil)

    /// Answers every pull with the forged page while `forged` is set, otherwise as `server`.
    private func transport(_ server: InMemorySyncServer<Note>, forged: OSAllocatedUnfairLock<Bool>) -> ScriptedTransport {
        ScriptedTransport(push: { try await server.push($0) }, pull: { token in
            if forged.withLock({ $0 }) { return Self.forgedPage }
            return try await server.pull(since: token)
        })
    }

    @Test func aPageWithoutAnEpochIsRefusedOnceTheStoreHoldsOne() async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        let forged = OSAllocatedUnfairLock(initialState: false)
        let transport = transport(server, forged: forged)
        let store = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock))
        await server.write(Note(id: "n", text: "real 1"))
        // The second sync reports the epoch a second time.
        try await store.sync()
        try await store.sync()
        let token = await store.state.token
        let epoch = await store.state.serverEpoch
        #expect(epoch != nil)
        #expect(await store.state.epochIsConfirmed)

        // Both requests of the check are answered without an epoch: refused, nothing changes.
        forged.withLock { $0 = true }
        let pullsBefore = await transport.pulls
        await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        #expect(await transport.pulls - pullsBefore == 2)
        #expect(await store.record("n")?.text == "real 1")
        #expect(await store.state.token == token)
        #expect(await store.state.serverEpoch == epoch)
        #expect(await store.state.entries["n"]?.sequence != 99_999)

        forged.withLock { $0 = false }
        await server.write(Note(id: "n", text: "real 2"))
        try await store.sync()
        #expect(await store.record("n")?.text == "real 2")
    }

    @Test func aSinglePageWithoutAnEpochIsDropped() async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        let forgedPulls = OSAllocatedUnfairLock(initialState: 0)
        let transport = ScriptedTransport(push: { try await server.push($0) }, pull: { token in
            let forged = forgedPulls.withLock { count in
                guard count > 0 else { return false }
                count -= 1
                return true
            }
            return forged ? Self.forgedPage : try await server.pull(since: token)
        })
        let store = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock))
        await server.write(Note(id: "n", text: "real 1"))
        try await store.sync()
        await server.write(Note(id: "n", text: "real 2"))

        // Only the first request goes elsewhere; the check asks the server, and the sync goes on.
        forgedPulls.withLock { $0 = 1 }
        try await store.sync()
        #expect(await store.record("n")?.text == "real 2")
        #expect(await store.state.entries["n"]?.revision?.hasPrefix("legacy") == false)
    }

    /// The edit made after the forged sync reaches the server, and nothing is parked.
    @Test func anEditAfterAPageWithoutAnEpochReachesTheServer() async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        let forged = OSAllocatedUnfairLock(initialState: false)
        let store = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport(server, forged: forged),
                                           configuration: makeConfiguration(clock: clock))
        await server.write(Note(id: "n", text: "real 1"))
        try await store.sync()
        try await store.sync()
        forged.withLock { $0 = true }
        _ = try? await store.sync()
        forged.withLock { $0 = false }
        try await store.save(Note(id: "n", text: "A's edit"))
        for _ in 0..<3 {
            _ = try? await store.sync()
            clock.advance(by: 120)
        }
        #expect(await server.record("n")?.text == "A's edit")
        #expect(await store.pendingChanges().isEmpty)
        #expect(await store.failedChanges().isEmpty)
    }

    /// A store that never held an epoch takes pages without one, as before.
    @Test func aServerWithoutEpochsIsFollowed() async throws {
        let clock = TestClock()
        let page = OSAllocatedUnfairLock(initialState: Self.forgedPage)
        let transport = ScriptedTransport(pull: { _ in page.withLock { $0 } })
        let store = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock))
        try await store.sync()
        #expect(await store.record("n")?.text == "old copy")
        page.withLock {
            $0 = PullResponse(changes: [RemoteChange(recordID: "n", record: Note(id: "n", text: "new copy"), revision: "legacy.100000",
                                                     timestamp: nil, sequence: 100_000)],
                              token: "legacy.100000", hasMore: false, epoch: nil)
        }
        try await store.sync()
        #expect(await store.record("n")?.text == "new copy")
        #expect(await store.state.serverEpoch == nil)
    }
}
