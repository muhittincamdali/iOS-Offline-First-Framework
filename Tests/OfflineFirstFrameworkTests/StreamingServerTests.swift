import Foundation
import Network
import os
import Testing
@testable import OfflineFirstFramework

/// A sync server on a real socket that answers every pull with a page it streams: one that
/// never ends, or one that ignores `limit`. It counts the bytes of the pages it got to send; a
/// socket takes only what the client reads and its buffers hold, so the count shows what the
/// transport downloaded.
final class StreamingServer: Sendable {
    /// What every pull is answered with.
    enum Answer: Sendable {
        /// A page of one change whose record never ends, in chunks.
        case endlessChange
        /// Changes with `size` bytes of text each, without end, in chunks.
        case endlessChanges(size: Int)
        /// `count` changes with `size` bytes of text each, with `Content-Length`.
        case page(count: Int, size: Int)

        /// The body of ``page(count:size:)``, built once.
        var page: Data? {
            guard case .page(let count, let size) = self else { return nil }
            let text = String(repeating: "x", count: size)
            var body = Data(#"{"changes":["#.utf8)
            for index in 0..<count {
                if index > 0 { body.append(UInt8(ascii: ",")) }
                body.append(StreamingServer.change(index, text: text))
            }
            body.append(contentsOf: Array(#"],"token":"t1","hasMore":false}"#.utf8))
            return body
        }
    }

    let url: URL
    private let listener: NWListener
    private let sent: OSAllocatedUnfairLock<Int>
    private let pulls: OSAllocatedUnfairLock<Int>

    /// Bytes of pages the socket took.
    var bytesSent: Int { sent.withLock { $0 } }
    /// Pull requests answered.
    var pullCount: Int { pulls.withLock { $0 } }

    private init(url: URL, listener: NWListener, sent: OSAllocatedUnfairLock<Int>, pulls: OSAllocatedUnfairLock<Int>) {
        self.url = url
        self.listener = listener
        self.sent = sent
        self.pulls = pulls
    }

    static func start(answering answer: Answer) async throws -> StreamingServer {
        let listener = try NWListener(using: .tcp, on: .any)
        let queue = DispatchQueue(label: "streaming-server")
        let sent = OSAllocatedUnfairLock(initialState: 0)
        let pulls = OSAllocatedUnfairLock(initialState: 0)
        let page = answer.page
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                let request = String(decoding: data ?? Data(), as: UTF8.self)
                guard request.hasPrefix("GET ") else {
                    respond(connection, header: "HTTP/1.1 200 OK\r\nContent-Length: 15\r\n\r\n", pieces: [Data(#"{"outcomes":{}}"#.utf8)])
                    return
                }
                pulls.withLock { $0 += 1 }
                serve(answer, page: page, on: connection, counting: sent)
            }
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { state in
                let value: Result<UInt16, any Error>
                switch state {
                case .ready: value = .success(listener.port?.rawValue ?? 0)
                case .failed(let error): value = .failure(error)
                default: return
                }
                if resumed.withLock({ was in defer { was = true }; return !was }) { continuation.resume(with: value) }
            }
            listener.start(queue: queue)
        }
        return StreamingServer(url: URL(string: "http://127.0.0.1:\(port)/sync/notes")!, listener: listener, sent: sent, pulls: pulls)
    }

    func stop() { listener.cancel() }

    private static func change(_ index: Int, size: Int) -> Data {
        change(index, text: String(repeating: "x", count: size))
    }

    fileprivate static func change(_ index: Int, text: String) -> Data {
        Data(#"{"recordID":"n\#(index)","revision":"\#(index)","record":{"id":"n\#(index)","text":"\#(text)"}}"#.utf8)
    }

    private static func serve(_ answer: Answer, page: Data?, on connection: NWConnection, counting sent: OSAllocatedUnfairLock<Int>) {
        let chunked = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n"
        switch answer {
        case .endlessChange:
            let filler = Data(repeating: UInt8(ascii: "x"), count: 65_536)
            var first = true
            pump(connection, counting: sent, chunked: true, header: chunked) {
                defer { first = false }
                return first ? Data(#"{"changes":[{"recordID":"a","revision":"1","record":{"id":"a","text":""#.utf8) : filler
            }
        case .endlessChanges(let size):
            var index = 0
            pump(connection, counting: sent, chunked: true, header: chunked) {
                defer { index += 1 }
                return index == 0 ? Data(#"{"changes":["#.utf8) : change(index, size: size) + Data(",".utf8)
            }
        case .page:
            let body = page ?? Data()
            var offset = 0
            let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\n\r\n"
            pump(connection, counting: sent, chunked: false, header: header) {
                guard offset < body.count else { return nil }
                defer { offset += 65_536 }
                return body.subdata(in: offset..<min(body.count, offset + 65_536))
            }
        }
    }

    /// Sends `header`, then the pieces `next` returns, each once the socket took the one before,
    /// until `next` returns `nil` or the client goes away.
    private static func pump(_ connection: NWConnection, counting sent: OSAllocatedUnfairLock<Int>, chunked: Bool, header: String,
                             next: @escaping () -> Data?) {
        // Called by one send completion after the other, never at the same time.
        nonisolated(unsafe) let next = next
        @Sendable func send() {
            guard let piece = next() else {
                connection.send(content: chunked ? Data("0\r\n\r\n".utf8) : nil, isComplete: true, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }
            let framed = chunked ? Data(String(piece.count, radix: 16).utf8) + Data("\r\n".utf8) + piece + Data("\r\n".utf8) : piece
            connection.send(content: framed, completion: .contentProcessed { error in
                guard error == nil else {
                    connection.cancel()
                    return
                }
                sent.withLock { $0 += piece.count }
                send()
            })
        }
        connection.send(content: Data(header.utf8), completion: .contentProcessed { error in
            if error == nil { send() } else { connection.cancel() }
        })
    }

    private static func respond(_ connection: NWConnection, header: String, pieces: [Data]) {
        var remaining = pieces
        pump(connection, counting: OSAllocatedUnfairLock(initialState: 0), chunked: false, header: header) {
            remaining.isEmpty ? nil : remaining.removeFirst()
        }
    }
}

/// Pages streamed over a real socket. The outline that sets a change too large to load aside
/// read without a limit: a change that never ended was read until the sync's deadline, and a
/// page of 40 MiB that ignored limit=1 was read to its end, also when it announced its length.
@Suite("HTTP transport: what a streamed page may cost", .heapExclusive)
struct StreamingServerTests {
    private func store(for server: StreamingServer, maximumResponseSize: Int) throws -> OfflineStore<Note> {
        let transport = HTTPSyncTransport<Note>(baseURL: server.url, session: URLSession(configuration: .ephemeral),
                                                maximumResponseSize: maximumResponseSize)
        var configuration = OfflineStore<Note>.Configuration()
        configuration.syncTimeout = .seconds(8)
        return try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport, configuration: configuration)
    }

    @Test func aChangeThatNeverEndsIsReadUpToFourTimesTheLimit() async throws {
        let server = try await StreamingServer.start(answering: .endlessChange)
        defer { server.stop() }
        let limit = 1 << 20
        let store = try store(for: server, maximumResponseSize: limit)
        let start = ContinuousClock.now
        await #expect(throws: HTTPSyncTransport<Note>.Failure.responseTooLarge(limit: limit)) { try await store.sync() }
        #expect(ContinuousClock.now - start < .seconds(6))
        // Seven requests asking for fewer changes, of 1 MiB each, and the outline of 4 MiB, with
        // what the sockets' buffers held: about 40 MiB in all.
        #expect(server.pullCount == 8)
        #expect(server.bytesSent < 128 << 20, "sent \(server.bytesSent >> 20) MiB")
        #expect(await store.state.token == nil)
    }

    @Test func aPageThatIgnoresTheLimitIsCancelledAtTheChangeAfterIt() async throws {
        let server = try await StreamingServer.start(answering: .endlessChanges(size: 1_024))
        defer { server.stop() }
        let store = try store(for: server, maximumResponseSize: 16 << 20)
        await #expect(throws: DecodingError.self) { try await store.sync() }
        #expect(server.pullCount == 1)
        #expect(server.bytesSent < 16 << 20, "sent \(server.bytesSent >> 20) MiB")
        #expect(await store.records().isEmpty)
    }

    @Test func aLongPageThatAnnouncesItsLengthIsNotReadToItsEnd() async throws {
        let server = try await StreamingServer.start(answering: .page(count: 160, size: 256 * 1024))
        defer { server.stop() }
        let store = try store(for: server, maximumResponseSize: 16 << 20)
        await #expect(throws: DecodingError.self) { try await store.sync() }
        // The pages asking for 100 to 1 changes are cancelled when their length arrives; the
        // outline stops at the second change.
        #expect(server.pullCount == 8)
        #expect(server.bytesSent < 32 << 20, "sent \(server.bytesSent >> 20) MiB")
        #expect(await store.records().isEmpty)
    }
}
