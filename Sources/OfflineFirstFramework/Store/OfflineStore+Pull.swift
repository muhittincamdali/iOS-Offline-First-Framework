import Foundation

/// Pulling server changes page by page.
extension OfflineStore {
    /// What one step of a pull stores: its pages in order, each with the token it answers, and
    /// how their epoch stands.
    struct PullStep {
        var pages: [(token: String?, response: PullResponse<Record>)]
        var standing: EpochStanding
    }

    func pull(using transport: any SyncTransport<Record>, until deadline: ContinuousClock.Instant,
              report: inout SyncReport) async throws {
        // The tokens this sync has pulled with since it last started from the beginning.
        var requested: Set<String> = []
        // A sync checks one epoch other than the store's; see nextStep(using:until:checkedEpoch:).
        var checkedEpoch = false
        for _ in 0..<configuration.maximumPullPages {
            try Task.checkCancellation()
            let generation = tokenGeneration
            let step = try await nextStep(using: transport, until: deadline, checkedEpoch: &checkedEpoch)
            // The token was reset while a request was on its way (discardChange(for:),
            // resetChangeToken()): the pages belong to the old position, so they are dropped and
            // the pull starts again from the beginning.
            guard generation == tokenGeneration else {
                checkedEpoch = false
                continue
            }
            for (index, page) in step.pages.enumerated() {
                if let token = page.token { requested.insert(token) } else { requested.removeAll() }
                // A page is checked before it is stored, so a broken one changes nothing.
                try Self.checkProgress(of: page.response, after: page.token, requested: requested)
                try store(page.response, startingHistory: index == 0 && step.standing.startsHistory,
                          isLaterEpoch: step.standing == .later, report: &report)
            }
            guard step.pages.last?.response.hasMore == true else { return }
        }
        report.hasMoreChanges = true
    }

    /// The pages of the next step after the store's token.
    ///
    /// A page that names a later epoch than the store's (``EpochStanding/later``) is believed
    /// only when a second request of the other kind reports the same epoch: a pull from the
    /// beginning after a pull with the token, or a pull with the first page's token after a pull
    /// from the beginning. An earlier epoch (``EpochStanding/earlier`` or
    /// ``EpochStanding/retired``) is refused even then, in every sync. A stale cache or replica,
    /// or another deployment behind the same URL, rarely answers both, and a shared cache answers
    /// the pull from the beginning first, since every device asks for the same URL. Both
    /// requests belong to the same step, so a sync that may fetch one page still gets there.
    ///
    /// When the second request reports the store's own epoch, the first page came from
    /// somewhere else: it is dropped, and the step asks with the store's token once more. Every
    /// other disagreement fails the sync with ``OfflineFirstError/invalidServerResponse(_:)``,
    /// without a change to the store, and a sync checks one such epoch at most: a pull either
    /// moves forward or fails, instead of spending its pages on requests it drops.
    private func nextStep(using transport: any SyncTransport<Record>, until deadline: ContinuousClock.Instant,
                          checkedEpoch: inout Bool) async throws -> PullStep {
        let token = state.token
        let first = try await page(after: token, using: transport, until: deadline)
        let standing = try Self.standing(of: first.epoch, in: state)
        guard standing.namesAnotherEpoch, let epoch = first.epoch else {
            return PullStep(pages: [(token, first)], standing: standing)
        }
        guard !checkedEpoch else {
            throw OfflineFirstError.invalidServerResponse("The server's epoch changed twice during one sync.")
        }
        checkedEpoch = true
        let secondToken = token == nil ? first.token : nil
        let second = try await page(after: secondToken, using: transport, until: deadline)
        if second.epoch == epoch {
            if standing.isRefused { throw Self.refusal(of: epoch, standing) }
            // After a token of the old history the first page is dropped; the pull starts over
            // from the beginning of the new one.
            if token == nil, secondToken != nil {
                return PullStep(pages: [(token, first), (secondToken, second)], standing: standing)
            }
            return PullStep(pages: [(nil, second)], standing: standing)
        }
        guard try Self.standing(of: second.epoch, in: state) == .current else {
            throw Self.disagreement(epoch, second.epoch)
        }
        let third = try await page(after: token, using: transport, until: deadline)
        guard try Self.standing(of: third.epoch, in: state) == .current else {
            throw Self.disagreement(third.epoch, second.epoch)
        }
        return PullStep(pages: [(token, third)], standing: .current)
    }

    /// One page after `token`, with its length and the length of its token checked.
    private func page(after token: String?, using transport: any SyncTransport<Record>,
                      until deadline: ContinuousClock.Instant) async throws -> PullResponse<Record> {
        let response = try await Self.run(until: deadline) { try await transport.pull(since: token) }
        if let next = response.token, next.utf8.count > Self.maximumRevisionLength {
            throw OfflineFirstError.invalidServerResponse("The change token has more than \(Self.maximumRevisionLength) bytes.")
        }
        let count = response.changes.count + response.quarantined.count
        guard count <= Self.maximumChangesPerPage else {
            throw OfflineFirstError.invalidServerResponse(
                "The page holds \(count) changes; a page may hold \(Self.maximumChangesPerPage) at most.")
        }
        return response
    }

    private static func disagreement(_ epoch: String?, _ other: String?) -> OfflineFirstError {
        func describe(_ epoch: String?) -> String { epoch.map { "“\($0.prefix(100))”" } ?? "none" }
        return OfflineFirstError.invalidServerResponse(
            "Two pulls of one sync named the server epochs \(describe(epoch)) and \(describe(other)), as a cache or another deployment that answers some requests would.")
    }

    /// Stores a checked page: its epoch, its changes and its token.
    private func store(_ response: PullResponse<Record>, startingHistory: Bool, isLaterEpoch: Bool,
                       report: inout SyncReport) throws {
        try update { state in
            if startingHistory {
                Self.beginHistory(epoch: response.epoch, isLaterEpoch: isLaterEpoch, in: &state)
            } else if let epoch = response.epoch {
                // The store's epoch, or the first one the server reports (a new store, an update
                // of the server).
                state.serverEpoch = epoch
            }
            for change in response.quarantined {
                Self.quarantine(change, in: &state, report: &report)
            }
            // Changes the transport only counted.
            report.quarantined += response.quarantinedCount - response.quarantined.count
            for change in response.changes {
                try applyRemote(change, to: &state, report: &report)
            }
            Self.pruneTombstones(in: &state, limit: configuration.maximumTombstones)
            // A page without a token keeps the previous one.
            state.token = response.token ?? state.token
        }
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
            entry.pushedInHistory = nil
            if let sequence = change.sequence {
                entry.sequence = sequence
                entry.minimumSequence = nil
                entry.olderRevisions = []
            }
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
            // The pending change itself: the server applied it, although no answer said so. A
            // version kept back for it came earlier in the pull, so it is older, unless the
            // server's sequences say otherwise.
            entry.rememberOwnWrite(changeID: pending.changeID, timestamp: entry.timestamp)
            let taken = entry.deferredRemote.flatMap { isOlder(change, than: $0) ? $0 : nil } ?? change
            Self.store(Self.entry(from: taken, replacing: entry, in: &state, configuration: configuration), in: &state)
            return
        case .earlierWrite:
            // The device's own earlier write: the pending change was made on top of it, so it is
            // not a conflict. The change's earlier versions in doubt stay known: a page out of
            // order, or the first page of a new epoch, may list this write before a newer one
            // of them, and only a push answer settles them.
            entry.rememberOwnWrite(changeID: change.changeID, timestamp: change.timestamp)
            // A change in doubt learns from its next push where it stands; this version is
            // older than it, so it is not kept back either.
            guard !pending.isInDoubt else {
                state.entries[change.recordID] = entry
                return
            }
            // A change of the current history goes out on this revision. One of an earlier
            // history keeps the version back like any other, below.
            if entry.history == state.history {
                Self.base(&entry, on: change, in: state, configuration: configuration)
                entry.pending = renewed(pending)
                state.entries[change.recordID] = entry
                return
            }
        case .other:
            break
        }
        // A change whose push may have been applied waits for its next push, which learns its
        // fate under the same change ID; resolving it here could put it back over this version.
        // The version is kept, since the token moves past it: if the push shows the change was
        // applied, this newer version replaces it.
        //
        // A change made on an earlier server history waits for its push too: the server's
        // conflict answer says what it holds now. The store believes a later epoch on two
        // answers of one sync, which a source that answers both requests passes; its version
        // would make the resolver weigh the edit against a copy the server may no longer hold.
        // The device's own earlier write, for a change of an earlier history, waits the same way.
        //
        // And so does a change that meets a version without a sequence: nothing tells whether
        // it is newer than the version the change is based on or a stale copy (a page out of
        // order, a lagging replica), and a timestamp does not, since a device clock wrote it.
        // Resolved here, a stale copy could make the resolver drop an edit the server never
        // saw; the push's conflict answer names the server's current version instead.
        if pending.isInDoubt || entry.history != state.history || change.sequence == nil {
            let keepsDeferred = entry.deferredRemote.map { $0.revision == change.revision || isOlder(change, than: $0) }
            if keepsDeferred != true { entry.deferredRemote = change }
            state.entries[change.recordID] = entry
            return
        }
        // Changed on the device and on the server: a conflict for the resolver.
        report.pulled += 1
        report.conflicts += 1
        Self.store(try resolve(entry, against: change, in: &state, pushesInThisSync: nil, report: &report), in: &state)
    }
}
