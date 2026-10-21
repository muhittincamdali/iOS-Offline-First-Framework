import Foundation

/// Server histories: which one a page belongs to, and when the store believes a new one.
///
/// A server reports a later ``PullResponse/epoch`` whenever its history may have changed, and
/// never an earlier one again (see <doc:ServerProtocol>). A page that names an earlier epoch
/// comes from a stale replica or cache, and its versions would roll records back; a page that
/// names a later one comes from a server that restarted or was restored, or from somewhere else
/// behind the same URL (another deployment, a misdirected request). The store therefore takes a
/// later epoch only when two requests of different kinds in one sync report it (a pull with the
/// token and a pull from the beginning), and never takes an earlier one, however many requests
/// or syncs report it: a server whose data really went back, restored from a backup, reports a
/// new epoch, later than every one before.
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
        /// The page names no epoch or the store's own.
        case current
        /// The first epoch the store hears of: a new store, a server that just started to report
        /// epochs, or another server.
        case first
        /// A later epoch than the store's: the server's history changed.
        case later
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
            self == .later
        }

        /// Whether a page of this epoch is never stored.
        var isRefused: Bool {
            self == .earlier || self == .retired
        }

        /// Whether a page of this epoch has to be checked by a second request of the sync.
        var namesAnotherEpoch: Bool {
            startsHistory || isRefused
        }
    }

    static func standing(of epoch: String?, in state: State) throws -> EpochStanding {
        guard let epoch else { return .current }
        guard epoch.utf8.count <= maximumRevisionLength else {
            throw OfflineFirstError.invalidServerResponse("The epoch has more than \(maximumRevisionLength) bytes.")
        }
        if epoch == state.serverEpoch { return .current }
        if state.retiredEpochs.contains(epoch) { return .retired }
        guard let known = state.serverEpoch else { return .first }
        return isLater(epoch, than: known) ? .later : .earlier
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
    static func refusal(of epoch: String, _ standing: EpochStanding) -> OfflineFirstError {
        let name = "“\(epoch.prefix(100))”"
        guard standing == .retired else {
            return OfflineFirstError.invalidServerResponse(
                "The server answered from an earlier history (epoch \(name)) than the store's, as a stale replica or cache would; a server's epochs only grow.")
        }
        return OfflineFirstError.invalidServerResponse(
            "The server answered from the epoch \(name), which the store left for a later one, as a stale replica or cache would.")
    }

    /// Starts a new server history: the server lost or replaced its data, or the store talks to
    /// another server. The token goes, so the next pull starts from the beginning. Entries keep
    /// their revisions (a pending change still names its base) but belong to the old history:
    /// the server's current versions replace the ones without a pending change whatever their
    /// timestamps say, and a pending change learns where it stands from its push's answer.
    ///
    /// `isLaterEpoch` is true for a later epoch of the same server and false for another server
    /// (``SyncTransport/serverIdentity``). A later epoch retires the store's previous one. And a
    /// version that a push answer brought and no pull has brought since
    /// (``StoredEntry/pushedInHistory``) moves into the later history with what the store knows
    /// about its order. The sync pushes before it pulls, so the server may have answered after its
    /// restart: a page of the new epoch from before that answer (a shared cache, a lagging
    /// replica) would otherwise roll back the store's accepted write, or the version a conflict
    /// answer brought, and the next edit would be resolved against the device's own write.
    static func beginHistory(epoch: String?, isLaterEpoch: Bool, in state: inout State) {
        let previous = state.history
        if isLaterEpoch, let left = state.serverEpoch, left != epoch {
            state.retiredEpochs.removeAll { $0 == left }
            state.retiredEpochs.append(left)
            state.retiredEpochs.removeFirst(max(0, state.retiredEpochs.count - maximumRetiredEpochs))
        }
        state.history &+= 1
        state.serverEpoch = epoch
        state.token = nil
        state.quarantine.removeAll()
        for (id, entry) in state.entries {
            let keepsPosition = isLaterEpoch && entry.pushedInHistory != nil && entry.history == previous
            guard entry.deferredRemote != nil || keepsPosition else { continue }
            state.entries[id]?.deferredRemote = nil
            if keepsPosition { state.entries[id]?.history = state.history }
        }
    }
}
