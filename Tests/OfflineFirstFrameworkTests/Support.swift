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

/// A transport whose answers the test writes.
actor ScriptedTransport: SyncTransport {
    typealias PushHandler = @Sendable ([OutgoingChange<Note>]) async throws -> [UUID: PushOutcome<Note>]
    typealias PullHandler = @Sendable (String?) async throws -> PullResponse<Note>

    private var pushHandler: PushHandler
    private var pullHandler: PullHandler
    private(set) var pushed: [[OutgoingChange<Note>]] = []
    private(set) var pulls = 0

    init(
        push: @escaping PushHandler = { changes in Dictionary(uniqueKeysWithValues: changes.map { ($0.id, .accepted(revision: "r-\($0.id)")) }) },
        pull: @escaping PullHandler = { token in PullResponse(changes: [], token: token, hasMore: false) }
    ) {
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
