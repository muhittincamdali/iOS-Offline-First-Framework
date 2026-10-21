import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// A server with epochs, sequences, change IDs and a memory of answers, which a restore from an
/// empty backup takes back to nothing under a later epoch, memory included.
private actor RestoringServer {
    struct Version { var text: String?; var revision: String; var sequence: UInt64; var changeID: UUID }
    private var epoch = 1
    private var sequence: UInt64 = 0
    private var stored: [String: Version] = [:]
    private var answers: [UUID: PushOutcome<Note>] = [:]

    func restoreFromAnEmptyBackup() {
        epoch += 1
        sequence = 0
        stored = [:]
        answers = [:]
    }

    func text(_ id: String) -> String? { stored[id]?.text }

    func push(_ changes: [OutgoingChange<Note>]) -> [UUID: PushOutcome<Note>] {
        var outcomes: [UUID: PushOutcome<Note>] = [:]
        for change in changes {
            if let answer = answers[change.id] {
                outcomes[change.id] = answer
                continue
            }
            let answer: PushOutcome<Note>
            if let current = stored[change.recordID], current.revision != change.baseRevision {
                answer = .conflict(current: remote(change.recordID, current))
            } else {
                sequence += 1
                let revision = "\(epoch).\(sequence)"
                stored[change.recordID] = Version(text: change.record?.text, revision: revision, sequence: sequence,
                                                  changeID: change.id)
                answer = .accepted(revision: revision)
            }
            answers[change.id] = answer
            outcomes[change.id] = answer
        }
        return outcomes
    }

    func pull(since token: String?) -> PullResponse<Note> {
        var after: UInt64 = 0
        if let token, let dot = token.firstIndex(of: "."), token[..<dot] == "\(epoch)",
           let position = UInt64(token[token.index(after: dot)...]), position <= sequence {
            after = position
        }
        let changed = stored.filter { $0.value.sequence > after }.sorted { $0.value.sequence < $1.value.sequence }
        return PullResponse(changes: changed.map { remote($0.key, $0.value) }, token: "\(epoch).\(changed.last?.value.sequence ?? after)",
                            hasMore: false, epoch: String(format: "%08d", epoch))
    }

    private func remote(_ id: String, _ version: Version) -> RemoteChange<Note> {
        RemoteChange(recordID: id, record: version.text.map { Note(id: id, text: $0) }, revision: version.revision,
                     timestamp: nil, sequence: version.sequence, changeID: version.changeID)
    }
}

/// A version a pull kept back for a change in doubt comes from the history the store is in. A push
/// answer names no epoch: after a restore from an empty backup the server answers from a later
/// history, whose sequences start again, before a pull shows the store that history. A kept-back
/// version with a later sequence of the earlier history then replaced the store's own accepted
/// write on the device, for every policy, and the next edit replaced that write on the server,
/// without the resolver. The answer now stands, and the next sync pulls from the beginning.
@Suite("A version kept back from the history before a restore")
struct KeptBackAcrossHistoriesTests {
    private static func resolver(_ policy: ScenarioPolicy) -> ConflictResolver<Note> {
        switch policy {
        case .serverWins: .serverWins
        case .clientWins: .clientWins
        case .lastWriteWins: .lastWriteWins
        case .merge: .merge { local, remote in Note(id: local.id, text: "\(local.text)&\(remote.text)") }
        }
    }

    @Test(arguments: ScenarioPolicy.allCases, [false, true])
    func anAcceptedWriteAfterARestoreFromAnEmptyBackupStays(policy: ScenarioPolicy, editInBetween: Bool) async throws {
        let clock = TestClock()
        let server = RestoringServer()
        let loseAnswer = OSAllocatedUnfairLock(initialState: false)
        let failPullAfterPush = OSAllocatedUnfairLock(initialState: false)
        let pushed = OSAllocatedUnfairLock(initialState: false)
        let link = ScriptedTransport(push: { changes in
            let outcomes = await server.push(changes)
            pushed.withLock { $0 = true }
            if loseAnswer.withLock({ lose in defer { lose = false }; return lose }) { throw URLError(.networkConnectionLost) }
            return outcomes
        }, pull: { token in
            if failPullAfterPush.withLock({ $0 }), pushed.withLock({ $0 }) { throw URLError(.networkConnectionLost) }
            return await server.pull(since: token)
        })
        let other = ScriptedTransport(push: { await server.push($0) }, pull: { await server.pull(since: $0) })
        let a = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: link,
                                       configuration: makeConfiguration(clock: clock, resolver: Self.resolver(policy)))
        let b = try OfflineStore<Note>(name: "b", storage: InMemoryStorage(), transport: other,
                                       configuration: makeConfiguration(clock: clock, resolver: Self.resolver(policy)))
        try await b.save(Note(id: "x", text: "B"))
        try await b.sync()
        clock.advance(by: 1)
        try await a.save(Note(id: "x", text: "A"))
        loseAnswer.withLock { $0 = true }
        _ = try? await a.sync()                    // The conflict answer is lost: A's change is in doubt.
        clock.advance(by: 1)
        _ = try? await a.sync()                    // Not due yet: the pull keeps B's version back.
        #expect(await a.state.entries["x"]?.pending?.isInDoubt == true)
        #expect(await a.state.entries["x"]?.deferredRemote?.record?.text == "B")

        await server.restoreFromAnEmptyBackup()
        clock.advance(by: 30)
        pushed.withLock { $0 = false }
        failPullAfterPush.withLock { $0 = true }
        _ = try? await a.sync()                    // The push is accepted in the later history; the pull fails.
        failPullAfterPush.withLock { $0 = false }
        #expect(await server.text("x") == "A")
        #expect(await a.record("x")?.text == "A", "the kept-back version of the earlier history replaced the accepted write")
        #expect(await a.pendingChanges().isEmpty)

        if editInBetween { try await a.save(Note(id: "x", text: (await a.record("x")?.text ?? "") + "|A2")) }
        for _ in 0..<4 {
            clock.advance(by: 120)
            try? await a.retryFailedChanges()
            _ = try? await a.sync()
            _ = try? await b.sync()
        }
        let expected = editInBetween ? "A|A2" : "A"
        #expect(await server.text("x") == expected)
        #expect(await a.record("x")?.text == expected)
        #expect(await b.record("x")?.text == expected)
        #expect(await a.pendingChanges().isEmpty)
    }
}
