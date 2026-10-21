import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// Ends the app at every file write made during a scripted series of syncs, opens the store
/// again from its file and lets it finish. Every crash point must end where the run without a
/// crash ends: the same records on the server and the device, and nothing queued.
@Suite("Offline store: a crash at every write")
struct CrashScanTests {
    @Test(arguments: ConvergenceTests.Policy.allCases)
    func aCrashAtAnyWriteDuringASyncConverges(policy: ConvergenceTests.Policy) async throws {
        let baseline = try await run(crashAt: nil, policy: policy)
        if policy == .lastWriteWins {
            #expect(baseline.server == ["a": "a2", "d": "d1", "e": "e-other"])
        }
        #expect(baseline.writesDuringSyncs > 5)
        for crashAt in 1...baseline.writesDuringSyncs {
            let run = try await run(crashAt: crashAt, policy: policy)
            #expect(run.server == baseline.server, "\(policy), crash at write \(crashAt)")
            #expect(run.device == run.server, "\(policy), crash at write \(crashAt)")
            #expect(run.pending == 0, "\(policy), crash at write \(crashAt)")
        }
    }

    private struct Outcome {
        var server: [String: String]
        var device: [String: String]
        var pending: Int
        var writesDuringSyncs: Int
    }

    private func run(crashAt: Int?, policy: ConvergenceTests.Policy) async throws -> Outcome {
        let clock = TestClock()
        let server = InMemorySyncServer<Note>(pageSize: 1, now: { [clock] in clock.now })
        let storage = CrashingStorage()
        let configuration = makeConfiguration(clock: clock, resolver: policy.resolver)
        var store = try OfflineStore<Note>(name: "device", storage: storage, transport: server, configuration: configuration)
        storage.crashAt = crashAt

        func syncOrCrash() async throws {
            storage.isSyncing = true
            _ = try? await store.sync()
            storage.isSyncing = false
            if storage.hasCrashed {
                storage.relaunch()
                store = try OfflineStore<Note>(name: "device", storage: storage, transport: server, configuration: configuration)
            }
        }

        try await store.save(Note(id: "a", text: "a1"))
        try await store.save(Note(id: "b", text: "b1"))
        try await syncOrCrash()
        clock.advance(by: 5)
        await server.write(Note(id: "c", text: "c1"))
        await server.write(Note(id: "a", text: "a-other"))
        clock.advance(by: 5)
        try await store.save(Note(id: "a", text: "a2"))
        if await store.record("b") != nil { try await store.delete("b") }
        try await syncOrCrash()
        clock.advance(by: 5)
        await server.delete("c")
        try await store.save(Note(id: "d", text: "d1"))
        try await store.save(Note(id: "e", text: "e1"))
        clock.advance(by: 5)
        await server.write(Note(id: "e", text: "e-other"))
        try await syncOrCrash()
        for _ in 0..<4 {
            clock.advance(by: 3_600)
            try await store.retryFailedChanges()
            try await syncOrCrash()
        }
        return Outcome(server: Dictionary(uniqueKeysWithValues: await server.records().map { ($0.id, $0.text) }),
                       device: Dictionary(uniqueKeysWithValues: await store.records().map { ($0.id, $0.text) }),
                       pending: await store.pendingChanges().count, writesDuringSyncs: storage.writesDuringSyncs)
    }
}

/// Storage that fails every write from the `crashAt`-th write made during a sync on, as if the
/// app ended there, until ``relaunch()``.
private final class CrashingStorage: StorageBackend, @unchecked Sendable {
    private let inner = InMemoryStorage()
    private let lock = OSAllocatedUnfairLock()
    var crashAt: Int?
    var isSyncing = false
    private(set) var writesDuringSyncs = 0
    private(set) var hasCrashed = false

    func relaunch() {
        lock.withLock {
            hasCrashed = false
            crashAt = nil
        }
    }

    func read(_ name: String) throws -> Data? { try inner.read(name) }

    func write(_ data: Data, to name: String) throws {
        try lock.withLock {
            if hasCrashed { throw OfflineFirstError.fileSystem(name: name, description: "the app ended") }
            guard isSyncing else { return }
            writesDuringSyncs += 1
            if let crashAt, writesDuringSyncs >= crashAt {
                hasCrashed = true
                throw OfflineFirstError.fileSystem(name: name, description: "the app ended")
            }
        }
        try inner.write(data, to: name)
    }

    func remove(_ name: String) throws { try inner.remove(name) }

    func move(_ name: String, to newName: String) throws { try inner.move(name, to: newName) }
}
