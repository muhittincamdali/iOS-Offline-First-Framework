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
/// ``maximumResponseSize`` bytes; a larger one is cancelled instead of being loaded. A pull asks
/// for ``pageSize`` changes and, while the page is larger than that, for half as many; a single
/// change that is larger on its own is set aside in ``OfflineStore/quarantinedChanges()`` and
/// the pull moves past it.
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

    /// The longest response, in bytes, that is read. Default: 16 MiB.
    public let maximumResponseSize: Int

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
    ///   - pageSize: The most changes a pull asks for.
    ///   - headers: Extra headers for each request, such as an `Authorization` header. Called
    ///     before every request, so it can refresh a token.
    public init(
        baseURL: URL,
        session: URLSession = .shared,
        maximumResponseSize: Int = 16 * 1024 * 1024,
        pageSize: Int = 100,
        headers: @escaping @Sendable () async throws -> [String: String] = { [:] }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.maximumResponseSize = max(1, maximumResponseSize)
        self.pageSize = min(max(1, pageSize), 1_000)
        self.headers = headers
    }

    public func push(_ changes: [OutgoingChange<Record>]) async throws -> [UUID: PushOutcome<Record>] {
        var request = try await makeRequest(url: baseURL.appending(path: "push"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PushBody(changes: changes.map(WireChange.init)))
        return try Self.outcomes(from: try await send(request), for: Set(changes.map(\.id)))
    }

    /// Pulls the page after `token`. A page must fit in ``maximumResponseSize``; while it does
    /// not, the pull asks for half as many changes, down to one. A change that is larger than
    /// the limit on its own is read as it streams in without what it holds, set aside, and the
    /// page's token moves past it, so one large record cannot stop every later pull. A server
    /// that ignores `limit` and sends a page that is too large still fails with
    /// ``Failure/responseTooLarge(limit:)``.
    public func pull(since token: String?) async throws -> PullResponse<Record> {
        var limit = pageSize
        while true {
            let request = try await makeRequest(url: changesURL(after: token, limit: limit))
            do {
                return try Self.page(from: try await send(request))
            } catch Failure.responseTooLarge(limit: _) where limit > 1 {
                limit /= 2
            } catch Failure.responseTooLarge(limit: _) {
                return try Self.oversizedPage(from: try await send(request, outlining: true), limit: maximumResponseSize)
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

    /// Sends `request` and returns the body of a 2xx answer, reading at most
    /// ``maximumResponseSize`` bytes; `outlining` keeps only the ``PageOutline`` of the body.
    private func send(_ request: URLRequest, outlining: Bool = false) async throws -> Data {
        do {
            return try await receive(request, outlining: outlining)
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            // URLSession reports a cancelled task as URLError(.cancelled). The store treats
            // CancellationError as "stopped", not as a failed attempt.
            throw CancellationError()
        }
    }

    private func receive(_ request: URLRequest, outlining: Bool) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.notHTTP }
        if !outlining, response.expectedContentLength > Int64(maximumResponseSize) {
            bytes.task.cancel()
            throw Failure.responseTooLarge(limit: maximumResponseSize)
        }
        var body = Data()
        var outline = PageOutline()
        for try await byte in bytes {
            if outlining {
                outline.append(byte, to: &body)
            } else {
                body.append(byte)
            }
            guard body.count <= maximumResponseSize else {
                bytes.task.cancel()
                throw Failure.responseTooLarge(limit: maximumResponseSize)
            }
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Failure.unexpectedStatus(code: http.statusCode, body: String(decoding: body.prefix(500), as: UTF8.self))
        }
        return body
    }

    // MARK: - Wire format

    private struct PushBody: Encodable {
        let changes: [WireChange]
    }

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
