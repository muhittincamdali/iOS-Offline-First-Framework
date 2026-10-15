import Foundation

/// An observed-remove set: elements can be added and removed on any replica, and an add that a
/// replica had not seen when it removed the element survives the merge ("add wins").
///
/// ```swift
/// var tags = ORSet<String>()
/// tags.insert("work")
/// tags.remove("work")
/// tags.merge(with: tagsFromOtherDevice)
/// print(tags.elements)
/// ```
///
/// Every insert gets a random tag, and a remove records the tags it saw. Those removal records
/// are kept so that a later merge with an old copy cannot bring the element back; the set
/// therefore grows with the number of removals, not only with its current size.
public struct ORSet<Element: Hashable & Codable & Sendable>: Mergeable, Codable, Equatable {
    /// The live tags of each element.
    public private(set) var additions: [Element: Set<UUID>]

    /// Tags that were removed.
    public private(set) var removals: Set<UUID>

    /// Creates an empty set.
    public init() {
        additions = [:]
        removals = []
    }

    /// Creates a set that contains `elements`.
    public init<S: Sequence>(_ elements: S) where S.Element == Element {
        self.init()
        for element in elements {
            insert(element)
        }
    }

    /// The elements currently in the set.
    public var elements: Set<Element> {
        Set(additions.keys)
    }

    /// Whether `element` is in the set.
    public func contains(_ element: Element) -> Bool {
        additions[element] != nil
    }

    /// Adds `element` with a new tag.
    public mutating func insert(_ element: Element) {
        additions[element, default: []].insert(UUID())
    }

    /// Removes `element` by recording every tag of it this replica has seen.
    public mutating func remove(_ element: Element) {
        guard let tags = additions.removeValue(forKey: element) else { return }
        removals.formUnion(tags)
    }

    public func merged(with other: ORSet) -> ORSet {
        var result = ORSet()
        result.removals = removals.union(other.removals)
        let all = additions.merging(other.additions) { $0.union($1) }
        for (element, tags) in all {
            let live = tags.subtracting(result.removals)
            if !live.isEmpty {
                result.additions[element] = live
            }
        }
        return result
    }

    private enum CodingKeys: String, CodingKey {
        case additions, removals
    }

    /// Decodes a set and drops tags that are also listed as removed, so a decoded value never
    /// reports an element that its own removals say is gone.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let removals = try container.decode(Set<UUID>.self, forKey: .removals)
        let additions = try container.decode([Element: Set<UUID>].self, forKey: .additions)
        self.removals = removals
        self.additions = additions.compactMapValues { tags in
            let live = tags.subtracting(removals)
            return live.isEmpty ? nil : live
        }
    }
}
