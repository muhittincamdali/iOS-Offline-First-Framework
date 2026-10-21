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

    /// The server bounds a pushed timestamp by its own clock, the one clock every device shares,
    /// and sends back the change ID that wrote the version, by which the pushing device
    /// recognises its own write.
    @Test func theInMemoryServerBoundsPushedTimestampsAndSendsBackTheChangeID() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let future = HLCTimestamp(wallTime: nowMilliseconds + 86_400_000, counter: 1, nodeID: "broken")
        let change = OutgoingChange<Note>(id: UUID(), recordID: "x", operation: .upsert(Note(id: "x", text: "X")), timestamp: future, baseRevision: nil)
        _ = try await server.push([change])
        let stored = try #require(try await server.pull(since: nil).changes.first)
        #expect(stored.timestamp == HLCTimestamp(wallTime: nowMilliseconds + 300_000, counter: 1, nodeID: "broken"))
        #expect(stored.changeID == change.id)
    }

    /// Device A's clock runs ahead by ten minutes or a day. A writes a record; B edits it
    /// offline later in real time, on the version before. B's edit is the newer one, on the
    /// server and on both devices.
    @Test(arguments: [(600.0, 480.0), (86_400.0, 7_200.0)])
    func aWriteFromADeviceAheadDoesNotBeatALaterEditOnAnotherDevice(ahead: TimeInterval, laterBy: TimeInterval) async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let aheadClock = TestClock()
        aheadClock.advance(by: ahead)
        let a = try makeStore(server, name: "a", clock: aheadClock)
        let b = try makeStore(server, name: "b")
        await server.write(Note(id: "x", text: "v0"))
        try await a.sync()
        try await b.sync()
        clock.advance(by: 60)
        aheadClock.advance(by: 60)
        try await a.save(Note(id: "x", text: "A edit"))
        try await a.sync()
        clock.advance(by: laterBy)
        aheadClock.advance(by: laterBy)
        try await b.save(Note(id: "x", text: "B edit, later in real time"))
        try await b.sync()
        try await a.sync()
        #expect(await server.record("x")?.text == "B edit, later in real time")
        #expect(await a.record("x")?.text == "B edit, later in real time")
        #expect(await b.record("x")?.text == "B edit, later in real time")
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

    /// The device clock is ten minutes ahead of the server's. The server applies a push whose
    /// answer is lost, and the user edits again. The reference server keeps the timestamp as it
    /// was pushed, so the store recognises its own write in the conflict answer: the newest edit
    /// goes out on top of it, and server wins does not drop it.
    @Test func aLostAnswerOnADeviceAheadOfTheServerIsTheDevicesOwnWrite() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let device = TestClock()
        device.advance(by: 600)
        let answerLost = OneShot()
        let losesAnswers = OSAllocatedUnfairLock(initialState: false)
        let transport = ScriptedTransport()
        await transport.onPush { changes in
            let outcomes = try await server.push(changes)
            if losesAnswers.withLock({ $0 }), await answerLost.fire() { throw URLError(.networkConnectionLost) }
            return outcomes
        }
        await transport.onPull { try await server.pull(since: $0) }
        let store = try makeStore(transport, clock: device, resolver: .serverWins)
        try await store.save(Note(id: "a", text: "v0"))
        try await store.sync()
        try await store.save(Note(id: "a", text: "v1"))
        losesAnswers.withLock { $0 = true }
        await #expect(throws: URLError.self) { try await store.sync() }
        #expect(await server.record("a")?.text == "v1")

        try await store.save(Note(id: "a", text: "v2 newest"))
        device.advance(by: 30)
        clock.advance(by: 30)
        let report = try await store.sync()
        #expect(report.conflicts == 0)
        #expect(await server.record("a")?.text == "v2 newest")
        #expect(await store.record("a")?.text == "v2 newest")
        #expect(await store.pendingChanges().isEmpty)
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
