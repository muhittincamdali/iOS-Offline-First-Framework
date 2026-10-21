import Foundation
import Testing
@testable import OfflineFirstFramework

/// The protocol's bodies are JSON in UTF-8, which may start with a byte order mark (some
/// frameworks write one). A page or push answer with it must be read; one in UTF-16 or UTF-32
/// must fail with an error that says so, not as broken JSON.
@Suite("HTTP transport: byte order marks and encodings")
struct ByteOrderMarkTests {
    private static let mark = Data([0xEF, 0xBB, 0xBF])

    private func store(prefix: Data, encoding: String.Encoding = .utf8) throws -> OfflineStore<Note> {
        let host = "bom-\(UUID().uuidString.lowercased()).example"
        let session = StubURLProtocol.session(host: host) { request, body in
            if request.httpMethod == "POST" {
                let sent = try JSONSerialization.jsonObject(with: body) as? [String: Any]
                let changes = sent?["changes"] as? [[String: Any]] ?? []
                let outcomes = changes.map { #""\#($0["id"] as? String ?? "")":{"status":"accepted","revision":"r1"}"# }
                return (200, prefix + Data(("{\"outcomes\":{" + outcomes.joined(separator: ",") + "}}").utf8))
            }
            let page = #"{"changes":[{"recordID":"s","record":{"id":"s","text":"server"},"revision":"1"}],"token":"t1","hasMore":false}"#
            return (200, prefix + (page.data(using: encoding) ?? Data()))
        }
        let transport = HTTPSyncTransport<Note>(baseURL: URL(string: "https://\(host)/sync/notes")!, session: session)
        return try OfflineStore<Note>(name: "notes", storage: InMemoryStorage(), transport: transport,
                                      configuration: makeConfiguration(clock: TestClock()))
    }

    @Test func aPageAndAPushAnswerWithAByteOrderMarkAreRead() async throws {
        let store = try store(prefix: Self.mark)
        try await store.save(Note(id: "mine", text: "m"))
        let report = try await store.sync()
        #expect(report.pushed == 1)
        #expect(await store.pendingChanges().isEmpty)
        #expect(await store.record("s")?.text == "server")
        #expect(await store.state.token == "t1")
    }

    @Test(arguments: [
        (Data([0xFE, 0xFF]), String.Encoding.utf16BigEndian),
        (Data([0xFF, 0xFE]), String.Encoding.utf16LittleEndian),
        (Data(), String.Encoding.utf16BigEndian),
        (Data([0xFF, 0xFE, 0x00, 0x00]), String.Encoding.utf32LittleEndian),
    ])
    func aPageInUTF16OrUTF32FailsWithAnErrorThatSaysSo(prefix: Data, encoding: String.Encoding) async throws {
        let store = try store(prefix: prefix, encoding: encoding)
        do {
            try await store.sync()
            Issue.record("expected the sync to fail")
        } catch let DecodingError.dataCorrupted(context) {
            #expect(context.debugDescription.contains("UTF-16 or UTF-32"))
        }
        #expect(await store.record("s") == nil)
        #expect(await store.state.token == nil)
    }
}
