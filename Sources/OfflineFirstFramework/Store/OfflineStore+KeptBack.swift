import Foundation

/// The rule every push answer follows for a version a pull kept back while its change was in
/// doubt (``StoredEntry/deferredRemote``).
///
/// A pull leaves a change in doubt to its next push, and keeps the server versions it brings
/// meanwhile. The push's answer then decides: accepted, a conflict or a rejection, it names the
/// version the record is at now. The kept-back version takes that version's place only when the
/// server's sequences show it is newer. A repeated push is answered from the server's memory of
/// change IDs, with what was current then, so a version pulled since may be newer; but the pull
/// may as well have come from a stale replica or cache, and a timestamp, which a device clock
/// wrote, tells nothing. When nothing tells, the answer stands, and the next sync pulls from the
/// beginning (``State/pullsFromBeginning``): that brings the server's current version, if it is
/// another one, without taking a stale page over the answer. Not in the same sync, whose pull may
/// go to the replica or cache the kept-back version came from.
extension OfflineStore {
    /// How a version a pull kept back stands against the version a push answer names.
    enum KeptBackOrder: Equatable {
        /// Nothing was kept back, or the same version.
        case none
        /// The server's sequences show the kept-back version is older.
        case older
        /// The server's sequences show the kept-back version is newer.
        case newer
        /// Nothing tells which of the two is newer.
        case unknown
    }

    /// How `deferred` stands against `answered`, the entry based on the version a push answer
    /// names: the version a conflict answer or a rejection brings, or the device's write the
    /// server accepted.
    ///
    /// An accepted write has no sequence of its own until its echo arrives, but the server
    /// applied it while the version it was based on was current (see <doc:ServerProtocol>): a
    /// version after that one (``StoredEntry/minimumSequence``) was written after the write, one
    /// up to it, or one the write's earlier versions replaced (``StoredEntry/olderRevisions``),
    /// before.
    func order(ofKeptBack deferred: RemoteChange<Record>?, against answered: StoredEntry<Record>, in state: State) -> KeptBackOrder {
        guard let deferred, deferred.revision != answered.revision else { return .none }
        if isNewer(deferred, than: answered) { return .newer }
        if isStale(deferred, comparedWith: answered, in: state) { return .older }
        return .unknown
    }

    /// `answered`, or the version `deferred` in its place when the server's sequences show it is
    /// newer. When nothing tells, `answered` stays and the next sync pulls from the beginning.
    func weigh(keptBack deferred: RemoteChange<Record>?, against answered: StoredEntry<Record>,
               in state: inout State) -> StoredEntry<Record> {
        switch order(ofKeptBack: deferred, against: answered, in: state) {
        case .newer:
            guard let deferred else { return answered }
            return Self.entry(from: deferred, replacing: answered, in: &state, configuration: configuration)
        case .unknown:
            state.pullsFromBeginning = true
            return answered
        case .none, .older:
            return answered
        }
    }
}
