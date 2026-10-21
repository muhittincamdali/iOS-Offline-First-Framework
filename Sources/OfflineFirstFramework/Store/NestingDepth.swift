import Foundation

/// Measures how deep a value nests objects and arrays when it is encoded, without building
/// JSON, and stops as soon as it is deeper than a limit.
///
/// `JSONEncoder` and `JSONDecoder` call themselves once per level, on the stack of the task that
/// syncs: 512 KiB on the threads of Swift concurrency on Apple platforms, where a record nested
/// about 180 levels (360 levels of JSON) ends the process with a stack overflow when the store
/// file is written, in debug and release builds alike. The store therefore measures every record
/// that comes into it, from a save, a pull or a push answer, before it is encoded. The
/// measurement calls the record's own `encode(to:)`, which recurses too, but stops once the
/// limit is passed.
enum NestingDepth {
    /// Whether `value` encodes as JSON that nests objects and arrays deeper than `limit` levels,
    /// its own object or array counting as one, as the reference server counts.
    static func exceeds(_ value: some Encodable, limit: Int) -> Bool {
        let probe = Probe(limit: limit)
        do {
            try probe.measure(value, at: 0)
        } catch {
            // Only Probe.TooDeep stops the measurement early. Any other error of the value's own
            // encoding is for the encoder to report when the store writes the value.
        }
        return probe.isTooDeep
    }
}

private final class Probe {
    struct TooDeep: Error {}

    let limit: Int
    private(set) var isTooDeep = false

    init(limit: Int) {
        self.limit = limit
    }

    /// A container opens at `level`; past the limit, every later call throws.
    func open(_ level: Int) -> Int {
        if level > limit { isTooDeep = true }
        return level
    }

    func check() throws {
        if isTooDeep { throw TooDeep() }
    }

    /// Encodes `value` inside `level` containers. Values that `JSONEncoder` writes as a string or
    /// a number are leaves; their own `Encodable` conformance would nest (`Data` as an array of
    /// bytes, `URL` and `Decimal` as objects) or call this again for the same value.
    func measure(_ value: some Encodable, at level: Int) throws {
        try check()
        if Self.isLeaf(value) { return }
        try value.encode(to: DepthEncoder(probe: self, depth: level))
        try check()
    }

    private static func isLeaf(_ value: Any) -> Bool {
        value is String || value is Bool || value is any BinaryInteger || value is any BinaryFloatingPoint || value is Data
            || value is URL || value is Decimal || value is Date
    }
}

/// Encodes a value that sits inside `depth` containers.
private struct DepthEncoder: Encoder {
    let probe: Probe
    let depth: Int
    var codingPath: [any CodingKey] { [] }
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        KeyedEncodingContainer(KeyedDepth<Key>(probe: probe, level: probe.open(depth + 1)))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        UnkeyedDepth(probe: probe, level: probe.open(depth + 1))
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        SingleDepth(probe: probe, depth: depth)
    }
}

/// The generic `encode` also stands for every primitive requirement of the container protocols.
private struct KeyedDepth<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let probe: Probe
    let level: Int
    var codingPath: [any CodingKey] { [] }

    mutating func encodeNil(forKey key: Key) throws { try probe.check() }

    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws { try probe.measure(value, at: level) }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    mutating func encode(_ value: Int128, forKey key: Key) throws { try probe.check() }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    mutating func encode(_ value: UInt128, forKey key: Key) throws { try probe.check() }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type,
                                                        forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        KeyedEncodingContainer(KeyedDepth<NestedKey>(probe: probe, level: probe.open(level + 1)))
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        UnkeyedDepth(probe: probe, level: probe.open(level + 1))
    }

    mutating func superEncoder() -> any Encoder { DepthEncoder(probe: probe, depth: level) }

    mutating func superEncoder(forKey key: Key) -> any Encoder { DepthEncoder(probe: probe, depth: level) }
}

private struct UnkeyedDepth: UnkeyedEncodingContainer {
    let probe: Probe
    let level: Int
    var codingPath: [any CodingKey] { [] }
    private(set) var count = 0

    init(probe: Probe, level: Int) {
        self.probe = probe
        self.level = level
    }

    mutating func encodeNil() throws {
        try probe.check()
        count += 1
    }

    mutating func encode<T: Encodable>(_ value: T) throws {
        try probe.measure(value, at: level)
        count += 1
    }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    mutating func encode(_ value: Int128) throws { try encodeNil() }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    mutating func encode(_ value: UInt128) throws { try encodeNil() }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        count += 1
        return KeyedEncodingContainer(KeyedDepth<NestedKey>(probe: probe, level: probe.open(level + 1)))
    }

    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        count += 1
        return UnkeyedDepth(probe: probe, level: probe.open(level + 1))
    }

    mutating func superEncoder() -> any Encoder {
        count += 1
        return DepthEncoder(probe: probe, depth: level)
    }
}

private struct SingleDepth: SingleValueEncodingContainer {
    let probe: Probe
    let depth: Int
    var codingPath: [any CodingKey] { [] }

    mutating func encodeNil() throws { try probe.check() }

    mutating func encode<T: Encodable>(_ value: T) throws { try probe.measure(value, at: depth) }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    mutating func encode(_ value: Int128) throws { try probe.check() }

    @available(macOS 15.0, iOS 18.0, tvOS 18.0, watchOS 11.0, visionOS 2.0, *)
    mutating func encode(_ value: UInt128) throws { try probe.check() }
}
