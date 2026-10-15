import Foundation
import os
import Testing
@testable import OfflineFirstFramework

/// Runs the README samples (ReadmeExamples.swift links to the example app's ReadmeSamples.swift).
@Suite("README samples")
struct ReadmeSamplesTests {
    @Test func twoDevicesSeeTheSameTodo() async throws {
        let (phone, laptop) = try await ReadmeSamples.twoDevices()
        #expect(phone.map(\.title) == ["Buy milk"])
        #expect(phone == laptop)
    }

    @Test func keepTicksMergesTheDoneFlag() throws {
        let id = UUID()
        let conflict = Conflict(recordID: id, local: Todo(id: id, title: "Milk", isDone: true),
                                localTimestamp: HLCTimestamp(wallTime: 1, nodeID: "a"),
                                remote: Todo(id: id, title: "Oat milk"), remoteTimestamp: HLCTimestamp(wallTime: 2, nodeID: "b"))
        guard case .merged(let merged) = ReadmeSamples.keepTicks.resolve(conflict) else {
            Issue.record("expected a merged record")
            return
        }
        #expect(merged == Todo(id: id, title: "Oat milk", isDone: true))
    }

    @Test(.enabled(if: KeychainAvailability.isAvailable, "This test host has no Keychain entitlement."))
    func secureStoreEncryptsItsFile() async throws {
        defer { try? KeychainStore(service: "com.example.todos").delete("todos-key") }
        let storage = InMemoryStorage()
        let server = InMemorySyncServer<Todo>()
        let store = try ReadmeSamples.makeSecureStore(transport: server, storage: storage)
        try await store.save(Todo(title: "Private"))
        try await store.sync()
        let file = try #require(try storage.read("secure-todos.store"))
        #expect(file.range(of: Data("Private".utf8)) == nil)
        #expect(await server.records().map(\.title) == ["Private"])
    }

    @Test func restTransportMapsStatusCodesAndPages() async throws {
        let created = UUID(), stale = UUID(), invalid = UUID(), failing = UUID()
        let host = "todos-\(UUID().uuidString.prefix(8).lowercased()).example"
        let session = StubURLProtocol.session(host: host) { request, _ in
            let path = request.url?.path() ?? ""
            if request.httpMethod == "GET" {
                let since = request.url?.query() ?? ""
                let body = #"{"items": [{"id": "\#(created.uuidString)", "etag": "e9", "todo": {"id": "\#(created.uuidString)", "title": "Synced", "isDone": false}}], "next": "c2", "more": \#(since.isEmpty)}"#
                return (200, Data(body.utf8))
            }
            if path.hasSuffix(created.uuidString) {
                #expect(request.value(forHTTPHeaderField: "If-None-Match") == "*")
                return (201, Data())
            }
            if path.hasSuffix(stale.uuidString) {
                #expect(request.value(forHTTPHeaderField: "If-Match") == "e1")
                return (412, Data(#"{"id": "\#(stale.uuidString)", "title": "Server", "isDone": true}"#.utf8))
            }
            if path.hasSuffix(invalid.uuidString) { return (422, Data("Title is empty".utf8)) }
            return (500, Data())
        }
        let api = TodoAPI(baseURL: URL(string: "https://\(host)/v1")!, session: session)
        let timestamp = HLCTimestamp(wallTime: 1, nodeID: "a")
        let outcomes = try await api.push([
            OutgoingChange(id: created, recordID: created, operation: .upsert(Todo(id: created, title: "New")), timestamp: timestamp, baseRevision: nil),
            OutgoingChange(id: stale, recordID: stale, operation: .upsert(Todo(id: stale, title: "Old")), timestamp: timestamp, baseRevision: "e1"),
            OutgoingChange(id: invalid, recordID: invalid, operation: .upsert(Todo(id: invalid, title: "")), timestamp: timestamp, baseRevision: nil),
            OutgoingChange(id: failing, recordID: failing, operation: .delete, timestamp: timestamp, baseRevision: "e3")
        ])
        guard case .accepted? = outcomes[created] else { Issue.record("created"); return }
        guard case .conflict(let current)? = outcomes[stale] else { Issue.record("stale"); return }
        #expect(current.record?.isDone == true)
        guard case .rejected(let reason, _)? = outcomes[invalid] else { Issue.record("invalid"); return }
        #expect(reason == "Title is empty")
        #expect(outcomes[failing] == nil)

        let first = try await api.pull(since: nil)
        #expect(first.changes.first?.record?.title == "Synced")
        #expect(first.hasMore)
        #expect(try await api.pull(since: "c1").hasMore == false)
    }
}
