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

        /// Pauses pulls after repeated failures. Default: 5 failures, 60 seconds.
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

        /// Deleted records the store remembers, so that an older version of one that arrives
        /// late (a page out of order, a lagging replica) does not bring it back. Beyond the
        /// limit the oldest are forgotten; such a late version could then return the record.
        /// Each takes a few hundred bytes in the file. Default: 10,000.
        public var maximumTombstones: Int

        /// How far a server timestamp may be ahead of the device clock, or of the newest
        /// timestamp the store holds when that is later (after the device clock was set back).
        /// The store does not move its clock to a timestamp further ahead of the device clock;
        /// last write wins weighs such a timestamp against local writes as if it were at the
        /// limit, and server versions are not ordered by it. Default: 5 minutes.
        public var maximumClockDrift: Duration

        /// What happens when the store file cannot be read. Default: ``CorruptionPolicy/fail``.
        public var corruptionPolicy: CorruptionPolicy

        /// The longest a sync may run, from one second to one day. When a sync runs longer, its
        /// request is cancelled and ``OfflineStore/sync()`` throws `URLError(.timedOut)`; what
        /// was stored so far stays, and the changes of a cancelled push count a failed attempt.
        /// A server that never answers, or answers a byte at a time, cannot keep every caller
        /// of ``OfflineStore/sync()`` and automatic sync waiting. Default: 5 minutes.
        public var syncTimeout: Duration

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
            maximumTombstones: Int = 10_000,
            maximumClockDrift: Duration = .seconds(300),
            corruptionPolicy: CorruptionPolicy = .fail,
            syncTimeout: Duration = .seconds(300),
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
            self.maximumTombstones = maximumTombstones
            self.maximumClockDrift = maximumClockDrift
            self.corruptionPolicy = corruptionPolicy
            self.syncTimeout = syncTimeout
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
            copy.maximumTombstones = max(0, maximumTombstones)
            copy.maximumClockDrift = max(.zero, maximumClockDrift)
            copy.syncTimeout = min(max(.seconds(1), syncTimeout), .seconds(86_400))
            return copy
        }
    }
}
