import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// Answers the next `count` pulls with `page`, the rest as `server` does: another deployment
/// behind the same URL that answers a new store's first request.
private func misrouting(_ server: InMemorySyncServer<Note>, _ count: Int, _ page: PullResponse<Note>) -> ScriptedTransport {
    let left = OSAllocatedUnfairLock(initialState: count)
    return ScriptedTransport(push: { try await server.push($0) }, pull: { token in
        let isMisrouted = left.withLock { count -> Bool in
            guard count > 0 else { return false }
            count -= 1
            return true
        }
        return isMisrouted ? page : try await server.pull(since: token)
    })
}

/// A new store's first page. It was taken from that one request: from another deployment behind
/// the same URL it brought records the server never held, which stayed on the device and were
/// created on the server once edited; a token the pull then went on after; sequences that hid
/// the server's versions; and with a later epoch than the server's, every page of the server was
/// refused, also after `resetChangeToken()` and a server restart. The first page is now checked
/// by a second request, after its token, and when the two disagree a third one, from the
/// beginning, decides: the epoch, or the lack of one, that the second and third report is the
/// server's, and the first page is dropped.
@Suite("Offline store: a new store's first page")
struct NewStoreTests {
    /// Verifier C12: the other deployment's epoch orders before the server's, so the store could
    /// follow the server, but its record "f" stayed on the device in every configuration, and an
    /// edit of it created it on the server.
    @Test(arguments: [false, true], [false, true])
    func aRecordOnlyTheOtherDeploymentHeldNeverEntersTheStore(serverReportsEpochs: Bool, sequences: Bool) async throws {
        let options = ScenarioOptions(sequences: sequences, changeIDs: true)
        let world = ScenarioWorld(policy: .lastWriteWins, options: options, pageSize: 5, reportsEpochs: serverReportsEpochs)
        let b = try world.device("B", seed: 2)
        try await b.store.save(Note(id: "s", text: "B#s1"))
        #expect(await scenarioSync(b.store) == nil)
        let a = try world.device("A")
        await a.network.setDeployment(ScenarioDeployment(epoch: "00000000", record: "f", sequence: sequences ? 900_000 : nil), pulls: 1)
        var errors: [String] = []
        for _ in 0..<5 {
            if let error = await scenarioSync(a.store) { errors.append("\(error)") }
            world.clock.advance(by: 120)
        }
        #expect(errors.isEmpty)
        let shown = Dictionary(uniqueKeysWithValues: await a.store.records().map { ($0.id, $0.text) })
        #expect(shown == ["s": "B#s1"])
        #expect(await a.store.state.entries["f"] == nil)
        #expect(await world.server.text("f") == nil)
    }

    /// Verifier C12: the server reports epochs, and the new store's first request is answered by
    /// a deployment without them, with a copy of "s" and a sequence of its own. The store then
    /// took the server's epoch as a first one and went on after the other deployment's token:
    /// with sequences it showed the copy, B's edit never arrived and A's edit never reached the
    /// server, without an error.
    @Test(arguments: [false, true])
    func aFirstPageWithoutAnEpochIsChecked(sequences: Bool) async throws {
        let world = ScenarioWorld(policy: .lastWriteWins, options: ScenarioOptions(sequences: sequences, changeIDs: true), pageSize: 5)
        let b = try world.device("B", seed: 2)
        try await b.store.save(Note(id: "s", text: "B#s1"))
        #expect(await scenarioSync(b.store) == nil)
        let a = try world.device("A")
        await a.network.setDeployment(ScenarioDeployment(epoch: nil, record: "s", sequence: sequences ? 900_000 : nil), pulls: 1)
        var errors: [String] = []
        if let error = await scenarioSync(a.store) { errors.append("\(error)") }
        #expect(await a.store.state.serverEpoch == "00000001")
        #expect(await a.store.state.epochIsConfirmed)
        try await b.store.save(Note(id: "s", text: "B#s2"))
        #expect(await scenarioSync(b.store) == nil)
        for _ in 0..<2 {
            world.clock.advance(by: 120)
            if let error = await scenarioSync(a.store) { errors.append("\(error)") }
        }
        #expect(await a.store.record("s")?.text == "B#s2")
        try await a.store.save(Note(id: "s", text: "A#s"))
        for _ in 0..<3 {
            world.clock.advance(by: 120)
            if let error = await scenarioSync(a.store) { errors.append("\(error)") }
        }
        #expect(errors.isEmpty)
        #expect(await world.server.text("s") == "A#s")
        #expect(await a.store.failedChanges().isEmpty)
        #expect(world.ownWriteViolations().isEmpty)
    }

    /// Verifier C12: the first page names a later epoch than the server's, as a deployment
    /// started after it does. Every later sync failed with an earlier epoch, B's new record never
    /// arrived, and with sequences A's edit was parked.
    @Test(arguments: [false, true])
    func aFirstPageFromALaterDeploymentDoesNotLockANewStoreOut(sequences: Bool) async throws {
        let world = ScenarioWorld(policy: .lastWriteWins, options: ScenarioOptions(sequences: sequences, changeIDs: true), pageSize: 5)
        let b = try world.device("B", seed: 2)
        try await b.store.save(Note(id: "s", text: "B#s1"))
        #expect(await scenarioSync(b.store) == nil)
        let a = try world.device("A")
        await a.network.setDeployment(ScenarioDeployment(epoch: "99999999", record: "s", sequence: sequences ? 900_000 : nil), pulls: 1)
        #expect(await scenarioSync(a.store) == nil)
        #expect(await a.store.state.serverEpoch == "00000001")
        #expect(await a.store.record("s")?.text == "B#s1")
        try await b.store.save(Note(id: "m", text: "B#m"))
        #expect(await scenarioSync(b.store) == nil)
        var failures: [String] = []
        for _ in 0..<3 {
            world.clock.advance(by: 120)
            if let error = await scenarioSync(a.store) { failures.append("\(error)") }
        }
        try await a.store.save(Note(id: "s", text: "A#s"))
        for _ in 0..<3 {
            world.clock.advance(by: 120)
            if let error = await scenarioSync(a.store) { failures.append("\(error)") }
        }
        #expect(failures.isEmpty)
        #expect(await a.store.record("m")?.text == "B#m")
        #expect(await world.server.text("s") == "A#s")
        #expect(await a.store.failedChanges().isEmpty)
    }

    /// Verifier A12: the new store's first request gets an empty page with a later epoch, 16 or
    /// 17 characters, which no epoch of the server passes. Six syncs out of six failed, also after
    /// a server restart and `resetChangeToken()`; pushes went out, pulls never came.
    @Test(arguments: ["ffffffffffffffff", "ffffffffffffffff0"])
    func anEmptyFirstPageWithALaterEpochDoesNotLockANewStoreOut(forgedEpoch: String) async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        await server.write(Note(id: "n", text: "real"))
        let transport = misrouting(server, 1, PullResponse(changes: [], token: nil, hasMore: false, epoch: forgedEpoch))
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport, configuration: makeConfiguration(clock: clock))
        try await a.sync()
        #expect(await a.state.serverEpoch != forgedEpoch)
        #expect(await a.record("n")?.text == "real")
        var failures = 0
        for round in 0..<6 {
            clock.advance(by: 120)
            if round == 2 { await server.restart() }
            if round == 4 { try await a.resetChangeToken() }
            do { try await a.sync() } catch { failures += 1 }
        }
        #expect(failures == 0)
        try await a.save(Note(id: "m", text: "A pushes"))
        try await a.sync()
        #expect(await server.record("m")?.text == "A pushes")
    }

    /// Verifier A9: a single misrouted first pull, with a later epoch and a record of a staging
    /// server, locked the new store out of its server after the server's next restart.
    @Test func aSingleMisroutedFirstPullLocksANewStoreOut() async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        let staging = RemoteChange<Note>(recordID: "staging", record: Note(id: "staging", text: "staging data"),
                                         revision: "ffffffffffffffff0.1", timestamp: nil, sequence: 1)
        let transport = misrouting(server, 1, PullResponse(changes: [staging], token: "ffffffffffffffff0.1", hasMore: false,
                                                           epoch: "ffffffffffffffff0"))
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport, configuration: makeConfiguration(clock: clock))
        try await a.sync()
        #expect(await a.record("staging") == nil)
        await server.write(Note(id: "n", text: "real"))
        await server.restart()
        var failures = 0
        for _ in 0..<4 { do { try await a.sync() } catch { failures += 1 } }
        #expect(failures == 0)
        #expect(await a.record("n")?.text == "real")
    }

    /// Verifier A10: the same with an epoch of 1,000 bytes, which no later epoch passes in
    /// length: no way back to the server short of a new store.
    @Test func aForgedMaximalFirstEpoch() async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        let epoch = String(repeating: "~", count: 1_000)
        let staging = RemoteChange<Note>(recordID: "staging", record: Note(id: "staging", text: "staging data"),
                                         revision: "\(epoch).1", timestamp: nil, sequence: 1)
        let transport = misrouting(server, 1, PullResponse(changes: [staging], token: "\(epoch).1", hasMore: false, epoch: epoch))
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport, configuration: makeConfiguration(clock: clock))
        try await a.sync()
        await server.write(Note(id: "n", text: "real"))
        var failures = 0
        for round in 0..<6 {
            if round == 2 { await server.restart() }
            if round == 4 { try await a.resetChangeToken() }
            do { try await a.sync() } catch { failures += 1 }
        }
        #expect(failures == 0)
        try await a.save(Note(id: "m", text: "A pushes"))
        try await a.sync()
        #expect(await server.record("m")?.text == "A pushes")
        #expect(await a.record("n")?.text == "real")
        #expect(await a.record("staging") == nil)
    }

    /// A deployment that answers the second request too, with the same epoch and no other answer
    /// in the sync to tell it from the server, is followed, as the limits say: the store holds its
    /// later epoch and refuses the server's earlier one in every sync, with an error, until the
    /// server reports a later one. Pushes still go out. Nothing is lost on the way.
    @Test func aDeploymentThatAnswersBothRequestsOfTheFirstSyncIsFollowed() async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        await server.write(Note(id: "n", text: "real"))
        let staging = RemoteChange<Note>(recordID: "staging", record: Note(id: "staging", text: "staging data"),
                                         revision: "ffffffffffffffff0.1", timestamp: nil, sequence: 1)
        let transport = misrouting(server, 2, PullResponse(changes: [staging], token: "ffffffffffffffff0.1", hasMore: false,
                                                           epoch: "ffffffffffffffff0"))
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport, configuration: makeConfiguration(clock: clock))
        try await a.sync()
        #expect(await a.state.serverEpoch == "ffffffffffffffff0")
        try await a.save(Note(id: "m", text: "A pushes"))
        for _ in 0..<3 {
            clock.advance(by: 120)
            await #expect(throws: OfflineFirstError.self) { try await a.sync() }
        }
        #expect(await server.record("m")?.text == "A pushes")
        #expect(await a.record("n") == nil)
    }
}
