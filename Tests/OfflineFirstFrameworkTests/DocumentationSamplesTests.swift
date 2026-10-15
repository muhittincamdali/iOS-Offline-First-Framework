import Foundation
import Testing
@testable import OfflineFirstFramework

/// The record from the "Resolving conflicts" article, copied verbatim.
struct Checklist: SyncableRecord, Mergeable {
    var id: UUID
    var items: ORSet<String>
    var views: GCounter

    func merged(with other: Checklist) -> Checklist {
        Checklist(id: id, items: items.merged(with: other.items), views: views.merged(with: other.views))
    }
}

@Suite("Documentation samples")
struct DocumentationSamplesTests {
    @Test func mergeableRecordsKeepEditsFromBothDevices() async throws {
        let server = InMemorySyncServer<Checklist>()
        var configuration = OfflineStore<Checklist>.Configuration()
        configuration.conflictResolver = .mergeable
        let phone = try OfflineStore<Checklist>(name: "phone", storage: InMemoryStorage(), transport: server, configuration: configuration)
        let laptop = try OfflineStore<Checklist>(name: "laptop", storage: InMemoryStorage(), transport: server, configuration: configuration)

        let id = UUID()
        try await phone.save(Checklist(id: id, items: ORSet(["Passport"]), views: GCounter()))
        try await phone.sync()
        try await laptop.sync()

        // Both devices change the list while neither has seen the other's change.
        var onPhone = try #require(await phone.record(id))
        onPhone.items.insert("Charger")
        onPhone.views.increment(node: phone.nodeID)
        try await phone.save(onPhone)

        var onLaptop = try #require(await laptop.record(id))
        onLaptop.items.remove("Passport")
        onLaptop.items.insert("Tickets")
        onLaptop.views.increment(by: 2, node: laptop.nodeID)
        try await laptop.save(onLaptop)

        try await phone.sync()
        let report = try await laptop.sync()
        #expect(report.conflicts == 1)
        try await phone.sync()

        let expected: Set = ["Charger", "Tickets"]
        #expect(await phone.record(id)?.items.elements == expected)
        #expect(await laptop.record(id)?.items.elements == expected)
        #expect(await phone.record(id)?.views.value == 3)
        #expect(await server.record(id)?.views.value == 3)
    }
}
