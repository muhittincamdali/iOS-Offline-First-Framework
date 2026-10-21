import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A feed server as the protocol allows it: no sequences, change IDs optional, and pushed
/// timestamps kept as they are or moved back to a limit ahead of its clock.
private actor FeedServer {
    struct Version {
        var record: Note?
        var revision: String
        var position: Int
        var timestamp: HLCTimestamp
        var changeID: UUID
    }

    let sendsChangeIDs: Bool
    let clampSeconds: Double?
    let now: @Sendable () -> Date
    private var stored: [String: Version] = [:]
    private var position = 0
    private var failingPulls = 0

    init(sendsChangeIDs: Bool, clampSeconds: Double?, now: @escaping @Sendable () -> Date) {
        self.sendsChangeIDs = sendsChangeIDs
        self.clampSeconds = clampSeconds
        self.now = now
    }

    func failNextPulls(_ count: Int) { failingPulls = count }
    func text(_ id: String) -> String? { stored[id]?.record?.text }

    private func remote(_ id: String, _ version: Version) -> RemoteChange<Note> {
        RemoteChange(recordID: id, record: version.record, revision: version.revision, timestamp: version.timestamp,
                     sequence: nil, changeID: sendsChangeIDs ? version.changeID : nil)
    }

    func push(_ changes: [OutgoingChange<Note>]) -> [UUID: PushOutcome<Note>] {
        var outcomes: [UUID: PushOutcome<Note>] = [:]
        for change in changes {
            if let current = stored[change.recordID], current.revision != change.baseRevision {
                outcomes[change.id] = .conflict(current: remote(change.recordID, current))
                continue
            }
            position += 1
            var timestamp = change.timestamp
            if let clampSeconds {
                let limit = HybridLogicalClock.milliseconds(since1970: now().addingTimeInterval(clampSeconds))
                if timestamp.wallTime > limit {
                    timestamp = HLCTimestamp(wallTime: limit, counter: timestamp.counter, nodeID: timestamp.nodeID)
                }
            }
            stored[change.recordID] = Version(record: change.record, revision: "v\(position)", position: position, timestamp: timestamp,
                                              changeID: change.id)
            outcomes[change.id] = .accepted(revision: "v\(position)")
        }
        return outcomes
    }

    func pull(_ token: String?) throws -> PullResponse<Note> {
        if failingPulls > 0 {
            failingPulls -= 1
            throw URLError(.networkConnectionLost)
        }
        let after = token.flatMap { Int($0) } ?? 0
        let changed = stored.filter { $0.value.position > after }.sorted { $0.value.position < $1.value.position }
        let next = changed.last?.value.position ?? after
        return PullResponse(changes: changed.map { remote($0.key, $0.value) }, token: "\(next)", hasMore: false)
    }
}

/// A server that sends no ``RemoteChange/sequence`` gives the store no order of its versions,
/// and the store does not make one up from timestamps: they are written by device clocks, and
/// a clock that was ahead, for a moment or for good, would hide every later version. Before,
/// the device whose clock had jumped a year ahead kept its own write, stamped a year ahead,
/// never took another device's later edit of the record, and every edit it made afterwards
/// was parked, also after thirty days and ``OfflineStore/retryFailedChanges()``.
@Suite("Offline store: device clocks on a server without sequences")
struct UnorderedServerClockTests {
    private static let year: Double = 365 * 86_400

    private func makeStores(_ server: FeedServer, clockOfA: TestClock, clockOfB: TestClock)
        throws -> (OfflineStore<Note>, OfflineStore<Note>) {
        let transportOfA = ScriptedTransport(push: { await server.push($0) }, pull: { try await server.pull($0) })
        let transportOfB = ScriptedTransport(push: { await server.push($0) }, pull: { try await server.pull($0) })
        return (try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transportOfA,
                                       configuration: makeConfiguration(clock: clockOfA)),
                try OfflineStore<Note>(name: "b", storage: InMemoryStorage(), transport: transportOfB,
                                       configuration: makeConfiguration(clock: clockOfB)))
    }

    private func advance(_ clocks: TestClock..., by seconds: Double) {
        for clock in clocks { clock.advance(by: seconds) }
    }

    /// A writes while its clock shows a time a year ahead; once the clock is back, B edits on
    /// top of A's write. A takes B's edit, and its own next edit reaches the server. Against a
    /// server that keeps the pushed timestamps and sends no change IDs, and against one that
    /// moves them back to five minutes ahead and sends change IDs, when the pull after A's push
    /// fails, so the echo of A's write never arrives.
    @Test(arguments: [false, true])
    func aMomentaryClockJumpHidesNoLaterVersion(clampingServer: Bool) async throws {
        let clock = TestClock()
        let clockOfA = TestClock()
        let server = FeedServer(sendsChangeIDs: clampingServer, clampSeconds: clampingServer ? 300 : nil, now: { clock.now })
        let (a, b) = try makeStores(server, clockOfA: clockOfA, clockOfB: clock)

        clockOfA.advance(by: Self.year)
        try await a.save(Note(id: "x", text: "A1"))
        if clampingServer { await server.failNextPulls(1) }
        _ = try? await a.sync()
        clockOfA.advance(by: -Self.year)
        #expect(await server.text("x") == "A1")

        advance(clock, clockOfA, by: 60)
        try await b.sync()
        #expect(await b.record("x")?.text == "A1")
        try await b.save(Note(id: "x", text: "B1"))
        try await b.sync()
        #expect(await server.text("x") == "B1")

        advance(clock, clockOfA, by: 60)
        try await a.sync()
        try await a.sync()
        #expect(await a.record("x")?.text == "B1", "A kept its own write stamped a year ahead")

        try await a.save(Note(id: "x", text: "A2"))
        for _ in 0..<6 {
            _ = try? await a.sync()
            advance(clock, clockOfA, by: 120)
        }
        #expect(await server.text("x") == "A2", "A's later edit did not reach the server")
        #expect(await a.failedChanges().isEmpty)
        #expect(await a.pendingChanges().isEmpty)
        try await b.sync()
        #expect(await b.record("x")?.text == "A2")
    }

    /// The same jump against a server that moves timestamps back and sends change IDs, without
    /// any failure: B's write lands between A's push and A's pull of the same sync.
    @Test func aMomentaryClockJumpAndARace() async throws {
        let clock = TestClock()
        let clockOfA = TestClock()
        let server = FeedServer(sendsChangeIDs: true, clampSeconds: 300, now: { clock.now })
        let transportOfB = ScriptedTransport(push: { await server.push($0) }, pull: { try await server.pull($0) })
        let b = try OfflineStore<Note>(name: "b", storage: InMemoryStorage(), transport: transportOfB,
                                       configuration: makeConfiguration(clock: clock))
        try await b.save(Note(id: "x", text: "B0"))
        try await b.sync()
        let race = OSAllocatedUnfairLock(initialState: false)
        let transportOfA = ScriptedTransport(push: { await server.push($0) }, pull: { token in
            if race.withLock({ armed in defer { armed = false }; return armed }) {
                try await b.sync()
                try await b.save(Note(id: "x", text: "B1"))
                try await b.sync()
            }
            return try await server.pull(token)
        })
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transportOfA,
                                       configuration: makeConfiguration(clock: clockOfA))
        try await a.sync()
        clockOfA.advance(by: Self.year)
        try await a.save(Note(id: "x", text: "A1"))
        race.withLock { $0 = true }
        try await a.sync()
        clockOfA.advance(by: -Self.year)
        for _ in 0..<3 {
            _ = try? await a.sync()
            advance(clock, clockOfA, by: 60)
        }
        #expect(await a.record("x")?.text == "B1")
        try await a.save(Note(id: "x", text: "A2"))
        for _ in 0..<6 {
            _ = try? await a.sync()
            advance(clock, clockOfA, by: 120)
        }
        #expect(await server.text("x") == "A2")
        #expect(await a.failedChanges().isEmpty)
    }

    /// A device whose clock stays an hour ahead takes the later edit of a device with a correct
    /// clock, and its own edit on top of it reaches the server.
    @Test(arguments: [false, true])
    func aClockThatStaysAheadHidesNoLaterVersion(clampingServer: Bool) async throws {
        let clock = TestClock()
        let clockOfA = TestClock()
        clockOfA.advance(by: 3_600)
        let server = FeedServer(sendsChangeIDs: clampingServer, clampSeconds: clampingServer ? 300 : nil, now: { clock.now })
        let (a, b) = try makeStores(server, clockOfA: clockOfA, clockOfB: clock)
        try await a.save(Note(id: "x", text: "A1"))
        if clampingServer { await server.failNextPulls(1) }
        _ = try? await a.sync()
        advance(clock, clockOfA, by: 60)
        try await b.sync()
        try await b.save(Note(id: "x", text: "B1"))
        try await b.sync()
        advance(clock, clockOfA, by: 60)
        try await a.sync()
        #expect(await a.record("x")?.text == "B1")
        try await a.save(Note(id: "x", text: "A2"))
        for _ in 0..<6 {
            _ = try? await a.sync()
            advance(clock, clockOfA, by: 120)
        }
        #expect(await server.text("x") == "A2")
        #expect(await a.failedChanges().isEmpty)
    }

    /// The reference server sends sequences, which order its versions whatever the clocks say.
    @Test func aMomentaryClockJumpWithSequences() async throws {
        let clock = TestClock()
        let clockOfA = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: server,
                                       configuration: makeConfiguration(clock: clockOfA))
        let b = try OfflineStore<Note>(name: "b", storage: InMemoryStorage(), transport: server,
                                       configuration: makeConfiguration(clock: clock))
        clockOfA.advance(by: Self.year)
        try await a.save(Note(id: "x", text: "A1"))
        try await a.sync()
        clockOfA.advance(by: -Self.year)
        advance(clock, clockOfA, by: 60)
        try await b.sync()
        try await b.save(Note(id: "x", text: "B1"))
        try await b.sync()
        try await a.sync()
        #expect(await a.record("x")?.text == "B1")
        try await a.save(Note(id: "x", text: "A2"))
        try await a.sync()
        #expect(await server.record("x")?.text == "A2")
    }
}
