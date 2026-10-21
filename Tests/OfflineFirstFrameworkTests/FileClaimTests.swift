import Foundation
import Testing
@testable import OfflineFirstFramework

/// The backend from the "Protecting and migrating data" article, copied verbatim.
struct WrappingStorage: StorageBackend {
    let base: FileStore
    var claimIdentity: String? { base.claimIdentity }

    func read(_ name: String) throws -> Data? { try base.read(name) }
    func write(_ data: Data, to name: String) throws { try base.write(data, to: name) }
    func remove(_ name: String) throws { try base.remove(name) }
    func move(_ name: String, to newName: String) throws { try base.move(name, to: newName) }
}

/// Two store instances on one file must not drop each other's saves. The protection covered
/// only `FileStore` and `InMemoryStorage` themselves: through a backend that wraps a file store,
/// the second instance's save returned normally and its write dropped the record the first one
/// had saved, although the documentation promised the protection without conditions.
@Suite("Offline store: one instance per file")
struct FileClaimTests {
    /// A custom backend that does not report an identity.
    final class AnonymousStorage: StorageBackend {
        let base = InMemoryStorage()

        func read(_ name: String) throws -> Data? { try base.read(name) }
        func write(_ data: Data, to name: String) throws { try base.write(data, to: name) }
        func remove(_ name: String) throws { try base.remove(name) }
        func move(_ name: String, to newName: String) throws { try base.move(name, to: newName) }
    }

    let clock = TestClock()

    private func makeStore(_ storage: any StorageBackend) throws -> OfflineStore<Note> {
        try OfflineStore<Note>(name: "notes", storage: storage, configuration: makeConfiguration(clock: clock))
    }

    @Test func aWrappedFileStoreThatForwardsItsIdentityKeepsTheFirstSave() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try FileStore(directory: directory, protection: .none)
        let wrapped = WrappingStorage(base: files)
        let first = try makeStore(wrapped)
        let second = try makeStore(wrapped)
        try await first.save(Note(id: "a", text: "A"))
        await #expect(throws: OfflineFirstError.storeChangedElsewhere(name: "notes")) {
            try await second.save(Note(id: "b", text: "B"))
        }
        // The wrapper and the file store it wraps share the claim, too.
        let bare = try makeStore(files)
        try await first.save(Note(id: "c", text: "C"))
        await #expect(throws: OfflineFirstError.storeChangedElsewhere(name: "notes")) {
            try await bare.save(Note(id: "d", text: "D"))
        }
        #expect(try await makeStore(files).records().map(\.id) == ["a", "c"])
    }

    @Test func aFileStoreReachedThroughALinkSharesTheClaim() async throws {
        let directory = temporaryDirectory()
        let link = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: link)
            try? FileManager.default.removeItem(at: directory)
        }
        let files = try FileStore(directory: directory, protection: .none)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: directory)
        let first = try makeStore(files)
        let second = try makeStore(try FileStore(directory: link, protection: .none))
        try await first.save(Note(id: "a", text: "A"))
        await #expect(throws: OfflineFirstError.storeChangedElsewhere(name: "notes")) {
            try await second.save(Note(id: "b", text: "B"))
        }
        #expect(try await makeStore(files).records().map(\.id) == ["a"])
    }

    /// The documented limit: a custom backend without an identity is not protected, and the
    /// instance that writes last keeps only its own records.
    @Test func aCustomBackendWithoutAnIdentityIsNotProtected() async throws {
        let anonymous = AnonymousStorage()
        #expect(anonymous.claimIdentity == nil)
        #expect(FileClaims.key(for: anonymous, name: "notes.store") == nil)
        let first = try makeStore(anonymous)
        let second = try makeStore(anonymous)
        try await first.save(Note(id: "a", text: "A"))
        try await second.save(Note(id: "b", text: "B"))
        #expect(try await makeStore(anonymous.base).records().map(\.id) == ["b"])
    }

    @Test func identitiesNameTheBackendsPlace() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try FileStore(directory: directory, protection: .none)
        let again = try FileStore(directory: directory.appending(path: "."), protection: .none)
        #expect(files.claimIdentity != nil)
        #expect(files.claimIdentity == again.claimIdentity)
        #expect(FileClaims.key(for: files, name: "a.store") != FileClaims.key(for: files, name: "b.store"))
        let memory = InMemoryStorage()
        #expect(memory.claimIdentity != nil)
        #expect(memory.claimIdentity != InMemoryStorage().claimIdentity)
        #expect(memory.claimIdentity != files.claimIdentity)
    }
}
