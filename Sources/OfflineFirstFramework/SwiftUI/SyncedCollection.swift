import Foundation
import Observation
import os

/// The records and sync state of an ``OfflineStore`` as an observable model for SwiftUI.
///
/// ```swift
/// struct NotesView: View {
///     @State private var notes = SyncedCollection(store: AppStores.notes)
///
///     var body: some View {
///         List(notes.records) { note in
///             Text(note.text)
///         }
///         .refreshable { await notes.sync() }
///     }
/// }
/// ```
///
/// The model follows the store: changes made through it, through the store directly or by a
/// sync all show up. Errors from its methods are kept in ``lastError`` instead of being thrown,
/// so views can call them from buttons.
@MainActor
@Observable
public final class SyncedCollection<Record: SyncableRecord> {
    /// The store this model follows.
    public let store: OfflineStore<Record>

    /// The records, in the order they were first stored.
    public private(set) var records: [Record] = []

    /// Local changes not yet accepted by the server.
    public private(set) var pendingCount = 0

    /// Changes parked after their last attempt or a rejection.
    public private(set) var failedCount = 0

    /// What the store is doing about sync.
    public private(set) var status: SyncStatus = .idle

    /// When the last sync finished successfully.
    public private(set) var lastSyncedAt: Date?

    /// The message of the last error from ``save(_:)``, ``delete(_:)``, ``sync()`` or
    /// ``retryFailedChanges()``, cleared by the next call that succeeds.
    public private(set) var lastError: String?

    /// Whether the model has received the store's state at least once.
    public private(set) var isLoaded = false

    @ObservationIgnored private let subscription = Subscription()

    /// Creates a model that follows `store`.
    public init(store: OfflineStore<Record>) {
        self.store = store
        subscription.set(Task { [weak self] in
            for await state in await store.states() {
                guard let self else { return }
                self.apply(state)
            }
        })
    }

    /// Saves `record` in the store.
    public func save(_ record: Record) async {
        await run { try await self.store.save(record) }
    }

    /// Deletes the record with `id`.
    public func delete(_ id: Record.ID) async {
        await run { try await self.store.delete(id) }
    }

    /// Runs a sync now.
    public func sync() async {
        await run { try await self.store.sync() }
    }

    /// Puts parked changes back in the queue.
    public func retryFailedChanges() async {
        await run { try await self.store.retryFailedChanges() }
    }

    private func run(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            lastError = nil
        } catch is CancellationError {
            return
        } catch {
            lastError = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    private func apply(_ state: StoreState<Record>) {
        records = state.records
        pendingCount = state.pendingCount
        failedCount = state.failedCount
        status = state.status
        lastSyncedAt = state.lastSyncedAt
        isLoaded = true
    }
}

/// Cancels the observation task when the model goes away.
private final class Subscription: Sendable {
    private let task = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

    func set(_ newTask: Task<Void, Never>) {
        task.withLock { $0 = newTask }
    }

    deinit {
        task.withLock { $0?.cancel() }
    }
}
