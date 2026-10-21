#if os(macOS)
import Foundation
import Testing
@testable import OfflineFirstFramework

/// The reference server applies device A's push, and a gateway between them answers 504 with a
/// body of 17 MiB it never sends. The transport took that for an answer too long to read and
/// parked the change as not applied: device B edited on top of A's version, A's pull met B's
/// version as a conflict with a change that was not in doubt, `.clientWins` kept A's edit, and
/// `retryFailedChanges()` put it back over B's edit on the server and on every device. A
/// connection reset at the same moment, the control, kept the change in doubt. A 200 whose body
/// is longer than the response limit was taken the same way: as a change rejected as not applied.
///
/// Runs where `OFFLINE_FIRST_NODE` names a Node 24 binary, as the "Examples" workflow does:
/// `OFFLINE_FIRST_NODE=$(command -v node) swift test --filter GatewayEndToEndTests`.
@Suite("Reference server: a push applied behind a gateway in trouble", .serialized,
       .enabled(if: referenceServerNode != nil, "Set OFFLINE_FIRST_NODE to the path of node."))
struct GatewayEndToEndTests {
    static let modes: [RogueProxy.Mode] = [.appliedThenGatewayTimeout, .appliedThenLongAnswer, .appliedThenReset]

    @Test(arguments: ConvergenceTests.Policy.allCases, modes)
    func aLaterEditOnAnotherDeviceSurvivesAnAnswerThatWasNeverRead(policy: ConvergenceTests.Policy,
                                                                   mode: RogueProxy.Mode) async throws {
        let server = try ReferenceServerProcess(node: try #require(referenceServerNode))
        defer { server.kill() }
        let serverURL = server.url
        let proxy = try await RogueProxy.start(upstream: { serverURL }, mode: .pass)
        defer { proxy.stop() }
        let clock = TestClock()
        let collection = "gateway-\(UUID().uuidString.prefix(8))"
        func device(_ name: String, through base: URL, resolver: ConflictResolver<Note>) throws -> OfflineStore<Note> {
            let transport = HTTPSyncTransport<Note>(baseURL: base.appending(path: "sync/\(collection)"),
                                                    session: URLSession(configuration: .ephemeral))
            return try OfflineStore<Note>(name: name, storage: InMemoryStorage(), transport: transport,
                                          configuration: makeConfiguration(clock: clock, resolver: resolver))
        }
        let a = try device("a", through: proxy.url, resolver: policy.resolver)
        let b = try device("b", through: server.url, resolver: .lastWriteWins)
        try await b.save(Note(id: "x", text: "v1"))
        try await b.sync()
        try await a.sync()

        try await a.save(Note(id: "x", text: "A edit"))
        proxy.setMode(mode)
        proxy.hold()
        let firstSync = Task { _ = try? await a.sync() }
        // The server applied A's edit; B edits on top of it before A hears anything.
        try await proxy.waitForForwardedPushes(1)
        clock.advance(by: 1)
        try await b.sync()
        #expect(await b.record("x")?.text == "A edit")
        try await b.save(Note(id: "x", text: "B after A"))
        try await b.sync()
        proxy.release()
        await firstSync.value
        proxy.setMode(.pass)
        #expect(await a.failedChanges().isEmpty, "\(policy) \(mode): the change was parked")

        // Before its retry date A only pulls, and meets B's version while its change is in doubt.
        _ = try? await a.sync()
        clock.advance(by: 3_600)
        try await a.retryFailedChanges()
        try await a.sync()
        try await a.sync()
        try await b.sync()

        #expect(await a.record("x")?.text == "B after A", "\(policy) \(mode)")
        #expect(await b.record("x")?.text == "B after A", "\(policy) \(mode)")
        #expect(await a.pendingChanges().isEmpty, "\(policy) \(mode)")
    }
}
#endif
