import Foundation

/// Errors thrown by the stores, storage backends and the sync engine of this module.
public enum OfflineFirstError: Error, Equatable, Sendable {
    /// A store or file name contains characters other than letters, digits, `.`, `_` and `-`,
    /// starts with a dot, or is empty or longer than 255 bytes.
    case invalidName(String)

    /// A stored file is larger than the limit the backend accepts.
    case fileTooLarge(name: String, size: Int, limit: Int)

    /// A file system operation failed.
    case fileSystem(name: String, description: String)

    /// A Keychain call returned an error status.
    case keychain(status: Int32)

    /// An encryption key does not have 128, 192 or 256 bits.
    case invalidKeySize(bytes: Int)

    /// Stored data could not be decrypted: the key is wrong, the data was changed, or it was
    /// not encrypted although the store requires encryption.
    case decryptionFailed

    /// The store file is encrypted, but the store was opened without a key.
    case encryptedStoreWithoutKey(name: String)

    /// The store file could not be decoded.
    case corruptStore(name: String, description: String)

    /// The store file was written by a newer schema version than the app knows.
    case unsupportedSchemaVersion(found: Int, supported: Int)

    /// A record migration threw an error.
    case migrationFailed(toVersion: Int, description: String)

    /// The store already holds the maximum number of unsynced changes.
    case outboxFull(limit: Int)

    /// The server answered a pull with the cursor it was given and said more changes follow,
    /// which would repeat the same page forever.
    case pullCursorDidNotAdvance(cursor: String?)

    /// One sync pulled the maximum number of pages and the server still had more.
    case tooManyPullPages(limit: Int)

    /// The hybrid logical clock could not produce a timestamp.
    case clock(HybridLogicalClock.Failure)
}

extension OfflineFirstError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            "“\(name)” is not a valid store name. Use 1 to 255 letters, digits, “.”, “_” or “-”, not starting with “.”."
        case .fileTooLarge(let name, let size, let limit):
            "The file “\(name)” has \(size) bytes, more than the limit of \(limit) bytes."
        case .fileSystem(let name, let description):
            "The file “\(name)” could not be accessed: \(description)"
        case .keychain(let status):
            "The Keychain returned error \(status)."
        case .invalidKeySize(let bytes):
            "An encryption key needs 16, 24 or 32 bytes, not \(bytes)."
        case .decryptionFailed:
            "The stored data could not be decrypted."
        case .encryptedStoreWithoutKey(let name):
            "The store “\(name)” is encrypted; open it with its encryption key."
        case .corruptStore(let name, let description):
            "The store “\(name)” could not be read: \(description)"
        case .unsupportedSchemaVersion(let found, let supported):
            "The store has schema version \(found), but this app supports up to version \(supported)."
        case .migrationFailed(let version, let description):
            "The migration to schema version \(version) failed: \(description)"
        case .outboxFull(let limit):
            "There are already \(limit) changes waiting to sync."
        case .pullCursorDidNotAdvance(let cursor):
            "The server returned the same sync cursor (\(cursor ?? "none")) and said more changes follow."
        case .tooManyPullPages(let limit):
            "The server still had changes after \(limit) pages; the rest will be pulled on the next sync."
        case .clock(let failure):
            "The sync clock failed: \(failure)."
        }
    }
}
