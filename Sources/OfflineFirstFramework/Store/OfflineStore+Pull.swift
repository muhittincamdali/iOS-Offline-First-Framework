import Foundation

/// Pulling server changes page by page.
extension OfflineStore {
    func pull(using transport: any SyncTransport<Record>, until deadline: ContinuousClock.Instant,
              report: inout SyncReport) async throws {
        var historyChanged = false
        // The tokens this sync has pulled with since it last started from the beginning.
        var requested: Set<String> = []
        // A later epoch a page reported, until a pull from the beginning reports it too.
        var unconfirmed: String?
        for _ in 0..<configuration.maximumPullPages {
            try Task.checkCancellation()
            let token = unconfirmed == nil ? state.token : nil
            if let token { requested.insert(token) } else if unconfirmed == nil { requested.removeAll() }
            let generation = tokenGeneration
            let response = try await Self.run(until: deadline) { try await transport.pull(since: token) }
            // The token was reset while the request was on its way (discardChange(for:),
            // resetChangeToken()): the page belongs to the old position, so it is dropped and the
            // pull starts again from the beginning.
            guard generation == tokenGeneration else {
                unconfirmed = nil
                continue
            }
            if let next = response.token, next.utf8.count > Self.maximumRevisionLength {
                throw OfflineFirstError.invalidServerResponse("The change token has more than \(Self.maximumRevisionLength) bytes.")
            }
            guard let startsHistory = try startsHistory(with: response, unconfirmed: &unconfirmed) else { continue }
            if startsHistory {
                guard !historyChanged else {
                    throw OfflineFirstError.invalidServerResponse("The server's epoch changed twice during one sync.")
                }
                historyChanged = true
                requested.removeAll()
                if token != nil {
                    // The page answers a token of the old history; start over from the beginning.
                    try update { Self.beginHistory(epoch: response.epoch, in: &$0) }
                    continue
                }
            }
            // A page is checked before it is stored, so a broken one changes nothing.
            try Self.checkProgress(of: response, after: token, requested: requested)
            try update { state in
                if startsHistory {
                    Self.beginHistory(epoch: response.epoch, in: &state)
                } else if let epoch = response.epoch {
                    // The store's epoch, or the first one the server reports (a new store, an
                    // update of the server): an earlier epoch refused before is no longer current.
                    state.serverEpoch = epoch
                    state.epochRefusal = nil
                    state.takesNextEpoch = false
                }
                for change in response.quarantined {
                    Self.quarantine(change, in: &state, report: &report)
                }
                for change in response.changes {
                    try applyRemote(change, to: &state, report: &report)
                }
                Self.pruneTombstones(in: &state, limit: configuration.maximumTombstones)
                // A page without a token keeps the previous one.
                state.token = response.token ?? state.token
            }
            guard response.hasMore else { return }
        }
        report.hasMoreChanges = true
    }

    /// Whether `response` starts a new server history, or `nil` when the page is dropped and the
    /// pull goes on. A later epoch counts once a pull from the beginning reports it too; until
    /// then `unconfirmed` holds it. An earlier epoch is refused (``takeOrRefuse(_:)``).
    private func startsHistory(with response: PullResponse<Record>, unconfirmed: inout String?) throws -> Bool? {
        let standing = try Self.standing(of: response.epoch, in: state)
        guard let epoch = response.epoch, standing != .current, standing != .first else {
            // A later epoch that the pull from the beginning does not report again came from
            // somewhere else (another deployment behind the same URL, a misdirected request):
            // the store stays in its history and goes on after its own token.
            guard unconfirmed == nil else {
                unconfirmed = nil
                return nil
            }
            return false
        }
        switch standing {
        case .later:
            guard let waiting = unconfirmed else {
                unconfirmed = epoch
                return nil
            }
            guard waiting == epoch else {
                throw OfflineFirstError.invalidServerResponse("The server's epoch changed twice during one sync.")
            }
        case .earlier:
            try takeOrRefuse(epoch)
        case .other, .current, .first:
            break
        }
        unconfirmed = nil
        return true
    }

    /// Throws when a page that says more changes follow would not move the pull forward: it
    /// has no token, the same one, or one this sync pulled with before (the tokens go round in
    /// a circle), which would repeat pages up to the page limit on every sync.
    private static func checkProgress(of response: PullResponse<Record>, after token: String?, requested: Set<String>) throws {
        guard response.hasMore else { return }
        guard let next = response.token, next != token else {
            throw OfflineFirstError.pullTokenDidNotAdvance(token: token)
        }
        guard !requested.contains(next) else {
            throw OfflineFirstError.invalidServerResponse(
                "The server sent the change token “\(next.prefix(100))” a second time in one sync, so the pull would go round in circles.")
        }
    }

    private func applyRemote(_ change: RemoteChange<Record>, to state: inout State, report: inout SyncReport) throws {
        // A change that cannot be used is set aside and reported; the rest of the page goes on.
        if let reason = Self.inconsistency(of: change, for: change.recordID) {
            Self.quarantine(QuarantinedChange(recordID: Self.describe(change.recordID), revision: change.revision, reason: reason),
                            in: &state, report: &report)
            return
        }
        if !state.quarantine.isEmpty {
            let recordID = Self.describe(change.recordID)
            state.quarantine.removeAll { $0.recordID == recordID }
        }
        receive(change, in: &state)
        guard var entry = state.entries[change.recordID] else {
            // A deletion is kept as a tombstone too, so an older version of the record that
            // arrives later (a page out of order) does not bring it back.
            if change.record != nil { report.pulled += 1 }
            Self.store(Self.entry(from: change, replacing: nil, in: &state, configuration: configuration), in: &state)
            return
        }
        // The same revision is the same version (a server never reuses one): the echo of a change
        // this store pushed, or a record the server kept across a restart. It may tell where the
        // version stands.
        guard entry.revision != change.revision else {
            entry.history = state.history
            if let sequence = change.sequence {
                entry.sequence = sequence
                entry.minimumSequence = nil
                entry.olderRevisions = []
            }
            entry.serverTimestamp = Self.orderable(change.timestamp, below: Self.driftLimit(of: state, configuration: configuration))
            state.entries[change.recordID] = entry
            return
        }
        // A server version older than the one the store holds (a page out of order, a lagging
        // replica, the earlier version of a deleted record) is skipped: the server already has
        // something newer, and it comes in its turn.
        guard !isStale(change, comparedWith: entry, in: state) else { return }
        guard let pending = entry.pending else {
            report.pulled += 1
            Self.store(Self.entry(from: change, replacing: entry, in: &state, configuration: configuration), in: &state)
            return
        }
        switch authorship(of: change, comparedWith: entry) {
        case .pendingChange:
            // The pending change itself: the server applied it, although no answer said so.
            Self.store(Self.entry(from: newer(entry.deferredRemote, than: change, in: state), replacing: entry, in: &state,
                                  configuration: configuration), in: &state)
            return
        case .earlierWrite:
            // The device's own earlier write: the pending change was made on top of it. A
            // change in doubt learns from its next push where it stands; one that is not goes
            // out on this revision.
            guard !pending.isInDoubt else { return }
            Self.base(&entry, on: change, in: state, configuration: configuration)
            entry.pending = rebased(pending)
            state.entries[change.recordID] = entry
            return
        case .other:
            break
        }
        // A change whose push may have been applied waits for its next push, which learns its
        // fate under the same change ID; resolving it here could put it back over this version.
        // The version is kept, since the token moves past it: if the push shows the change was
        // applied, this newer version replaces it.
        if pending.isInDoubt {
            if let deferred = entry.deferredRemote, deferred.revision == change.revision || isOlder(change, than: deferred, in: state) {
                return
            }
            entry.deferredRemote = change
            state.entries[change.recordID] = entry
            return
        }
        // Changed on the device and on the server: a conflict for the resolver.
        report.pulled += 1
        report.conflicts += 1
        Self.store(try resolve(entry, against: change, in: &state, pushesInThisSync: nil, report: &report), in: &state)
    }
}
