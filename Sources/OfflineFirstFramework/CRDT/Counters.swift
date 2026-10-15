/// A grow-only counter: each node counts its own increments, and merging keeps the larger
/// count of every node.
///
/// ```swift
/// var views = GCounter()
/// views.increment(node: deviceID)
/// views.merge(with: viewsFromServer)
/// print(views.value)
/// ```
///
/// Counts stop at `UInt64.max` instead of overflowing, including the total in ``value``, so a
/// counter decoded from untrusted data cannot crash the app.
public struct GCounter: Mergeable, Codable, Hashable {
    /// The count of each node.
    public private(set) var counts: [String: UInt64]

    /// Creates a counter, optionally with existing counts.
    public init(counts: [String: UInt64] = [:]) {
        self.counts = counts
    }

    /// The sum of all node counts, at most `UInt64.max`.
    public var value: UInt64 {
        counts.values.reduce(0) { total, count in
            let (sum, overflow) = total.addingReportingOverflow(count)
            return overflow ? .max : sum
        }
    }

    /// Adds `amount` to the count of `node`.
    public mutating func increment(by amount: UInt64 = 1, node: String) {
        let (sum, overflow) = counts[node, default: 0].addingReportingOverflow(amount)
        counts[node] = overflow ? .max : sum
    }

    public func merged(with other: GCounter) -> GCounter {
        GCounter(counts: counts.merging(other.counts, uniquingKeysWith: max))
    }
}

/// A counter that can go up and down, made of two ``GCounter``s: one for increments and one
/// for decrements.
public struct PNCounter: Mergeable, Codable, Hashable {
    /// The increments of each node.
    public private(set) var increments: GCounter

    /// The decrements of each node.
    public private(set) var decrements: GCounter

    /// Creates a counter at zero.
    public init() {
        increments = GCounter()
        decrements = GCounter()
    }

    /// Increments minus decrements, clamped to the `Int64` range.
    public var value: Int64 {
        let up = increments.value
        let down = decrements.value
        if up >= down {
            return Int64(clamping: up - down)
        }
        let magnitude = down - up
        // Int64.min has a magnitude one larger than Int64.max.
        return magnitude > UInt64(Int64.max) ? .min : -Int64(magnitude)
    }

    /// Adds `amount` on behalf of `node`.
    public mutating func increment(by amount: UInt64 = 1, node: String) {
        increments.increment(by: amount, node: node)
    }

    /// Subtracts `amount` on behalf of `node`.
    public mutating func decrement(by amount: UInt64 = 1, node: String) {
        decrements.increment(by: amount, node: node)
    }

    public func merged(with other: PNCounter) -> PNCounter {
        var result = self
        result.increments = increments.merged(with: other.increments)
        result.decrements = decrements.merged(with: other.decrements)
        return result
    }
}
