import Foundation
import Testing
@testable import OfflineFirstFramework

@Suite("Offline store: sync")
struct SyncTests {
    let clock = TestClock()

    private func makeStore(_ transport: any SyncTransport<Note>, storage: any StorageBackend = InMemoryStorage(),
                           configure: (inout OfflineStore<Note>.Configuration) -> Void = { _ in }) throws -> OfflineStore<Note> {
        var configuration = makeConfiguration(clock: clock)
        configure(&configuration)
        return try OfflineStore<Note>(name: "notes", storage: storage, transport: transport, configuration: configuration)
    }

    @Test func changesTravelFromOneDeviceToAnother() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let phone = try makeStore(server)
        let laptop = try makeStore(server)
        try await phone.save(Note(id: "a", text: "Buy milk"))
        let pushReport = try await phone.sync()
        #expect(pushReport.pushed == 1)
        #expect(await phone.pendingChanges().isEmpty)
        #expect(await server.records() == [Note(id: "a", text: "Buy milk")])

        let pullReport = try await laptop.sync()
        #expect(pullReport.pulled == 1)
        #expect(await laptop.records() == [Note(id: "a", text: "Buy milk")])
        // The phone's own change comes back as an echo and is not counted again.
        #expect(try await phone.sync().pulled == 0)
        #expect(await phone.lastSyncedAt == clock.now)
    }

    @Test func deletionsSyncAndDisappearEverywhere() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let phone = try makeStore(server)
        let laptop = try makeStore(server)
        try await phone.save(Note(id: "a", text: "Old"))
        try await phone.sync()
        try await laptop.sync()
        try await phone.delete("a")
        #expect(await phone.pendingChanges().first?.isDelete == true)
        try await phone.sync()
        #expect(await server.record("a") == nil)
        #expect(await phone.pendingChanges().isEmpty)
        try await laptop.sync()
        #expect(await laptop.records().isEmpty)
    }

    @Test func offlineSyncRetriesWithBackoffAndThenSucceeds() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try makeStore(server)
        try await store.save(Note(id: "a", text: "Offline note"))
        await server.setOnline(false)
        await #expect(throws: URLError.self) { try await store.sync() }
        #expect(await store.status == .offline)
        let pending = try #require(await store.pendingChanges().first)
        #expect(pending.attempts == 1)
        #expect(pending.nextAttemptAt == clock.now.addingTimeInterval(10))

        await server.setOnline(true)
        let early = try await store.sync()
        #expect(early.pushed == 0)
        clock.advance(by: 10)
        let due = try await store.sync()
        #expect(due.pushed == 1)
        #expect(await store.status == .idle)
        #expect(await server.records() == [Note(id: "a", text: "Offline note")])
    }

    @Test func changesAreParkedAfterTheLastAttemptAndCanBeRetried() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try makeStore(server) { $0.retryPolicy = RetryPolicy(maximumAttempts: 2, initialDelay: .zero, jitter: 0) }
        try await store.save(Note(id: "a", text: "A"))
        await server.setOnline(false)
        await #expect(throws: URLError.self) { try await store.sync() }
        await #expect(throws: URLError.self) { try await store.sync() }
        #expect(await store.failedChanges().count == 1)
        await server.setOnline(true)
        #expect(try await store.sync().pushed == 0)

        try await store.retryFailedChanges()
        #expect(await store.failedChanges().isEmpty)
        #expect(try await store.sync().pushed == 1)
    }

    @Test func lastWriteWinsKeepsTheNewerLocalEdit() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try makeStore(server)
        try await store.save(Note(id: "a", text: "v1"))
        try await store.sync()
        await server.write(Note(id: "a", text: "server edit"), at: clock.now.addingTimeInterval(1))
        clock.advance(by: 5)
        try await store.save(Note(id: "a", text: "newer local edit"))
        let report = try await store.sync()
        #expect(report.conflicts == 1)
        #expect(await server.record("a")?.text == "newer local edit")
        #expect(await store.record("a")?.text == "newer local edit")
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test func lastWriteWinsTakesTheNewerServerEdit() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try makeStore(server)
        try await store.save(Note(id: "a", text: "v1"))
        try await store.sync()
        try await store.save(Note(id: "a", text: "older local edit"))
        await server.write(Note(id: "a", text: "newer server edit"), at: clock.now.addingTimeInterval(60))
        try await store.sync()
        #expect(await store.record("a")?.text == "newer server edit")
        #expect(await server.record("a")?.text == "newer server edit")
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test(arguments: [true, false])
    func fixedPoliciesPickTheirSide(serverWins: Bool) async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try makeStore(server) { $0.conflictResolver = serverWins ? .serverWins : .clientWins }
        try await store.save(Note(id: "a", text: "v1"))
        try await store.sync()
        try await store.save(Note(id: "a", text: "local"))
        await server.write(Note(id: "a", text: "remote"), at: clock.now.addingTimeInterval(-60))
        try await store.sync()
        let expected = serverWins ? "remote" : "local"
        #expect(await store.record("a")?.text == expected)
        #expect(await server.record("a")?.text == expected)
    }

    @Test func mergeResolverPushesTheCombination() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try makeStore(server) {
            $0.conflictResolver = .merge { local, remote in Note(id: local.id, text: "\(remote.text) + \(local.text)") }
        }
        try await store.save(Note(id: "a", text: "v1"))
        try await store.sync()
        try await store.save(Note(id: "a", text: "phone"))
        await server.write(Note(id: "a", text: "laptop"))
        try await store.sync()
        #expect(await store.record("a")?.text == "laptop + phone")
        #expect(await server.record("a")?.text == "laptop + phone")
    }

    @Test func mergedRecordWithAnotherIDIsIgnored() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try makeStore(server) { $0.conflictResolver = .merge { _, _ in Note(id: "other", text: "wrong") } }
        try await store.save(Note(id: "a", text: "v1"))
        try await store.sync()
        try await store.save(Note(id: "a", text: "phone"))
        await server.write(Note(id: "a", text: "laptop"))
        try await store.sync()
        #expect(await store.records() == [Note(id: "a", text: "laptop")])
    }

    @Test func conflictsFoundWhilePullingAreResolvedToo() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try makeStore(server) { $0.conflictResolver = .serverWins }
        try await store.save(Note(id: "a", text: "v1"))
        try await store.sync()
        try await store.save(Note(id: "a", text: "local"))
        // Make the local change wait, so the pull meets it first.
        await server.setOnline(false)
        await #expect(throws: URLError.self) { try await store.sync() }
        await server.setOnline(true)
        await server.write(Note(id: "a", text: "remote"))
        let report = try await store.sync()
        #expect(report.pushed == 0)
        #expect(report.conflicts == 1)
        #expect(await store.record("a")?.text == "remote")
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test func rejectedChangesRevertOrPark() async throws {
        let server = InMemorySyncServer<Note>(
            validate: { $0.text.isEmpty ? "Text is required. " + String(repeating: "!", count: 5_000) : nil },
            now: { [clock] in clock.now }
        )
        let store = try makeStore(server)
        try await store.save(Note(id: "a", text: "valid"))
        try await store.sync()
        try await store.save(Note(id: "a", text: ""))
        try await store.save(Note(id: "b", text: ""))
        let report = try await store.sync()
        #expect(report.rejected == 2)
        // "a" exists on the server, so the store goes back to the server's copy.
        #expect(await store.record("a")?.text == "valid")
        // "b" does not, so its change is parked with the (shortened) reason.
        let parked = try #require(await store.failedChanges().first)
        #expect(parked.recordID == "b")
        #expect(parked.lastError?.hasPrefix("Text is required.") == true)
        #expect(parked.lastError?.count == 1_000)
    }

    @Test func editsDuringAPushAreKeptAndPushedNext() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = ScriptedTransport()
        let store = try makeStore(transport)
        await transport.onPush { changes in
            if changes.contains(where: { $0.record?.text == "first" }) {
                try await store.save(Note(id: "a", text: "edited while pushing"))
            }
            return try await server.push(changes)
        }
        await transport.onPull { try await server.pull(since: $0) }
        try await store.save(Note(id: "a", text: "first"))
        let report = try await store.sync()
        #expect(report.conflicts == 0)
        #expect(await server.record("a")?.text == "edited while pushing")
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test func deletingARecordWhileItsCreationIsPushedDeletesItOnTheServer() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let transport = ScriptedTransport()
        let store = try makeStore(transport)
        await transport.onPush { changes in
            if changes.contains(where: { $0.record != nil }) {
                try await store.delete("a")
            }
            return try await server.push(changes)
        }
        await transport.onPull { try await server.pull(since: $0) }
        try await store.save(Note(id: "a", text: "short-lived"))
        try await store.sync()
        #expect(await server.record("a") == nil)
        #expect(await server.revision(of: "a") != nil)
        #expect(await store.records().isEmpty)
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test func serverThatConflictsForeverDoesNotHangTheSync() async throws {
        let transport = ScriptedTransport()
        let counter = Counter()
        await transport.onPush { changes in
            let revision = await counter.next()
            return Dictionary(uniqueKeysWithValues: changes.map {
                ($0.id, .conflict(current: RemoteChange(recordID: $0.recordID, record: Note(id: $0.recordID, text: "server"), revision: "\(revision)", timestamp: nil)))
            })
        }
        let store = try makeStore(transport) { $0.conflictResolver = .clientWins }
        try await store.save(Note(id: "a", text: "mine"))
        let report = try await store.sync()
        #expect(report.conflicts == OfflineStore<Note>.maximumPushesPerRecord)
        #expect(await transport.pushed.count == OfflineStore<Note>.maximumPushesPerRecord)
        #expect(await store.pendingChanges().count == 1)
    }

    @Test func missingAnswersCountAsFailedAttempts() async throws {
        let transport = ScriptedTransport(push: { _ in [:] })
        let store = try makeStore(transport)
        try await store.save(Note(id: "a", text: "A"))
        let report = try await store.sync()
        #expect(report.pushed == 0)
        let pending = try #require(await store.pendingChanges().first)
        #expect(pending.attempts == 1)
        #expect(pending.lastError == "The server did not answer this change.")
    }

    @Test func aTokenThatDoesNotMoveStopsThePull() async throws {
        let transport = ScriptedTransport(pull: { token in PullResponse(changes: [], token: token, hasMore: true) })
        let store = try makeStore(transport)
        await #expect(throws: OfflineFirstError.pullTokenDidNotAdvance(token: nil)) {
            try await store.sync()
        }
        #expect(await transport.pulls == 1)
        guard case .failed = await store.status else {
            Issue.record("expected a failed status")
            return
        }
    }

    @Test func pullStopsAtThePageLimitAndContinuesNextTime() async throws {
        let server = InMemorySyncServer<Note>(pageSize: 1)
        for index in 0..<5 {
            await server.write(Note(id: "n\(index)", text: "\(index)"))
        }
        let store = try makeStore(server) { $0.maximumPullPages = 2 }
        let first = try await store.sync()
        #expect(first.pulled == 2)
        #expect(first.hasMoreChanges)
        try await store.sync()
        try await store.sync()
        #expect(await store.records().map(\.id) == ["n0", "n1", "n2", "n3", "n4"])
    }

    @Test func malformedServerRecordsAreIgnored() async throws {
        let transport = ScriptedTransport(pull: { _ in
            PullResponse(changes: [
                RemoteChange(recordID: "a", record: Note(id: "b", text: "mismatched"), revision: "1", timestamp: nil),
                RemoteChange(recordID: "c", record: Note(id: "c", text: "fine"), revision: "2", timestamp: nil)
            ], token: "2", hasMore: false)
        })
        let store = try makeStore(transport)
        try await store.sync()
        #expect(await store.records() == [Note(id: "c", text: "fine")])
    }

    @Test func oversizedRevisionsAndNodeIDsAreIgnored() async throws {
        let long = String(repeating: "r", count: OfflineStore<Note>.maximumRevisionLength + 1)
        let transport = ScriptedTransport(pull: { _ in
            PullResponse(changes: [
                RemoteChange(recordID: "a", record: Note(id: "a", text: "long revision"), revision: long, timestamp: nil),
                RemoteChange(recordID: "b", record: Note(id: "b", text: "long node"), revision: "2",
                             timestamp: HLCTimestamp(wallTime: 1, nodeID: String(repeating: "n", count: 300))),
                RemoteChange(recordID: "c", record: Note(id: "c", text: "fine"), revision: "3", timestamp: nil)
            ], token: "3", hasMore: false)
        })
        let store = try makeStore(transport)
        try await store.sync()
        #expect(await store.records() == [Note(id: "c", text: "fine")])
    }

    @Test func oversizedChangeTokensFailTheSyncWithoutBeingSaved() async throws {
        let long = String(repeating: "t", count: OfflineStore<Note>.maximumRevisionLength + 1)
        let transport = ScriptedTransport(pull: { _ in
            PullResponse(changes: [RemoteChange(recordID: "a", record: Note(id: "a", text: "A"), revision: "1", timestamp: nil)],
                         token: long, hasMore: false)
        })
        let store = try makeStore(transport)
        await #expect(throws: OfflineFirstError.self) { try await store.sync() }
        #expect(await store.state.token == nil)
        #expect(await store.records().isEmpty)
    }

    @Test func automaticSyncWaitsStayBetweenASecondAndADay() {
        #expect(OfflineStore<Note>.clampedDelay(.zero) == .seconds(1))
        #expect(OfflineStore<Note>.clampedDelay(.seconds(-5)) == .seconds(1))
        #expect(OfflineStore<Note>.clampedDelay(.seconds(90)) == .seconds(90))
        #expect(OfflineStore<Note>.clampedDelay(.seconds(Int64.max)) == .seconds(86_400))
    }

    @Test func farFutureServerTimestampsDoNotMoveTheClock() async throws {
        let transport = ScriptedTransport(pull: { _ in
            PullResponse(changes: [
                RemoteChange(recordID: "a", record: Note(id: "a", text: "from the future"), revision: "1",
                             timestamp: HLCTimestamp(wallTime: .max, counter: .max, nodeID: "evil"))
            ], token: "1", hasMore: false)
        })
        let store = try makeStore(transport)
        try await store.sync()
        try await store.save(Note(id: "b", text: "now"))
        let state = await store.state
        let wallTime = try #require(state.entries["b"]?.timestamp.wallTime)
        #expect(wallTime == HybridLogicalClock.milliseconds(since1970: clock.now))
    }

    @Test func openCircuitBreakerSkipsSyncsUntilTheCooldownEnds() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try makeStore(server) { $0.circuitBreaker = CircuitBreaker(failureThreshold: 1, cooldown: .seconds(30)) }
        await server.setOnline(false)
        await #expect(throws: URLError.self) { try await store.sync() }
        await server.setOnline(true)
        let skipped = try await store.sync()
        #expect(skipped.skipped)
        #expect(await store.status == .paused(until: clock.now.addingTimeInterval(30)))
        #expect(await server.pullRequests == 1)
        clock.advance(by: 30)
        #expect(try await store.sync().skipped == false)
    }

    @Test func concurrentSyncCallsShareOneRun() async throws {
        let server = InMemorySyncServer<Note>(latency: .milliseconds(100))
        let store = try makeStore(server)
        try await store.save(Note(id: "a", text: "A"))
        async let first = store.sync()
        async let second = store.sync()
        let reports = try await [first, second]
        #expect(reports[0] == reports[1])
        #expect(await server.pushRequests == 1)
    }

    @Test func discardingAChangeRestoresTheServerCopy() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let store = try makeStore(server)
        try await store.save(Note(id: "a", text: "server copy"))
        try await store.sync()
        try await store.save(Note(id: "a", text: "unwanted edit"))
        try await store.save(Note(id: "draft", text: "never synced"))
        try await store.discardChange(for: "a")
        try await store.discardChange(for: "draft")
        #expect(await store.records().isEmpty)
        try await store.sync()
        #expect(await store.records() == [Note(id: "a", text: "server copy")])
        #expect(await store.pendingChanges().isEmpty)
    }

    @Test func serverAppliesARepeatedChangeOnlyOnce() async throws {
        let server = InMemorySyncServer<Note>(now: { [clock] in clock.now })
        let change = OutgoingChange<Note>(id: UUID(), recordID: "a", operation: .upsert(Note(id: "a", text: "A")),
                                          timestamp: HLCTimestamp(wallTime: 1, nodeID: "x"), baseRevision: nil)
        let first = try await server.push([change])
        let second = try await server.push([change])
        guard case .accepted(let revision)? = first[change.id], case .accepted(let repeated)? = second[change.id] else {
            Issue.record("expected both pushes to be accepted")
            return
        }
        #expect(revision == repeated)
        #expect(await server.revision(of: "a") == revision)
    }
}

actor Counter {
    private var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}
