import Foundation

extension OfflineStore {
    /// Settings of an ``OfflineStore``. Every property has a default, so set only what you need:
    ///
    /// ```swift
    /// var configuration = OfflineStore<Note>.Configuration()
    /// configuration.conflictResolver = .serverWins
    /// configuration.encryption = try .keychain(account: "notes", keychain: KeychainStore(service: "com.example.notes"))
    /// ```
    public struct Configuration: Sendable {
        /// How the store file is encrypted. Default: ``StoreEncryption/none``.
        public var encryption: StoreEncryption

        /// Who wins when a record changed on the device and on the server. Default:
        /// ``ConflictResolver/lastWriteWins``.
        public var conflictResolver: ConflictResolver<Record>

        /// Backoff and attempt limit for failed pushes. Default: ``RetryPolicy/default``.
        public var retryPolicy: RetryPolicy

        /// Pauses syncing after repeated failures. Default: 5 failures, 60 seconds.
        public var circuitBreaker: CircuitBreaker

        /// The schema version of `Record`. Raise it, and add a ``RecordMigration``, when you
        /// change the record type in a way its `Decodable` conformance cannot read. Default: 1.
        public var schemaVersion: Int

        /// Migrations that bring stored records up to ``schemaVersion``.
        public var migrations: [RecordMigration]

        /// Changes sent in one push call, from 1 to 1,000. Default: 100.
        public var pushBatchSize: Int

        /// Local changes the store keeps before ``OfflineStore/save(_:)`` throws
        /// ``OfflineFirstError/outboxFull(limit:)``. Default: 10,000.
        public var maximumPendingChanges: Int

        /// Pull pages fetched in one sync; the rest waits for the next sync. Default: 100.
        public var maximumPullPages: Int

        /// How far ahead of the device clock a server timestamp may be before the store stops
        /// moving its clock to it. Default: 5 minutes.
        public var maximumClockDrift: Duration

        /// What happens when the store file cannot be read. Default: ``CorruptionPolicy/fail``.
        public var corruptionPolicy: CorruptionPolicy

        /// The current time. Replace it in tests.
        public var now: @Sendable () -> Date

        /// A random number in `0..<1` for retry jitter. Replace it in tests.
        public var random: @Sendable () -> Double

        /// Creates a configuration with the defaults.
        public init(
            encryption: StoreEncryption = .none,
            conflictResolver: ConflictResolver<Record> = .lastWriteWins,
            retryPolicy: RetryPolicy = .default,
            circuitBreaker: CircuitBreaker = CircuitBreaker(),
            schemaVersion: Int = 1,
            migrations: [RecordMigration] = [],
            pushBatchSize: Int = 100,
            maximumPendingChanges: Int = 10_000,
            maximumPullPages: Int = 100,
            maximumClockDrift: Duration = .seconds(300),
            corruptionPolicy: CorruptionPolicy = .fail,
            now: @escaping @Sendable () -> Date = { Date() },
            random: @escaping @Sendable () -> Double = { Double.random(in: 0..<1) }
        ) {
            self.encryption = encryption
            self.conflictResolver = conflictResolver
            self.retryPolicy = retryPolicy
            self.circuitBreaker = circuitBreaker
            self.schemaVersion = schemaVersion
            self.migrations = migrations
            self.pushBatchSize = pushBatchSize
            self.maximumPendingChanges = maximumPendingChanges
            self.maximumPullPages = maximumPullPages
            self.maximumClockDrift = maximumClockDrift
            self.corruptionPolicy = corruptionPolicy
            self.now = now
            self.random = random
        }

        /// The settings with every count clamped to its allowed range.
        var normalized: Configuration {
            var copy = self
            copy.schemaVersion = max(1, schemaVersion)
            copy.pushBatchSize = min(max(1, pushBatchSize), 1_000)
            copy.maximumPendingChanges = max(1, maximumPendingChanges)
            copy.maximumPullPages = max(1, maximumPullPages)
            copy.maximumClockDrift = max(.zero, maximumClockDrift)
            return copy
        }
    }
}
