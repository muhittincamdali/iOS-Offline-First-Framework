import Testing

/// Runs each test of a suite while no other test with this trait runs. The heap is the
/// process's: a test that measures how far it grows (``peakHeapGrowth(of:)``) counts what another
/// test allocates or frees at the same moment, and the suites that build pages of 16 to 40 MiB
/// would make it see too much or too little.
struct HeapExclusive: SuiteTrait, TestTrait, TestScoping {
    var isRecursive: Bool { true }

    func provideScope(for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void) async throws {
        await HeapLock.shared.acquire()
        do {
            try await function()
        } catch {
            await HeapLock.shared.release()
            throw error
        }
        await HeapLock.shared.release()
    }
}

extension Trait where Self == HeapExclusive {
    /// See ``HeapExclusive``.
    static var heapExclusive: Self { Self() }
}

/// One holder at a time, the others waiting in order.
private actor HeapLock {
    static let shared = HeapLock()

    private var held = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard held else {
            held = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        guard !waiting.isEmpty else {
            held = false
            return
        }
        waiting.removeFirst().resume()
    }
}
