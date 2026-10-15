import Foundation

/// A ``StorageBackend`` that keeps one file per name in a directory.
///
/// Writes are atomic (the data goes to a temporary file that replaces the old one), and on iOS,
/// tvOS, watchOS and visionOS the files get the
/// `completeUntilFirstUserAuthentication` data protection class by default, so background sync
/// can read them once the device has been unlocked after a restart.
///
/// ```swift
/// let files = try FileStore.applicationSupport()
/// let store = try OfflineStore<Note>(name: "notes", storage: files)
/// ```
///
/// Names are checked with ``StorageName/validate(_:)``, which rejects path separators and
/// `..`, so a name cannot point outside ``directory``.
public struct FileStore: StorageBackend {
    /// The file protection class for written files. It has an effect on iOS, tvOS, watchOS and
    /// visionOS; macOS ignores it.
    public enum Protection: Sendable {
        /// Readable once the user has unlocked the device after it started. The default.
        case untilFirstUserAuthentication
        /// Readable only while the device is unlocked. Background sync with a locked device
        /// fails with this class.
        case complete
        /// No data protection beyond the system default.
        case none

        var writingOptions: Data.WritingOptions {
            switch self {
            case .untilFirstUserAuthentication: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            case .complete: [.atomic, .completeFileProtection]
            case .none: [.atomic]
            }
        }
    }

    /// The default limit for ``maximumFileSize``: 256 MiB.
    public static let defaultMaximumFileSize = 256 * 1024 * 1024

    /// The directory that holds the files.
    public let directory: URL

    /// How written files are protected.
    public let protection: Protection

    /// Files larger than this many bytes are not read, so a damaged or planted file cannot make
    /// the app load an arbitrary amount of data into memory.
    public let maximumFileSize: Int

    /// Creates a store in `directory`, creating the directory if needed.
    public init(directory: URL, protection: Protection = .untilFirstUserAuthentication, maximumFileSize: Int = FileStore.defaultMaximumFileSize) throws {
        self.directory = directory
        self.protection = protection
        self.maximumFileSize = max(0, maximumFileSize)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw OfflineFirstError.fileSystem(name: directory.lastPathComponent, description: error.localizedDescription)
        }
    }

    /// A store in `Application Support/<subdirectory>` of the app's container.
    public static func applicationSupport(subdirectory: String = "OfflineFirst", protection: Protection = .untilFirstUserAuthentication) throws -> FileStore {
        try StorageName.validate(subdirectory)
        let base = URL.applicationSupportDirectory
        return try FileStore(directory: base.appending(path: subdirectory, directoryHint: .isDirectory), protection: protection)
    }

    /// The URL of the file for `name`.
    public func url(for name: String) throws -> URL {
        try StorageName.validate(name)
        return directory.appending(path: name, directoryHint: .notDirectory)
    }

    public func read(_ name: String) throws -> Data? {
        let url = try url(for: name)
        let size: Int
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else {
                throw OfflineFirstError.fileSystem(name: name, description: "not a regular file")
            }
            size = values.fileSize ?? 0
        } catch let error as OfflineFirstError {
            throw error
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw OfflineFirstError.fileSystem(name: name, description: error.localizedDescription)
        }
        guard size <= maximumFileSize else {
            throw OfflineFirstError.fileTooLarge(name: name, size: size, limit: maximumFileSize)
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw OfflineFirstError.fileSystem(name: name, description: error.localizedDescription)
        }
    }

    public func write(_ data: Data, to name: String) throws {
        let url = try url(for: name)
        do {
            try data.write(to: url, options: protection.writingOptions)
        } catch {
            throw OfflineFirstError.fileSystem(name: name, description: error.localizedDescription)
        }
    }

    public func remove(_ name: String) throws {
        let url = try url(for: name)
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            throw OfflineFirstError.fileSystem(name: name, description: error.localizedDescription)
        }
    }

    public func move(_ name: String, to newName: String) throws {
        let source = try url(for: name)
        let destination = try url(for: newName)
        do {
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: source)
            } else {
                try FileManager.default.moveItem(at: source, to: destination)
            }
        } catch {
            throw OfflineFirstError.fileSystem(name: name, description: error.localizedDescription)
        }
    }

    /// The names of the files in ``directory``, sorted.
    public func names() throws -> [String] {
        do {
            return try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
                .filter { (try? StorageName.validate($0)) != nil }
                .sorted()
        } catch {
            throw OfflineFirstError.fileSystem(name: directory.lastPathComponent, description: error.localizedDescription)
        }
    }
}
