import Foundation
import Testing
@testable import OfflineFirstFramework

/// An edit made on the server's current version while a stale page (a lagging replica) brings an
/// older write of the device itself. Without sequences nothing shows that write is older than
/// the version the edit is based on, so the pull must leave the edit to its push instead of
/// basing it on the write: based on it, the push met the newer version as a conflict, and
/// `.serverWins` dropped the edit.
@Suite("A stale own write while an edit on the current version waits")
struct StaleOwnWriteTests {
    enum Delivery: String, CaseIterable, Sendable, CustomStringConvertible {
        /// The edit is saved while the pull is on its way.
        case saveDuringPull
        /// The edit's first push never left the device; the next sync pulls while it waits.
        case waitingForRetry
        var description: String { rawValue }
    }

    static let options: [ScenarioOptions] = [
        ScenarioOptions(sequences: false, changeIDs: true), ScenarioOptions(sequences: false, changeIDs: false),
        ScenarioOptions(sequences: true, changeIDs: true), ScenarioOptions(sequences: true, changeIDs: false),
    ]

    @Test(arguments: ScenarioPolicy.allCases, Self.options)
    func anEditSavedDuringThePull(policy: ScenarioPolicy, options: ScenarioOptions) async throws {
        try await Self.run(policy: policy, options: options, delivery: .saveDuringPull)
    }

    @Test(arguments: ScenarioPolicy.allCases, Self.options)
    func anEditWaitingForItsRetry(policy: ScenarioPolicy, options: ScenarioOptions) async throws {
        try await Self.run(policy: policy, options: options, delivery: .waitingForRetry)
    }

    /// The store knows no sequence for its own accepted write (a lagging replica answered the
    /// pulls since), and a pull brings a later version in doubt of the device itself while the
    /// next edit waits. The store cannot order the two, so the version waits for the push like
    /// any other; it is the device's own write, so it never meets the resolver.
    @Test(arguments: ScenarioPolicy.allCases, Self.options)
    func anOwnWriteTheStoreCannotOrderIsNotAConflict(policy: ScenarioPolicy, options: ScenarioOptions) async throws {
        let world = ScenarioWorld(policy: policy, options: options)
        let a = try world.device("A")
        let b = try world.device("B", seed: 2)
        let empty = await world.server.snapshot()
        _ = try await a.store.scenarioSave(Note(id: "t", text: "A#1"))
        await a.network.setReplica(empty, pulls: 1)
        #expect(await scenarioSync(a.store) == nil)
        world.clock.advance(by: 5)
        // A#2 is applied and its answer lost, which ends that sync before its pull.
        _ = try await a.store.scenarioSave(Note(id: "t", text: "A#2"))
        await a.network.loseNextAnswers(1)
        _ = await scenarioSync(a.store)
        #expect(await world.server.text("t") == "A#2")
        world.clock.advance(by: 5)
        // A#3's first push never leaves the device; the next sync pulls A#2 while A#3 waits.
        _ = try await a.store.scenarioSave(Note(id: "t", text: "A#3"))
        await a.network.failNextPushes(unsent: 1)
        _ = await scenarioSync(a.store)
        _ = await scenarioSync(a.store)
        for _ in 0..<4 {
            world.clock.advance(by: 120)
            _ = await scenarioSync(a.store)
            _ = await scenarioSync(b.store)
        }
        #expect(world.ownWriteViolations().isEmpty, "\(policy) \(options): \(world.ownWriteViolations())")
        #expect(world.conflicts.all.isEmpty, "\(policy) \(options): the resolver was asked: \(world.conflicts.all)")
        #expect(await world.server.text("t") == "A#3", "\(policy) \(options): the last edit was lost")
        #expect(await a.store.pendingChanges().isEmpty)
        #expect(await b.store.record("t")?.text == "A#3")
    }

    static func run(policy: ScenarioPolicy, options: ScenarioOptions, delivery: Delivery) async throws {
        let world = ScenarioWorld(policy: policy, options: options)
        let a = try world.device("A")
        let b = try world.device("B", seed: 2)
        // A#1 is accepted; a replica keeps this state.
        _ = try await a.store.scenarioSave(Note(id: "t", text: "A#1"))
        #expect(await scenarioSync(a.store) == nil)
        let afterFirst = await world.server.snapshot()
        world.clock.advance(by: 5)
        // B edits on top of A#1; A pulls B#2 and shows it.
        #expect(await scenarioSync(b.store) == nil)
        _ = try await b.store.scenarioSave(Note(id: "t", text: "B#2"))
        #expect(await scenarioSync(b.store) == nil)
        world.clock.advance(by: 5)
        #expect(await scenarioSync(a.store) == nil)
        #expect(await a.store.record("t")?.text == "B#2")
        world.clock.advance(by: 5)
        // The user edits B#2 on A, and a lagging replica that still holds A#1 answers a pull.
        switch delivery {
        case .saveDuringPull:
            let store = a.store
            await a.network.setPullHook { _ = try? await store.scenarioSave(Note(id: "t", text: "A#3")) }
            await a.network.setReplica(afterFirst, pulls: 1)
            _ = await scenarioSync(a.store)
        case .waitingForRetry:
            _ = try await a.store.scenarioSave(Note(id: "t", text: "A#3"))
            await a.network.failNextPushes(unsent: 1)
            _ = await scenarioSync(a.store)
            await a.network.setReplica(afterFirst, pulls: 1)
            _ = await scenarioSync(a.store)
        }
        for _ in 0..<4 {
            world.clock.advance(by: 120)
            _ = await scenarioSync(a.store)
            _ = await scenarioSync(b.store)
        }
        let onServer = await world.server.text("t")
        #expect(world.ownWriteViolations().isEmpty, "\(world.ownWriteViolations())")
        #expect(onServer == "A#3", "\(delivery) \(policy) \(options): the edit was lost: server=\(onServer ?? "nil") resolver=\(world.conflicts.all)")
        #expect(world.conflicts.all.isEmpty, "\(delivery) \(policy) \(options): the resolver was asked: \(world.conflicts.all)")
        #expect(await a.store.pendingChanges().isEmpty)
        #expect(await a.store.record("t")?.text == onServer)
        #expect(await b.store.record("t")?.text == onServer)
    }
}
