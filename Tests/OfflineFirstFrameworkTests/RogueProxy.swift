import Foundation
import Network
import os

/// A proxy on a real socket in front of a sync server that misbehaves as a gateway in trouble
/// does. It forwards requests to its upstream (the reference server) and answers pushes as its
/// ``Mode`` says; pulls are forwarded, or answered with pages the test recorded earlier, as a
/// stale replica or cache would.
final class RogueProxy: Sendable {
    enum Mode: Sendable {
        /// Forwards everything.
        case pass
        /// Answers a push with 503 and a `Content-Length` of 17 MiB without sending the body,
        /// and closes the connection; the push never reaches the server.
        case overloaded
        /// Answers a push with a 502 error page that streams without end; the push never
        /// reaches the server.
        case streamingError
        /// Forwards a push, which the server applies, and answers it with 504 and a
        /// `Content-Length` of 17 MiB without the body.
        case appliedThenGatewayTimeout
        /// Forwards a push, which the server applies, and closes the connection without an answer.
        case appliedThenReset
        /// Forwards a push, which the server applies, and answers it with 200 and a
        /// `Content-Length` of 17 MiB without the body, as a proxy that puts a page of its own
        /// in place of the answer would.
        case appliedThenLongAnswer
    }

    /// Pages recorded earlier: the one from the beginning and the one after its token.
    struct StalePages: Sendable {
        var first: Data
        var second: Data
    }

    struct Counts: Sendable {
        var pushes = 0
        var pulls = 0
        /// Pushes the server answered in the modes that forward them.
        var forwardedPushes = 0
        /// Bytes of error pages the socket took in ``Mode/streamingError``.
        var errorBytesSent = 0
    }

    /// The base URL of the server (`http://localhost:<port>`), looked up for every request, so
    /// the proxy follows a server to the port of its next start.
    typealias Upstream = @Sendable () -> URL?
    private typealias State = OSAllocatedUnfairLock<(mode: Mode, stale: StalePages?, holding: Bool, counts: Counts)>

    let url: URL
    private let listener: NWListener
    private let state: State

    var counts: Counts { state.withLock { $0.counts } }

    func setMode(_ mode: Mode) { state.withLock { $0.mode = mode } }

    func serveStalePages(_ pages: StalePages?) { state.withLock { $0.stale = pages } }

    /// Holds the answer to every push the proxy forwards in a misbehaving mode until
    /// ``release()``, so a test can act while the device waits for it.
    func hold() { state.withLock { $0.holding = true } }

    func release() { state.withLock { $0.holding = false } }

    /// Waits until the server answered `count` forwarded pushes.
    func waitForForwardedPushes(_ count: Int) async throws {
        while state.withLock({ $0.counts.forwardedPushes < count }) { try await Task.sleep(for: .milliseconds(5)) }
    }

    private init(url: URL, listener: NWListener, state: State) {
        self.url = url
        self.listener = listener
        self.state = state
    }

    /// Starts a proxy for `upstream`; without one, every request the proxy forwards fails with 502.
    static func start(upstream: @escaping Upstream = { nil }, mode: Mode) async throws -> RogueProxy {
        let listener = try NWListener(using: .tcp, on: .any)
        let queue = DispatchQueue(label: "rogue-proxy")
        let state = State(initialState: (mode: mode, stale: nil, holding: false, counts: Counts()))
        let session = URLSession(configuration: .ephemeral)
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            readRequest(on: connection, buffer: Data()) { head, body in
                Task { await handle(head, body: body, on: connection, upstream: upstream, session: session, state: state) }
            }
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { listenerState in
                let value: Result<UInt16, any Error>
                switch listenerState {
                case .ready: value = .success(listener.port?.rawValue ?? 0)
                case .failed(let error): value = .failure(error)
                default: return
                }
                if resumed.withLock({ was in defer { was = true }; return !was }) { continuation.resume(with: value) }
            }
            listener.start(queue: queue)
        }
        return RogueProxy(url: URL(string: "http://127.0.0.1:\(port)")!, listener: listener, state: state)
    }

    func stop() { listener.cancel() }

    // MARK: - Requests

    /// Reads one request: the head up to the empty line, then `Content-Length` bytes of body.
    private static func readRequest(on connection: NWConnection, buffer: Data, done: @escaping @Sendable (String, Data) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, isComplete, error in
            var buffer = buffer
            buffer.append(data ?? Data())
            if let end = buffer.firstRange(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                let length = head.split(separator: "\r\n")
                    .first { $0.lowercased().hasPrefix("content-length:") }
                    .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                let body = buffer[end.upperBound...]
                if body.count >= length {
                    done(head, Data(body.prefix(length)))
                    return
                }
            }
            guard error == nil, !isComplete else {
                connection.cancel()
                return
            }
            readRequest(on: connection, buffer: buffer, done: done)
        }
    }

    private static func handle(_ head: String, body: Data, on connection: NWConnection, upstream: @escaping Upstream,
                               session: URLSession, state: State) async {
        let parts = (head.split(separator: "\r\n").first ?? "").split(separator: " ")
        guard parts.count >= 2 else { return connection.cancel() }
        let method = String(parts[0])
        let target = String(parts[1])
        if method == "GET" {
            let stale = state.withLock { $0.counts.pulls += 1; return $0.stale }
            if let stale {
                let since = URLComponents(string: target)?.queryItems?.contains { $0.name == "since" } ?? false
                return respond(connection, status: 200, body: since ? stale.second : stale.first)
            }
            return await forward(method, target, body: body, upstream: upstream, session: session, to: connection)
        }
        let mode = state.withLock { $0.counts.pushes += 1; return $0.mode }
        switch mode {
        case .pass:
            await forward(method, target, body: body, upstream: upstream, session: session, to: connection)
        case .overloaded:
            announceLargeBody(connection, status: "503 Service Unavailable")
        case .streamingError:
            streamErrorPage(connection, state: state)
        case .appliedThenGatewayTimeout:
            await forwardAndHold(method, target, body: body, upstream: upstream, session: session, state: state)
            announceLargeBody(connection, status: "504 Gateway Timeout")
        case .appliedThenReset:
            await forwardAndHold(method, target, body: body, upstream: upstream, session: session, state: state)
            connection.cancel()
        case .appliedThenLongAnswer:
            await forwardAndHold(method, target, body: body, upstream: upstream, session: session, state: state)
            announceLargeBody(connection, status: "200 OK")
        }
    }

    /// Lets the server apply a push, then waits while the proxy holds answers.
    private static func forwardAndHold(_ method: String, _ target: String, body: Data, upstream: @escaping Upstream,
                                       session: URLSession, state: State) async {
        _ = try? await send(method, target, body: body, upstream: upstream, session: session)
        state.withLock { $0.counts.forwardedPushes += 1 }
        while state.withLock({ $0.holding }) { try? await Task.sleep(for: .milliseconds(5)) }
    }

    // MARK: - Answers

    private static func send(_ method: String, _ target: String, body: Data, upstream: Upstream,
                             session: URLSession) async throws -> (status: Int, body: Data) {
        guard let base = upstream(), let url = URL(string: target, relativeTo: base) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        if method == "POST" {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? 502, data)
    }

    private static func forward(_ method: String, _ target: String, body: Data, upstream: Upstream, session: URLSession,
                                to connection: NWConnection) async {
        let answer = try? await send(method, target, body: body, upstream: upstream, session: session)
        respond(connection, status: answer?.status ?? 502, body: answer?.body ?? Data())
    }

    private static func respond(_ connection: NWConnection, status: Int, body: Data) {
        let head = "HTTP/1.1 \(status) \(HTTPURLResponse.localizedString(forStatusCode: status))\r\n"
            + "Content-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + body, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Sends the head of an answer whose body of 17 MiB never comes, and closes the connection
    /// a moment later, as a proxy that gives up does.
    private static func announceLargeBody(_ connection: NWConnection, status: String) {
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html\r\nContent-Length: \(17 << 20)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { connection.cancel() }
        })
    }

    /// Streams an error page in chunks of 256 KiB until the client goes away, counting what the
    /// socket took.
    private static func streamErrorPage(_ connection: NWConnection, state: State) {
        let head = "HTTP/1.1 502 Bad Gateway\r\nContent-Type: text/html\r\nTransfer-Encoding: chunked\r\n\r\n"
        let filler = Data(repeating: UInt8(ascii: "x"), count: 256 * 1024)
        let chunk = Data(String(filler.count, radix: 16).utf8) + Data("\r\n".utf8) + filler + Data("\r\n".utf8)
        @Sendable func next() {
            connection.send(content: chunk, completion: .contentProcessed { error in
                guard error == nil else { return connection.cancel() }
                let total = state.withLock { $0.counts.errorBytesSent += filler.count; return $0.counts.errorBytesSent }
                // A bound for the test itself; the transport stops long before.
                guard total < 64 << 20 else { return connection.cancel() }
                next()
            })
        }
        connection.send(content: Data(head.utf8), completion: .contentProcessed { error in
            if error == nil { next() } else { connection.cancel() }
        })
    }
}
