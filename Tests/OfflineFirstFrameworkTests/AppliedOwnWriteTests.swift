import Foundation
import Testing
@testable import OfflineFirstFramework

/// A push the server applied whose answer was lost, learned from a page that brings the change
/// itself, from a server without sequences. Then a stale page (a lagging replica that answers
/// the pull from the beginning after `resetChangeToken()`) brings the version the write
/// replaced. After an accepted answer the store knows that version is older and skips it; when
/// a page told it the write was applied, it did not (verifier C12): it showed the replaced
/// version, and the edit the user made on it replaced the write on the server without a
/// conflict.
@Suite("Offline store: an own write a page showed applied")
struct AppliedOwnWriteTests {
    /// Change IDs on and off, and the answer of the edit's push lost or not.
    static let variants: [(changeIDs: Bool, answerArrives: Bool)] = [(false, false), (false, true), (true, false), (true, true)]

    @Test(arguments: ScenarioPolicy.allCases, Self.variants)
    func theReplacedVersionComesBackOnAStalePage(policy: ScenarioPolicy, variant: (changeIDs: Bool, answerArrives: Bool)) async throws {
        let (changeIDs, answerArrives) = variant
        let world = ScenarioWorld(policy: policy, options: ScenarioOptions(sequences: false, changeIDs: changeIDs), pageSize: 5)
        let a = try world.device("A")
        let context = "\(policy) cid=\(changeIDs) answer=\(answerArrives)"
        try await a.store.save(Note(id: "r", text: "A#r|1"))
        #expect(await scenarioSync(a.store) == nil)
        let old = await world.server.snapshot()
        try await a.store.save(Note(id: "r", text: "A#r|1|2"))
        if !answerArrives { await a.network.loseNextAnswers(1) }
        _ = await scenarioSync(a.store)
        // Within the retry delay: the push waits, and the pull brings the change itself.
        #expect(await scenarioSync(a.store) == nil)
        #expect(await a.store.pendingChanges().isEmpty, "\(context)")

        await a.network.setReplica(old, pulls: 1)
        try await a.store.resetChangeToken()
        #expect(await scenarioSync(a.store) == nil)
        let shown = await a.store.record("r")?.text ?? "nil"
        #expect(shown == "A#r|1|2", "\(context)")
        try await a.store.save(Note(id: "r", text: shown + "|3"))
        for _ in 0..<3 {
            world.clock.advance(by: 120)
            _ = await scenarioSync(a.store)
        }
        #expect(await world.server.text("r") == "A#r|1|2|3", "\(context): the applied write was lost")
        #expect(await a.store.record("r")?.text == "A#r|1|2|3", "\(context)")
        #expect(world.conflicts.all.isEmpty, "\(context): \(world.conflicts.all)")
        #expect(world.ownWriteViolations().isEmpty)
    }
}
