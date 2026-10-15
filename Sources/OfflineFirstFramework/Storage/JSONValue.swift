/// A JSON value, used to rewrite stored records in a ``RecordMigration``.
///
/// Whole numbers decode as ``integer(_:)`` so 64-bit identifiers keep every digit; other
/// numbers decode as ``double(_:)``.
public enum JSONValue: Hashable, Codable, Sendable {
    /// `null`.
    case null
    /// `true` or `false`.
    case bool(Bool)
    /// A whole number that fits in 64 bits.
    case integer(Int64)
    /// Any other number.
    case double(Double)
    /// A string.
    case string(String)
    /// An array.
    case array([JSONValue])
    /// An object.
    case object([String: JSONValue])

    /// Decodes any JSON value.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// Encodes the value as the JSON it holds.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// The member `key` of an object, or `nil` for other values. Setting a member of a value
    /// that is not an object does nothing.
    public subscript(key: String) -> JSONValue? {
        get {
            guard case .object(let members) = self else { return nil }
            return members[key]
        }
        set {
            guard case .object(var members) = self else { return }
            members[key] = newValue
            self = .object(members)
        }
    }

    /// The string, or `nil` for other values.
    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    /// The number as a `Double`, or `nil` for other values.
    public var doubleValue: Double? {
        switch self {
        case .integer(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral, ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral, ExpressibleByNilLiteral {
    /// Creates a ``string(_:)``.
    public init(stringLiteral value: String) { self = .string(value) }
    /// Creates an ``integer(_:)``.
    public init(integerLiteral value: Int64) { self = .integer(value) }
    /// Creates a ``double(_:)``.
    public init(floatLiteral value: Double) { self = .double(value) }
    /// Creates a ``bool(_:)``.
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    /// Creates an ``array(_:)``.
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    /// Creates an ``object(_:)``; for a repeated key the last value wins.
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
    }
    /// Creates ``null``.
    public init(nilLiteral: ()) { self = .null }
}
