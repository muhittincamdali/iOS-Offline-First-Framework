import Foundation

/// Finds the parts of a JSON document without reading their values: the members of an object
/// and the elements of an array, as byte ranges.
///
/// `JSONDecoder` refuses a whole document when any part of it nests deeper than 512 levels, so
/// one deep record would make a whole page, or a whole push answer, unreadable. The layout lets
/// ``HTTPSyncTransport`` decode each change and each outcome on its own instead. It counts
/// brackets rather than calling itself, so no depth can exhaust the stack, and it checks only
/// what it needs to find the parts: the decoder checks each part.
enum JSONLayout {
    struct Member {
        /// The key, a JSON string with its quotes.
        let key: Range<Int>
        let value: Range<Int>
    }

    /// The document's structure is broken where the layout needs it.
    struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    /// The value the document consists of; only whitespace may surround it.
    static func root(of bytes: [UInt8]) throws -> Range<Int> {
        let range = try value(in: bytes, from: try contentStart(of: bytes))
        guard skipWhitespace(in: bytes, from: range.upperBound) == bytes.count else {
            throw Failure(description: "The document goes on after its value.")
        }
        return range
    }

    /// Where the JSON text starts: after a UTF-8 byte order mark, which some servers write and
    /// JSON parsers ignore. A document in UTF-16 or UTF-32, with or without a mark, is refused by
    /// name: JSON text starts with an ASCII character, so one of its first two bytes is then zero.
    static func contentStart(of bytes: [UInt8]) throws -> Int {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return 3 }
        if bytes.starts(with: [0xFE, 0xFF]) || bytes.starts(with: [0xFF, 0xFE]) || bytes.prefix(2).contains(0) {
            throw Failure(description: "The document is in UTF-16 or UTF-32; the sync protocol uses UTF-8.")
        }
        return 0
    }

    /// The members of the object at `range`, in order.
    static func members(of bytes: [UInt8], in range: Range<Int>) throws -> [Member] {
        var members: [Member] = []
        try parts(of: bytes, in: range, open: UInt8(ascii: "{"), close: UInt8(ascii: "}")) { index in
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else {
                throw Failure(description: "An object member does not start with a key.")
            }
            let key = try value(in: bytes, from: index)
            let colon = skipWhitespace(in: bytes, from: key.upperBound)
            guard colon < bytes.count, bytes[colon] == UInt8(ascii: ":") else {
                throw Failure(description: "An object key is not followed by a colon.")
            }
            let member = Member(key: key, value: try value(in: bytes, from: colon + 1))
            members.append(member)
            return member.value.upperBound
        }
        return members
    }

    /// The elements of the array at `range`, in order.
    static func elements(of bytes: [UInt8], in range: Range<Int>) throws -> [Range<Int>] {
        var elements: [Range<Int>] = []
        try parts(of: bytes, in: range, open: UInt8(ascii: "["), close: UInt8(ascii: "]")) { index in
            let element = try value(in: bytes, from: index)
            elements.append(element)
            return element.upperBound
        }
        return elements
    }

    /// Walks the comma-separated parts between `open` and `close`; `part` reads one part that
    /// starts at the given index and returns where it ends.
    private static func parts(of bytes: [UInt8], in range: Range<Int>, open: UInt8, close: UInt8,
                              _ part: (Int) throws -> Int) throws {
        guard !range.isEmpty, bytes[range.lowerBound] == open, bytes[range.upperBound - 1] == close else {
            throw Failure(description: "Expected \(Character(UnicodeScalar(open)))…\(Character(UnicodeScalar(close))).")
        }
        let end = range.upperBound - 1
        var index = skipWhitespace(in: bytes, from: range.lowerBound + 1)
        guard index < end else { return }
        while true {
            index = skipWhitespace(in: bytes, from: try part(index))
            guard index < end else { return }
            guard bytes[index] == UInt8(ascii: ",") else {
                throw Failure(description: "Parts are not separated by commas.")
            }
            index = skipWhitespace(in: bytes, from: index + 1)
        }
    }

    /// The value that starts at `start`, after whitespace: a string, an object or array with
    /// everything it holds, or a number or literal up to the next delimiter.
    static func value(in bytes: [UInt8], from start: Int) throws -> Range<Int> {
        let index = skipWhitespace(in: bytes, from: start)
        guard index < bytes.count else { throw Failure(description: "A value is missing.") }
        switch bytes[index] {
        case UInt8(ascii: "\""):
            return index..<(try endOfString(in: bytes, from: index))
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            return index..<(try endOfContainer(in: bytes, from: index))
        default:
            var end = index
            while end < bytes.count, !isDelimiter(bytes[end]) { end += 1 }
            guard end > index else { throw Failure(description: "A value is missing.") }
            return index..<end
        }
    }

    /// The index after the closing quote of the string that starts at `start`.
    private static func endOfString(in bytes: [UInt8], from start: Int) throws -> Int {
        var index = start + 1
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "\\"): index += 2
            case UInt8(ascii: "\""): return index + 1
            default: index += 1
            }
        }
        throw Failure(description: "A string is not closed.")
    }

    /// The index after the bracket that closes the object or array that starts at `start`.
    private static func endOfContainer(in bytes: [UInt8], from start: Int) throws -> Int {
        var depth = 0
        var index = start
        while index < bytes.count {
            switch bytes[index] {
            case UInt8(ascii: "\""):
                index = try endOfString(in: bytes, from: index)
                continue
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
            case UInt8(ascii: "}"), UInt8(ascii: "]"):
                depth -= 1
                if depth == 0 { return index + 1 }
            default:
                break
            }
            index += 1
        }
        throw Failure(description: "An object or array is not closed.")
    }

    private static func skipWhitespace(in bytes: [UInt8], from start: Int) -> Int {
        var index = start
        while index < bytes.count, isWhitespace(bytes[index]) { index += 1 }
        return index
    }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
    }

    private static func isDelimiter(_ byte: UInt8) -> Bool {
        isWhitespace(byte) || byte == UInt8(ascii: ",") || byte == UInt8(ascii: "}") || byte == UInt8(ascii: "]")
            || byte == UInt8(ascii: ":")
    }
}

/// A JSON answer whose parts are found by ``JSONLayout`` and decoded one by one.
struct WireDocument {
    let bytes: [UInt8]
    let root: Range<Int>
    private let decoder = JSONDecoder()

    init(_ data: Data) throws {
        let bytes = [UInt8](data)
        self.bytes = bytes
        root = try Self.reading { try JSONLayout.root(of: bytes) }
    }

    /// The value of the root object's member `name`; the first one when it appears twice.
    func member(_ name: String) throws -> Range<Int>? {
        try members(of: root).first { (try? decode(String.self, at: $0.key)) == name }?.value
    }

    func members(of range: Range<Int>) throws -> [JSONLayout.Member] {
        try Self.reading { try JSONLayout.members(of: bytes, in: range) }
    }

    func elements(of range: Range<Int>) throws -> [Range<Int>] {
        try Self.reading { try JSONLayout.elements(of: bytes, in: range) }
    }

    func decode<T: Decodable>(_ type: T.Type, at range: Range<Int>) throws -> T {
        try decoder.decode(type, from: Data(bytes[range]))
    }

    static func missing(_ name: String) -> DecodingError {
        DecodingError.keyNotFound(Key(stringValue: name), DecodingError.Context(codingPath: [], debugDescription: "No value for “\(name)”."))
    }

    /// Reports a broken structure as the decoder would.
    private static func reading<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch let failure as JSONLayout.Failure {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: failure.description))
        }
    }

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
