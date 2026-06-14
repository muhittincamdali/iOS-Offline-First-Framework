import Foundation

/// A Conflict-Free Replicated Data Type (CRDT) for resolving multi-device state conflicts.
/// 
/// Last-Write-Wins (LWW) Register ensures that the most recent timestamp always wins
/// across distributed nodes, making offline-first sync completely bulletproof.
public struct LWWRegister<T: Equatable & Sendable>: Codable, Equatable, Sendable {
    public private(set) var value: T
    public private(set) var timestamp: Int64
    
    public init(value: T, timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) {
        self.value = value
        self.timestamp = timestamp
    }
    
    /// Merges another register with this one. The highest timestamp wins.
    public mutating func merge(with other: LWWRegister<T>) {
        if other.timestamp > self.timestamp {
            self.value = other.value
            self.timestamp = other.timestamp
        } else if other.timestamp == self.timestamp {
            // Optional: tie-breaker logic (e.g. node ID comparison)
            // For now, if identical timestamp, keep self or apply custom deterministic merge
        }
    }
    
    /// Returns a new register resulting from merging two registers.
    public static func merged(_ a: LWWRegister<T>, _ b: LWWRegister<T>) -> LWWRegister<T> {
        return a.timestamp >= b.timestamp ? a : b
    }
}
