import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A store file from before the check holds an epoch only one request reported: a development
/// build took a new store's first epoch from its first page. That page may have come from
/// another deployment behind the same URL. When two requests of a sync report an earlier epoch
/// or none instead, the store starts a new history (it was locked out by an earlier epoch, and
/// followed a history without an epoch with the server's epoch as a first one, after the other
/// deployment's token); the records without a pending change of the unchecked history go.
@Suite("Offline store: an epoch one request reported, from a file before the check")
struct UncheckedEpochTests {
    private static let forgedPage = PullResponse(
        changes: [RemoteChange(recordID: "n", record: Note(id: "n", text: "old copy"), revision: "legacy.99999",
                               timestamp: nil, sequence: 99_999)],
        token: "legacy.99999", hasMore: false, epoch: nil)

    /// The store file as a development build left it after a new store's first sync.
    private func forgetConfirmation(of store: OfflineStore<Note>) async throws {
        try await store.update { $0.epochIsConfirmed = false }
    }

    /// Verifier A12's regression with a file from before the check: both requests of a sync come
    /// from a deployment without epochs, with a forged sequence. That history replaces the
    /// unchecked epoch; when the server's epoch comes back, it starts a new history instead of
    /// going on after the forged token, and the edit reaches the server. The store is opened
    /// again in between, so what it knows survives in its file.
    @Test func theServersEpochAfterAHistoryWithoutOneStartsANewHistory() async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        let forged = OSAllocatedUnfairLock(initialState: false)
        let transport = ScriptedTransport(push: { try await server.push($0) }, pull: { token in
            forged.withLock { $0 } ? Self.forgedPage : try await server.pull(since: token)
        })
        let storage = InMemoryStorage()
        let a = try OfflineStore<Note>(name: "a", storage: storage, transport: transport, configuration: makeConfiguration(clock: clock))
        await server.write(Note(id: "n", text: "real 1"))
        try await a.sync()
        let epoch = try #require(await a.state.serverEpoch)
        try await forgetConfirmation(of: a)

        forged.withLock { $0 = true }
        try await a.sync()
        forged.withLock { $0 = false }
        #expect(await a.state.serverEpoch == nil)
        #expect(await a.state.retiredEpochs.isEmpty)

        let reopened = try OfflineStore<Note>(name: "a", storage: storage, transport: transport, configuration: makeConfiguration(clock: clock))
        #expect(await reopened.state.hasHeldEpoch)
        let history = await reopened.state.history
        try await reopened.sync()
        #expect(await reopened.state.serverEpoch == epoch)
        #expect(await reopened.state.history == history + 1)
        #expect(await reopened.state.token?.hasPrefix(epoch) == true)
        #expect(await reopened.record("n")?.text == "real 1")
        #expect(await reopened.state.entries["n"]?.sequence != 99_999)

        try await reopened.save(Note(id: "n", text: "A's edit"))
        for _ in 0..<3 {
            clock.advance(by: 120)
            try await reopened.sync()
        }
        #expect(await server.record("n")?.text == "A's edit")
        #expect(await reopened.failedChanges().isEmpty)
    }

    /// The same with a server whose tokens are positions: after the other deployment's token
    /// "99999" the server answered every pull with nothing, without an error.
    @Test func theServersEpochDoesNotGoOnAfterTheOtherDeploymentsToken() async throws {
        let clock = TestClock()
        let server = EpochFeedServer(epoch: "e1", sendsSequences: false)
        let forged = OSAllocatedUnfairLock(initialState: false)
        let ta = ScriptedTransport(push: { await server.push($0) }, pull: { token in
            if forged.withLock({ $0 }) { return PullResponse(changes: [], token: "99999", hasMore: false, epoch: nil) }
            return await server.pull(token)
        })
        let tb = ScriptedTransport(push: { await server.push($0) }, pull: { await server.pull($0) })
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: ta, configuration: makeConfiguration(clock: clock))
        let b = try OfflineStore<Note>(name: "b", storage: InMemoryStorage(), transport: tb, configuration: makeConfiguration(clock: clock))
        try await b.save(Note(id: "n", text: "B1"))
        try await b.sync()
        try await a.sync()
        try await forgetConfirmation(of: a)
        forged.withLock { $0 = true }
        try await a.sync()
        forged.withLock { $0 = false }
        try await b.save(Note(id: "m", text: "B's new note"))
        try await b.save(Note(id: "n", text: "B2"))
        try await b.sync()
        try await a.sync()
        #expect(await a.state.serverEpoch == "e1")
        #expect(await a.state.token == "3")
        #expect(await a.record("m")?.text == "B's new note")
        #expect(await a.record("n")?.text == "B2")
    }

    /// The unchecked epoch came from a deployment whose epoch orders before the server's, with a
    /// record "f" the server never held: the server's later epoch starts a new history as always,
    /// and "f" goes with the unchecked history, also from the server, where an edit would have
    /// created it.
    @Test(arguments: [false, true])
    func aRecordOfAnUncheckedHistoryGoesWhenTheServerIsFollowed(sequences: Bool) async throws {
        let world = ScenarioWorld(policy: .lastWriteWins, options: ScenarioOptions(sequences: sequences, changeIDs: true), pageSize: 5)
        let b = try world.device("B", seed: 2)
        try await b.store.save(Note(id: "s", text: "B#s1"))
        #expect(await scenarioSync(b.store) == nil)
        let a = try world.device("A")
        await a.network.setDeployment(ScenarioDeployment(epoch: "00000000", record: "f", sequence: sequences ? 900_000 : nil), pulls: 2)
        #expect(await scenarioSync(a.store) == nil)
        #expect(await a.store.record("f") != nil)
        try await forgetConfirmation(of: a.store)
        #expect(await scenarioSync(a.store) == nil)
        #expect(await a.store.state.serverEpoch == "00000001")
        #expect(await a.store.state.retiredEpochs == ["00000000"])
        let shown = Dictionary(uniqueKeysWithValues: await a.store.records().map { ($0.id, $0.text) })
        #expect(shown == ["s": "B#s1"])
        #expect(await a.store.state.entries["f"] == nil)
    }

    /// The unchecked epoch is later than the server's (verifier A12's lockout, in a file from
    /// before the check): the server's earlier epoch, which two requests report, replaces it,
    /// the deployment's record goes, and the deployment's epoch is not retired.
    @Test(arguments: [false, true])
    func anEarlierEpochReplacesAnUncheckedOne(sequences: Bool) async throws {
        let world = ScenarioWorld(policy: .lastWriteWins, options: ScenarioOptions(sequences: sequences, changeIDs: true), pageSize: 5)
        let b = try world.device("B", seed: 2)
        try await b.store.save(Note(id: "s", text: "B#s1"))
        #expect(await scenarioSync(b.store) == nil)
        let a = try world.device("A")
        await a.network.setDeployment(ScenarioDeployment(epoch: "99999999", record: "f", sequence: sequences ? 900_000 : nil), pulls: 2)
        #expect(await scenarioSync(a.store) == nil)
        try await forgetConfirmation(of: a.store)
        #expect(await scenarioSync(a.store) == nil)
        #expect(await a.store.state.serverEpoch == "00000001")
        #expect(await a.store.state.epochIsConfirmed)
        #expect(await a.store.state.retiredEpochs.isEmpty)
        #expect(await a.store.state.entries["f"] == nil)
        try await a.store.save(Note(id: "s", text: "A#s"))
        for _ in 0..<3 {
            world.clock.advance(by: 120)
            #expect(await scenarioSync(a.store) == nil)
        }
        #expect(await world.server.text("s") == "A#s")
        #expect(await a.store.record("s")?.text == "A#s")
        #expect(await a.store.failedChanges().isEmpty)
    }

    /// A file from before the check whose epoch is the server's own: the next sync confirms it
    /// with its second request, and keeps the records and the token.
    @Test func theServersOwnEpochIsConfirmedAndNothingGoes() async throws {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(now: { clock.now })
        let transport = ScriptedTransport(push: { try await server.push($0) }, pull: { try await server.pull(since: $0) })
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: transport, configuration: makeConfiguration(clock: clock))
        await server.write(Note(id: "n", text: "one"))
        try await a.sync()
        let token = await a.state.token
        let history = await a.state.history
        try await forgetConfirmation(of: a)
        await server.write(Note(id: "m", text: "two"))
        let pulls = await transport.pulls
        try await a.sync()
        #expect(await transport.pulls - pulls == 2)
        #expect(await a.state.epochIsConfirmed)
        #expect(await a.state.history == history)
        #expect(await a.state.token != token)
        #expect(await a.records().map(\.id).sorted() == ["m", "n"])
    }
}
