import Foundation

/// Reads the body of a server's answer as its bytes stream in, and stops as soon as the body
/// cannot be used, so a server cannot make the transport download more than it would keep.
///
/// It reads at most `maximumResponseSize` bytes, and stops before the first byte when the
/// answer announces more (`Content-Length`). For a page it follows the bytes with a
/// ``PageScanner`` and stops at the start of the change after the `limit` the request asked
/// for. While outlining, it keeps only the outline of the page and reads at most
/// ``outlineReadFactor`` times `maximumResponseSize`: a change up to that size can be set aside,
/// and one that never ends, or a page that never closes, costs that much and no more.
struct ResponseReader {
    /// Why the reader stopped.
    enum Stop: Error, Equatable {
        /// The body is longer than the reader reads or keeps.
        case tooLarge
        /// The page holds more changes than its request asked for.
        case tooManyChanges
    }

    /// How many times the response limit an outline reads.
    static let outlineReadFactor = 4

    /// What was kept: the body, or the outline of the page.
    private(set) var body = Data()
    /// How many bytes were read.
    private(set) var bytesRead = 0

    private let readLimit: Int
    private let keptLimit: Int
    private let changeLimit: Int?
    private let outlining: Bool
    private var scanner = PageScanner()

    /// - Parameters:
    ///   - expectedLength: The length the answer announces, or a negative number.
    ///   - maximumResponseSize: The most bytes kept, and the most read unless `outlining`.
    ///   - changeLimit: For a page, the most changes its request asked for; `nil` for any
    ///     other body, which is kept as it is.
    ///   - outlining: Whether to keep only the outline of the page.
    init(expectedLength: Int64, maximumResponseSize: Int, changeLimit: Int?, outlining: Bool) throws(Stop) {
        let outlineLimit = maximumResponseSize.multipliedReportingOverflow(by: Self.outlineReadFactor)
        readLimit = outlining && changeLimit != nil ? (outlineLimit.overflow ? .max : outlineLimit.partialValue) : maximumResponseSize
        keptLimit = maximumResponseSize
        self.changeLimit = changeLimit
        self.outlining = outlining && changeLimit != nil
        guard expectedLength <= Int64(readLimit) else { throw .tooLarge }
    }

    /// Reads the next byte of the body.
    mutating func read(_ byte: UInt8) throws(Stop) {
        bytesRead += 1
        guard bytesRead <= readLimit else { throw .tooLarge }
        guard let changeLimit else {
            body.append(byte)
            return
        }
        let kept = scanner.scan(byte)
        guard scanner.changesStarted <= changeLimit else { throw .tooManyChanges }
        guard outlining else {
            body.append(byte)
            return
        }
        switch kept {
        case .byte: body.append(byte)
        case .null: body.append(contentsOf: Self.null)
        case .nothing: break
        }
        guard body.count <= keptLimit else { throw .tooLarge }
    }

    private static let null = Array("null".utf8)
}

/// Follows a page as its bytes stream in, with a few bytes of state: how many changes of the
/// page's `changes` array have started, and what the outline of the page keeps of each byte.
///
/// In the outline every object or array inside a change (its record, its timestamp) becomes
/// `null` and everything else stays. It still names the change's record ID and revision and the
/// page's token, so ``HTTPSyncTransport`` can set a change that is too large to load aside and
/// move past it while holding a few hundred bytes instead of the change.
///
/// The count covers the elements of every array that is the value of a root member named
/// `changes`, the name written without escapes; the walk of the page (``JSONLayout``) checks
/// the page again as it reads it.
struct PageScanner {
    /// What the outline keeps of a byte.
    enum Kept: Equatable {
        /// The byte itself.
        case byte
        /// `null` in place of the object or array the byte opens.
        case null
        /// Nothing: the byte is inside an object or array that is left out.
        case nothing
    }

    /// The elements of the page's list of changes that have started.
    private(set) var changesStarted = 0

    /// Objects and arrays deeper than this are left out of the outline: the page, its list of
    /// changes, and a change are kept.
    private static let keptDepth = 3
    private static let changesKey = Array("changes".utf8)

    private var depth = 0
    /// The depth of the object or array being left out, while one is.
    private var omitted: Int?
    private var inString = false
    private var escaped = false
    /// The first bytes of the string being read at the root, or of the last one read there: the
    /// key of the value that follows.
    private var rootString: [UInt8] = []
    /// Whether the array being read at depth 2 is a list of changes.
    private var inChanges = false
    /// Whether the next byte of the list that is not whitespace starts a change.
    private var awaitingChange = false

    mutating func scan(_ byte: UInt8) -> Kept {
        if inString {
            if escaped {
                escaped = false
            } else if byte == UInt8(ascii: "\\") {
                escaped = true
            } else if byte == UInt8(ascii: "\"") {
                inString = false
                return kept
            }
            if depth == 1, rootString.count <= Self.changesKey.count { rootString.append(byte) }
            return kept
        }
        if awaitingChange, !Self.isWhitespace(byte), byte != UInt8(ascii: "]") {
            changesStarted += 1
            awaitingChange = false
        }
        switch byte {
        case UInt8(ascii: "\""):
            inString = true
            if depth == 1 { rootString.removeAll(keepingCapacity: true) }
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            depth += 1
            if depth == 2 {
                inChanges = byte == UInt8(ascii: "[") && rootString == Self.changesKey
                awaitingChange = inChanges
            }
            if omitted == nil, depth > Self.keptDepth {
                omitted = depth
                return .null
            }
        case UInt8(ascii: "}"), UInt8(ascii: "]"):
            depth -= 1
            if depth < 2 {
                inChanges = false
                awaitingChange = false
            }
            if let level = omitted {
                if depth < level { omitted = nil }
                return .nothing
            }
        case UInt8(ascii: ","):
            if inChanges, depth == 2 { awaitingChange = true }
        default:
            break
        }
        return kept
    }

    private var kept: Kept { omitted == nil ? .byte : .nothing }

    private static func isWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09
    }
}
