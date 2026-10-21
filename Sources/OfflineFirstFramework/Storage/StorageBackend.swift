import Foundation
import os

/// Where an ``OfflineStore`` keeps its bytes.
///
/// The module ships two backends: ``FileStore`` (files on disk, the default) and
/// ``InMemoryStorage`` (for tests and SwiftUI previews). Conform your own type to store the
/// data elsewhere, for example in an app group container.
public protocol StorageBackend: Sendable {
    /// Returns the bytes stored under `name`, or `nil` when there are none.
    func read(_ name: String) throws -> Data?

    /// Replaces the bytes stored under `name`. The write must be atomic: after a crash the
    /// old or the new bytes are stored, never a mix. A backend that limits what it reads must
    /// refuse to write more, so the store never writes a file it cannot open again.
    func write(_ data: Data, to name: String) throws

    /// Deletes the bytes stored under `name`. Deleting a missing name is not an error.
    func remove(_ name: String) throws

    /// Renames `name` to `newName`, replacing anything stored under `newName`.
    func move(_ name: String, to newName: String) throws

    /// Names the place this backend keeps its bytes in, so that two ``OfflineStore`` instances
    /// in this process that open one file through it do not overwrite each other: once one of
    /// them wrote the file, the other one's write throws
    /// ``OfflineFirstError/storeChangedElsewhere(name:)``.
    ///
    /// Two backends with the same identity must keep a name in the same place, and two that
    /// keep it in different places need different identities. ``FileStore`` and
    /// ``InMemoryStorage`` report one; a backend that wraps one of them and keeps its names can
    /// return the wrapped backend's identity. The default, `nil`, leaves the backend's files
    /// unprotected: two instances on one file then each write their own state, and the last
    /// writer drops the records the other one saved.
    var claimIdentity: String? { get }
}

extension StorageBackend {
    /// `nil`: stores on this backend are not kept from overwriting each other.
    public var claimIdentity: String? { nil }
}

/// Checks that names are safe to use as file names.
public enum StorageName {
    /// The longest name, in UTF-8 bytes, that file systems on Apple platforms accept.
    public static let maximumLength = 255

    private static let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-".utf8)

    /// Throws ``OfflineFirstError/invalidName(_:)`` unless `name` is 1 to 255 bytes of letters,
    /// digits, `.`, `_` and `-` that does not start with a dot.
    ///
    /// The rule leaves no way to name a parent directory (`..`), an absolute path or a
    /// subdirectory, so a name that comes from outside the app cannot reach other files.
    public static func validate(_ name: String) throws(OfflineFirstError) {
        let bytes = Array(name.utf8)
        guard !bytes.isEmpty,
              bytes.count <= maximumLength,
              bytes.first != UInt8(ascii: "."),
              bytes.allSatisfy(allowed.contains)
        else {
            throw .invalidName(name)
        }
    }
}

/// A ``StorageBackend`` that keeps everything in memory. Use it in tests and previews.
public final class InMemoryStorage: StorageBackend {
    private let files = OSAllocatedUnfairLock<[String: Data]>(initialState: [:])

    /// Creates empty storage.
    public init() {}

    /// The names that currently hold data, sorted.
    public var names: [String] {
        files.withLock { $0.keys.sorted() }
    }

    /// This instance: stores on the same `InMemoryStorage` share their files.
    public var claimIdentity: String? {
        "memory:\(ObjectIdentifier(self))"
    }

    public func read(_ name: String) throws -> Data? {
        try StorageName.validate(name)
        return files.withLock { $0[name] }
    }

    public func write(_ data: Data, to name: String) throws {
        try StorageName.validate(name)
        files.withLock { $0[name] = data }
    }

    public func remove(_ name: String) throws {
        try StorageName.validate(name)
        _ = files.withLock { $0.removeValue(forKey: name) }
    }

    public func move(_ name: String, to newName: String) throws {
        try StorageName.validate(name)
        try StorageName.validate(newName)
        try files.withLock { files in
            guard let data = files.removeValue(forKey: name) else {
                throw OfflineFirstError.fileSystem(name: name, description: "nothing is stored under this name")
            }
            files[newName] = data
        }
    }
}
