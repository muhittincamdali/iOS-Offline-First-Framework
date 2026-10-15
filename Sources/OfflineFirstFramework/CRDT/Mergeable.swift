/// A value that two replicas can change independently and merge without a conflict.
///
/// The types in this module that conform (``LWWRegister``, ``GCounter``, ``PNCounter``,
/// ``ORSet`` and ``LWWMap``) are conflict-free replicated data types (CRDTs): their merge is
/// commutative (`a.merged(with: b) == b.merged(with: a)`), associative and idempotent
/// (`a.merged(with: a) == a`), so every replica that has seen the same changes ends up with the
/// same value, whatever order the changes arrived in.
///
/// Use them as fields of a record and merge records field by field with
/// ``ConflictResolver/merge(_:)``.
public protocol Mergeable: Sendable {
    /// Returns the combination of this value and `other`.
    func merged(with other: Self) -> Self
}

extension Mergeable {
    /// Replaces this value with its combination with `other`.
    public mutating func merge(with other: Self) {
        self = merged(with: other)
    }
}
