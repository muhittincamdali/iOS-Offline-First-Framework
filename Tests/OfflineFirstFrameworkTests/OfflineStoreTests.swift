import CryptoKit
import Foundation
import Testing
@testable import OfflineFirstFramework

@Suite("Offline store: local data")
struct OfflineStoreTests {
    let clock = TestClock()

    private func makeStore(_ storage: any StorageBackend = InMemoryStorage(), name: String = "notes",
                           configure: (inout OfflineStore<Note>.Configuration) -> Void = { _ in }) throws -> OfflineStore<Note> {
        var configuration = makeConfiguration(clock: clock)
        configure(&configuration)
        return try OfflineStore<Note>(name: name, storage: storage, configuration: configuration)
    }

    @Test func savesReadsAndKeepsInsertionOrder() async throws {
        let store = try makeStore()
        try await store.save(Note(id: "b", text: "Second"))
        try await store.save(Note(id: "a", text: "First"))
        try await store.save(Note(id: "b", text: "Second, edited"))
        #expect(await store.records() == [Note(id: "b", text: "Second, edited"), Note(id: "a", text: "First")])
        #expect(await store.record("a")?.text == "First")
        #expect(await store.count == 2)
        #expect(await store.pendingChanges().map(\.recordID) == ["b", "a"])
    }

    @Test func editingAQueuedRecordReplacesItsChange() async throws {
        let store = try makeStore()
        try await store.save(Note(id: "a", text: "One"))
        let first = try #require(await store.pendingChanges().first)
        try await store.save(Note(id: "a", text: "Two"))
        let second = try #require(await store.pendingChanges().first)
        #expect(await store.pendingChanges().count == 1)
        #expect(first.id != second.id)
        #expect(second.record?.text == "Two")
    }

    @Test func survivesReopening() async throws {
        let storage = InMemoryStorage()
        let first = try makeStore(storage)
        try await first.save(contentsOf: [Note(id: "a", text: "A"), Note(id: "b", text: "B")])
        let reopened = try makeStore(storage)
        #expect(await reopened.records() == [Note(id: "a", text: "A"), Note(id: "b", text: "B")])
        #expect(await reopened.pendingChanges().count == 2)
        #expect(reopened.nodeID == first.nodeID)
        #expect(storage.names == ["notes.store"])
    }

    @Test func deletingANeverSyncedRecordRemovesItsChange() async throws {
        let store = try makeStore()
        try await store.save(Note(id: "a", text: "Draft"))
        try await store.delete("a")
        try await store.delete("missing")
        #expect(await store.records().isEmpty)
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test func fullOutboxRefusesNewRecordsButAcceptsEdits() async throws {
        let store = try makeStore { $0.maximumPendingChanges = 2 }
        try await store.save(contentsOf: [Note(id: "a", text: "A"), Note(id: "b", text: "B")])
        await #expect(throws: OfflineFirstError.outboxFull(limit: 2)) {
            try await store.save(Note(id: "c", text: "C"))
        }
        try await store.save(Note(id: "a", text: "A2"))
        #expect(await store.count == 2)
        // A batch that does not fit is not stored at all.
        await #expect(throws: OfflineFirstError.outboxFull(limit: 2)) {
            try await store.save(contentsOf: [Note(id: "a", text: "A3"), Note(id: "d", text: "D")])
        }
        #expect(await store.record("a")?.text == "A2")
    }

    @Test func failedWriteLeavesTheStoreUnchanged() async throws {
        let storage = FailingStorage()
        let store = try makeStore(storage)
        try await store.save(Note(id: "a", text: "Kept"))
        storage.setFailing(true)
        await #expect(throws: OfflineFirstError.self) {
            try await store.save(Note(id: "a", text: "Lost"))
        }
        #expect(await store.record("a")?.text == "Kept")
        storage.setFailing(false)
        #expect(try await makeStore(storage.inner).records() == [Note(id: "a", text: "Kept")])
    }

    @Test(arguments: ["", "../notes", "a/b", ".hidden", String(repeating: "n", count: 250)])
    func rejectsUnsafeNames(name: String) {
        #expect(throws: OfflineFirstError.self) {
            try makeStore(name: name)
        }
    }

    @Test func encryptedStoresHideTheirContent() async throws {
        let storage = InMemoryStorage()
        let encryption = try StoreEncryption.aesGCM(key: SymmetricKey(size: .bits256))
        let store = try makeStore(storage) { $0.encryption = encryption }
        try await store.save(Note(id: "a", text: "Secret plan"))
        let bytes = try #require(try storage.read("notes.store"))
        #expect(bytes.range(of: Data("Secret plan".utf8)) == nil)
        #expect(try await makeStore(storage) { $0.encryption = encryption }.records() == [Note(id: "a", text: "Secret plan")])
        #expect(throws: OfflineFirstError.encryptedStoreWithoutKey(name: "notes")) {
            try makeStore(storage)
        }
    }

    @Test func turningOnEncryptionMigratesAPlainStoreOnlyWhenAllowed() async throws {
        let storage = InMemoryStorage()
        try await makeStore(storage).save(Note(id: "a", text: "Plain"))
        let key = SymmetricKey(size: .bits256)
        #expect(throws: OfflineFirstError.decryptionFailed) {
            try makeStore(storage) { $0.encryption = try! .aesGCM(key: key) }
        }
        let migrating = try makeStore(storage) { $0.encryption = try! .aesGCM(key: key, acceptsUnencryptedData: true) }
        try await migrating.save(Note(id: "b", text: "Now sealed"))
        #expect(try await makeStore(storage) { $0.encryption = try! .aesGCM(key: key) }.count == 2)
    }

    @Test func corruptFilesFailOrAreMovedAside() async throws {
        let storage = InMemoryStorage()
        try storage.write(Data("not json".utf8), to: "notes.store")
        #expect(throws: OfflineFirstError.self) {
            try makeStore(storage)
        }
        let store = try makeStore(storage) { $0.corruptionPolicy = .moveAsideAndStartEmpty }
        #expect(await store.records().isEmpty)
        #expect(storage.names == ["notes.store.corrupt-1700000000000"])
    }

    /// A server that sends more data than the file may hold cannot make the store unopenable:
    /// the page is not stored, the sync fails, and the store still opens.
    @Test func aPullThatWouldOutgrowTheFileLimitIsNotStored() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try FileStore(directory: directory, protection: .none, maximumFileSize: 64 * 1024)
        let page = (0..<2_000).map {
            RemoteChange<Note>(recordID: "r\($0)", record: Note(id: "r\($0)", text: String(repeating: "x", count: 100)), revision: "1", timestamp: nil)
        }
        let transport = ScriptedTransport(pull: { token in
            token == nil ? PullResponse(changes: page, token: "t1", hasMore: false) : PullResponse(changes: [], token: token, hasMore: false)
        })
        let store = try OfflineStore<Note>(name: "notes", storage: files, transport: transport, configuration: makeConfiguration(clock: clock))
        try await store.save(Note(id: "mine", text: "kept"))
        await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        guard case .failed = await store.status else {
            Issue.record("expected a failed status")
            return
        }
        #expect(await store.state.token == nil)
        #expect(await store.records() == [Note(id: "mine", text: "kept")])

        let reopened = try OfflineStore<Note>(name: "notes", storage: files, configuration: makeConfiguration(clock: clock))
        #expect(await reopened.records() == [Note(id: "mine", text: "kept")])
        // The push before the pull went through and was stored.
        #expect(await reopened.pendingChanges().isEmpty)
    }

    /// A file over the limit (written before writes were limited, or the limit was lowered)
    /// is moved aside with `.moveAsideAndStartEmpty`, like a damaged one.
    @Test func aFileOverTheLimitIsMovedAside() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let large = try FileStore(directory: directory, protection: .none)
        try await makeStore(large).save(contentsOf: (0..<100).map { Note(id: "n\($0)", text: String(repeating: "x", count: 100)) })
        let small = try FileStore(directory: directory, protection: .none, maximumFileSize: 1_024)
        #expect(throws: OfflineFirstError.self) { try makeStore(small) }
        let store = try makeStore(small) { $0.corruptionPolicy = .moveAsideAndStartEmpty }
        #expect(await store.records().isEmpty)
        #expect(try small.names() == ["notes.store.corrupt-1700000000000"])
    }

    /// Two instances on one file: the second one's write is refused instead of dropping the
    /// record the first one saved.
    @Test func aSecondInstanceCannotDropTheFirstOnesSave() async throws {
        let storage = InMemoryStorage()
        let first = try makeStore(storage)
        let second = try makeStore(storage)
        try await first.save(Note(id: "a", text: "A"))
        await #expect(throws: OfflineFirstError.storeChangedElsewhere(name: "notes")) {
            try await second.save(Note(id: "b", text: "B"))
        }
        #expect(await second.records().isEmpty)
        let reopened = try makeStore(storage)
        #expect(await reopened.records() == [Note(id: "a", text: "A")])
        try await reopened.save(Note(id: "b", text: "B"))
        #expect(await reopened.count == 2)
    }

    @Test func twoFileStoresForOneDirectoryShareTheProtection() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try makeStore(try FileStore(directory: directory, protection: .none))
        let second = try makeStore(try FileStore(directory: directory.appending(path: "."), protection: .none))
        try await second.save(Note(id: "b", text: "B"))
        await #expect(throws: OfflineFirstError.storeChangedElsewhere(name: "notes")) {
            try await first.save(Note(id: "a", text: "A"))
        }
        // Another store name is another file.
        try await makeStore(try FileStore(directory: directory, protection: .none), name: "other").save(Note(id: "c", text: "C"))
    }

    @Test func storesFromANewerSchemaAreNeverReset() throws {
        let storage = InMemoryStorage()
        try storage.write(Data(#"{"format":1,"schemaVersion":5,"nodeID":"x","nextSequence":0,"entries":[]}"#.utf8), to: "notes.store")
        #expect(throws: OfflineFirstError.unsupportedSchemaVersion(found: 5, supported: 1)) {
            try makeStore(storage) { $0.corruptionPolicy = .moveAsideAndStartEmpty }
        }
        #expect(storage.names == ["notes.store"])
    }

    @Test func migrationsRewriteStoredRecords() async throws {
        struct OldNote: SyncableRecord { var id: String; var body: String }
        let storage = InMemoryStorage()
        let old = try OfflineStore<OldNote>(name: "notes", storage: storage)
        try await old.save(OldNote(id: "a", body: "Renamed field"))

        let store = try makeStore(storage) { configuration in
            configuration.schemaVersion = 2
            configuration.migrations = [RecordMigration(to: 2) { record in
                record["text"] = record["body"]
                record["body"] = nil
            }]
        }
        #expect(await store.records() == [Note(id: "a", text: "Renamed field")])
        #expect(await store.pendingChanges().count == 1)
    }

    @Test func damagedCountersAreRepairedInsteadOfOverflowing() async throws {
        let storage = InMemoryStorage()
        let file = #"""
        {"format":1,"schemaVersion":1,"nodeID":"","nextSequence":18446744073709551615,
         "entries":[
           {"id":"a","record":{"id":"a","text":"A"},"timestamp":{"wallTime":1,"counter":0,"nodeID":"x"},
            "position":18446744073709551615,
            "pending":{"changeID":"\#(UUID().uuidString)","sequence":18446744073709551615,"attempts":-7,"isParked":false}},
           {"id":"a","record":{"id":"a","text":"A, later copy"},"timestamp":{"wallTime":2,"counter":0,"nodeID":"x"},
            "position":3},
           {"id":"gone","timestamp":{"wallTime":1,"counter":0,"nodeID":"x"},"position":4}
         ]}
        """#
        try storage.write(Data(file.utf8), to: "notes.store")
        let store = try makeStore(storage)
        #expect(!store.nodeID.isEmpty)
        #expect(await store.records() == [Note(id: "a", text: "A, later copy")])
        try await store.save(Note(id: "b", text: "B"))
        #expect(await store.pendingChanges().allSatisfy { $0.attempts >= 0 })
        #expect(await store.records().map(\.id) == ["a", "b"])
    }

    @Test func statesStreamTheCurrentStateAndEveryChange() async throws {
        let store = try makeStore()
        var states = await store.states().makeAsyncIterator()
        let initial = await states.next()
        #expect(initial?.records.isEmpty == true)
        try await store.save(Note(id: "a", text: "A"))
        let afterSave = await states.next()
        #expect(afterSave?.records == [Note(id: "a", text: "A")])
        #expect(afterSave?.pendingCount == 1)
        #expect(afterSave?.status == .idle)
    }

    @Test func localOnlyStoresSkipSync() async throws {
        let store = try makeStore()
        try await store.save(Note(id: "a", text: "A"))
        let report = try await store.sync()
        #expect(report.skipped)
        #expect(await store.pendingChanges().count == 1)
    }
}
