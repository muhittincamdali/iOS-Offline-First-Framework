import Foundation
import os

/// Keeps two stores in one process that use the same file from overwriting each other.
///
/// Each store writes its whole state. Two instances on one file (a store created twice, or
/// opened again while the first one is still in use) would each write their own state, and the
/// last writer would silently drop the other's saved records. Every write of a file therefore
/// moves the file's generation on, and a store writes only while the file is still at the
/// generation it read or last wrote itself. Another process (an app extension) is not covered.
final class FileClaims: Sendable {
    static let shared = FileClaims()

    /// The generation of one file, with the lock that serialises its writes.
    private final class Claim: Sendable {
        let generation = OSAllocatedUnfairLock(initialState: UInt64(0))
    }

    private let claims = OSAllocatedUnfairLock<[String: Claim]>(initialState: [:])

    /// The key of the file `name` in `storage`, or `nil` for a backend whose files cannot be
    /// told apart (a custom one).
    static func key(for storage: any StorageBackend, name: String) -> String? {
        if let files = storage as? FileStore, let url = try? files.url(for: name) {
            return "file:" + url.standardizedFileURL.path(percentEncoded: false)
        }
        if let memory = storage as? InMemoryStorage {
            return "memory:\(ObjectIdentifier(memory)):\(name)"
        }
        return nil
    }

    /// The file's current generation.
    func generation(of key: String) -> UInt64 {
        claim(for: key).generation.withLock { $0 }
    }

    /// Runs `write` if the file is still at `expected` and returns the file's new generation,
    /// or returns `nil` without writing when another store wrote the file in the meantime.
    func write(_ key: String, expecting expected: UInt64, _ write: () throws -> Void) rethrows -> UInt64? {
        try claim(for: key).generation.withLockUnchecked { generation in
            guard generation == expected else { return nil }
            try write()
            generation &+= 1
            return generation
        }
    }

    private func claim(for key: String) -> Claim {
        claims.withLock { claims in
            if let claim = claims[key] { return claim }
            let claim = Claim()
            claims[key] = claim
            return claim
        }
    }
}
