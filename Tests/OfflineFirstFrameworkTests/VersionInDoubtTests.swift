import Foundation
import Testing
@testable import OfflineFirstFramework

/// A connection to a ``ScenarioServer`` whose next pulls can be scripted, and whose next push
/// answers can be lost after the server applied them.
private actor ScriptedScenarioNetwork: SyncTransport {
    typealias Record = Note
    nonisolated let serverIdentity: String? = "scenario-server"
    let server: ScenarioServer
    private var scripted: [@Sendable (String?) async -> PullResponse<Note>] = []
    private var lostAnswers = 0
    private var hook: (@Sendable () async -> Void)?

    init(server: ScenarioServer) { self.server = server }

    func script(_ page: @escaping @Sendable (String?) async -> PullResponse<Note>) { scripted.append(page) }
    func loseNextAnswers(_ count: Int) { lostAnswers = count }
    func beforeNextPull(_ action: (@Sendable () async -> Void)?) { hook = action }

    func push(_ changes: [OutgoingChange<Note>]) async throws -> [UUID: PushOutcome<Note>] {
        let outcomes = await server.push(changes)
        if lostAnswers > 0 {
            lostAnswers -= 1
            throw URLError(.networkConnectionLost)
        }
        return outcomes
    }

    func pull(since token: String?) async throws -> PullResponse<Note> {
        if let action = hook {
            hook = nil
            await action()
        }
        guard scripted.isEmpty else { return await scripted.removeFirst()(token) }
        return await server.pull(since: token)
    }
}

/// The versions in doubt of a pending change are forgotten only when a push is answered. A
/// device's own write that a page lists before them is older than they may be: a page out of
/// order, or the first page of a new epoch, as a log or a cache that merges pages sends it.
/// Before, such an own write rebased the pending change and the store forgot the versions in
/// doubt, so the next version on the page, the device's own write whose answer was lost, went
/// to the resolver as another device's: `.serverWins` dropped the user's last edit, a merge
/// merged it with the device's own write.
@Suite("Offline store: an older own write before a version in doubt")
struct VersionInDoubtTests {
    static let options = [ScenarioOptions(sequences: true, changeIDs: true), ScenarioOptions(sequences: true, changeIDs: false),
                          ScenarioOptions(sequences: false, changeIDs: true), ScenarioOptions(sequences: false, changeIDs: false)]
    /// Each server option with the own write on a page of its own and on the page of the
    /// server's versions.
    static let variants: [(ScenarioOptions, Bool)] = options.flatMap { [($0, false), ($0, true)] }

    /// A writes the record three times; the server applies the third push but its answer is
    /// lost, and A edits again, so the fourth version waits on top of the third one in doubt.
    /// The server restarts and keeps its data. The new epoch's first page lists the device's
    /// first write before its third one, the server's current version. The fourth version
    /// reaches the server and the resolver never meets A's own write.
    @Test(arguments: ScenarioPolicy.allCases, variants)
    func olderOwnWriteBeforeTheVersionInDoubt(policy: ScenarioPolicy, variant: (ScenarioOptions, Bool)) async throws {
        let (options, ownPage) = variant
        let conflicts = ScenarioLines()
        let violations = ScenarioLines()
        let clock = TestClock()
        let server = ScenarioServer(options: options, pageSize: 10)
        let network = ScriptedScenarioNetwork(server: server)
        let nodeID = ScenarioText()
        let configuration = OfflineStore<Note>.Configuration(
            conflictResolver: scenarioResolver(policy, device: "A", nodeID: nodeID, conflicts: conflicts, violations: violations,
                                               merges: ScenarioCounter()),
            retryPolicy: RetryPolicy(maximumAttempts: 8, initialDelay: .seconds(10), maximumDelay: .seconds(60), jitter: 0),
            now: { clock.now }, random: { 0 })
        let store = try OfflineStore<Note>(name: "a", storage: InMemoryStorage(), transport: network, configuration: configuration)
        nodeID.set(store.nodeID)

        try await store.save(Note(id: "t", text: "A#1"))
        try await store.sync()
        let first = try #require(await server.snapshot().stored["t"])
        clock.advance(by: 1)
        try await store.save(Note(id: "t", text: "A#2"))
        try await store.sync()
        await server.restart()
        clock.advance(by: 1)
        try await store.save(Note(id: "t", text: "A#3"))
        await network.loseNextAnswers(1)
        _ = await scenarioSync(store)
        #expect(await server.text("t") == "A#3")
        clock.advance(by: 1)
        // Saved while the next pull is on its way, so A#4 waits on top of A#3, which is in doubt.
        await network.beforeNextPull { try? await store.save(Note(id: "t", text: "A#4")) }
        let firstChange = ScenarioServer.remote("t", first, options)
        if ownPage {
            // The check of the later epoch takes two requests; then a page with the old own
            // write only, then the server's own pages.
            await network.script { token in await server.pull(since: token) }
            await network.script { _ in
                let snapshot = await server.snapshot()
                return PullResponse(changes: [firstChange], token: "\(snapshot.epoch).1", hasMore: true, epoch: snapshot.epoch)
            }
        } else {
            for _ in 0..<2 {
                await network.script { _ in
                    let page = await server.pull(since: nil)
                    return PullResponse(changes: [firstChange] + page.changes, token: page.token, hasMore: page.hasMore,
                                        epoch: page.epoch)
                }
            }
        }
        _ = await scenarioSync(store)
        for _ in 0..<4 {
            clock.advance(by: 120)
            _ = await scenarioSync(store)
        }
        #expect(violations.all.isEmpty, "\(violations.all)")
        let onServer = await server.text("t")
        #expect(onServer == "A#4", "the user's last edit was lost: server=\(onServer ?? "nil") conflicts=\(conflicts.all)")
        #expect(await store.record("t")?.text == "A#4")
        #expect(await store.pendingChanges().isEmpty)
    }
}
