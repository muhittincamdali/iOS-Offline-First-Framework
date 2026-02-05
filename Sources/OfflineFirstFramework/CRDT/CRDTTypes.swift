import Foundation

// MARK: - CRDT Protocol

/// Protocol for Conflict-free Replicated Data Types
public protocol CRDTValue {
    associatedtype State: Codable & Equatable
    var state: State { get }
    var timestamp: VectorClock { get }
    func merge(with other: Self) -> Self
}

// MARK: - Vector Clock

/// Vector clock for distributed timestamp tracking
public struct VectorClock: Codable, Equatable, Comparable {
    public private(set) var clock: [String: UInt64]
    
    public init() {
        self.clock = [:]
    }
    
    public init(clock: [String: UInt64]) {
        self.clock = clock
    }
    
    /// Increment clock for a specific node
    public mutating func increment(for nodeId: String) {
        clock[nodeId, default: 0] += 1
    }
    
    /// Get timestamp for a specific node
    public func timestamp(for nodeId: String) -> UInt64 {
        clock[nodeId, default: 0]
    }
    
    /// Merge two vector clocks (take max of each component)
    public func merge(with other: VectorClock) -> VectorClock {
        var merged = clock
        for (key, value) in other.clock {
            merged[key] = max(merged[key, default: 0], value)
        }
        return VectorClock(clock: merged)
    }
    
    /// Check if this clock happened before another
    public func happenedBefore(_ other: VectorClock) -> Bool {
        var atLeastOneLess = false
        
        for (key, value) in clock {
            let otherValue = other.clock[key, default: 0]
            if value > otherValue {
                return false
            }
            if value < otherValue {
                atLeastOneLess = true
            }
        }
        
        for (key, otherValue) in other.clock where clock[key] == nil {
            if otherValue > 0 {
                atLeastOneLess = true
            }
        }
        
        return atLeastOneLess
    }
    
    /// Check if clocks are concurrent (neither happened before the other)
    public func isConcurrent(with other: VectorClock) -> Bool {
        !happenedBefore(other) && !other.happenedBefore(self) && self != other
    }
    
    public static func < (lhs: VectorClock, rhs: VectorClock) -> Bool {
        lhs.happenedBefore(rhs)
    }
}

// MARK: - LWW Register (Last Writer Wins)

/// Last-Writer-Wins Register CRDT
public struct LWWRegister<T: Codable & Equatable>: CRDTValue, Codable where T: Sendable {
    public typealias State = T
    
    public let value: T
    public let timestamp: VectorClock
    public let nodeId: String
    public let wallClockTime: Date
    
    public var state: T { value }
    
    public init(value: T, nodeId: String) {
        self.value = value
        self.nodeId = nodeId
        var clock = VectorClock()
        clock.increment(for: nodeId)
        self.timestamp = clock
        self.wallClockTime = Date()
    }
    
    public init(value: T, nodeId: String, timestamp: VectorClock, wallClockTime: Date) {
        self.value = value
        self.nodeId = nodeId
        self.timestamp = timestamp
        self.wallClockTime = wallClockTime
    }
    
    /// Update the register value
    public func update(_ newValue: T) -> LWWRegister<T> {
        var newTimestamp = timestamp
        newTimestamp.increment(for: nodeId)
        return LWWRegister(value: newValue, nodeId: nodeId, timestamp: newTimestamp, wallClockTime: Date())
    }
    
    /// Merge with another register (last writer wins based on vector clock, then wall clock)
    public func merge(with other: LWWRegister<T>) -> LWWRegister<T> {
        if timestamp.happenedBefore(other.timestamp) {
            return other
        } else if other.timestamp.happenedBefore(timestamp) {
            return self
        } else {
            // Concurrent - use wall clock as tiebreaker
            return wallClockTime >= other.wallClockTime ? self : other
        }
    }
}

// MARK: - G-Counter (Grow-only Counter)

/// Grow-only Counter CRDT
public struct GCounter: CRDTValue, Codable {
    public typealias State = [String: UInt64]
    
    public private(set) var counts: [String: UInt64]
    public let timestamp: VectorClock
    public let nodeId: String
    
    public var state: [String: UInt64] { counts }
    
    /// Total value across all nodes
    public var value: UInt64 {
        counts.values.reduce(0, +)
    }
    
    public init(nodeId: String) {
        self.counts = [:]
        self.timestamp = VectorClock()
        self.nodeId = nodeId
    }
    
    public init(counts: [String: UInt64], nodeId: String, timestamp: VectorClock) {
        self.counts = counts
        self.nodeId = nodeId
        self.timestamp = timestamp
    }
    
    /// Increment counter for this node
    public func increment(by amount: UInt64 = 1) -> GCounter {
        var newCounts = counts
        newCounts[nodeId, default: 0] += amount
        var newTimestamp = timestamp
        newTimestamp.increment(for: nodeId)
        return GCounter(counts: newCounts, nodeId: nodeId, timestamp: newTimestamp)
    }
    
    /// Merge with another counter (take max of each node's count)
    public func merge(with other: GCounter) -> GCounter {
        var merged = counts
        for (key, value) in other.counts {
            merged[key] = max(merged[key, default: 0], value)
        }
        return GCounter(counts: merged, nodeId: nodeId, timestamp: timestamp.merge(with: other.timestamp))
    }
}

// MARK: - PN-Counter (Positive-Negative Counter)

/// Positive-Negative Counter CRDT (supports increment and decrement)
public struct PNCounter: CRDTValue, Codable {
    public typealias State = Int64
    
    public let positive: GCounter
    public let negative: GCounter
    public let timestamp: VectorClock
    
    public var state: Int64 { value }
    
    /// Net value (positive - negative)
    public var value: Int64 {
        Int64(positive.value) - Int64(negative.value)
    }
    
    public init(nodeId: String) {
        self.positive = GCounter(nodeId: nodeId)
        self.negative = GCounter(nodeId: nodeId)
        self.timestamp = VectorClock()
    }
    
    public init(positive: GCounter, negative: GCounter, timestamp: VectorClock) {
        self.positive = positive
        self.negative = negative
        self.timestamp = timestamp
    }
    
    /// Increment counter
    public func increment(by amount: UInt64 = 1) -> PNCounter {
        PNCounter(
            positive: positive.increment(by: amount),
            negative: negative,
            timestamp: positive.timestamp.merge(with: negative.timestamp)
        )
    }
    
    /// Decrement counter
    public func decrement(by amount: UInt64 = 1) -> PNCounter {
        PNCounter(
            positive: positive,
            negative: negative.increment(by: amount),
            timestamp: positive.timestamp.merge(with: negative.timestamp)
        )
    }
    
    /// Merge with another counter
    public func merge(with other: PNCounter) -> PNCounter {
        PNCounter(
            positive: positive.merge(with: other.positive),
            negative: negative.merge(with: other.negative),
            timestamp: timestamp.merge(with: other.timestamp)
        )
    }
}

// MARK: - G-Set (Grow-only Set)

/// Grow-only Set CRDT
public struct GSet<T: Codable & Hashable>: CRDTValue, Codable where T: Sendable {
    public typealias State = Set<T>
    
    public private(set) var elements: Set<T>
    public let timestamp: VectorClock
    public let nodeId: String
    
    public var state: Set<T> { elements }
    
    public init(nodeId: String) {
        self.elements = []
        self.timestamp = VectorClock()
        self.nodeId = nodeId
    }
    
    public init(elements: Set<T>, nodeId: String, timestamp: VectorClock) {
        self.elements = elements
        self.nodeId = nodeId
        self.timestamp = timestamp
    }
    
    /// Add element to set
    public func add(_ element: T) -> GSet<T> {
        var newElements = elements
        newElements.insert(element)
        var newTimestamp = timestamp
        newTimestamp.increment(for: nodeId)
        return GSet(elements: newElements, nodeId: nodeId, timestamp: newTimestamp)
    }
    
    /// Check if set contains element
    public func contains(_ element: T) -> Bool {
        elements.contains(element)
    }
    
    /// Merge with another set (union)
    public func merge(with other: GSet<T>) -> GSet<T> {
        GSet(
            elements: elements.union(other.elements),
            nodeId: nodeId,
            timestamp: timestamp.merge(with: other.timestamp)
        )
    }
}

// MARK: - OR-Set (Observed-Remove Set)

/// Observed-Remove Set CRDT (supports add and remove)
public struct ORSet<T: Codable & Hashable>: CRDTValue, Codable where T: Sendable {
    public typealias State = Set<T>
    
    /// Element with unique tag for tracking
    public struct TaggedElement: Codable, Hashable {
        public let element: T
        public let tag: String
        public let nodeId: String
        
        public init(element: T, tag: String, nodeId: String) {
            self.element = element
            self.tag = tag
            self.nodeId = nodeId
        }
    }
    
    public private(set) var added: Set<TaggedElement>
    public private(set) var removed: Set<TaggedElement>
    public let timestamp: VectorClock
    public let nodeId: String
    
    public var state: Set<T> { elements }
    
    /// Current elements (added - removed)
    public var elements: Set<T> {
        let addedElements = added.filter { !removed.contains($0) }
        return Set(addedElements.map { $0.element })
    }
    
    public init(nodeId: String) {
        self.added = []
        self.removed = []
        self.timestamp = VectorClock()
        self.nodeId = nodeId
    }
    
    public init(added: Set<TaggedElement>, removed: Set<TaggedElement>, nodeId: String, timestamp: VectorClock) {
        self.added = added
        self.removed = removed
        self.nodeId = nodeId
        self.timestamp = timestamp
    }
    
    /// Add element to set
    public func add(_ element: T) -> ORSet<T> {
        let tagged = TaggedElement(element: element, tag: UUID().uuidString, nodeId: nodeId)
        var newAdded = added
        newAdded.insert(tagged)
        var newTimestamp = timestamp
        newTimestamp.increment(for: nodeId)
        return ORSet(added: newAdded, removed: removed, nodeId: nodeId, timestamp: newTimestamp)
    }
    
    /// Remove element from set
    public func remove(_ element: T) -> ORSet<T> {
        let toRemove = added.filter { $0.element == element && !removed.contains($0) }
        var newRemoved = removed
        newRemoved.formUnion(toRemove)
        var newTimestamp = timestamp
        newTimestamp.increment(for: nodeId)
        return ORSet(added: added, removed: newRemoved, nodeId: nodeId, timestamp: newTimestamp)
    }
    
    /// Check if set contains element
    public func contains(_ element: T) -> Bool {
        elements.contains(element)
    }
    
    /// Merge with another set
    public func merge(with other: ORSet<T>) -> ORSet<T> {
        ORSet(
            added: added.union(other.added),
            removed: removed.union(other.removed),
            nodeId: nodeId,
            timestamp: timestamp.merge(with: other.timestamp)
        )
    }
}

// MARK: - LWW-Map (Last-Writer-Wins Map)

/// Last-Writer-Wins Map CRDT
public struct LWWMap<K: Codable & Hashable, V: Codable & Equatable>: CRDTValue, Codable where K: Sendable, V: Sendable {
    public typealias State = [K: V]
    
    public struct Entry: Codable {
        public let value: V
        public let timestamp: VectorClock
        public let wallClockTime: Date
        public let isDeleted: Bool
        
        public init(value: V, timestamp: VectorClock, wallClockTime: Date, isDeleted: Bool = false) {
            self.value = value
            self.timestamp = timestamp
            self.wallClockTime = wallClockTime
            self.isDeleted = isDeleted
        }
    }
    
    public private(set) var entries: [K: Entry]
    public let timestamp: VectorClock
    public let nodeId: String
    
    public var state: [K: V] {
        entries.compactMapValues { $0.isDeleted ? nil : $0.value }
    }
    
    /// Get all keys
    public var keys: [K] {
        Array(state.keys)
    }
    
    /// Get all values
    public var values: [V] {
        Array(state.values)
    }
    
    public init(nodeId: String) {
        self.entries = [:]
        self.timestamp = VectorClock()
        self.nodeId = nodeId
    }
    
    public init(entries: [K: Entry], nodeId: String, timestamp: VectorClock) {
        self.entries = entries
        self.nodeId = nodeId
        self.timestamp = timestamp
    }
    
    /// Get value for key
    public subscript(key: K) -> V? {
        guard let entry = entries[key], !entry.isDeleted else { return nil }
        return entry.value
    }
    
    /// Set value for key
    public func set(_ key: K, value: V) -> LWWMap<K, V> {
        var newEntries = entries
        var newTimestamp = timestamp
        newTimestamp.increment(for: nodeId)
        newEntries[key] = Entry(value: value, timestamp: newTimestamp, wallClockTime: Date())
        return LWWMap(entries: newEntries, nodeId: nodeId, timestamp: newTimestamp)
    }
    
    /// Remove value for key
    public func remove(_ key: K) -> LWWMap<K, V> {
        guard let existing = entries[key] else { return self }
        var newEntries = entries
        var newTimestamp = timestamp
        newTimestamp.increment(for: nodeId)
        newEntries[key] = Entry(value: existing.value, timestamp: newTimestamp, wallClockTime: Date(), isDeleted: true)
        return LWWMap(entries: newEntries, nodeId: nodeId, timestamp: newTimestamp)
    }
    
    /// Merge with another map
    public func merge(with other: LWWMap<K, V>) -> LWWMap<K, V> {
        var merged = entries
        
        for (key, otherEntry) in other.entries {
            if let existingEntry = merged[key] {
                // Take entry with later timestamp
                if existingEntry.timestamp.happenedBefore(otherEntry.timestamp) {
                    merged[key] = otherEntry
                } else if otherEntry.timestamp.happenedBefore(existingEntry.timestamp) {
                    // Keep existing
                } else {
                    // Concurrent - use wall clock
                    if otherEntry.wallClockTime > existingEntry.wallClockTime {
                        merged[key] = otherEntry
                    }
                }
            } else {
                merged[key] = otherEntry
            }
        }
        
        return LWWMap(entries: merged, nodeId: nodeId, timestamp: timestamp.merge(with: other.timestamp))
    }
}
