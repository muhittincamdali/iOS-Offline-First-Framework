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

    /// discardChange(for:) resets the token so the next pull brings the server's copy back. A
    /// pull on its way at that moment must not store its own token over the reset.
    @Test func discardingAChangeWhileAPullRunsBringsBackTheServerCopy() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = ScriptedTransport()
        await transport.onPush { try await server.push($0) }
        await transport.onPull { try await server.pull(since: $0) }
        let store = try makeStore(transport)
        try await store.save(Note(id: "a", text: "v1"))
        try await store.sync()
        let once = OneShot()
        await transport.onPull { token in
            if await once.fire() {
                try await store.save(Note(id: "a", text: "local edit"))
                try await store.discardChange(for: "a")
            }
            return try await server.pull(since: token)
        }
        try await store.sync()
        #expect(await server.record("a") == Note(id: "a", text: "v1"))
        #expect(await store.record("a") == Note(id: "a", text: "v1"))
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test func aTokenResetDuringAPullIsKept() async throws {
        let gate = PullGate()
        let serverCopy = RemoteChange<Note>(recordID: "a", record: Note(id: "a", text: "server"), revision: "1", timestamp: nil)
        let transport = ScriptedTransport(pull: { token in
            switch token {
            case nil: return PullResponse(changes: [serverCopy], token: "t1", hasMore: false)
            case "t1":
                await gate.enter()
                return PullResponse(changes: [], token: "t2", hasMore: false)
            default: return PullResponse(changes: [], token: token, hasMore: false)
            }
        })
        let store = try makeStore(transport)
        try await store.sync()

        let running = Task { try await store.sync() }
        await gate.waitUntilEntered()
        try await store.save(Note(id: "a", text: "local edit"))
        try await store.discardChange(for: "a")
        #expect(await store.state.token == nil)
        await gate.release()
        _ = try await running.value
        // The page for "t1" was dropped; the pull started over and brought the server copy.
        #expect(await store.state.token == "t1")
        #expect(await store.record("a")?.text == "server")
    }

    /// A save made while a sync pulls, followed by `sync()`: the call must not return the
    /// running sync's report before the save was pushed.
    @Test func aSyncCalledDuringAPullPushesTheNewSave() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let gate = PullGate()
        let transport = ScriptedTransport()
        await transport.onPush { try await server.push($0) }
        await transport.onPull { token in
            await gate.enter()
            return try await server.pull(since: token)
        }
        let store = try makeStore(transport)
        let running = Task { try await store.sync() }
        await gate.waitUntilEntered()
        try await store.save(Note(id: "late", text: "saved during the pull"))
        let mine = Task { try await store.sync() }
        try await Task.sleep(for: .milliseconds(50))
        await gate.release()
        _ = try await running.value
        let report = try await mine.value
        #expect(report.pushed == 1)
        #expect(await store.pendingChanges().isEmpty)
        #expect(await server.record("late") != nil)
    }

    /// Without new changes a call made during the pull still joins the running sync.
    @Test func aSyncCalledDuringAPullWithoutNewChangesJoinsIt() async throws {
        let gate = PullGate()
        let transport = ScriptedTransport(pull: { token in
            await gate.enter()
            return PullResponse(changes: [], token: token, hasMore: false)
        })
        let store = try makeStore(transport)
        let running = Task { try await store.sync() }
        await gate.waitUntilEntered()
        let mine = Task { try await store.sync() }
        try await Task.sleep(for: .milliseconds(50))
        await gate.release()
        _ = try await running.value
        _ = try await mine.value
        #expect(await transport.pulls == 1)
    }

    @Test func resettingTheChangeTokenPullsEverythingAgain() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        for id in ["a", "b"] { await server.write(Note(id: id, text: id)) }
        let tokens = TokenRecorder()
        let transport = ScriptedTransport()
        await transport.onPush { try await server.push($0) }
        await transport.onPull { token in
            await tokens.add(token)
            return try await server.pull(since: token)
        }
        let store = try makeStore(transport)
        try await store.sync()
        try await store.save(Note(id: "local", text: "pending"))
        try await store.resetChangeToken()
        #expect(await store.state.token == nil)
        #expect(await store.pendingChanges().count == 1)

        let report = try await store.sync()
        // Everything came again; the store already had it.
        #expect(report.pulled == 0)
        #expect(await tokens.all == [nil, nil])
        #expect(await store.records().map(\.id) == ["a", "b", "local"])
        #expect(await store.pendingChanges().isEmpty)
    }
}

/// Holds a pull until the test releases it.
private actor PullGate {
    private var entered = false
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        entered = true
        while !released {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    func waitUntilEntered() async {
        while !entered {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func release() {
        released = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

private actor TokenRecorder {
    private(set) var all: [String?] = []

    func add(_ token: String?) {
        all.append(token)
    }
}
