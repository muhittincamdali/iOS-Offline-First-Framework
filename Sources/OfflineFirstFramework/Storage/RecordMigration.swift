/// Rewrites stored records when their type changes between app versions.
///
/// A store remembers the schema version its records were written with. When the app opens the
/// store with a higher ``OfflineStore/Configuration/schemaVersion``, every migration whose
/// ``version`` is above the stored version runs, in order, on the JSON object of each record
/// (stored records and records waiting to sync), before the records are decoded.
///
/// ```swift
/// // Version 2 renamed `text` to `body` and added `isPinned`.
/// let renameText = RecordMigration(to: 2) { record in
///     record["body"] = record["text"]
///     record["text"] = nil
///     record["isPinned"] = false
/// }
/// ```
///
/// A store written by a higher version than the app knows is not opened
/// (``OfflineFirstError/unsupportedSchemaVersion(found:supported:)``), so an older app version
/// never drops fields it does not know.
public struct RecordMigration: Sendable {
    /// The schema version the records have after this migration.
    public let version: Int

    private let transform: @Sendable (inout [String: JSONValue]) throws -> Void

    /// Creates a migration that produces schema version `version` (1 or higher).
    public init(to version: Int, _ transform: @escaping @Sendable (inout [String: JSONValue]) throws -> Void) {
        self.version = version
        self.transform = transform
    }

    /// Applies the migrations above `storedVersion`, up to `currentVersion`, to `records`.
    ///
    /// - Throws: ``OfflineFirstError/unsupportedSchemaVersion(found:supported:)`` when
    ///   `storedVersion` is above `currentVersion`, and
    ///   ``OfflineFirstError/migrationFailed(toVersion:description:)`` when two migrations share
    ///   a version, a record is not a JSON object, or a transform throws.
    public static func migrate(
        _ records: inout [JSONValue],
        from storedVersion: Int,
        to currentVersion: Int,
        using migrations: [RecordMigration]
    ) throws(OfflineFirstError) {
        guard storedVersion <= currentVersion else {
            throw .unsupportedSchemaVersion(found: storedVersion, supported: currentVersion)
        }
        let steps = migrations
            .filter { $0.version > storedVersion && $0.version <= currentVersion }
            .sorted { $0.version < $1.version }
        for (step, next) in zip(steps, steps.dropFirst()) where step.version == next.version {
            throw .migrationFailed(toVersion: step.version, description: "two migrations produce version \(step.version)")
        }
        for step in steps {
            for index in records.indices {
                guard case .object(var members) = records[index] else {
                    throw .migrationFailed(toVersion: step.version, description: "a stored record is not a JSON object")
                }
                do {
                    try step.transform(&members)
                } catch {
                    throw .migrationFailed(toVersion: step.version, description: String(describing: error))
                }
                records[index] = .object(members)
            }
        }
    }
}
