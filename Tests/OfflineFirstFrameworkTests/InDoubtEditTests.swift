import Foundation
import Testing
@testable import OfflineFirstFramework

/// One device, nobody else writing: a push is applied but its answer is lost, and the user
/// changes the record again. The server's version is then the device's own earlier write,
/// which is not a conflict: the newer local change goes out on top of it, whatever the policy.
@Suite("Offline store: changes on top of a change in doubt")
struct InDoubtEditTests {
    let clock = TestClock()

    /// A transport to `server` that loses the answer to the first push.
    private func losingFirstAnswer(of server: InMemorySyncServer<Note>) async -> ScriptedTransport {
        let transport = ScriptedTransport()
        let answerLost = OneShot()
        await transport.onPush { changes in
            let outcomes = try await server.push(changes)
            if await answerLost.fire() { throw URLError(.networkConnectionLost) }
            return outcomes
        }
        await transport.onPull { try await server.pull(since: $0) }
        return transport
    }

    @Test(arguments: ConvergenceTests.Policy.allCases, [false, true])
    func aChangeAfterALostAnswerIsNotDroppedForTheOwnEarlierWrite(policy: ConvergenceTests.Policy, deletes: Bool) async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = await losingFirstAnswer(of: server)
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock, resolver: policy.resolver))
        try await store.save(Note(id: "b", text: "x,y"))
        await #expect(throws: URLError.self) { try await store.sync() }
        #expect(await server.record("b")?.text == "x,y")

        clock.advance(by: 10)
        if deletes { try await store.delete("b") } else { try await store.save(Note(id: "b", text: "x")) }
        let report = try await store.sync()
        try await store.sync()
        let expected: String? = deletes ? nil : "x"
        #expect(report.conflicts == 0, "\(policy)")
        #expect(await server.record("b")?.text == expected, "\(policy)")
        #expect(await store.record("b")?.text == expected, "\(policy)")
        #expect(await store.pendingChanges().isEmpty, "\(policy)")
    }

    /// A server that keeps timestamps to the second only, and sends back the change ID that
    /// wrote each version. The store recognises its own earlier write by the change ID, so the
    /// newer change goes out on top of it, whatever the policy.
    @Test(arguments: ConvergenceTests.Policy.allCases)
    func theChangeIDShowsTheOwnWriteWhenTheServerChangedItsTimestamp(policy: ConvergenceTests.Policy) async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = ScriptedTransport()
        let answerLost = OneShot()
        await transport.onPush { changes in
            let outcomes = try await server.push(changes)
            if await answerLost.fire() { throw URLError(.networkConnectionLost) }
            return outcomes.mapValues(Self.toSeconds)
        }
        await transport.onPull { token in
            let page = try await server.pull(since: token)
            return PullResponse(changes: page.changes.map(Self.toSeconds), token: page.token, hasMore: page.hasMore, epoch: page.epoch)
        }
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock, resolver: policy.resolver))
        clock.advance(by: 0.25)
        try await store.save(Note(id: "b", text: "first"))
        await #expect(throws: URLError.self) { try await store.sync() }
        clock.advance(by: 10)
        try await store.save(Note(id: "b", text: "second"))
        let report = try await store.sync()
        try await store.sync()
        #expect(report.conflicts == 0, "\(policy)")
        #expect(await server.record("b")?.text == "second", "\(policy)")
        #expect(await store.record("b")?.text == "second", "\(policy)")
        #expect(await store.pendingChanges().isEmpty, "\(policy)")
    }

    private static func toSeconds(_ change: RemoteChange<Note>) -> RemoteChange<Note> {
        let timestamp = change.timestamp.map { HLCTimestamp(wallTime: $0.wallTime / 1_000 * 1_000, counter: $0.counter, nodeID: $0.nodeID) }
        return RemoteChange(recordID: change.recordID, record: change.record, revision: change.revision, timestamp: timestamp,
                            sequence: change.sequence, changeID: change.changeID)
    }

    private static func toSeconds(_ outcome: PushOutcome<Note>) -> PushOutcome<Note> {
        switch outcome {
        case .accepted: outcome
        case .conflict(let current): .conflict(current: toSeconds(current))
        case .rejected(let reason, let current): .rejected(reason: reason, current: current.map(toSeconds))
        }
    }

    /// A union merge would bring back the item the user removed.
    @Test func aUnionMergeDoesNotBringBackARemovedItem() async throws {
        let union = ConflictResolver<Note>.merge { local, remote in
            let items = Set(local.text.split(separator: ",")).union(remote.text.split(separator: ","))
            return Note(id: local.id, text: items.sorted().joined(separator: ","))
        }
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = await losingFirstAnswer(of: server)
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock, resolver: union))
        try await store.save(Note(id: "b", text: "x,y"))
        _ = try? await store.sync()
        clock.advance(by: 10)
        try await store.save(Note(id: "b", text: "x"))
        try await store.sync()
        try await store.sync()
        #expect(await server.record("b")?.text == "x")
    }

    /// The same when a pull, not a push, brings the own earlier write: the new change's push
    /// never left the device, so it waits for its retry while the pull runs.
    @Test(arguments: ConvergenceTests.Policy.allCases)
    func aPullWithTheOwnEarlierWriteKeepsTheNewerChange(policy: ConvergenceTests.Policy) async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = await losingFirstAnswer(of: server)
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock, resolver: policy.resolver))
        try await store.save(Note(id: "b", text: "x,y"))
        _ = try? await store.sync()
        clock.advance(by: 10)
        try await store.save(Note(id: "b", text: "x"))
        let offline = OneShot()
        await transport.onPush { changes in
            if await offline.fire() { throw URLError(.notConnectedToInternet) }
            return try await server.push(changes)
        }
        await #expect(throws: URLError.self) { try await store.sync() }
        let report = try await store.sync()
        #expect(report.conflicts == 0, "\(policy)")
        #expect(await store.record("b")?.text == "x", "\(policy)")

        clock.advance(by: 60)
        try await store.sync()
        #expect(await server.record("b")?.text == "x", "\(policy)")
        #expect(await store.pendingChanges().isEmpty, "\(policy)")
    }

    /// A conflict with another device's write after a lost answer still goes to the resolver.
    @Test func anotherDevicesWriteAfterALostAnswerIsStillAConflict() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = await losingFirstAnswer(of: server)
        let store = try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                           configuration: makeConfiguration(clock: clock, resolver: .serverWins))
        try await store.save(Note(id: "b", text: "x,y"))
        _ = try? await store.sync()
        clock.advance(by: 5)
        await server.write(Note(id: "b", text: "other device"))
        clock.advance(by: 5)
        try await store.save(Note(id: "b", text: "x"))
        let report = try await store.sync()
        #expect(report.conflicts == 1)
        #expect(await server.record("b")?.text == "other device")
        #expect(await store.record("b")?.text == "other device")
    }
}
