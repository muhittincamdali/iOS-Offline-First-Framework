/// A vector clock: one event counter per node.
///
/// Vector clocks detect concurrent edits. If neither clock happened before the other, the two
/// replicas changed the same value without seeing each other's change, and a conflict policy has
/// to decide. Vector clocks are only partially ordered, so the type deliberately does not
/// conform to `Comparable`; use ``compare(to:)`` instead.
public struct VectorClock: Hashable, Codable, Sendable {
    /// How two vector clocks relate.
    public enum Ordering: Equatable, Sendable {
        /// Both clocks have the same counters.
        case equal
        /// This clock happened before the other one.
        case before
        /// This clock happened after the other one.
        case after
        /// Neither clock has seen all the events of the other.
        case concurrent
    }

    /// The event counter of each node. Nodes without an entry count as zero.
    public private(set) var counters: [String: UInt64]

    /// Creates a clock, optionally with existing counters. Zero counters are dropped.
    public init(counters: [String: UInt64] = [:]) {
        self.counters = counters.filter { $0.value > 0 }
    }

    private enum CodingKeys: String, CodingKey {
        case counters
    }

    /// Decodes a clock, dropping zero counters so equal clocks compare equal.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(counters: try container.decode([String: UInt64].self, forKey: .counters))
    }

    /// The counter for `nodeID`.
    public subscript(nodeID: String) -> UInt64 {
        counters[nodeID, default: 0]
    }

    /// Records one more event on `nodeID`. The counter stops at `UInt64.max` instead of trapping.
    public mutating func increment(_ nodeID: String) {
        let current = counters[nodeID, default: 0]
        counters[nodeID] = current == .max ? .max : current + 1
    }

    /// Returns a clock with the larger counter of each node.
    public func merged(with other: VectorClock) -> VectorClock {
        VectorClock(counters: counters.merging(other.counters, uniquingKeysWith: max))
    }

    /// Compares this clock with another one.
    public func compare(to other: VectorClock) -> Ordering {
        var hasSmaller = false
        var hasLarger = false
        for nodeID in Set(counters.keys).union(other.counters.keys) {
            let mine = self[nodeID]
            let theirs = other[nodeID]
            if mine < theirs { hasSmaller = true }
            if mine > theirs { hasLarger = true }
        }
        switch (hasSmaller, hasLarger) {
        case (false, false): return .equal
        case (true, false): return .before
        case (false, true): return .after
        case (true, true): return .concurrent
        }
    }

    /// Whether every event of this clock is also in `other`, and `other` has at least one more.
    public func happened(before other: VectorClock) -> Bool {
        compare(to: other) == .before
    }

    /// Whether neither clock happened before the other.
    public func isConcurrent(with other: VectorClock) -> Bool {
        compare(to: other) == .concurrent
    }
}
