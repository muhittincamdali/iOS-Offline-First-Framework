import Foundation
import os
@testable import OfflineFirstFramework

struct Note: SyncableRecord, Equatable {
    var id: String
    var text: String
}

/// A clock the tests move by hand.
final class TestClock: Sendable {
    private let current = OSAllocatedUnfairLock(initialState: Date(timeIntervalSince1970: 1_700_000_000))

    var now: Date {
        current.withLock { $0 }
    }

    func advance(by seconds: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}

/// Storage whose writes can be made to fail.
final class FailingStorage: StorageBackend {
    let inner = InMemoryStorage()
    private let failing = OSAllocatedUnfairLock(initialState: false)

    func setFailing(_ value: Bool) {
        failing.withLock { $0 = value }
    }

    func read(_ name: String) throws -> Data? { try inner.read(name) }

    func write(_ data: Data, to name: String) throws {
        if failing.withLock({ $0 }) { throw OfflineFirstError.fileSystem(name: name, description: "disk full") }
        try inner.write(data, to: name)
    }

    func remove(_ name: String) throws { try inner.remove(name) }

    func move(_ name: String, to newName: String) throws { try inner.move(name, to: newName) }
}

/// Storage that counts its writes.
final class WriteCountingStorage: StorageBackend {
    let inner = InMemoryStorage()
    private let count = OSAllocatedUnfairLock(initialState: 0)

    var writes: Int { count.withLock { $0 } }

    func read(_ name: String) throws -> Data? { try inner.read(name) }

    func write(_ data: Data, to name: String) throws {
        count.withLock { $0 += 1 }
        try inner.write(data, to: name)
    }

    func remove(_ name: String) throws { try inner.remove(name) }

    func move(_ name: String, to newName: String) throws { try inner.move(name, to: newName) }
}

/// A transport whose answers the test writes.
actor ScriptedTransport: SyncTransport {
    typealias PushHandler = @Sendable ([OutgoingChange<Note>]) async throws -> [UUID: PushOutcome<Note>]
    typealias PullHandler = @Sendable (String?) async throws -> PullResponse<Note>

    private var pushHandler: PushHandler
    private var pullHandler: PullHandler
    private(set) var pushed: [[OutgoingChange<Note>]] = []
    private(set) var pulls = 0
    nonisolated let serverIdentity: String?

    init(
        identity: String? = nil,
        push: @escaping PushHandler = { changes in Dictionary(uniqueKeysWithValues: changes.map { ($0.id, .accepted(revision: "r-\($0.id)")) }) },
        pull: @escaping PullHandler = { token in PullResponse(changes: [], token: token, hasMore: false) }
    ) {
        serverIdentity = identity
        pushHandler = push
        pullHandler = pull
    }

    func onPush(_ handler: @escaping PushHandler) { pushHandler = handler }
    func onPull(_ handler: @escaping PullHandler) { pullHandler = handler }

    func push(_ changes: [OutgoingChange<Note>]) async throws -> [UUID: PushOutcome<Note>] {
        pushed.append(changes)
        return try await pushHandler(changes)
    }

    func pull(since token: String?) async throws -> PullResponse<Note> {
        pulls += 1
        return try await pullHandler(token)
    }
}

func makeConfiguration(
    clock: TestClock,
    resolver: ConflictResolver<Note> = .lastWriteWins,
    retry: RetryPolicy = RetryPolicy(maximumAttempts: 3, initialDelay: .seconds(10), maximumDelay: .seconds(60), jitter: 0)
) -> OfflineStore<Note>.Configuration {
    OfflineStore<Note>.Configuration(
        conflictResolver: resolver,
        retryPolicy: retry,
        circuitBreaker: CircuitBreaker(failureThreshold: 100, cooldown: .seconds(1)),
        now: { clock.now },
        random: { 0 }
    )
}

// MARK: - Servers that hold one page

// A new store checks its first page with a second request, a pull after that page's token
// (see OfflineStore+Pull.swift). A transport that answered every pull with the same page made
// that check bring the page twice; these answer as a server that holds the page would.

/// A pull handler for a server that holds `page`: the pull from the beginning gets it, a pull
/// after a token nothing new, in the page's epoch.
func servingOnePage(_ page: PullResponse<Note>) -> ScriptedTransport.PullHandler {
    { token in token == nil ? page : PullResponse(changes: [], token: nil, hasMore: false, epoch: page.epoch) }
}

/// What a server that holds the page `body` answers a pull over HTTP: `body` from the
/// beginning, nothing new after a token (`since`), in the epoch `body` names.
func onePageAnswer(_ request: URLRequest, holding body: Data) -> Data {
    let items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
    guard items.contains(where: { $0.name == "since" }) else { return body }
    return Data((#"{"changes":[],"hasMore":false"# + epochField(of: body) + "}").utf8)
}

/// `,"epoch":"<epoch>"` for the epoch a page ends with, or nothing; read from the page's last
/// bytes, so a page of any size or depth is not parsed.
private func epochField(of body: Data) -> String {
    let tail = String(decoding: body.suffix(1_200), as: UTF8.self)
    guard let start = tail.range(of: #""epoch":""#, options: .backwards)?.upperBound,
          let end = tail[start...].firstIndex(of: "\"") else { return "" }
    return #","epoch":""# + tail[start..<end] + "\""
}

/// A server of pages the test publishes one at a time, as other devices write: a pull after a
/// token gets the next published page, or nothing new. Tokens are `t1`, `t2`, ….
actor PageFeed: SyncTransport {
    typealias Record = Note
    nonisolated let serverIdentity: String? = nil
    private var pages: [[RemoteChange<Note>]] = []
    private(set) var pulls = 0

    func publish(_ changes: RemoteChange<Note>...) { pages.append(changes) }

    func push(_ changes: [OutgoingChange<Note>]) async throws -> [UUID: PushOutcome<Note>] {
        Dictionary(uniqueKeysWithValues: changes.map { ($0.id, .accepted(revision: "r-\($0.id)")) })
    }

    func pull(since token: String?) async throws -> PullResponse<Note> {
        pulls += 1
        let position = token.flatMap { Int($0.dropFirst()) } ?? 0
        guard position < pages.count else { return PullResponse(changes: [], token: token, hasMore: false) }
        return PullResponse(changes: pages[position], token: "t\(position + 1)", hasMore: position + 1 < pages.count)
    }
}
