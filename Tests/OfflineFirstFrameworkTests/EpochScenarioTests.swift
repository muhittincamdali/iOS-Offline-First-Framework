import Foundation
import Testing
@testable import OfflineFirstFramework

@Suite("Scenarios: restarts, epochs, replicas")
struct EpochScenarioTests {
    /// After a restart and a reset, a replica of the old epoch answers both requests of many
    /// syncs while an edit made on the new epoch waits for its retry date.
    @Test(arguments: ScenarioPolicy.allCases, [false, true])
    func retiredEpochAfterResetNeverDecidesAnEdit(policy: ScenarioPolicy, reset: Bool) async throws {
        let world = ScenarioWorld(policy: policy)
        let a = try world.device("A")
        let b = try world.device("B", seed: 2)
        _ = try await a.store.scenarioSave(Note(id: "r", text: "A#1"))
        _ = try await a.store.scenarioSave(Note(id: "s", text: "A#s1"))
        try await a.store.sync()
        try await b.store.sync()
        let old = await world.server.snapshot()
        await world.server.restart()
        _ = try await b.store.scenarioSave(Note(id: "r", text: "B#1"))
        _ = try await b.store.scenarioSave(Note(id: "s", text: "B#s1"))
        try await b.store.sync()
        try await a.store.sync()
        let epochAfter = await a.store.scenarioEpoch()
        #expect(await a.store.record("r")?.text == "B#1")
        _ = try await a.store.scenarioSave(Note(id: "r", text: "A#2"))
        await a.network.failNextPushes(unsent: 1)
        #expect(await scenarioSync(a.store) != nil)
        if reset { try await a.store.resetChangeToken() }
        #expect(await a.store.scenarioRetired().contains(old.epoch))
        await a.network.setReplica(old, pulls: 1_000)
        for _ in 0..<12 {
            #expect(await scenarioSync(a.store) != nil, "a sync with only the retired epoch's pages must fail")
            #expect(await a.store.record("r")?.text == "A#2")
            #expect(await a.store.record("s")?.text == "B#s1", "record without a pending change rolled back")
            #expect(await a.store.scenarioEpoch() == epochAfter)
        }
        await a.network.setReplica(nil, pulls: 0)
        world.clock.advance(by: 120)
        try await a.store.sync()
        try await b.store.sync()
        #expect(await world.server.text("r") == "A#2", "the edit made on the server's current version must reach it")
        #expect(await b.store.record("r")?.text == "A#2")
        #expect(world.conflicts.all.isEmpty, "\(world.conflicts.all)")
        #expect(world.ownWriteViolations().isEmpty, "\(world.ownWriteViolations())")
    }

    /// A replica of an epoch the store never held (between two restarts) answers ten syncs in a
    /// row while an edit waits; the store never takes that earlier epoch. The edit must meet only
    /// the server's own answer.
    @Test(arguments: ScenarioPolicy.allCases, [false, true])
    func stickyReplicaOfNeverHeldEpoch(policy: ScenarioPolicy, otherDeviceEdits: Bool) async throws {
        let world = ScenarioWorld(policy: policy)
        let a = try world.device("A")
        let b = try world.device("B", seed: 2)
        _ = try await a.store.scenarioSave(Note(id: "r", text: "A#1"))
        _ = try await a.store.scenarioSave(Note(id: "s", text: "A#s1"))
        try await a.store.sync()
        await world.server.restart()
        let between = await world.server.snapshot()
        await world.server.restart()
        _ = try await a.store.scenarioSave(Note(id: "r", text: "A#2"))
        try await a.store.sync()
        try await b.store.sync()
        if otherDeviceEdits {
            world.clock.advance(by: 1)
            _ = try await b.store.scenarioSave(Note(id: "r", text: "B#1"))
            try await b.store.sync()
        }
        world.clock.advance(by: 1)
        _ = try await a.store.scenarioSave(Note(id: "r", text: "A#3"))
        await a.network.failNextPushes(unsent: 1)
        #expect(await scenarioSync(a.store) != nil)
        await a.network.setReplica(between, pulls: 1_000)
        for _ in 0..<10 {
            _ = await scenarioSync(a.store)
            #expect(await a.store.record("r")?.text == "A#3", "the waiting edit must stay on the device")
        }
        #expect(await a.store.scenarioEpoch() != between.epoch, "the store took an earlier epoch")
        await a.network.setReplica(nil, pulls: 0)
        world.clock.advance(by: 120)
        for _ in 0..<3 {
            _ = await scenarioSync(a.store)
            _ = await scenarioSync(b.store)
        }
        let serverText = await world.server.text("r")
        if otherDeviceEdits {
            let expected: String? = switch policy {
            case .serverWins: "B#1"
            case .clientWins, .lastWriteWins: "A#3"
            case .merge: serverText?.hasPrefix("A#M") == true ? serverText : "A#M?"
            }
            #expect(serverText == expected)
            #expect(world.conflicts.all.count == 1, "\(world.conflicts.all)")
            #expect(world.conflicts.all.allSatisfy { $0.contains("remote=B#1") }, "\(world.conflicts.all)")
        } else {
            #expect(serverText == "A#3", "the edit made on the server's current version must reach it")
            #expect(world.conflicts.all.isEmpty, "\(world.conflicts.all)")
        }
        #expect(await a.store.record("r")?.text == serverText)
        #expect(await b.store.record("r")?.text == serverText)
        #expect(await a.store.record("s")?.text == "A#s1")
        #expect(await a.store.pendingChanges().isEmpty)
        #expect(world.ownWriteViolations().isEmpty, "\(world.ownWriteViolations())")
    }

    /// The server restarts between the push and the pull of one sync, then a cache serves the
    /// new epoch's first pages from before the push. The accepted write must not go back.
    @Test(arguments: ScenarioPolicy.allCases)
    func restartBetweenPushAndPullThenStalePagesOfTheNewEpoch(policy: ScenarioPolicy) async throws {
        let world = ScenarioWorld(policy: policy, pageSize: 1)
        let a = try world.device("A")
        let b = try world.device("B", seed: 2)
        for id in ["p", "q", "r"] { _ = try await b.store.scenarioSave(Note(id: id, text: "B#\(id)")) }
        try await b.store.sync()
        try await a.store.sync()
        await world.server.restart()
        let early = await world.server.snapshot()
        _ = try await a.store.scenarioSave(Note(id: "q", text: "A#q"))
        // The pull of this sync is answered by a replica of the new epoch from before the push,
        // in pages that hold the old version of the record the push replaced.
        await a.network.setPageSize(3)
        await a.network.setReplica(early, pulls: 2)
        _ = await scenarioSync(a.store)
        #expect(await a.store.record("q")?.text == "A#q", "the accepted write went back to the replica's copy")
        try await a.store.sync()
        #expect(await a.store.record("q")?.text == "A#q")
        world.clock.advance(by: 1)
        _ = try await a.store.scenarioSave(Note(id: "q", text: "A#q2"))
        try await a.store.sync()
        #expect(await world.server.text("q") == "A#q2")
        #expect(world.conflicts.all.isEmpty, "\(world.conflicts.all)")
        #expect(world.ownWriteViolations().isEmpty)
    }
}

/// A replica of the epoch between two server restarts sticks to a device for many syncs. The
/// store used to take that earlier epoch after eight syncs in a row: records went back to the
/// replica's copies, also the device's own accepted write, and the user's next edit met that
/// write in the resolver, so `.serverWins` dropped the edit. The store now refuses an earlier
/// epoch in every sync, and the device's own accepted write is never a conflict.
@Suite("Scenarios: a sticky replica of an earlier epoch and the device's own write")
struct OwnWriteScenarioTests {
    static let options = [ScenarioOptions(sequences: true, changeIDs: true), ScenarioOptions(sequences: true, changeIDs: false)]

    /// While a sticky replica of an earlier epoch answers, the device pushes an edit that the
    /// real server accepts; a reset then asks the replica from the beginning, and the user edits
    /// on top of what the store shows.
    @Test(arguments: ScenarioPolicy.allCases, options)
    func acceptedWriteWhileFollowingAStickyReplica(policy: ScenarioPolicy, options: ScenarioOptions) async throws {
        let world = ScenarioWorld(policy: policy, options: options)
        let a = try world.device("A")
        _ = try await a.store.scenarioSave(Note(id: "r", text: "A#1"))
        try await a.store.sync()
        await world.server.restart()
        let between = await world.server.snapshot()
        await world.server.restart()
        world.clock.advance(by: 1)
        _ = try await a.store.scenarioSave(Note(id: "r", text: "A#2"))
        try await a.store.sync()
        await a.network.setReplica(between, pulls: 1_000)
        let epoch = await a.store.scenarioEpoch()
        for _ in 0..<9 { _ = await scenarioSync(a.store) }
        #expect(await a.store.scenarioEpoch() == epoch, "the store took an earlier epoch")
        world.clock.advance(by: 1)
        _ = try await a.store.scenarioSave(Note(id: "r", text: "A#3"))
        _ = await scenarioSync(a.store)
        #expect(await world.server.text("r") == "A#3")
        try await a.store.resetChangeToken()
        _ = await scenarioSync(a.store)
        #expect(await a.store.record("r")?.text == "A#3")
        world.clock.advance(by: 1)
        _ = try await a.store.scenarioSave(Note(id: "r", text: "A#4"))
        _ = await scenarioSync(a.store)
        await a.network.setReplica(nil, pulls: 0)
        world.clock.advance(by: 120)
        for _ in 0..<3 { _ = await scenarioSync(a.store) }
        #expect(await world.server.text("r") == "A#4", "the device's latest edit, made on its own accepted write")
        #expect(world.ownWriteViolations().isEmpty, "\(world.ownWriteViolations())")
        #expect(await a.store.scenarioEpoch() == epoch)
    }

    /// The device writes A#1; the server restarts twice, and a replica of the epoch in between
    /// holds A#1. The device writes A#2, accepted; the replica then answers both requests of
    /// eight syncs in a row, and the user edits A#3 on what the store shows.
    @Test(arguments: ScenarioPolicy.allCases, options)
    func editOnARolledBackOwnWrite(policy: ScenarioPolicy, options: ScenarioOptions) async throws {
        let world = ScenarioWorld(policy: policy, options: options)
        let a = try world.device("A")
        _ = try await a.store.scenarioSave(Note(id: "r", text: "A#1"))
        try await a.store.sync()
        await world.server.restart()
        let between = await world.server.snapshot()
        await world.server.restart()
        world.clock.advance(by: 1)
        _ = try await a.store.scenarioSave(Note(id: "r", text: "A#2"))
        try await a.store.sync()
        await a.network.setReplica(between, pulls: 16)
        for _ in 0..<8 { _ = await scenarioSync(a.store) }
        #expect(await a.store.record("r")?.text == "A#2", "the store went back to the replica's copy")
        world.clock.advance(by: 1)
        _ = try await a.store.scenarioSave(Note(id: "r", text: "A#3"))
        world.clock.advance(by: 120)
        for _ in 0..<3 { _ = await scenarioSync(a.store) }
        let server = await world.server.text("r")
        #expect(world.ownWriteViolations().isEmpty, "\(world.ownWriteViolations())")
        #expect(server == "A#3", "the user's last edit was lost")
        #expect(await a.store.record("r")?.text == "A#3")
        #expect(world.conflicts.all.isEmpty, "\(world.conflicts.all)")
    }
}
