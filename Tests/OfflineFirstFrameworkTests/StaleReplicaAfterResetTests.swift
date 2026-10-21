import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// The store follows the server's later epoch E2. A lagging replica, or a shared cache (whose
/// pull from the beginning and the pull after its token are the same URLs for every device),
/// still serves E1. After `resetChangeToken()` it answers both requests of the confirming step.
/// The store took E1 at once: every record went back to the replica's copy, and a pending edit
/// the server never saw met the device's own older write in the resolver. `.serverWins`
/// dropped the edit on the device and on the server; the other policies asked the resolver
/// about the device's own write.
@Suite("Offline store: a stale replica after resetChangeToken()")
struct StaleReplicaAfterResetTests {
    let clock = TestClock()

    /// `resolver`, recording each time it is asked about the device's own write.
    private func recording(_ resolver: ConflictResolver<Note>, into asked: OSAllocatedUnfairLock<[String]>) -> ConflictResolver<Note> {
        ConflictResolver { conflict in
            if let remote = conflict.remoteTimestamp, remote.nodeID == conflict.localTimestamp.nodeID {
                asked.withLock { $0.append("\(conflict.recordID): \(conflict.local?.text ?? "nil") vs \(conflict.remote?.text ?? "nil")") }
            }
            return resolver.resolve(conflict)
        }
    }

    @Test(arguments: ConvergenceTests.Policy.allCases)
    func aReplicaThatAnswersBothRequestsCannotTakeTheStoreBack(policy: ConvergenceTests.Policy) async throws {
        let asked = OSAllocatedUnfairLock<[String]>(initialState: [])
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = ScriptedTransport()
        await transport.onPush { try await server.push($0) }
        await transport.onPull { try await server.pull(since: $0) }
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock, resolver: recording(policy.resolver, into: asked)))

        try await store.save(contentsOf: [Note(id: "c", text: "v1"), Note(id: "d", text: "d1")])
        try await store.sync()
        // The replica's copy, from before the restart.
        let staleFirst = try await server.pull(since: nil)
        let staleSecond = try await server.pull(since: staleFirst.token)

        await server.restart()
        clock.advance(by: 5)
        try await store.save(contentsOf: [Note(id: "d", text: "d2"), Note(id: "c", text: "v1b")])
        try await store.sync()
        let epoch = try #require(await store.state.serverEpoch)
        #expect(epoch != staleFirst.epoch)

        // An edit the server has not seen: its push failed before it left the device.
        clock.advance(by: 5)
        try await store.save(Note(id: "c", text: "v2, never pushed"))
        await transport.onPush { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: URLError.self) { try await store.sync() }

        try await store.resetChangeToken()
        await transport.onPull { token in token == nil ? staleFirst : staleSecond }
        await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        #expect(await store.state.serverEpoch == epoch, "\(policy)")
        #expect(await store.record("d")?.text == "d2", "\(policy)")
        #expect(await store.pendingChanges().first { $0.recordID == "c" }?.record?.text == "v2, never pushed", "\(policy)")

        // The server answers again.
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
}
