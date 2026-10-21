import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A pending change made on an earlier server history meets the server's versions of the new
/// history through its push's conflict answer, never through a page. A replica that sticks to a
/// device with an epoch between two the store saw used to be taken after eight syncs in a row:
/// its pages rolled records back until the server answered again, and they decided pending
/// edits, so the resolver met the device's own older write and `.serverWins` dropped an edit
/// the server had never seen. An earlier epoch is now refused in every sync.
@Suite("Offline store: pending changes and a new server history")
struct EarlierHistoryTests {
    let clock = TestClock()

    @Test(arguments: ConvergenceTests.Policy.allCases)
    func aStickyReplicaOfAnEpochTheStoreNeverHeldCannotDecideAPendingEdit(policy: ConvergenceTests.Policy) async throws {
        let asked = OSAllocatedUnfairLock<[String]>(initialState: [])
        let resolver = ConflictResolver<Note> { conflict in
            if let remote = conflict.remoteTimestamp, remote.nodeID == conflict.localTimestamp.nodeID {
                asked.withLock { $0.append("\(conflict.recordID): \(conflict.local?.text ?? "nil") vs \(conflict.remote?.text ?? "nil")") }
            }
            return policy.resolver.resolve(conflict)
        }
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = ScriptedTransport()
        await transport.onPush { try await server.push($0) }
        await transport.onPull { try await server.pull(since: $0) }
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock, resolver: resolver))
        try await store.save(contentsOf: [Note(id: "c", text: "v1"), Note(id: "d", text: "d1")])
        try await store.sync()

        // The server restarts twice while the device is away; a replica keeps the pages of the
        // epoch in between, which the store never holds.
        await server.restart()
        let staleFirst = try await server.pull(since: nil)
        let staleSecond = try await server.pull(since: staleFirst.token)
        await server.restart()
        clock.advance(by: 5)
        try await store.save(contentsOf: [Note(id: "d", text: "d2"), Note(id: "c", text: "v1b")])
        try await store.sync()

        clock.advance(by: 5)
        try await store.save(Note(id: "c", text: "v2, never pushed"))
        await transport.onPush { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: URLError.self) { try await store.sync() }

        // The replica answers every request of sixteen syncs in a row; each one refuses it.
        let epoch = await store.state.serverEpoch
        await transport.onPull { token in token == nil ? staleFirst : staleSecond }
        for _ in 0..<16 {
            await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        }
        #expect(await store.state.serverEpoch == epoch)
        #expect(await store.record("d")?.text == "d2", "\(policy)")
        #expect(await store.pendingChanges().first { $0.recordID == "c" }?.record?.text == "v2, never pushed", "\(policy)")

        // The server answers again, with its later epoch.
        await transport.onPush { try await server.push($0) }
        await transport.onPull { try await server.pull(since: $0) }
        clock.advance(by: 3_600)
        try await store.retryFailedChanges()
        try await store.sync()
        try await store.sync()
        #expect(asked.withLock { $0 }.isEmpty, "\(policy): \(asked.withLock { $0 })")
        #expect(await server.record("c")?.text == "v2, never pushed", "\(policy)")
        #expect(await store.record("c")?.text == "v2, never pushed", "\(policy)")
        #expect(await store.record("d")?.text == "d2", "\(policy)")
        #expect(await store.pendingChanges().isEmpty, "\(policy)")
    }

    /// The version a page of the new history brought for a pending change is kept back, and
    /// the push decides: accepted, the device's edit stays, also when the pull after it fails.
    @Test func anAcceptedPushKeepsTheEditOverAVersionAPageBroughtBefore() async throws {
        @Sendable func page(_ epoch: String, _ text: String, sequence: UInt64) -> PullResponse<Note> {
            PullResponse(changes: [RemoteChange(recordID: "c", record: Note(id: "c", text: text), revision: "\(epoch).\(sequence)",
                                                timestamp: nil, sequence: sequence)],
                         token: "\(epoch).\(sequence)", hasMore: false, epoch: epoch)
        }
        let transport = ScriptedTransport(pull: { _ in page("e1", "first", sequence: 1) })
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock))
        try await store.sync()
        try await store.save(Note(id: "c", text: "edit"))
        await transport.onPush { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: URLError.self) { try await store.sync() }

        // A later epoch whose page holds another version: kept back, not resolved.
        await transport.onPull { _ in page("e2", "on a page", sequence: 5) }
        try await store.sync()
        #expect(await store.state.serverEpoch == "e2")
        #expect(await store.record("c")?.text == "edit")
        #expect(await store.state.entries["c"]?.deferredRemote?.record?.text == "on a page")

        await transport.onPush { changes in Dictionary(uniqueKeysWithValues: changes.map { ($0.id, .accepted(revision: "e2.6")) }) }
        await transport.onPull { _ in throw URLError(.timedOut) }
        clock.advance(by: 3_600)
        await #expect(throws: URLError.self) { try await store.sync() }
        #expect(await store.pendingChanges().isEmpty)
        #expect(await store.record("c")?.text == "edit")
        #expect(await store.state.entries["c"]?.revision == "e2.6")
    }
}
