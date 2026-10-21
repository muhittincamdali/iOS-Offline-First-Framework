import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// Epochs grow. Another epoch than the store's is believed only when two requests of one sync
/// report it, a pull with the token and a pull from the beginning: a later one starts a new
/// history, an earlier one the store never left is refused until eight syncs in a row met it,
/// and one the store left is refused for good. Neither a stale page nor one misdirected request
/// may stop the store from following the real server.
@Suite("Offline store: server epochs")
struct EpochTests {
    let clock = TestClock()

    private func makeStore(_ transport: any SyncTransport<Note>, storage: any StorageBackend = InMemoryStorage()) throws -> OfflineStore<Note> {
        try OfflineStore<Note>(name: "notes", storage: storage, transport: transport, configuration: makeConfiguration(clock: clock))
    }

    private func forwarding(to server: InMemorySyncServer<Note>) async -> ScriptedTransport {
        let transport = ScriptedTransport()
        await transport.onPush { try await server.push($0) }
        await transport.onPull { try await server.pull(since: $0) }
        return transport
    }

    /// The next `count` pulls get `page`, every later one the server's answer.
    private func answerPulls(_ count: Int, of transport: ScriptedTransport, with page: PullResponse<Note>,
                             from server: InMemorySyncServer<Note>) async {
        let answered = Counter()
        await transport.onPull { token in
            if await answered.next() <= count { return page }
            return try await server.pull(since: token)
        }
    }

    @Test func aLongerEpochIsLaterAndEpochsAsLongAreOrderedByTheirBytes() {
        #expect(OfflineStore<Note>.isLater("10", than: "9"))
        #expect(OfflineStore<Note>.isLater("0000000000000010", than: "000000000000000f"))
        #expect(OfflineStore<Note>.isLater("e2", than: "e1"))
        #expect(!OfflineStore<Note>.isLater("e1", than: "e2"))
        #expect(!OfflineStore<Note>.isLater("e1", than: "e1"))
    }

    /// The store first meets the server after a restart (E2). A lagging replica still in E1,
    /// which the store never saw, answers one pull: the page is not stored, the pull from the
    /// beginning and the pull with the token reach the server, and the sync goes on with it,
    /// also after an app restart.
    @Test func aStaleReplicaFromAnEarlierEpochTheStoreNeverSawIsRefused() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        await server.write(Note(id: "a", text: "v1"))
        let staleE1 = try await server.pull(since: nil)
        await server.restart()
        let transport = await forwarding(to: server)
        let storage = InMemoryStorage()
        var store = try makeStore(transport, storage: storage)
        try await store.sync()
        let epoch = await store.state.serverEpoch

        await answerPulls(1, of: transport, with: staleE1, from: server)
        try await store.sync()
        #expect(await store.state.serverEpoch == epoch)
        #expect(await store.state.epochRefusal == nil)

        clock.advance(by: 10)
        await server.write(Note(id: "b", text: "written later on another device"))
        try await store.sync()
        #expect(await store.record("b") != nil)
        #expect(await store.state.epochRefusal == nil)

        store = try makeStore(transport, storage: storage)
        try await store.resetChangeToken()
        try await store.sync()
        #expect(await store.records().map(\.id).sorted() == ["a", "b"])
        #expect(await store.state.serverEpoch == epoch)
    }

    /// The replica answers every pull of two syncs, with and without the token, with a page
    /// from before a deletion. Both syncs refuse it, so the deleted record never comes back, and
    /// the store goes on with the server.
    @Test func aStaleReplicaFromAnEarlierEpochDoesNotBringBackADeletedRecord() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        await server.write(Note(id: "a", text: "v1"))
        let staleE1 = try await server.pull(since: nil)
        await server.restart()
        clock.advance(by: 10)
        await server.delete("a")
        let transport = await forwarding(to: server)
        let store = try makeStore(transport)
        try await store.sync()
        #expect(await store.record("a") == nil)

        await answerPulls(4, of: transport, with: staleE1, from: server)
        for _ in 0..<2 {
            await #expect(throws: OfflineFirstError.self) { try await store.sync() }
            #expect(await store.record("a") == nil)
        }
        try await store.sync()
        #expect(await store.record("a") == nil)
        #expect(await store.count == 0)
    }

    /// One pull is answered by another deployment behind the same URL (staging), whose epoch
    /// is later or earlier than production's. The store does not leave production's history:
    /// the pull from the beginning names production's epoch, so the staging page is dropped and
    /// the sync goes on after the token. New production records arrive and local edits reach
    /// production.
    @Test(arguments: [true, false])
    func onePullFromAnotherDeploymentDoesNotLockTheStoreOut(stagingIsLater: Bool) async throws {
        let first = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let second = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let (production, staging) = stagingIsLater ? (first, second) : (second, first)
        await production.write(Note(id: "a", text: "production"))
        let misroute = OSAllocatedUnfairLock(initialState: false)
        let transport = ScriptedTransport(identity: "https://api.example.com/sync/notes", push: { try await production.push($0) },
                                          pull: { token in
            let once = misroute.withLock { value in
                defer { value = false }
                return value
            }
            return try await (once ? staging : production).pull(since: token)
        })
        let store = try makeStore(transport)
        try await store.sync()
        let epoch = await store.state.serverEpoch

        misroute.withLock { $0 = true }
        try await store.sync()
        #expect(await store.state.serverEpoch == epoch)
        await production.write(Note(id: "b", text: "new on production"))
        try await store.sync()
        try await store.save(Note(id: "c", text: "local"))
        try await store.sync()
        #expect(await store.record("b")?.text == "new on production")
        #expect(await production.record("c")?.text == "local")
        #expect(await store.pendingChanges().isEmpty)
    }

    /// The store's first epoch came from somewhere else, and the real server's epoch is
    /// earlier, one the store never held (a server whose epochs do not grow looks the same). Its
    /// pages, with and without the token, are refused, eight syncs in a row at most, counted
    /// across app restarts; then the store follows it. A page of the store's own epoch in
    /// between starts the count over.
    @Test func anEarlierEpochTheStoreNeverHeldIsTakenAfterItWasRefusedEightSyncsInARow() async throws {
        let wrong = PullResponse<Note>(changes: [RemoteChange(recordID: "w", record: Note(id: "w", text: "elsewhere"), revision: "e2.1",
                                                             timestamp: nil, sequence: 1)], token: "e2.1", hasMore: false, epoch: "e2")
        let real = PullResponse<Note>(changes: [RemoteChange(recordID: "a", record: Note(id: "a", text: "real"), revision: "e1.1",
                                                            timestamp: nil, sequence: 1)], token: "e1.1", hasMore: false, epoch: "e1")
        let answers = OSAllocatedUnfairLock<[PullResponse<Note>]>(initialState: [wrong])
        let transport = ScriptedTransport(pull: { _ in
            answers.withLock { $0.count > 1 ? $0.removeFirst() : $0[0] }
        })
        let storage = InMemoryStorage()
        var store = try makeStore(transport, storage: storage)
        try await store.sync()
        #expect(await store.state.serverEpoch == "e2")
        #expect(await store.record("w") != nil)

        answers.withLock { $0 = [real] }
        for attempt in 1..<OfflineStore<Note>.maximumEpochRefusals {
            await #expect(throws: OfflineFirstError.self) { try await store.sync() }
            #expect(await store.state.epochRefusal == EpochRefusal(epoch: "e1", syncs: attempt))
            if attempt == 3 { store = try makeStore(transport, storage: storage) }
        }
        try await store.sync()
        #expect(await store.state.serverEpoch == "e1")
        #expect(await store.state.epochRefusal == nil)
        #expect(await store.record("a")?.text == "real")

        // Going back retired nothing. Two refusals of another epoch the store never held, then
        // a page of the store's own epoch: the count starts over.
        #expect(await store.state.retiredEpochs.isEmpty)
        let older = PullResponse<Note>(changes: [], token: "e0.0", hasMore: false, epoch: "e0")
        answers.withLock { $0 = [older, older, older, older, real] }
        for _ in 0..<2 {
            await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        }
        #expect(await store.state.epochRefusal?.syncs == 2)
        try await store.sync()
        #expect(await store.state.epochRefusal == nil)
    }

    /// The store left e1 for e2. Pages of e1, with and without the token, are refused in every
    /// sync, more than eight in a row, after resetChangeToken() and after an app restart; the
    /// store keeps e2 and its records. A new epoch of the server, e3, is followed.
    @Test func anEpochTheStoreLeftIsRefusedForGood() async throws {
        @Sendable func page(_ epoch: String, _ text: String) -> PullResponse<Note> {
            PullResponse(changes: [RemoteChange(recordID: "a", record: Note(id: "a", text: text), revision: "\(epoch).1", timestamp: nil,
                                                sequence: 1)], token: "\(epoch).1", hasMore: false, epoch: epoch)
        }
        let answer = OSAllocatedUnfairLock(initialState: page("e1", "first"))
        let transport = ScriptedTransport(pull: { _ in answer.withLock { $0 } })
        let storage = InMemoryStorage()
        var store = try makeStore(transport, storage: storage)
        try await store.sync()
        answer.withLock { $0 = page("e2", "after the restart") }
        try await store.sync()
        #expect(await store.state.serverEpoch == "e2")
        #expect(await store.state.retiredEpochs == ["e1"])

        answer.withLock { $0 = page("e1", "first") }
        let history = await store.state.history
        for attempt in 0..<(2 * OfflineStore<Note>.maximumEpochRefusals) {
            if attempt == 3 { try await store.resetChangeToken() }
            if attempt == 5 { store = try makeStore(transport, storage: storage) }
            await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        }
        #expect(await store.state.serverEpoch == "e2")
        #expect(await store.state.history == history)
        #expect(await store.state.retiredEpochs == ["e1"])
        #expect(await store.record("a")?.text == "after the restart")

        answer.withLock { $0 = page("e3", "after the next restart") }
        try await store.sync()
        #expect(await store.state.serverEpoch == "e3")
        #expect(await store.state.retiredEpochs == ["e1", "e2"])
        #expect(await store.record("a")?.text == "after the next restart")
    }
}
