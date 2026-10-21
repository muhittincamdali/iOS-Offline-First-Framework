import Foundation

/// A JSON answer from the sync server, walked part by part in one pass before any part is
/// decoded: the members of an object and the elements of an array, as byte ranges, with how
/// deep each one nests.
///
/// ``HTTPSyncTransport`` decodes each change and each push outcome on its own. One that nests
/// deeper than a record may (``OfflineStore/maximumRecordDepth``) is set aside without being
/// decoded: decoding it, storing it and encoding it again would recurse as deep as it nests, on
/// a stack of 512 KiB. The walk counts brackets instead of calling itself, so no depth exhausts
/// its own stack, and it checks only what it needs to find the parts; the decoder checks each
/// part it decodes. Brackets of the wrong kind inside a part are left to the decoder too.
struct JSONLayout {
    /// A measured value: where it is, and how many objects and arrays it nests, its own
    /// included (0 for a string, number or literal).
    struct Value {
        let range: Range<Int>
        let depth: Int
    }

    private let bytes: UnsafeBufferPointer<UInt8>
    /// Where the JSON text starts, after a UTF-8 byte order mark.
    private let start: Int
    private let decoder = JSONDecoder()

    /// Runs `body` with the document in `data`, without copying it.
    static func read<T>(_ data: Data, _ body: (JSONLayout) throws -> T) throws -> T {
        try data.withUnsafeBytes { raw in
            try body(try JSONLayout(raw.assumingMemoryBound(to: UInt8.self)))
        }
    }

    private init(_ bytes: UnsafeBufferPointer<UInt8>) throws {
        self.bytes = bytes
        start = try Self.contentStart(of: bytes)
    }

    /// Where the JSON text starts: after a UTF-8 byte order mark, which some servers write and
    /// JSON parsers ignore. A document in UTF-16 or UTF-32, with or without a mark, is refused by
    /// name: JSON text starts with an ASCII character, so one of its first two bytes is then zero.
    private static func contentStart(of bytes: UnsafeBufferPointer<UInt8>) throws -> Int {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return 3 }
        if bytes.starts(with: [0xFE, 0xFF]) || bytes.starts(with: [0xFF, 0xFE]) || bytes.prefix(2).contains(0) {
            throw corrupted("The document is in UTF-16 or UTF-32; the sync protocol uses UTF-8.")
        }
        return 0
    }

    // MARK: - Walking

    /// Walks the members of the root object, which only whitespace may surround. `body` gets
    /// each member's key and the index its value starts at, and returns the index after the
    /// value: it measures the value with ``value(at:)`` or walks it.
    func forEachRootMember(_ body: (_ key: Range<Int>, _ valueStart: Int) throws -> Int) throws {
        let end = try forEachMember(ofObjectAt: start, body)
        guard skipWhitespace(from: end) == bytes.count else {
            throw Self.corrupted("The document goes on after its value.")
        }
    }

    /// Walks the members of the object at `start`, as ``forEachRootMember(_:)`` does, and returns
    /// the index after the object.
    func forEachMember(ofObjectAt start: Int, _ body: (_ key: Range<Int>, _ valueStart: Int) throws -> Int) throws -> Int {
        try forEachPart(ofContainerAt: start, open: UInt8(ascii: "{"), close: UInt8(ascii: "}")) { index in
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                throw Self.corrupted("An object member does not start with a key.")
            }
            let key = index..<(try endOfString(from: index))
            let colon = skipWhitespace(from: key.upperBound)
            guard colon < bytes.count, bytes[colon] == UInt8(ascii: ":") else {
                throw Self.corrupted("An object key is not followed by a colon.")
            }
            return try body(key, colon + 1)
        }
    }

    /// Walks the elements of the array at `start`: `body` gets the index each element starts at
    /// and returns the index after it. Returns the index after the array.
    func forEachElement(ofArrayAt start: Int, _ body: (_ elementStart: Int) throws -> Int) throws -> Int {
        try forEachPart(ofContainerAt: start, open: UInt8(ascii: "["), close: UInt8(ascii: "]"), body)
    }

    private func forEachPart(ofContainerAt start: Int, open: UInt8, close: UInt8, _ part: (Int) throws -> Int) throws -> Int {
        var index = skipWhitespace(from: start)
        guard index < bytes.count, bytes[index] == open else {
            throw Self.corrupted("Expected \(Character(UnicodeScalar(open)))…\(Character(UnicodeScalar(close))).")
        }
        index = skipWhitespace(from: index + 1)
        if index < bytes.count, bytes[index] == close { return index + 1 }
        while true {
            index = skipWhitespace(from: try part(index))
            guard index < bytes.count else { throw Self.corrupted("An object or array is not closed.") }
            if bytes[index] == close { return index + 1 }
            guard bytes[index] == UInt8(ascii: ",") else { throw Self.corrupted("Parts are not separated by commas.") }
            index = skipWhitespace(from: index + 1)
        }
    }

    /// The value that starts at `start`, after whitespace: a string, an object or array with
    /// everything it holds, or a number or literal up to the next delimiter, and its depth.
    func value(at start: Int) throws -> Value {
        let index = skipWhitespace(from: start)
        guard index < bytes.count else { throw Self.corrupted("A value is missing.") }
        switch bytes[index] {
        case UInt8(ascii: "\""):
            return Value(range: index..<(try endOfString(from: index)), depth: 0)
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            return try container(at: index)
        default:
            var end = index
            while end < bytes.count, !Self.isDelimiter(bytes[end]) { end += 1 }
            guard end > index else { throw Self.corrupted("A value is missing.") }
            return Value(range: index..<end, depth: 0)
        }
    }

    /// Whether the value at `start`, after whitespace, is an object.
    func isObject(at start: Int) -> Bool {
        let index = skipWhitespace(from: start)
        return index < bytes.count && bytes[index] == UInt8(ascii: "{")
    }

    /// The object or array that starts at `start`, with its depth.
    private func container(at start: Int) throws -> Value {
        var depth = 0
        var deepest = 0
        var index = start
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "\""):
                index = try endOfString(from: index)
                continue
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                deepest = max(deepest, depth)
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                if depth == 0 { return Value(range: start..<(index + 1), depth: deepest) }
            default:
                break
            }
            index += 1
        }
        throw Self.corrupted("An object or array is not closed.")
    }

    /// The index after the closing quote of the string that starts at `start`.
    private func endOfString(from start: Int) throws -> Int {
        var index = start + 1
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "\\"): index += 2
            case UInt8(ascii: "\""): return index + 1
            default: index += 1
            }
        }
        throw Self.corrupted("A string is not closed.")
    }

    private func skipWhitespace(from start: Int) -> Int {
        var index = start
        while index < bytes.count, Self.isWhitespace(bytes[index]) { index += 1 }
        return index
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
    }

    private static func isDelimiter(_ byte: UInt8) -> Bool {
        isWhitespace(byte) || byte == UInt8(ascii: ",") || byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]")
            || byte == UInt8(ascii: ":")
    }

    // MARK: - Decoding

    /// Decodes the part at `range`.
    func decode<T: Decodable>(_ type: T.Type, at range: Range<Int>) throws -> T {
        try decoder.decode(type, from: Data(UnsafeBufferPointer(rebasing: bytes[range])))
    }

    /// The string at `range`, such as a member's key, or `nil` when it is not one. A string
    /// without escapes is read without the decoder, so walking many members stays cheap.
    func string(at range: Range<Int>) -> String? {
        guard range.count >= 2, bytes[range.lowerBound] == UInt8(ascii: "\"") else { return nil }
        let inner = UnsafeBufferPointer(rebasing: bytes[(range.lowerBound + 1)..<(range.upperBound - 1)])
        guard inner.contains(UInt8(ascii: "\\")) else { return String(decoding: inner, as: UTF8.self) }
        return try? decode(String.self, at: range)
    }

    static func missing(_ name: String) -> DecodingError {
        DecodingError.keyNotFound(Key(stringValue: name), DecodingError.Context(codingPath: [], debugDescription: "No value for “\(name)”."))
    }

    /// A broken structure, reported as the decoder would.
    static func corrupted(_ description: String) -> DecodingError {
        DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: description))
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
