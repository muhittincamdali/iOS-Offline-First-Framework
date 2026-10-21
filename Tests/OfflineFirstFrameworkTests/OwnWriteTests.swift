import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A server of one record without epochs or sequences, as the protocol allows: it answers a push
/// on another base than its current revision with a conflict, and a pull with its current
/// version, or with the version the test serves instead (a stale page it cannot be ordered by).
private actor OneRecordServer {
    let sendsChangeIDs: Bool
    private(set) var current: RemoteChange<Note>?
    private var writes = 0
    private var stale: RemoteChange<Note>?

    init(sendsChangeIDs: Bool) {
        self.sendsChangeIDs = sendsChangeIDs
    }

    func serve(_ change: RemoteChange<Note>?) { stale = change }

    func push(_ changes: [OutgoingChange<Note>]) -> [UUID: PushOutcome<Note>] {
        var outcomes: [UUID: PushOutcome<Note>] = [:]
        for change in changes {
            if let current, current.revision != change.baseRevision {
                outcomes[change.id] = .conflict(current: current)
                continue
            }
            writes += 1
            let revision = "s.\(writes)"
            current = RemoteChange(recordID: change.recordID, record: change.record, revision: revision, timestamp: change.timestamp,
                                   sequence: nil, changeID: sendsChangeIDs ? change.id : nil)
            outcomes[change.id] = .accepted(revision: revision)
        }
        return outcomes
    }

    func pull() -> PullResponse<Note> {
        let change = stale ?? current
        return PullResponse(changes: change.map { [$0] } ?? [], token: "t", hasMore: false)
    }
}

/// A write of this device that the server accepted is the device's own, also after a page the
/// store cannot order took the record back to another version (a server without sequences
/// sends a version without a timestamp) and the user edited on top of that: the server's
/// answer, or a later page, that names the accepted write is not a conflict. Before, the
/// resolver weighed the user's last edit against the device's own earlier write, and
/// `.serverWins` dropped the edit on the device and the server.
@Suite("Offline store: the device's own accepted writes")
struct OwnWriteTests {
    let clock = TestClock()

    private func makeStore(server: OneRecordServer, conflicts: OSAllocatedUnfairLock<[String]>,
                           policy: ConvergenceTests.Policy) throws -> (OfflineStore<Note>, ScriptedTransport) {
        let resolver = ConflictResolver<Note> { conflict in
            conflicts.withLock { $0.append("local=\(conflict.local?.text ?? "nil") remote=\(conflict.remote?.text ?? "nil")") }
            return policy.resolver.resolve(conflict)
        }
        let transport = ScriptedTransport(push: { await server.push($0) }, pull: { _ in await server.pull() })
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock, resolver: resolver))
        return (store, transport)
    }

    /// Two accepted writes, then a page with a version the store cannot order.
    private func writeTwiceThenServeAStaleVersion(_ store: OfflineStore<Note>, server: OneRecordServer) async throws {
        try await store.save(Note(id: "r", text: "A#1"))
        try await store.sync()
        clock.advance(by: 1)
        try await store.save(Note(id: "r", text: "A#2"))
        try await store.sync()
        #expect(await server.current?.record?.text == "A#2")
        await server.serve(RemoteChange(recordID: "r", record: Note(id: "r", text: "X#0"), revision: "x.0", timestamp: nil, sequence: nil))
        try await store.sync()
        #expect(await store.record("r")?.text == "X#0")
        await server.serve(nil)
        clock.advance(by: 1)
    }

    @Test(arguments: ConvergenceTests.Policy.allCases, [true, false])
    func aConflictAnswerWithTheDevicesAcceptedWriteIsNotAConflict(policy: ConvergenceTests.Policy, changeIDs: Bool) async throws {
        let server = OneRecordServer(sendsChangeIDs: changeIDs)
        let conflicts = OSAllocatedUnfairLock<[String]>(initialState: [])
        let (store, _) = try makeStore(server: server, conflicts: conflicts, policy: policy)
        try await writeTwiceThenServeAStaleVersion(store, server: server)

        // The edit goes out on the stale version; the server answers with the device's A#2.
        try await store.save(Note(id: "r", text: "A#3"))
        try await store.sync()
        #expect(conflicts.withLock { $0 }.isEmpty, "\(policy) cid=\(changeIDs): \(conflicts.withLock { $0 })")
        #expect(await server.current?.record?.text == "A#3", "\(policy) cid=\(changeIDs): the user's last edit was lost")
        #expect(await store.record("r")?.text == "A#3")
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test(arguments: ConvergenceTests.Policy.allCases, [true, false])
    func aPageWithTheDevicesAcceptedWriteIsNotAConflict(policy: ConvergenceTests.Policy, changeIDs: Bool) async throws {
        let server = OneRecordServer(sendsChangeIDs: changeIDs)
        let conflicts = OSAllocatedUnfairLock<[String]>(initialState: [])
        let (store, transport) = try makeStore(server: server, conflicts: conflicts, policy: policy)
        try await writeTwiceThenServeAStaleVersion(store, server: server)

        // The edit on the stale version cannot be sent; the next pull brings the server's A#2.
        // Without sequences nothing shows A#2 is newer than the stale X#0 the edit is based on,
        // so the pull keeps it back, and the push's answer tells.
        try await store.save(Note(id: "r", text: "A#3"))
        await transport.onPush { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: URLError.self) { try await store.sync() }
        await transport.onPush { await server.push($0) }
        try await store.sync()
        #expect(conflicts.withLock { $0 }.isEmpty, "\(policy) cid=\(changeIDs): \(conflicts.withLock { $0 })")
        #expect(await store.record("r")?.text == "A#3")
        #expect(await store.state.entries["r"]?.revision == "x.0")
        #expect(await store.state.entries["r"]?.deferredRemote?.revision == "s.2")

        clock.advance(by: 3_600)
        try await store.sync()
        #expect(await server.current?.record?.text == "A#3", "\(policy) cid=\(changeIDs): the user's last edit was lost")
        #expect(await store.pendingChanges().isEmpty)
        #expect(conflicts.withLock { $0 }.isEmpty)
    }

    /// An entry remembers sixteen own writes at most, and a file keeps them.
    @Test func ownWritesAreBoundedAndKeptInTheFile() async throws {
        let storage = InMemoryStorage()
        let server = OneRecordServer(sendsChangeIDs: true)
        let transport = ScriptedTransport(push: { await server.push($0) }, pull: { _ in await server.pull() })
        var store = try OfflineStore<Note>(name: "notes", storage: storage, transport: transport,
                                           configuration: makeConfiguration(clock: clock))
        for index in 0..<20 {
            clock.advance(by: 1)
            try await store.save(Note(id: "r", text: "A#\(index)"))
            try await store.sync()
        }
        let entry = try #require(await store.state.entries["r"])
        #expect(entry.ownChangeIDs.count == StoredEntry<Note>.maximumOwnWrites)
        #expect(entry.ownTimestamps.count == StoredEntry<Note>.maximumOwnWrites)
        #expect(await entry.ownChangeIDs.last == server.current?.changeID)

        store = try OfflineStore<Note>(name: "notes", storage: storage, transport: transport,
                                       configuration: makeConfiguration(clock: clock))
        #expect(await store.state.entries["r"]?.ownChangeIDs == entry.ownChangeIDs)
        #expect(await store.state.entries["r"]?.ownTimestamps == entry.ownTimestamps)
    }
}
