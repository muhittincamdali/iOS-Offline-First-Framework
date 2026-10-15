/// A last-writer-wins register: a single value where the write with the newest timestamp wins.
///
/// ```swift
/// var title = LWWRegister("Groceries", timestamp: try clock.tick())
/// title.set("Weekend groceries", timestamp: try clock.tick())
/// title.merge(with: titleFromOtherDevice)
/// ```
///
/// Timestamps come from a ``HybridLogicalClock``, which never hands out the same timestamp
/// twice, so two different writes cannot tie.
public struct LWWRegister<Value: Codable & Sendable & Equatable>: Mergeable, Codable, Equatable {
    /// The current value.
    public private(set) var value: Value

    /// The timestamp of the write that produced ``value``.
    public private(set) var timestamp: HLCTimestamp

    /// Creates a register holding `value`, written at `timestamp`.
    public init(_ value: Value, timestamp: HLCTimestamp) {
        self.value = value
        self.timestamp = timestamp
    }

    /// Writes `value` if `timestamp` is newer than the current one; older writes are ignored.
    public mutating func set(_ value: Value, timestamp: HLCTimestamp) {
        guard timestamp > self.timestamp else { return }
        self.value = value
        self.timestamp = timestamp
    }

    /// Keeps the write with the newer timestamp.
    public func merged(with other: LWWRegister) -> LWWRegister {
        other.timestamp > timestamp ? other : self
    }
}

/// A map whose keys are last-writer-wins registers: concurrent writes to different keys both
/// survive, and for the same key the newest write wins. Removing a key is a write too, so a
/// newer removal beats an older value and a newer value beats an older removal.
public struct LWWMap<Key: Hashable & Codable & Sendable, Value: Codable & Sendable & Equatable>: Mergeable, Codable, Equatable {
    /// Every key that was ever written, with its value or `nil` when it was removed.
    public private(set) var registers: [Key: LWWRegister<Value?>]

    /// Creates an empty map.
    public init() {
        registers = [:]
    }

    /// The current value for `key`, or `nil` when it is absent or removed.
    public subscript(key: Key) -> Value? {
        registers[key]?.value ?? nil
    }

    /// The keys that currently have a value.
    public var keys: Set<Key> {
        Set(registers.compactMap { $0.value.value == nil ? nil : $0.key })
    }

    /// The keys and values that are currently present.
    public var values: [Key: Value] {
        registers.compactMapValues { $0.value }
    }

    /// Writes `value` for `key` at `timestamp`; an older write than the current one is ignored.
    public mutating func set(_ value: Value, forKey key: Key, timestamp: HLCTimestamp) {
        write(value, forKey: key, timestamp: timestamp)
    }

    /// Removes `key` at `timestamp`; an older removal than the current write is ignored.
    public mutating func removeValue(forKey key: Key, timestamp: HLCTimestamp) {
        write(nil, forKey: key, timestamp: timestamp)
    }

    /// Merges the register of every key.
    public func merged(with other: LWWMap) -> LWWMap {
        var result = self
        result.registers.merge(other.registers) { $0.merged(with: $1) }
        return result
    }

    private mutating func write(_ value: Value?, forKey key: Key, timestamp: HLCTimestamp) {
        if var register = registers[key] {
            register.set(value, timestamp: timestamp)
            registers[key] = register
        } else {
            registers[key] = LWWRegister(value, timestamp: timestamp)
        }
    }
}
