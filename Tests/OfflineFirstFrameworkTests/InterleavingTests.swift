import Foundation
import Testing
@testable import OfflineFirstFramework

/// Failures and local edits in the middle of a pull.
@Suite("Offline store: interleavings")
struct InterleavingTests {
    let clock = TestClock()

    private func makeStore(_ transport: any SyncTransport<Note>, storage: any StorageBackend = InMemoryStorage()) throws -> OfflineStore<Note> {
        try OfflineStore<Note>(name: "notes", storage: storage, transport: transport, configuration: makeConfiguration(clock: clock))
    }

    @Test func aWriteThatFailsWhileApplyingAPageKeepsTheOldTokenAndRecords() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        await server.write(Note(id: "a", text: "A"))
        let storage = FailingStorage()
        let transport = ScriptedTransport()
        await transport.onPull { token in
            // The disk fails between receiving the page and storing it, as a crash would.
            storage.setFailing(true)
            return try await server.pull(since: token)
        }
        let store = try makeStore(transport, storage: storage)
        await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        #expect(await store.records().isEmpty)
        #expect(await store.state.token == nil)
        let reopened = try makeStore(server, storage: storage.inner)
        #expect(await reopened.records().isEmpty)

        storage.setFailing(false)
        await transport.onPull { try await server.pull(since: $0) }
        #expect(try await store.sync().pulled == 1)
        #expect(await store.records() == [Note(id: "a", text: "A")])
        #expect(await store.state.token != nil)
    }

    @Test func aLocalEditMadeWhileAPullIsOnItsWayIsNotOverwritten() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = ScriptedTransport()
        await transport.onPush { try await server.push($0) }
        await transport.onPull { try await server.pull(since: $0) }
        let store = try makeStore(transport)
        try await store.save(Note(id: "a", text: "first"))
        try await store.sync()

        await server.write(Note(id: "a", text: "server edit"))
        clock.advance(by: 10)
        let editDuringPull = OneShot()
        await transport.onPull { token in
            if await editDuringPull.fire() {
                try await store.save(Note(id: "a", text: "local edit"))
            }
            return try await server.pull(since: token)
        }
        let report = try await store.sync()
        #expect(report.conflicts == 1)
        #expect(await store.record("a")?.text == "local edit")
        #expect(await store.pendingChanges().count == 1)
        try await store.sync()
        #expect(await server.record("a")?.text == "local edit")
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test func aNewerServerEditWinsOverAnOlderEditMadeDuringThePull() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = ScriptedTransport()
        await transport.onPush { try await server.push($0) }
        await transport.onPull { try await server.pull(since: $0) }
        let store = try makeStore(transport)
        try await store.save(Note(id: "a", text: "first"))
        try await store.sync()

        let editDuringPull = OneShot()
        await transport.onPull { [clock] token in
            if await editDuringPull.fire() {
                try await store.save(Note(id: "a", text: "local edit"))
                clock.advance(by: 10)
                await server.write(Note(id: "a", text: "newer server edit"))
            }
            return try await server.pull(since: token)
        }
        try await store.sync()
        #expect(await store.record("a")?.text == "newer server edit")
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test func aPageDeliveredTwiceChangesNothing() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        await server.write(Note(id: "a", text: "A"))
        let page = try await server.pull(since: nil)
        let transport = ScriptedTransport(pull: { _ in page })
        let store = try makeStore(transport)
        #expect(try await store.sync().pulled == 1)
        #expect(try await store.sync().pulled == 0)
        #expect(await store.records() == [Note(id: "a", text: "A")])
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test(arguments: [true, false])
    func aDeleteThatMeetsAServerEditFollowsLastWriteWins(deleteIsNewer: Bool) async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try makeStore(server)
        try await store.save(Note(id: "a", text: "v1"))
        try await store.sync()
        if deleteIsNewer {
            await server.write(Note(id: "a", text: "server edit"))
            clock.advance(by: 10)
            try await store.delete("a")
        } else {
            try await store.delete("a")
            clock.advance(by: 10)
            await server.write(Note(id: "a", text: "server edit"))
        }
        let report = try await store.sync()
        #expect(report.conflicts == 1)
        #expect(await store.pendingChanges().isEmpty)
        let expected: Note? = deleteIsNewer ? nil : Note(id: "a", text: "server edit")
        #expect(await store.record("a") == expected)
        #expect(await server.record("a") == expected)
    }
}
