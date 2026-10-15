import Foundation

/// A ``SyncTransport`` that speaks a small JSON protocol over HTTP.
///
/// Point it at a server that implements two endpoints (the documentation article "Server
/// protocol" describes them, and `Examples/SyncServer` is a working server in about 200 lines
/// of JavaScript):
///
/// - `POST <baseURL>/push` with `{"changes": [...]}`, answered with `{"outcomes": {...}}`.
/// - `GET <baseURL>/changes?since=<token>`, answered with
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
/// ``maximumResponseSize`` bytes; a larger one is cancelled instead of being loaded.
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
    ///   - headers: Extra headers for each request, such as an `Authorization` header. Called
    ///     before every request, so it can refresh a token.
    public init(
        baseURL: URL,
        session: URLSession = .shared,
        maximumResponseSize: Int = 16 * 1024 * 1024,
        headers: @escaping @Sendable () async throws -> [String: String] = { [:] }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.maximumResponseSize = max(1, maximumResponseSize)
        self.headers = headers
    }

    public func push(_ changes: [OutgoingChange<Record>]) async throws -> [UUID: PushOutcome<Record>] {
        var request = try await makeRequest(url: baseURL.appending(path: "push"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(PushBody(changes: changes.map(WireChange.init)))
        let answer = try JSONDecoder().decode(PushAnswer.self, from: try await send(request))
        var outcomes: [UUID: PushOutcome<Record>] = [:]
        for (key, outcome) in answer.outcomes {
            // An outcome that cannot be read leaves only its own change without an answer; the
            // store retries that change and settles the others.
            guard let id = UUID(uuidString: key), let outcome = try? outcome.wire?.pushOutcome() else { continue }
            outcomes[id] = outcome
        }
        return outcomes
    }

    public func pull(since token: String?) async throws -> PullResponse<Record> {
        var url = baseURL.appending(path: "changes")
        // Encoded by hand: URLQueryItem leaves "+" as it is, and servers that decode the query
        // as a form (URLSearchParams, the reference server) read it as a space.
        if let token, let encoded = token.addingPercentEncoding(withAllowedCharacters: changeTokenCharacters),
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.percentEncodedQuery = "since=\(encoded)"
            url = components.url ?? url
        }
        let request = try await makeRequest(url: url)
        let page = try JSONDecoder().decode(PullPage.self, from: try await send(request))
        var changes: [RemoteChange<Record>] = []
        var quarantined: [QuarantinedChange] = []
        for change in page.changes {
            switch change {
            case .readable(let change): changes.append(change)
            case .unreadable(let entry): quarantined.append(entry)
            }
        }
        return PullResponse(changes: changes, token: page.token, hasMore: page.hasMore, epoch: page.epoch, quarantined: quarantined)
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
    /// ``maximumResponseSize`` bytes.
    private func send(_ request: URLRequest) async throws -> Data {
        do {
            return try await receive(request)
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            // URLSession reports a cancelled task as URLError(.cancelled). The store treats
            // CancellationError as "stopped", not as a failed attempt.
            throw CancellationError()
        }
    }

    private func receive(_ request: URLRequest) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.notHTTP }
        if response.expectedContentLength > Int64(maximumResponseSize) {
            bytes.task.cancel()
            throw Failure.responseTooLarge(limit: maximumResponseSize)
        }
        var body = Data()
        for try await byte in bytes {
            guard body.count < maximumResponseSize else {
                bytes.task.cancel()
                throw Failure.responseTooLarge(limit: maximumResponseSize)
            }
            body.append(byte)
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

    private struct PushAnswer: Decodable {
        let outcomes: [String: LossyOutcome]
    }

    /// One outcome of a push answer, or `nil` when it cannot be read.
    private struct LossyOutcome: Decodable {
        let wire: WireOutcome?

        init(from decoder: any Decoder) throws {
            wire = try? WireOutcome(from: decoder)
        }
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

    private struct PullPage: Decodable {
        let changes: [LossyChange]
        let token: String?
        let hasMore: Bool
        let epoch: String?
    }

    /// One change of a page, or why it cannot be read, so one bad record does not make the
    /// whole page, and every later pull, fail.
    private enum LossyChange: Decodable {
        case readable(RemoteChange<Record>)
        case unreadable(QuarantinedChange)

        init(from decoder: any Decoder) throws {
            do {
                self = .readable(try RemoteChange<Record>(from: decoder))
            } catch {
                let raw = try? JSONValue(from: decoder)
                let recordID = raw?["recordID"].flatMap { try? JSONEncoder().encode($0) }.map { String(decoding: $0, as: UTF8.self) }
                var revision: String?
                if case .string(let value)? = raw?["revision"] { revision = value }
                self = .unreadable(QuarantinedChange(recordID: recordID ?? "null", revision: revision, reason: Self.describe(error)))
            }
        }

        private static func describe(_ error: any Error) -> String {
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
    }
}

/// The characters a change token keeps unencoded in the query: the URL query characters without
/// `+`, `&`, `=` and `;`, which form decoding would read as separators or a space.
private let changeTokenCharacters = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&=;"))
