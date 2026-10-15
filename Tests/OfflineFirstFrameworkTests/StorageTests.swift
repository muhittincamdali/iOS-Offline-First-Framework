import CryptoKit
import Foundation
import Security
import Testing
@testable import OfflineFirstFramework

func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "OfflineFirstTests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

@Suite("Storage names")
struct StorageNameTests {
    @Test(arguments: ["notes", "notes.store", "a_b-c.1", String(repeating: "x", count: 255)])
    func acceptsPlainNames(name: String) throws {
        try StorageName.validate(name)
    }

    @Test(arguments: ["", "..", ".", ".hidden", "../secrets", "a/b", "/etc/passwd", "a\\b", "notes\0", "ünïcode", "with space", String(repeating: "x", count: 256)])
    func rejectsNamesThatCouldLeaveTheDirectory(name: String) {
        #expect(throws: OfflineFirstError.invalidName(name)) {
            try StorageName.validate(name)
        }
    }
}

@Suite("File store")
struct FileStoreTests {
    @Test func writesReadsAndRemoves() throws {
        let store = try FileStore(directory: temporaryDirectory())
        #expect(try store.read("notes") == nil)
        try store.write(Data("one".utf8), to: "notes")
        try store.write(Data("two".utf8), to: "notes")
        #expect(try store.read("notes") == Data("two".utf8))
        #expect(try store.names() == ["notes"])
        try store.remove("notes")
        try store.remove("notes")
        #expect(try store.read("notes") == nil)
    }

    @Test func refusesNamesOutsideTheDirectory() throws {
        let directory = temporaryDirectory()
        let store = try FileStore(directory: directory.appending(path: "inner"))
        #expect(throws: OfflineFirstError.invalidName("../escaped")) {
            try store.write(Data("x".utf8), to: "../escaped")
        }
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "escaped").path(percentEncoded: false)))
    }

    @Test func refusesFilesAboveTheSizeLimit() throws {
        let store = try FileStore(directory: temporaryDirectory(), maximumFileSize: 8)
        try store.write(Data(repeating: 1, count: 9), to: "big")
        #expect(throws: OfflineFirstError.fileTooLarge(name: "big", size: 9, limit: 8)) {
            try store.read("big")
        }
        try store.write(Data(repeating: 1, count: 8), to: "fits")
        #expect(try store.read("fits")?.count == 8)
    }

    @Test func refusesToReadADirectory() throws {
        let directory = temporaryDirectory()
        let store = try FileStore(directory: directory)
        try FileManager.default.createDirectory(at: directory.appending(path: "folder"), withIntermediateDirectories: true)
        #expect(throws: OfflineFirstError.self) {
            try store.read("folder")
        }
    }

    @Test func moveReplacesTheDestination() throws {
        let store = try FileStore(directory: temporaryDirectory())
        try store.write(Data("new".utf8), to: "a")
        try store.write(Data("old".utf8), to: "b")
        try store.move("a", to: "b")
        #expect(try store.read("a") == nil)
        #expect(try store.read("b") == Data("new".utf8))
        try store.move("b", to: "c")
        #expect(try store.read("c") == Data("new".utf8))
    }

    @Test func applicationSupportValidatesTheSubdirectory() {
        #expect(throws: OfflineFirstError.invalidName("../Library")) {
            try FileStore.applicationSupport(subdirectory: "../Library")
        }
    }
}

@Suite("In-memory storage")
struct InMemoryStorageTests {
    @Test func behavesLikeTheFileStore() throws {
        let storage = InMemoryStorage()
        #expect(try storage.read("a") == nil)
        try storage.write(Data([1]), to: "a")
        try storage.move("a", to: "b")
        #expect(storage.names == ["b"])
        #expect(try storage.read("b") == Data([1]))
        try storage.remove("b")
        try storage.remove("b")
        #expect(storage.names.isEmpty)
        #expect(throws: OfflineFirstError.self) { try storage.move("missing", to: "c") }
        #expect(throws: OfflineFirstError.invalidName("../a")) { try storage.write(Data(), to: "../a") }
    }
}

@Suite("Store encryption")
struct StoreEncryptionTests {
    private let plaintext = Data(#"{"records":[]}"#.utf8)

    @Test func sealedDataOpensWithTheSameKeyAndName() throws {
        let encryption = try StoreEncryption.aesGCM(key: SymmetricKey(size: .bits256))
        let sealed = try encryption.seal(plaintext, name: "notes")
        #expect(sealed.starts(with: StoreEncryption.header))
        #expect(sealed.range(of: Data("records".utf8)) == nil)
        #expect(try encryption.open(sealed, name: "notes") == plaintext)
    }

    @Test func wrongKeyTamperingAndOtherStoresFail() throws {
        let encryption = try StoreEncryption.aesGCM(key: SymmetricKey(size: .bits256))
        let other = try StoreEncryption.aesGCM(key: SymmetricKey(size: .bits256))
        let sealed = try encryption.seal(plaintext, name: "notes")
        var tampered = sealed
        tampered[tampered.count - 1] ^= 0x01

        #expect(throws: OfflineFirstError.decryptionFailed) { try other.open(sealed, name: "notes") }
        #expect(throws: OfflineFirstError.decryptionFailed) { try encryption.open(tampered, name: "notes") }
        #expect(throws: OfflineFirstError.decryptionFailed) { try encryption.open(sealed, name: "accounts") }
        #expect(throws: OfflineFirstError.decryptionFailed) { try encryption.open(StoreEncryption.header, name: "notes") }
    }

    @Test func unencryptedDataIsRefusedUnlessAllowed() throws {
        let key = SymmetricKey(size: .bits128)
        let strict = try StoreEncryption.aesGCM(key: key)
        let migrating = try StoreEncryption.aesGCM(key: key, acceptsUnencryptedData: true)
        #expect(throws: OfflineFirstError.decryptionFailed) { try strict.open(plaintext, name: "notes") }
        #expect(try migrating.open(plaintext, name: "notes") == plaintext)
    }

    @Test func encryptedDataNeedsAKey() throws {
        let sealed = try StoreEncryption.aesGCM(key: SymmetricKey(size: .bits192)).seal(plaintext, name: "notes")
        #expect(throws: OfflineFirstError.encryptedStoreWithoutKey(name: "notes")) {
            try StoreEncryption.none.open(sealed, name: "notes")
        }
        #expect(try StoreEncryption.none.seal(plaintext, name: "notes") == plaintext)
        #expect(!StoreEncryption.none.isEnabled)
    }

    @Test(arguments: [0, 1, 15, 31, 33, 64])
    func rejectsKeysOfOtherSizes(bytes: Int) {
        #expect(throws: OfflineFirstError.invalidKeySize(bytes: bytes)) {
            try StoreEncryption.aesGCM(key: SymmetricKey(data: Data(repeating: 7, count: bytes)))
        }
    }
}

/// Unhosted test bundles on the iOS simulator have no Keychain entitlement
/// (errSecMissingEntitlement); the Keychain tests run on macOS and wherever the host allows it.
enum KeychainAvailability {
    static let isAvailable: Bool = {
        let probe = KeychainStore(service: "OfflineFirstFrameworkTests.probe.\(UUID().uuidString)")
        do {
            try probe.save(Data([1]), for: "probe")
            try? probe.delete("probe")
            return true
        } catch OfflineFirstError.keychain(status: errSecMissingEntitlement) {
            return false
        } catch {
            return true
        }
    }()
}

@Suite("Keychain store", .enabled(if: KeychainAvailability.isAvailable, "This test host has no Keychain entitlement."))
struct KeychainStoreTests {
    @Test func savesLoadsAndDeletes() throws {
        let keychain = KeychainStore(service: "OfflineFirstFrameworkTests.\(UUID().uuidString)")
        defer { try? keychain.delete("token") }
        #expect(try keychain.load("token") == nil)
        try keychain.save(Data("one".utf8), for: "token")
        try keychain.save(Data("two".utf8), for: "token")
        #expect(try keychain.load("token") == Data("two".utf8))
        #expect(try keychain.saveIfAbsent(Data("three".utf8), for: "token") == Data("two".utf8))
        try keychain.delete("token")
        try keychain.delete("token")
        #expect(try keychain.load("token") == nil)
    }

    @Test func keychainEncryptionReusesItsKey() throws {
        let keychain = KeychainStore(service: "OfflineFirstFrameworkTests.\(UUID().uuidString)")
        defer { try? keychain.delete("store-key") }
        let first = try StoreEncryption.keychain(account: "store-key", keychain: keychain)
        let sealed = try first.seal(Data("secret".utf8), name: "notes")
        let second = try StoreEncryption.keychain(account: "store-key", keychain: keychain)
        #expect(try second.open(sealed, name: "notes") == Data("secret".utf8))
        #expect(try keychain.load("store-key")?.count == 32)
    }
}
