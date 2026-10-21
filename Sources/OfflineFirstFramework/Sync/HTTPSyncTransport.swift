import Foundation

/// A ``SyncTransport`` that speaks a small JSON protocol over HTTP.
///
/// Point it at a server that implements two endpoints (the documentation article "Server
/// protocol" describes them, and `Examples/SyncServer` is a working server in about 200 lines
/// of JavaScript):
///
/// - `POST <baseURL>/push` with `{"changes": [...]}`, answered with `{"outcomes": {...}}`.
/// - `GET <baseURL>/changes?since=<token>&limit=<n>`, answered with
///   `{"changes": [...], "token": "...", "hasMore": false, "epoch": "..."}`.
///
/// ```swift
/// let transport = HTTPSyncTransport<Note>(
///     baseURL: URL(string: "https://api.example.com/sync/notes")!,
///     headers: { ["Authorization": "Bearer \(try await session.token())"] }
/// )
/// let store = try OfflineStore<Note>(name: "notes", transport: transport)
/// ```
///
/// Any answer outside 200–299 throws ``Failure/unexpectedStatus(code:body:)``, so the store
/// retries the changes with its ``RetryPolicy``. Responses are read up to
/// ``maximumResponseSize`` bytes; a larger one is cancelled instead of being loaded, at once
/// when it announces its length. A push is split into requests of at most
/// ``maximumRequestSize`` bytes, and a request is halved while the server answers it with
/// status 413 or with more than ``maximumResponseSize``. A pull asks for ``pageSize`` changes
/// and, while the page is larger than that, for half as many; a single change that is larger on
/// its own, up to four times ``maximumResponseSize``, is set aside in
/// ``OfflineStore/quarantinedChanges()`` and the pull moves past it. A page with more changes
/// than the pull asked for is cancelled as soon as the change after the limit starts, and
/// refused.
public struct HTTPSyncTransport<Record: SyncableRecord>: SyncTransport {
    /// Errors of the HTTP transport.
    public enum Failure: Error, Equatable, Sendable, LocalizedError {
        /// The server answered with a status outside 200–299.
        case unexpectedStatus(code: Int, body: String)
        /// The response was longer than the limit.
        case responseTooLarge(limit: Int)
        /// The response was not an HTTP response.
        case notHTTP
        /// The push answer used an outcome status other than accepted, conflict or rejected.
        ///
        /// No longer thrown: an outcome that cannot be read counts as a missing answer for its
        /// change only, so the other changes of the push are still settled.
        case unknownOutcome(String)

        public var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let code, let body):
                body.isEmpty ? "The sync server answered with status \(code)." : "The sync server answered with status \(code): \(body)"
            case .responseTooLarge(let limit):
                "The sync server's response was longer than \(limit) bytes."
            case .notHTTP:
                "The sync server's response was not an HTTP response."
            case .unknownOutcome(let status):
                "The sync server answered a change with the unknown status “\(status)”."
            }
        }
    }

    /// The URL the `push` and `changes` paths are added to.
    public let baseURL: URL

    /// The session that sends the requests.
    public let session: URLSession

    /// The longest response, in bytes, that is read. Default: 16 MiB. To set aside a single change
    /// that is larger, the pull reads its page without what the change holds, up to four times
    /// this size.
    public let maximumResponseSize: Int

    /// The longest push request body, in bytes. A push of more changes is sent in several
    /// requests, one after the other; a change that is larger on its own is sent alone. Default:
    /// 1 MiB, the limit of the reference server.
    public let maximumRequestSize: Int

    /// The most changes a pull asks for (the `limit` of the request), from 1 to 1,000. Default:
    /// 100, the reference server's page size.
    public let pageSize: Int

    private let headers: @Sendable () async throws -> [String: String]

    /// The base URL: a store opened with a transport for another URL pulls everything again.
    public var serverIdentity: String? {
        baseURL.absoluteString
    }

    /// Creates a transport.
    ///
    /// - Parameters:
    ///   - baseURL: The sync endpoint of one collection, for example
    ///     `https://api.example.com/sync/notes`.
    ///   - session: The URL session. Default: `URLSession.shared`.
    ///   - maximumResponseSize: The longest response that is read, in bytes.
    ///   - maximumRequestSize: The longest push request body, in bytes.
    ///   - pageSize: The most changes a pull asks for.
    ///   - headers: Extra headers for each request, such as an `Authorization` header. Called
    ///     before every request, so it can refresh a token.
    public init(
        baseURL: URL,
        session: URLSession = .shared,
        maximumResponseSize: Int = 16 * 1024 * 1024,
        maximumRequestSize: Int = 1024 * 1024,
        pageSize: Int = 100,
        headers: @escaping @Sendable () async throws -> [String: String] = { [:] }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.maximumResponseSize = max(1, maximumResponseSize)
        self.maximumRequestSize = max(1, maximumRequestSize)
        self.pageSize = min(max(1, pageSize), OfflineStore<Record>.maximumChangesPerPage)
        self.headers = headers
    }

    /// Pushes `changes` in requests of at most ``maximumRequestSize`` bytes, in order.
    ///
    /// A request the server refuses as too large (status 413), or whose answer is longer than
    /// ``maximumResponseSize`` (conflicts that each bring a large version), is sent again as two
    /// halves; the server answers the changes it already applied from its memory of change IDs.
    /// A single change that stays too large is answered ``PushOutcome/rejected(reason:current:)``
    /// and parked, since the same request can never succeed: with status 413, or with
    /// ``answerTooLarge`` when its answer alone is longer than the limit. A push of n changes
    /// takes at most 2n − 1 requests. When a request fails after earlier ones were answered,
    /// their outcomes are returned, and the changes without an answer are retried later.
    public func push(_ changes: [OutgoingChange<Record>]) async throws -> [UUID: PushOutcome<Record>] {
        let encoder = JSONEncoder()
        let encoded = try changes.map { EncodedChange(id: $0.id, json: try encoder.encode(WireChange($0))) }
        var requests = Self.requests(for: encoded, upTo: maximumRequestSize)
        var outcomes: [UUID: PushOutcome<Record>] = [:]
        while !requests.isEmpty {
            let batch = requests.removeFirst()
            do {
                outcomes.merge(try await push(batch)) { _, answer in answer }
            } catch Failure.unexpectedStatus(code: 413, body: _) where batch.count > 1,
                    Failure.responseTooLarge(limit: _) where batch.count > 1 {
                let half = batch.count / 2
                requests.insert(contentsOf: [Array(batch[..<half]), Array(batch[half...])], at: 0)
            } catch Failure.unexpectedStatus(code: 413, body: let body) {
                let reason = "The sync server refused the change as too large (status 413)" + (body.isEmpty ? "." : ": \(body)")
                outcomes[batch[0].id] = .rejected(reason: reason, current: nil)
            } catch Failure.responseTooLarge(limit: let limit) {
                let reason = "\(Self.answerTooLarge): the sync server's answer to this change alone was longer than \(limit) bytes."
                outcomes[batch[0].id] = .rejected(reason: reason, current: nil)
            } catch where !outcomes.isEmpty && !(error is CancellationError) {
                return outcomes
            }
        }
        return outcomes
    }

    /// Starts the ``PendingChange/lastError`` of a change that is parked because the server's
    /// answer to it alone was longer than ``maximumResponseSize``. The server has to keep that
    /// answer within the limit (the documentation article "Server protocol"); until then,
    /// ``OfflineStore/retryFailedChanges()`` meets the same answer, and
    /// ``OfflineStore/discardChange(for:)`` drops the change.
    public static var answerTooLarge: String { "answerTooLarge" }

    /// One pushed change as the JSON it is sent as.
    private struct EncodedChange {
        let id: UUID
        let json: Data
    }

    /// `{"changes":[]}`.
    private static var emptyPushSize: Int { 14 }

    /// Splits `changes`, in order, into request bodies of at most `limit` bytes; a change that is
    /// larger on its own goes alone.
    private static func requests(for changes: [EncodedChange], upTo limit: Int) -> [[EncodedChange]] {
        var requests: [[EncodedChange]] = []
        var current: [EncodedChange] = []
        var size = emptyPushSize
        for change in changes {
            if !current.isEmpty, size + 1 + change.json.count > limit {
                requests.append(current)
                current = []
                size = emptyPushSize
            }
            size += change.json.count + (current.isEmpty ? 0 : 1)
            current.append(change)
        }
        if !current.isEmpty { requests.append(current) }
        return requests
    }

    /// Sends one request of `batch` and reads the outcomes of its changes.
    private func push(_ batch: [EncodedChange]) async throws -> [UUID: PushOutcome<Record>] {
        var request = try await makeRequest(url: baseURL.appending(path: "push"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body = Data(#"{"changes":["#.utf8)
        for (index, change) in batch.enumerated() {
            if index > 0 { body.append(UInt8(ascii: ",")) }
            body.append(change.json)
        }
        body.append(contentsOf: Array("]}".utf8))
        request.httpBody = body
        return try Self.outcomes(from: try await send(request), for: Set(batch.map(\.id)))
    }

    /// Pulls the page after `token`. A page must fit in ``maximumResponseSize``; while it does
    /// not, the pull asks for half as many changes, down to one. A change that is larger than
    /// the limit on its own is read as it streams in without what it holds, set aside, and the
    /// page's token moves past it, so one large record cannot stop every later pull; that read
    /// stops after four times ``maximumResponseSize`` with ``Failure/responseTooLarge(limit:)``,
    /// and before it starts when the page announces more. A page with more changes than the
    /// request's `limit`, readable or not, is cancelled when the change after the limit starts
    /// and refused with a `DecodingError`, so a server that ignores `limit` fails the pull after
    /// one request, without a change to the store.
    public func pull(since token: String?) async throws -> PullResponse<Record> {
        var limit = pageSize
        while true {
            let request = try await makeRequest(url: changesURL(after: token, limit: limit))
            do {
                return try Self.page(from: try await send(request, page: limit), limit: limit)
            } catch Failure.responseTooLarge(limit: _) where limit > 1 {
                limit /= 2
            } catch Failure.responseTooLarge(limit: _) {
                return try Self.oversizedPage(from: try await send(request, page: 1, outlining: true), limit: maximumResponseSize)
            }
        }
    }

    /// `<base>/changes?since=<token>&limit=<n>`, without `since` on the first pull. The token is
    /// encoded by hand: URLQueryItem leaves "+" as it is, and servers that decode the query as a
    /// form (URLSearchParams, the reference server) read it as a space.
    private func changesURL(after token: String?, limit: Int) -> URL {
        let url = baseURL.appending(path: "changes")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var query: [String] = []
        if let token, let encoded = token.addingPercentEncoding(withAllowedCharacters: changeTokenCharacters) {
            query.append("since=\(encoded)")
        }
        query.append("limit=\(limit)")
        components.percentEncodedQuery = query.joined(separator: "&")
        return components.url ?? url
    }

    // MARK: - HTTP

    private func makeRequest(url: URL) async throws -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (name, value) in try await headers() {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    /// Sends `request` and returns the body of a 2xx answer, read by a ``ResponseReader``: at
    /// most ``maximumResponseSize`` bytes, for a page of at most `page` changes, and with
    /// `outlining` only the outline of the page.
    private func send(_ request: URLRequest, page changeLimit: Int? = nil, outlining: Bool = false) async throws -> Data {
        do {
            return try await receive(request, page: changeLimit, outlining: outlining)
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            // URLSession reports a cancelled task as URLError(.cancelled). The store treats
            // CancellationError as "stopped", not as a failed attempt.
            throw CancellationError()
        }
    }

    /// The body of the answer to `request`. The answer is read as a page only when its status
    /// is 2xx; the download is cancelled as soon as the reader stops.
    private func receive(_ request: URLRequest, page changeLimit: Int?, outlining: Bool) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.notHTTP }
        let succeeded = (200..<300).contains(http.statusCode)
        do {
            var reader = try ResponseReader(expectedLength: response.expectedContentLength, maximumResponseSize: maximumResponseSize,
                                            changeLimit: succeeded ? changeLimit : nil, outlining: outlining)
            for try await byte in bytes { try reader.read(byte) }
            guard succeeded else {
                throw Failure.unexpectedStatus(code: http.statusCode, body: String(decoding: reader.body.prefix(500), as: UTF8.self))
            }
            return reader.body
        } catch let stop as ResponseReader.Stop {
            bytes.task.cancel()
            switch stop {
            case .tooLarge: throw Failure.responseTooLarge(limit: maximumResponseSize)
            case .tooManyChanges: throw Self.tooManyChanges(changeLimit ?? 0)
            }
        }
    }

    // MARK: - Wire format

    private struct WireChange: Encodable {
        let id: UUID
        let recordID: Record.ID
        let operation: String
        let record: Record?
        let timestamp: HLCTimestamp
        let baseRevision: String?

        init(_ change: OutgoingChange<Record>) {
            id = change.id
            recordID = change.recordID
            operation = change.record == nil ? "delete" : "upsert"
            record = change.record
            timestamp = change.timestamp
            baseRevision = change.baseRevision
        }
    }
}

/// The characters a change token keeps unencoded in the query: the URL query characters without
/// `+`, `&`, `=` and `;`, which form decoding would read as separators or a space.
private let changeTokenCharacters = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=;"))
