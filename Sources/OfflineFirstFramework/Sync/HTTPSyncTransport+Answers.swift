import Foundation

/// Reading the server's answers: push outcomes and pages, each change and outcome measured and
/// decoded on its own.
extension HTTPSyncTransport {
    /// How deep a push outcome may nest: the outcome, the change it names as current, and that
    /// change's record.
    private static var maximumOutcomeDepth: Int { OfflineStore<Record>.maximumRecordDepth + 2 }

    /// Unreadable changes of one page that are listed with their record ID and revision, as many
    /// as the store keeps; the others are only counted (``PullResponse/quarantinedCount``).
    static var listedQuarantinePerPage: Int { OfflineStore<Record>.maximumQuarantinedChanges }

    /// A page with more changes that cannot be read is refused. Each one costs a decoding
    /// attempt, and a 16 MiB page holds millions of elements: without the limit such a page
    /// took seconds and gigabytes on every sync. A page of the reference server (1,000 changes
    /// at most) can always be set aside in full.
    static var maximumUnreadableChangesPerPage: Int { 1_000 }

    /// The outcomes of a push answer, each measured and read on its own: one that cannot be
    /// read, also one nested deeper than a record may, leaves only its own change without an
    /// answer; the store retries that change and settles the others. Outcomes for change IDs
    /// that are not in `sent` are skipped without being decoded.
    static func outcomes(from data: Data, for sent: Set<UUID>) throws -> [UUID: PushOutcome<Record>] {
        try JSONLayout.read(data) { answer in
            var result: [UUID: PushOutcome<Record>] = [:]
            var found = false
            try answer.forEachRootMember { key, start in
                guard !found, answer.string(at: key) == "outcomes" else { return try answer.value(at: start).range.upperBound }
                found = true
                return try answer.forEachMember(ofObjectAt: start) { key, start in
                    try Task.checkCancellation()
                    let value = try answer.value(at: start)
                    if value.depth <= maximumOutcomeDepth, let id = answer.string(at: key).flatMap(UUID.init(uuidString:)), sent.contains(id),
                       let outcome = try? answer.decode(WireOutcome.self, at: value.range).pushOutcome() {
                        result[id] = outcome
                    }
                    return value.range.upperBound
                }
            }
            guard found else { throw JSONLayout.missing("outcomes") }
            return result
        }
    }

    /// A page, each change measured and read on its own: one that cannot be read, also one
    /// nested deeper than a record may, is set aside and the rest of the page is used. The first
    /// of two members with the same name counts.
    ///
    /// What an untrusted page costs stays bounded: the page is walked once without being copied,
    /// only the first ``listedQuarantinePerPage`` unreadable changes are listed, a page with more
    /// than ``maximumUnreadableChangesPerPage`` of them is refused with a `DecodingError`, and the
    /// walk stops with `CancellationError` once its task is cancelled, as the store does when a
    /// sync passes ``OfflineStore/Configuration/syncTimeout``.
    static func page(from data: Data) throws -> PullResponse<Record> {
        try page(from: data, settingAsideEveryChange: nil)
    }

    /// The page of one change that is larger than the transport reads, from the outline of the
    /// page (``PageOutline``): the change is set aside with its record ID and revision, and the
    /// page's token moves past it. An outline with more or fewer changes comes from a server that
    /// ignored `limit=1`, or one whose page is too large for another reason.
    static func oversizedPage(from outline: Data, limit: Int) throws -> PullResponse<Record> {
        let reason = "The change is larger than the \(limit) bytes the transport reads (maximumResponseSize)."
        let page = try page(from: outline, settingAsideEveryChange: reason)
        guard page.quarantinedCount == 1 else { throw Failure.responseTooLarge(limit: limit) }
        return page
    }

    /// A page; with `reason`, every change of it is set aside for that reason, unread.
    private static func page(from data: Data, settingAsideEveryChange reason: String?) throws -> PullResponse<Record> {
        try JSONLayout.read(data) { page in
            var changes: [RemoteChange<Record>] = []
            var quarantined: [QuarantinedChange] = []
            var unreadable = 0
            var fields: [String: Range<Int>] = [:]
            try page.forEachRootMember { key, start in
                let name = page.string(at: key) ?? ""
                guard fields[name] == nil else { return try page.value(at: start).range.upperBound }
                switch name {
                case "changes":
                    let end = try page.forEachElement(ofArrayAt: start) { start in
                        try Task.checkCancellation()
                        let (end, element) = try change(in: page, at: start, listing: quarantined.count < listedQuarantinePerPage,
                                                        settingAsideBecause: reason)
                        switch element {
                        case .readable(let change):
                            changes.append(change)
                        case .unreadable(let entry):
                            unreadable += 1
                            guard unreadable <= maximumUnreadableChangesPerPage else {
                                throw JSONLayout.corrupted(
                                    "More than \(maximumUnreadableChangesPerPage) changes of the page cannot be read; the page is refused.")
                            }
                            if let entry { quarantined.append(entry) }
                        }
                        return end
                    }
                    fields[name] = start..<end
                    return end
                case "token", "hasMore", "epoch":
                    let value = try page.value(at: start)
                    fields[name] = value.range
                    return value.range.upperBound
                default:
                    return try page.value(at: start).range.upperBound
                }
            }
            guard fields["changes"] != nil else { throw JSONLayout.missing("changes") }
            guard let hasMore = fields["hasMore"] else { throw JSONLayout.missing("hasMore") }
            return PullResponse(changes: changes, token: try fields["token"].flatMap { try page.decode(String?.self, at: $0) },
                                hasMore: try page.decode(Bool.self, at: hasMore),
                                epoch: try fields["epoch"].flatMap { try page.decode(String?.self, at: $0) }, quarantined: quarantined,
                                quarantinedCount: unreadable)
        }
    }

    /// One change of a page, or why it cannot be used, so one bad record does not make the
    /// whole page, and every later pull, fail. An unreadable change beyond those a page lists
    /// has no entry.
    private enum Change {
        case readable(RemoteChange<Record>)
        case unreadable(QuarantinedChange?)
    }

    /// The change that starts at `start`, walked once for its depth, record ID and revision, and
    /// decoded unless it lacks either of them, one of its fields nests deeper than a record may,
    /// or there is a `reason` to set it aside anyway. Of a change that cannot be used, only the
    /// record ID and the revision are read, each as the type it should have, only when it is not
    /// nested too deeply itself, and only while `listing`. Returns the index after the change.
    private static func change(in page: JSONLayout, at start: Int, listing: Bool,
                               settingAsideBecause reason: String?) throws -> (end: Int, change: Change) {
        guard page.isObject(at: start) else {
            let value = try page.value(at: start)
            return (value.range.upperBound, unreadable(page, reason: "The change is not an object.", recordID: nil, revision: nil,
                                                       listing: listing))
        }
        var deepest = 0
        var recordID: JSONLayout.Value?
        var revision: JSONLayout.Value?
        let end = try page.forEachMember(ofObjectAt: start) { key, start in
            let value = try page.value(at: start)
            deepest = max(deepest, value.depth)
            switch page.string(at: key) {
            case "recordID" where recordID == nil: recordID = value
            case "revision" where revision == nil: revision = value
            default: break
            }
            return value.range.upperBound
        }
        if let reason {
            return (end, unreadable(page, reason: reason, recordID: recordID, revision: revision, listing: listing))
        }
        guard recordID != nil, revision != nil else {
            return (end, unreadable(page, reason: "The change has no recordID or no revision.", recordID: recordID, revision: revision,
                                    listing: listing))
        }
        guard deepest <= OfflineStore<Record>.maximumRecordDepth else {
            let reason = "The change nests objects and arrays deeper than \(OfflineStore<Record>.maximumRecordDepth) levels."
            return (end, unreadable(page, reason: reason, recordID: recordID, revision: revision, listing: listing))
        }
        do {
            return (end, .readable(try page.decode(RemoteChange<Record>.self, at: start..<end)))
        } catch {
            return (end, unreadable(page, reason: describe(error), recordID: recordID, revision: revision, listing: listing))
        }
    }

    private static func unreadable(_ page: JSONLayout, reason: String, recordID: JSONLayout.Value?, revision: JSONLayout.Value?,
                                   listing: Bool) -> Change {
        guard listing else { return .unreadable(nil) }
        func read<T: Decodable>(_ value: JSONLayout.Value?, as type: T.Type) -> T? {
            guard let value, value.depth <= OfflineStore<Record>.maximumRecordDepth else { return nil }
            return try? page.decode(type, at: value.range)
        }
        return .unreadable(QuarantinedChange(recordID: read(recordID, as: Record.ID.self).map(OfflineStore<Record>.describe) ?? "null",
                                             revision: read(revision, as: String.self), reason: reason))
    }

    static func describe(_ error: any Error) -> String {
        guard let error = error as? DecodingError else { return String(describing: error) }
        let context: DecodingError.Context
        switch error {
        case .typeMismatch(_, let found), .valueNotFound(_, let found), .keyNotFound(_, let found), .dataCorrupted(let found):
            context = found
        @unknown default:
            return String(describing: error)
        }
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        return path.isEmpty ? context.debugDescription : "\(path): \(context.debugDescription)"
    }

    private struct WireOutcome: Decodable {
        let status: String
        let revision: String?
        let reason: String?
        let current: RemoteChange<Record>?

        func pushOutcome() throws -> PushOutcome<Record> {
            switch status {
            case "accepted":
                guard let revision else { throw Failure.unknownOutcome("accepted without a revision") }
                return .accepted(revision: revision)
            case "conflict":
                guard let current else { throw Failure.unknownOutcome("conflict without the current record") }
                return .conflict(current: current)
            case "rejected":
                return .rejected(reason: reason ?? "Rejected by the server.", current: current)
            default:
                throw Failure.unknownOutcome(String(status.prefix(100)))
            }
        }
    }
}
