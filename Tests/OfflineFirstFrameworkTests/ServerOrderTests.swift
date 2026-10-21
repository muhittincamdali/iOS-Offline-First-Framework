import Foundation
import Testing
@testable import OfflineFirstFramework

/// Servers that send no ``RemoteChange/sequence``: the store does not order their versions,
/// neither by a time of its own nor by the timestamps the devices wrote. Each version a page
/// brings is taken as the newest, as the server sends them in order.
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
        let feed = PageFeed()
        await feed.publish(older)
        let store = try makeStore(feed, clock: behind)
        try await store.sync()
        #expect(await store.record("a")?.text == "older")
        await feed.publish(newer)
        try await store.sync()
        #expect(await store.record("a")?.text == "newer")
    }

    /// A page out of order is taken: without sequences nothing tells it is older, and a
    /// timestamp does not, since a device clock wrote it. The record shows the older version
    /// until it changes again, as the limits say.
    @Test func anOlderPageIsTakenUntilTheRecordChangesAgain() async throws {
        let newer = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "new"), revision: "r2",
                                       timestamp: HLCTimestamp(wallTime: nowMilliseconds - 1_000, nodeID: "B"))
        let older = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "old"), revision: "r1",
                                       timestamp: HLCTimestamp(wallTime: nowMilliseconds - 5_000, nodeID: "B"))
        let newest = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "newest"), revision: "r3",
                                        timestamp: HLCTimestamp(wallTime: nowMilliseconds - 3_000, nodeID: "C"))
        let feed = PageFeed()
        let store = try makeStore(feed)
        await feed.publish(newer)
        try await store.sync()
        await feed.publish(older)
        try await store.sync()
        #expect(await store.record("a")?.text == "old")
        await feed.publish(newest)
        try await store.sync()
        #expect(await store.record("a")?.text == "newest")
    }

    /// The same pages with sequences: the older one is skipped.
    @Test func anOlderPageWithSequencesIsSkipped() async throws {
        let newer = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "new"), revision: "r2", timestamp: nil, sequence: 2)
        let older = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "old"), revision: "r1", timestamp: nil, sequence: 1)
        let store = try makeStore(twoPages(newer, older))
        try await store.sync()
        try await store.sync()
        #expect(await store.record("a")?.text == "new")
    }

    /// Earlier builds of this version kept a server timestamp per record to order the versions
    /// of a server without sequences; a file with that key opens, and the key is not written
    /// again.
    @Test func filesWithAServerTimestampOpen() throws {
        let timestamp = #""timestamp":{"wallTime":5000,"counter":0,"nodeID":"B"}"#
        let file = Data(#"{"id":"a","record":{"id":"a","text":"A"},\#(timestamp),"revision":"r1","position":0,"serverTimestamp":{"wallTime":9000,"counter":0,"nodeID":"B"}}"#.utf8)
        let entry = try JSONDecoder().decode(StoredEntry<Note>.self, from: file)
        #expect(entry.record?.text == "A")
        #expect(entry.revision == "r1")
        let written = String(decoding: try JSONEncoder().encode(entry), as: UTF8.self)
        #expect(!written.contains("serverTimestamp"))
    }
}
