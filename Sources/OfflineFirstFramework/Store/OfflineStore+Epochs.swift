import Foundation

/// Server histories: which one a page belongs to, and when the store believes a new one.
///
/// A server reports a later ``PullResponse/epoch`` whenever its history may have changed, and
/// never an earlier one again (see <doc:ServerProtocol>). A page that names an earlier epoch
/// comes from a stale replica or cache, and its versions would roll records back; a page that
/// names a later one comes from a server that restarted or was restored, or from somewhere else
/// behind the same URL (another deployment, a misdirected request). The store therefore believes
/// an epoch, or that the pages name none, only when two requests of different kinds in one sync
/// report it (a pull with the token and a pull from the beginning), and never takes an earlier
/// one, however many requests or syncs report it: a server whose data really went back,
/// restored from a backup, reports a new epoch, later than every one before.
///
/// That holds for the first page of a new store as well. Taken from one request, a page from
/// another deployment would bring records the server never held, a token for the pull to go
/// on after, and sequences that make the server's own versions look older; and a later epoch on
/// it would make the store refuse every page of its real server. The store holds an epoch, or
/// none, once two requests reported it (``State/epochIsConfirmed``). A page that names no
/// epoch, once two requests reported the store's, belongs to no history the store knows: a
/// server that reports epochs reports one on every page. It is refused like an earlier epoch, so
/// one page from another deployment cannot bring revisions, sequences and a token of its own
/// into the store's history.
///
/// A store file from before this check may hold an epoch only one request reported. Its next
/// sync checks that epoch like another one. When two requests report an earlier epoch or none
/// instead, the store cannot tell which of the two came from its server, and refusing the pages
/// of the server would lock the store out for good: such an epoch, or the lack of one, starts a
/// new history (``EpochStanding/replacing``), and the epoch the store held is not retired. A
/// later epoch starts one as always. Either way the records without a pending change that the
/// unchecked history brought go, since they may come from another deployment; the server's
/// pages bring its own again. And once a history without an epoch replaced one, an epoch that
/// two requests report again starts a new history too, instead of going on after the token of
/// the history without one, which may be another deployment's.
///
/// Epochs go one way. An epoch the store left for a later one is retired: the store keeps the
/// last ``maximumRetiredEpochs`` of them in its file, ``OfflineStore/resetChangeToken()`` keeps
/// them and the store's own epoch, and a page that names an earlier epoch is refused in every
/// sync. A stale replica or a shared cache that answers both requests of a sync with an earlier
/// epoch, as one does after a reset, when every device asks for the same URLs, or one that
/// sticks to a device for many syncs, therefore cannot take the store back.
extension OfflineStore {
    /// The epochs a store remembers having left for a later one: 32, the oldest dropped first.
    static var maximumRetiredEpochs: Int { 32 }

    /// How the epoch of a page relates to the store's history.
    enum EpochStanding: Equatable {
        /// The page names the store's own epoch, or no epoch while the store holds none, and two
        /// requests reported it.
        case current
        /// The page names the store's own epoch, or no epoch while the store holds none, and no
        /// two requests reported it yet: a new store, or a store file from before the check.
        /// Taken once a second request reports it too; it does not start a history.
        case unconfirmed
        /// The first epoch the store hears of: the first page of a new store, a server that just
        /// started to report epochs, or another server. Taken once a second request reports it
        /// too. It does not start a history, so the pull goes on after the store's token.
        case first
        /// A later epoch than the store's: the server's history changed.
        case later
        /// An epoch, or none, that replaces one the store cannot go by: an earlier epoch, or no
        /// epoch, while no two requests reported the store's (a store file from before the
        /// check), whose epoch may have come from another deployment behind the same URL; or an
        /// epoch after a history without one replaced the store's. Once a second request reports
        /// it too, it starts a new history; the store's epoch is not retired.
        case replacing
        /// The page names no epoch although the store holds one that two requests reported. A
        /// server that reports epochs reports one on every page (see <doc:ServerProtocol>), so
        /// the page comes from somewhere else behind the same URL: another deployment, a server
        /// of an older version, a proxy or cache that answers for it. Its revisions, sequences
        /// and token belong to no history the store knows, so it is never taken.
        case missing
        /// An earlier epoch than the store's that the store never held: a stale replica or cache
        /// of a history between two the store saw, or a server whose epochs do not grow. It is
        /// never taken.
        case earlier
        /// An epoch the store left for a later one: a stale replica or cache answered. It is
        /// never taken.
        case retired

        /// Whether a page of this epoch, once a second request confirmed it, starts a new server
        /// history.
        var startsHistory: Bool {
            self == .later || self == .replacing
        }

        /// Whether a page of this epoch is never stored.
        var isRefused: Bool {
            self == .earlier || self == .retired || self == .missing
        }
    }

    static func standing(of epoch: String?, in state: State) throws -> EpochStanding {
        if let epoch, epoch.utf8.count > maximumRevisionLength {
            throw OfflineFirstError.invalidServerResponse("The epoch has more than \(maximumRevisionLength) bytes.")
        }
        if epoch == state.serverEpoch { return state.epochIsConfirmed ? .current : .unconfirmed }
        if let epoch, state.retiredEpochs.contains(epoch) { return .retired }
        guard let known = state.serverEpoch else { return state.hasHeldEpoch ? .replacing : .first }
        if let epoch, isLater(epoch, than: known) { return .later }
        guard state.epochIsConfirmed else { return .replacing }
        return epoch == nil ? .missing : .earlier
    }

    /// The order of epochs: a longer one is later; of two as long, the one that is greater byte
    /// by byte. Counters, with or without leading zeros, and times in fixed-width digits grow
    /// in this order.
    static func isLater(_ epoch: String, than other: String) -> Bool {
        let (bytes, otherBytes) = (Array(epoch.utf8), Array(other.utf8))
        guard bytes.count == otherBytes.count else { return bytes.count > otherBytes.count }
        return otherBytes.lexicographicallyPrecedes(bytes)
    }

    /// The error for two requests of one sync that both reported `epoch`, which the store
    /// refuses (``EpochStanding/isRefused``).
    static func refusal(of epoch: String?, _ standing: EpochStanding, in state: State) -> OfflineFirstError {
        guard let epoch else {
            let held = state.serverEpoch.map { "“\($0.prefix(100))”" } ?? "one"
            return OfflineFirstError.invalidServerResponse(
                "The server answered without an epoch although it reported the epoch \(held) before, as another deployment behind the same URL would; a server that reports epochs reports one on every page.")
        }
        let name = "“\(epoch.prefix(100))”"
        guard standing == .retired else {
            return OfflineFirstError.invalidServerResponse(
                "The server answered from an earlier history (epoch \(name)) than the store's, as a stale replica or cache would; a server's epochs only grow.")
        }
        return OfflineFirstError.invalidServerResponse(
            "The server answered from the epoch \(name), which the store left for a later one, as a stale replica or cache would.")
    }

    /// Why a new server history starts.
    enum HistoryChange: Equatable {
        /// Two requests reported a later epoch than the store's (``EpochStanding/later``).
        case laterEpoch
        /// Two requests reported an epoch, or none, in place of one the store cannot go by
        /// (``EpochStanding/replacing``).
        case replacement
        /// The transport names another server (``SyncTransport/serverIdentity``).
        case anotherServer
    }

    /// Starts a new server history: the server lost or replaced its data, or the store talks to
    /// another server. The token goes, so the next pull starts from the beginning. Entries keep
    /// their revisions (a pending change still names its base) but belong to the old history:
    /// the server's current versions replace the ones without a pending change whatever their
    /// timestamps say, and a pending change learns where it stands from its push's answer.
    ///
    /// A later epoch retires the store's previous one. And a version that a push answer brought
    /// and no pull has brought since (``StoredEntry/pushedInHistory``) moves into the later
    /// history with what the store knows about its order. The sync pushes before it pulls, so
    /// the server may have answered after its restart: a page of the new epoch from before that
    /// answer (a shared cache, a lagging replica) would otherwise roll back the store's accepted
    /// write, or the version a conflict answer brought, and the next edit would be resolved
    /// against the device's own write.
    ///
    /// A history no two requests reported (a store file from before the check) may be another
    /// deployment's. When pages start the next one, its entries without a pending change go, and
    /// none moves into the next history; the pull from the beginning brings the server's versions.
    ///
    /// Two requests reported the new history's epoch, or that it has none, unless the store
    /// talks to another server: then its first page is checked like a new store's, and that
    /// server's first epoch is a first one again.
    static func beginHistory(epoch: String?, _ change: HistoryChange, in state: inout State) {
        let previous = state.history
        let leavesUncheckedHistory = change != .anotherServer && !state.epochIsConfirmed
        if change == .laterEpoch, let left = state.serverEpoch, left != epoch {
            state.retiredEpochs.removeAll { $0 == left }
            state.retiredEpochs.append(left)
            state.retiredEpochs.removeFirst(max(0, state.retiredEpochs.count - maximumRetiredEpochs))
        }
        state.history &+= 1
        state.serverEpoch = epoch
        state.epochIsConfirmed = change != .anotherServer
        state.hasHeldEpoch = change == .anotherServer ? false : state.hasHeldEpoch || epoch != nil
        state.token = nil
        state.quarantine.removeAll()
        for (id, entry) in state.entries where entry.history == previous || entry.deferredRemote != nil {
            if leavesUncheckedHistory, entry.pending == nil, entry.history == previous {
                state.entries[id] = nil
                continue
            }
            let keepsPosition = change == .laterEpoch && !leavesUncheckedHistory && entry.pushedInHistory != nil
                && entry.history == previous
            guard entry.deferredRemote != nil || keepsPosition else { continue }
            state.entries[id]?.deferredRemote = nil
            if keepsPosition { state.entries[id]?.history = state.history }
        }
    }
}
