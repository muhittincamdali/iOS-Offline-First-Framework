import Foundation

/// An earlier epoch than the store's that syncs in a row refused, and how many.
struct EpochRefusal: Codable, Hashable, Sendable {
    var epoch: String
    var syncs: Int
}

/// Server histories: which one a page belongs to, and when the store believes a new one.
///
/// A server reports a later ``PullResponse/epoch`` whenever its history may have changed, and
/// never an earlier one again. A page that names an earlier epoch comes from a stale replica or
/// cache, and its versions would roll records back; a page that names a later one comes from a
/// server that restarted or was restored, or from somewhere else behind the same URL (another
/// deployment, a misdirected request). The store therefore believes another epoch than its own
/// only when two requests of different kinds in one sync report it (a pull with the token and a
/// pull from the beginning), takes a later one then, and refuses an earlier one until the syncs
/// in a row that met it reach ``maximumEpochRefusals``; after
/// ``OfflineStore/resetChangeToken()`` it takes any other epoch the two requests report.
extension OfflineStore {
    /// Syncs in a row that meet the same earlier epoch until the store takes it as the server's
    /// history: the last of them takes it, the ones before refuse it. A server whose epochs went
    /// back (the store took a later one from elsewhere, or the server's epochs do not grow) is
    /// followed again after that many syncs without ``OfflineStore/resetChangeToken()``; a stale
    /// replica or cache rarely answers that many syncs in a row, both with and without a token.
    static var maximumEpochRefusals: Int { 8 }

    /// How the epoch of a page relates to the store's history.
    enum EpochStanding: Equatable {
        /// The page names no epoch or the store's own.
        case current
        /// The first epoch the store hears of: a new store, a server that just started to report
        /// epochs, or another server.
        case first
        /// A later epoch than the store's: the server's history changed.
        case later
        /// An earlier epoch than the store's: a stale replica or cache answered, or the store
        /// took a later epoch from elsewhere before.
        case earlier
        /// After ``OfflineStore/resetChangeToken()``, another epoch than the store's, whatever
        /// its order.
        case other

        /// Whether a page of this epoch, once believed, starts a new server history.
        var startsHistory: Bool {
            self == .later || self == .earlier || self == .other
        }
    }

    static func standing(of epoch: String?, in state: State) throws -> EpochStanding {
        guard let epoch else { return .current }
        guard epoch.utf8.count <= maximumRevisionLength else {
            throw OfflineFirstError.invalidServerResponse("The epoch has more than \(maximumRevisionLength) bytes.")
        }
        guard let known = state.serverEpoch else { return .first }
        if epoch == known { return .current }
        if state.takesNextEpoch { return .other }
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

    /// Counts a sync in which two requests reported `epoch`, earlier than the store's, and
    /// returns when the store now takes it: in the ``maximumEpochRefusals``th sync in a row.
    /// Otherwise the refusal is written to the file and thrown.
    func takeOrRefuse(_ epoch: String) throws {
        let previous = state.epochRefusal?.epoch == epoch ? state.epochRefusal?.syncs ?? 0 : 0
        guard previous + 1 < Self.maximumEpochRefusals else { return }
        try update { $0.epochRefusal = EpochRefusal(epoch: epoch, syncs: previous + 1) }
        throw OfflineFirstError.invalidServerResponse(
            "The server answered from an earlier history (epoch “\(epoch.prefix(100))”) than the store's, as a stale replica or cache would.")
    }

    /// Starts a new server history: the server lost or replaced its data, or the store talks to
    /// another server. The token goes, so the next pull starts from the beginning. Entries keep
    /// their revisions (a pending change still names its base) but belong to the old history:
    /// the server's current versions replace them whatever their timestamps say.
    ///
    /// With `keepingPushAnswers`, for a later epoch of the same server, a version that a push
    /// answer brought and no pull has brought since (``StoredEntry/pushedInHistory``) moves into
    /// the new history with what the store knows about its order. The sync pushes before it
    /// pulls, so the server may have answered after its restart: a page of the new epoch
    /// from before that answer (a shared cache, a lagging replica) would otherwise roll back the
    /// store's accepted write, or the version a conflict answer brought, and the next edit
    /// would be resolved against the device's own write.
    static func beginHistory(epoch: String?, keepingPushAnswers: Bool, in state: inout State) {
        let previous = state.history
        state.history &+= 1
        state.serverEpoch = epoch
        state.token = nil
        state.quarantine.removeAll()
        state.epochRefusal = nil
        state.takesNextEpoch = false
        for (id, entry) in state.entries {
            let keepsPosition = keepingPushAnswers && entry.pushedInHistory != nil && entry.history == previous
            guard entry.deferredRemote != nil || keepsPosition else { continue }
            state.entries[id]?.deferredRemote = nil
            if keepsPosition { state.entries[id]?.history = state.history }
        }
    }
}
