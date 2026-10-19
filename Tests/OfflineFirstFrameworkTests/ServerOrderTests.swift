import Foundation
import Testing
@testable import OfflineFirstFramework

/// Servers that send no ``RemoteChange/sequence``: the store orders their versions by the
/// timestamps the server sent, never by a time of its own, and not by a timestamp it cannot
/// trust.
@Suite("Offline store: servers without sequences")
struct ServerOrderTests {
    let clock = TestClock()

    private var nowMilliseconds: Int64 {
        HybridLogicalClock.milliseconds(since1970: clock.now)
    }

    private func makeStore(_ transport: any SyncTransport<Note>, name: String = "notes", clock: TestClock? = nil) throws -> OfflineStore<Note> {
        try OfflineStore<Note>(name: name, storage: InMemoryStorage(), transport: transport,
                               configuration: makeConfiguration(clock: clock ?? self.clock))
    }

    /// Two pages: `first` for the first pull, `second` for the next one.
    private func twoPages(_ first: RemoteChange<Note>, _ second: RemoteChange<Note>) -> ScriptedTransport {
        ScriptedTransport(pull: { token in
            switch token {
            case nil: PullResponse(changes: [first], token: "t1", hasMore: false)
            case "t1": PullResponse(changes: [second], token: "t2", hasMore: false)
            default: PullResponse(changes: [], token: token, hasMore: false)
            }
        })
    }

    /// The first version has no timestamp (an import on the server), the second one has the
    /// timestamp of an edit made before the store received the first. The store's own time of
    /// receipt says nothing about the server's order.
    @Test func aVersionWithoutATimestampDoesNotHideTheNextOne() async throws {
        let imported = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "imported"), revision: "r1", timestamp: nil)
        let edited = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "edited on B"), revision: "r2",
                                        timestamp: HLCTimestamp(wallTime: nowMilliseconds - 30_000, nodeID: "B"))
        let store = try makeStore(twoPages(imported, edited))
        try await store.sync()
        clock.advance(by: 20)
        try await store.sync()
        #expect(await store.record("a")?.text == "edited on B")
        #expect(await store.state.token == "t2")
    }

    /// A version stamped a day ahead of the device's time is not used to order the next one:
    /// the edit made on top of it carries an earlier timestamp.
    @Test func aVersionStampedFarAheadDoesNotHideALaterOne() async throws {
        let ahead = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "F"), revision: "r1",
                                       timestamp: HLCTimestamp(wallTime: nowMilliseconds + 86_400_000, nodeID: "F"))
        let later = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "G after F"), revision: "r2",
                                       timestamp: HLCTimestamp(wallTime: nowMilliseconds + 60_000, nodeID: "B"))
        let store = try makeStore(twoPages(ahead, later))
        try await store.sync()
        clock.advance(by: 60)
        try await store.sync()
        #expect(await store.record("a")?.text == "G after F")
    }

    /// A device whose clock is a day behind receives two versions an hour apart. Moved to its
    /// own drift limit, both would end at the same time and their order would be lost.
    @Test func aDeviceWhoseClockIsBehindTakesTheNewerVersion() async throws {
        let behind = TestClock()
        behind.advance(by: -86_400)
        let older = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "older"), revision: "r1",
                                       timestamp: HLCTimestamp(wallTime: nowMilliseconds, counter: 1, nodeID: "Z"))
        let newer = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "newer"), revision: "r2",
                                       timestamp: HLCTimestamp(wallTime: nowMilliseconds + 3_600_000, nodeID: "A"))
        let store = try makeStore(twoPages(older, newer), clock: behind)
        try await store.sync()
        #expect(await store.record("a")?.text == "older")
        try await store.sync()
        #expect(await store.record("a")?.text == "newer")
    }

    /// An older page with the timestamps still recognised as older.
    @Test func anOlderPageIsStillSkipped() async throws {
        let newer = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "new"), revision: "r2",
                                       timestamp: HLCTimestamp(wallTime: nowMilliseconds - 1_000, nodeID: "B"))
        let older = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "old"), revision: "r1",
                                       timestamp: HLCTimestamp(wallTime: nowMilliseconds - 5_000, nodeID: "B"))
        let store = try makeStore(twoPages(newer, older))
        try await store.sync()
        try await store.sync()
        #expect(await store.record("a")?.text == "new")
    }

    /// Files from before the server's timestamp was kept knew it only as the record's
    /// timestamp; a file that says the server sent none is not read as having one.
    @Test func filesTellAMissingServerTimestampFromAnUnknownOne() throws {
        let timestamp = #""timestamp":{"wallTime":5000,"counter":0,"nodeID":"B"}"#
        let old = Data(#"{"id":"a","record":{"id":"a","text":"A"},\#(timestamp),"revision":"r1","position":0}"#.utf8)
        let none = Data(#"{"id":"a","record":{"id":"a","text":"A"},\#(timestamp),"revision":"r1","position":0,"serverTimestamp":null}"#.utf8)
        let decoder = JSONDecoder()
        #expect(try decoder.decode(StoredEntry<Note>.self, from: old).serverTimestamp == HLCTimestamp(wallTime: 5_000, nodeID: "B"))
        #expect(try decoder.decode(StoredEntry<Note>.self, from: none).serverTimestamp == nil)

        var entry = try decoder.decode(StoredEntry<Note>.self, from: none)
        entry.record = Note(id: "a", text: "B")
        let roundTrip = try decoder.decode(StoredEntry<Note>.self, from: JSONEncoder().encode(entry))
        #expect(roundTrip.serverTimestamp == nil)
    }
}
