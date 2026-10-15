import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A device whose clock is far ahead must not decide every later conflict, nor make other
/// devices undo later edits.
@Suite("Offline store: wrong clocks")
struct ClockSkewTests {
    let clock = TestClock()

    private var nowMilliseconds: Int64 {
        HybridLogicalClock.milliseconds(since1970: clock.now)
    }

    private func makeStore(_ transport: any SyncTransport<Note>, name: String = "notes", clock: TestClock? = nil,
                           resolver: ConflictResolver<Note> = .lastWriteWins) throws -> OfflineStore<Note> {
        try OfflineStore<Note>(name: name, storage: InMemoryStorage(), transport: transport,
                               configuration: makeConfiguration(clock: clock ?? self.clock, resolver: resolver))
    }

    /// Device A's clock is a hundred years ahead. B's later edit must stay, on the server and on
    /// every device, through the reference server.
    @Test func aDeviceWithAClockYearsAheadDoesNotFreezeARecord() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let wrongClock = TestClock()
        wrongClock.advance(by: 100 * 365 * 86_400)
        let a = try makeStore(server, name: "a", clock: wrongClock)
        let b = try makeStore(server, name: "b")
        let c = try makeStore(server, name: "c")

        try await a.save(Note(id: "x", text: "from broken clock"))
        try await a.sync()
        try await b.sync()
        try await c.sync()

        clock.advance(by: 60)
        try await b.save(Note(id: "x", text: "B real edit"))
        try await b.sync()
        #expect(await server.record("x")?.text == "B real edit")

        try await c.sync()
        try await c.sync()
        try await b.sync()
        #expect(await server.record("x")?.text == "B real edit")
        #expect(await b.record("x")?.text == "B real edit")
        #expect(await c.record("x")?.text == "B real edit")
        #expect(await c.pendingChanges().isEmpty)
    }

    /// A server that keeps any timestamp it receives: the store moves one from the future back
    /// to the drift limit before it stores the version or hands it to the resolver.
    @Test func timestampsFromTheFutureAreMovedBackToTheDriftLimit() async throws {
        let future = HLCTimestamp(wallTime: nowMilliseconds + 100 * 365 * 86_400_000, counter: 7, nodeID: "broken")
        let transport = ScriptedTransport(push: { _ in throw URLError(.notConnectedToInternet) }, pull: { token in
            token == nil
                ? PullResponse(changes: [RemoteChange(recordID: "x", record: Note(id: "x", text: "first"), revision: "1", timestamp: future, sequence: 1)],
                               token: "t1", hasMore: false)
                : PullResponse(changes: [RemoteChange(recordID: "x", record: Note(id: "x", text: "second"), revision: "2", timestamp: future, sequence: 2)],
                               token: "t2", hasMore: false)
        })
        let seen = OSAllocatedUnfairLock<HLCTimestamp?>(initialState: nil)
        let resolver = ConflictResolver<Note> { conflict in
            seen.withLock { $0 = conflict.remoteTimestamp }
            return .keepLocal
        }
        let store = try makeStore(transport, resolver: resolver)
        try await store.sync()
        let limit = nowMilliseconds + 300_000
        #expect(await store.state.entries["x"]?.timestamp == HLCTimestamp(wallTime: limit, counter: 7, nodeID: "broken"))

        clock.advance(by: 600)
        try await store.save(Note(id: "x", text: "local edit"))
        await #expect(throws: URLError.self) { try await store.sync() }
        try await store.sync()
        #expect(seen.withLock { $0 } == HLCTimestamp(wallTime: nowMilliseconds + 300_000, counter: 7, nodeID: "broken"))
        // The device clock did not move to the future either.
        try await store.save(Note(id: "y", text: "now"))
        #expect(await store.state.entries["y"]?.timestamp.wallTime == nowMilliseconds)
    }

    @Test func theInMemoryServerMovesPushedTimestampsFromTheFutureBack() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let future = HLCTimestamp(wallTime: nowMilliseconds + 86_400_000, counter: 1, nodeID: "broken")
        let change = OutgoingChange<Note>(id: UUID(), recordID: "x", operation: .upsert(Note(id: "x", text: "X")), timestamp: future, baseRevision: nil)
        _ = try await server.push([change])
        let stored = try #require(try await server.pull(since: nil).changes.first?.timestamp)
        #expect(stored == HLCTimestamp(wallTime: nowMilliseconds + 300_000, counter: 1, nodeID: "broken"))
    }
}
