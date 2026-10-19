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

    /// X edits offline, then its clock is set back, by ten minutes or a day; Y edits an hour
    /// later. The drift limit must not push Y's newer edit below X's older one, or last write
    /// wins would put X's edit back on the server.
    @Test(arguments: [600.0, 86_400.0])
    func aDeviceWhoseClockWasSetBackDoesNotOverwriteANewerEdit(setBack: TimeInterval) async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let xClock = TestClock()
        let x = try makeStore(server, name: "x", clock: xClock)
        let y = try makeStore(server, name: "y")
        try await x.save(Note(id: "r", text: "v0"))
        try await x.sync()
        try await y.sync()

        clock.advance(by: 10)
        xClock.advance(by: 10)
        try await x.save(Note(id: "r", text: "X older edit"))
        xClock.advance(by: -setBack)
        clock.advance(by: 3_600)
        try await y.save(Note(id: "r", text: "Y newer edit"))
        try await y.sync()

        try await x.sync()
        try await y.sync()
        #expect(await server.record("r")?.text == "Y newer edit")
        #expect(await x.record("r")?.text == "Y newer edit")
        #expect(await y.record("r")?.text == "Y newer edit")
        #expect(await x.pendingChanges().isEmpty)
    }

    /// A push fails while the device clock is a year ahead (a game's time travel), so its retry
    /// date is a year ahead too. Once the clock is set right, the change goes out with the next
    /// sync: no wait of the retry policy is that long.
    @Test func aRetryDateSetWhileTheClockWasAheadDoesNotHoldTheChangeBack() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let device = TestClock()
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: server,
                                           configuration: makeConfiguration(clock: device, retry: .default))
        try await store.save(Note(id: "a", text: "edit"))
        device.advance(by: 365 * 86_400)
        await server.setOnline(false)
        await #expect(throws: URLError.self) { try await store.sync() }
        let retryDate = try #require(await store.pendingChanges().first?.nextAttemptAt)
        #expect(retryDate > device.now)

        device.advance(by: -365 * 86_400)
        await server.setOnline(true)
        try await store.sync()
        #expect(await server.record("a")?.text == "edit")
        #expect(await store.pendingChanges().isEmpty)
    }
}
