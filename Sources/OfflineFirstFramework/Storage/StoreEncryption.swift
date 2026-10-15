import CryptoKit
import Foundation

/// How an ``OfflineStore`` encrypts its file.
///
/// With a key, the store seals its data with AES-GCM before writing it, and authenticates the
/// store name with it, so a file copied over the file of another store fails to open instead of
/// replacing that store's data.
///
/// ```swift
/// // A random 256-bit key, created on first use and kept in the Keychain.
/// let encryption = try StoreEncryption.keychain(
///     account: "notes-store-key",
///     keychain: KeychainStore(service: "com.example.notes")
/// )
/// ```
public struct StoreEncryption: Sendable {
    /// The bytes every encrypted file starts with.
    static let header = Data("OFE1".utf8)

    private let key: Data?

    /// Whether an unencrypted file is read anyway (and written back encrypted). Use it once
    /// when you turn on encryption for an existing store, then turn it off: while it is on,
    /// someone who can write the file can replace its data without knowing the key.
    public let acceptsUnencryptedData: Bool

    private init(key: Data?, acceptsUnencryptedData: Bool) {
        self.key = key
        self.acceptsUnencryptedData = acceptsUnencryptedData
    }

    /// No encryption. Files are plain JSON, protected only by the platform's file protection.
    public static let none = StoreEncryption(key: nil, acceptsUnencryptedData: true)

    /// AES-GCM with the given 128-, 192- or 256-bit key.
    public static func aesGCM(key: SymmetricKey, acceptsUnencryptedData: Bool = false) throws -> StoreEncryption {
        let bytes = key.withUnsafeBytes { Data($0) }
        guard [16, 24, 32].contains(bytes.count) else {
            throw OfflineFirstError.invalidKeySize(bytes: bytes.count)
        }
        return StoreEncryption(key: bytes, acceptsUnencryptedData: acceptsUnencryptedData)
    }

    /// AES-GCM with a 256-bit key stored in the Keychain under `account`. The key is created
    /// with the system random number generator the first time.
    public static func keychain(account: String, keychain: KeychainStore, acceptsUnencryptedData: Bool = false) throws -> StoreEncryption {
        let stored: Data
        if let existing = try keychain.load(account) {
            stored = existing
        } else {
            let fresh = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
            stored = try keychain.saveIfAbsent(fresh, for: account)
        }
        return try aesGCM(key: SymmetricKey(data: stored), acceptsUnencryptedData: acceptsUnencryptedData)
    }

    /// Whether data is encrypted before it is written.
    public var isEnabled: Bool {
        key != nil
    }

    /// Encrypts `plaintext` for the store `name`, or returns it unchanged without a key.
    func seal(_ plaintext: Data, name: String) throws -> Data {
        guard let key else { return plaintext }
        do {
            let box = try AES.GCM.seal(plaintext, using: SymmetricKey(data: key), authenticating: Data(name.utf8))
            guard let combined = box.combined else { throw OfflineFirstError.decryptionFailed }
            return Self.header + combined
        } catch let error as OfflineFirstError {
            throw error
        } catch {
            throw OfflineFirstError.fileSystem(name: name, description: "encryption failed: \(error.localizedDescription)")
        }
    }

    /// Decrypts data read for the store `name`.
    func open(_ stored: Data, name: String) throws -> Data {
        let isEncrypted = stored.starts(with: Self.header)
        guard let key else {
            if isEncrypted { throw OfflineFirstError.encryptedStoreWithoutKey(name: name) }
            return stored
        }
        guard isEncrypted else {
            if acceptsUnencryptedData { return stored }
            throw OfflineFirstError.decryptionFailed
        }
        do {
            let box = try AES.GCM.SealedBox(combined: stored.dropFirst(Self.header.count))
            return try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data(name.utf8))
        } catch {
            throw OfflineFirstError.decryptionFailed
        }
    }
}
