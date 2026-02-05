import Foundation
import Combine

// MARK: - Optimistic Update Configuration

/// Configuration for optimistic UI updates
public struct OptimisticUpdateConfiguration: Sendable {
    public let rollbackTimeout: TimeInterval
    public let maxPendingUpdates: Int
    public let enableAnimations: Bool
    public let showPendingIndicator: Bool
    
    public static let `default` = OptimisticUpdateConfiguration(
        rollbackTimeout: 30.0,
        maxPendingUpdates: 100,
        enableAnimations: true,
        showPendingIndicator: true
    )
    
    public init(
        rollbackTimeout: TimeInterval = 30.0,
        maxPendingUpdates: Int = 100,
        enableAnimations: Bool = true,
        showPendingIndicator: Bool = true
    ) {
        self.rollbackTimeout = rollbackTimeout
        self.maxPendingUpdates = maxPendingUpdates
        self.enableAnimations = enableAnimations
        self.showPendingIndicator = showPendingIndicator
    }
}

// MARK: - Pending Update

/// Represents a pending optimistic update
public struct PendingUpdate<T: Codable & Identifiable>: Identifiable where T.ID: Hashable {
    public let id: String
    public let entityId: T.ID
    public let originalValue: T?
    public let optimisticValue: T
    public let operation: UpdateOperation
    public let timestamp: Date
    public var status: UpdateStatus
    public var error: Error?
    
    public init(
        id: String = UUID().uuidString,
        entityId: T.ID,
        originalValue: T?,
        optimisticValue: T,
        operation: UpdateOperation,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.entityId = entityId
        self.originalValue = originalValue
        self.optimisticValue = optimisticValue
        self.operation = operation
        self.timestamp = timestamp
        self.status = .pending
    }
}

public enum UpdateOperation: String, Codable, Sendable {
    case create
    case update
    case delete
}

public enum UpdateStatus: String, Codable, Sendable {
    case pending
    case syncing
    case confirmed
    case failed
    case rolledBack
}

// MARK: - Optimistic Store Protocol

/// Protocol for stores that support optimistic updates
public protocol OptimisticStore: AnyObject {
    associatedtype Entity: Codable & Identifiable where Entity.ID: Hashable
    
    var entities: [Entity] { get set }
    var entitiesPublisher: AnyPublisher<[Entity], Never> { get }
    
    func find(id: Entity.ID) -> Entity?
    func insert(_ entity: Entity)
    func update(_ entity: Entity)
    func remove(id: Entity.ID)
}

// MARK: - Optimistic Update Manager

/// Manages optimistic UI updates with automatic rollback
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public final class OptimisticUpdateManager<Store: OptimisticStore>: ObservableObject {
    
    public typealias Entity = Store.Entity
    
    // MARK: - Published State
    
    @Published public private(set) var pendingUpdates: [PendingUpdate<Entity>] = []
    @Published public private(set) var failedUpdates: [PendingUpdate<Entity>] = []
    
    // MARK: - Properties
    
    private weak var store: Store?
    private let configuration: OptimisticUpdateConfiguration
    private var cancellables = Set<AnyCancellable>()
    private var rollbackTimers: [String: Timer] = [:]
    
    private let queue = DispatchQueue(label: "com.offlinefirst.optimistic", qos: .userInitiated)
    
    // MARK: - Computed Properties
    
    public var hasPendingUpdates: Bool {
        !pendingUpdates.isEmpty
    }
    
    public var pendingCount: Int {
        pendingUpdates.count
    }
    
    public func isPending(entityId: Entity.ID) -> Bool {
        pendingUpdates.contains { $0.entityId == entityId && $0.status == .pending }
    }
    
    public func isFailed(entityId: Entity.ID) -> Bool {
        failedUpdates.contains { $0.entityId == entityId }
    }
    
    // MARK: - Initialization
    
    public init(store: Store, configuration: OptimisticUpdateConfiguration = .default) {
        self.store = store
        self.configuration = configuration
    }
    
    // MARK: - Optimistic Operations
    
    /// Perform an optimistic create operation
    @discardableResult
    public func optimisticCreate(
        _ entity: Entity,
        syncOperation: @escaping () async throws -> Entity
    ) -> String {
        let update = PendingUpdate<Entity>(
            entityId: entity.id,
            originalValue: nil,
            optimisticValue: entity,
            operation: .create
        )
        
        // Apply optimistic update immediately
        store?.insert(entity)
        addPendingUpdate(update)
        
        // Perform actual sync in background
        Task {
            await performSync(updateId: update.id, operation: syncOperation)
        }
        
        return update.id
    }
    
    /// Perform an optimistic update operation
    @discardableResult
    public func optimisticUpdate(
        _ entity: Entity,
        syncOperation: @escaping () async throws -> Entity
    ) -> String {
        let originalValue = store?.find(id: entity.id)
        
        let update = PendingUpdate<Entity>(
            entityId: entity.id,
            originalValue: originalValue,
            optimisticValue: entity,
            operation: .update
        )
        
        // Apply optimistic update immediately
        store?.update(entity)
        addPendingUpdate(update)
        
        // Perform actual sync in background
        Task {
            await performSync(updateId: update.id, operation: syncOperation)
        }
        
        return update.id
    }
    
    /// Perform an optimistic delete operation
    @discardableResult
    public func optimisticDelete(
        id: Entity.ID,
        syncOperation: @escaping () async throws -> Void
    ) -> String {
        let originalValue = store?.find(id: id)
        
        // Create a placeholder for deleted entity
        guard let original = originalValue else {
            return ""
        }
        
        let update = PendingUpdate<Entity>(
            entityId: id,
            originalValue: original,
            optimisticValue: original,
            operation: .delete
        )
        
        // Apply optimistic delete immediately
        store?.remove(id: id)
        addPendingUpdate(update)
        
        // Perform actual sync in background
        Task {
            await performSyncDelete(updateId: update.id, operation: syncOperation)
        }
        
        return update.id
    }
    
    // MARK: - Sync Operations
    
    private func performSync(
        updateId: String,
        operation: @escaping () async throws -> Entity
    ) async {
        updateStatus(updateId: updateId, status: .syncing)
        
        do {
            let confirmedEntity = try await operation()
            
            await MainActor.run {
                // Update store with confirmed entity
                store?.update(confirmedEntity)
                
                // Mark as confirmed
                updateStatus(updateId: updateId, status: .confirmed)
                
                // Remove from pending after short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.removePendingUpdate(updateId: updateId)
                }
            }
            
        } catch {
            await MainActor.run {
                // Mark as failed
                if let index = pendingUpdates.firstIndex(where: { $0.id == updateId }) {
                    pendingUpdates[index].status = .failed
                    pendingUpdates[index].error = error
                    
                    // Move to failed updates
                    let failedUpdate = pendingUpdates[index]
                    failedUpdates.append(failedUpdate)
                }
                
                // Rollback
                rollback(updateId: updateId)
            }
        }
    }
    
    private func performSyncDelete(
        updateId: String,
        operation: @escaping () async throws -> Void
    ) async {
        updateStatus(updateId: updateId, status: .syncing)
        
        do {
            try await operation()
            
            await MainActor.run {
                // Mark as confirmed
                updateStatus(updateId: updateId, status: .confirmed)
                
                // Remove from pending
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.removePendingUpdate(updateId: updateId)
                }
            }
            
        } catch {
            await MainActor.run {
                // Mark as failed and rollback
                if let index = pendingUpdates.firstIndex(where: { $0.id == updateId }) {
                    pendingUpdates[index].status = .failed
                    pendingUpdates[index].error = error
                    
                    let failedUpdate = pendingUpdates[index]
                    failedUpdates.append(failedUpdate)
                }
                
                rollback(updateId: updateId)
            }
        }
    }
    
    // MARK: - Rollback
    
    /// Rollback a specific update
    public func rollback(updateId: String) {
        guard let index = pendingUpdates.firstIndex(where: { $0.id == updateId }) else { return }
        
        let update = pendingUpdates[index]
        
        switch update.operation {
        case .create:
            // Remove the created entity
            store?.remove(id: update.entityId)
            
        case .update:
            // Restore original value
            if let original = update.originalValue {
                store?.update(original)
            }
            
        case .delete:
            // Restore deleted entity
            if let original = update.originalValue {
                store?.insert(original)
            }
        }
        
        // Update status
        pendingUpdates[index].status = .rolledBack
        
        // Cancel rollback timer
        rollbackTimers[updateId]?.invalidate()
        rollbackTimers.removeValue(forKey: updateId)
        
        // Remove from pending updates
        removePendingUpdate(updateId: updateId)
    }
    
    /// Rollback all pending updates
    public func rollbackAll() {
        let updateIds = pendingUpdates.map { $0.id }
        for updateId in updateIds {
            rollback(updateId: updateId)
        }
    }
    
    /// Retry a failed update
    public func retry(
        updateId: String,
        syncOperation: @escaping () async throws -> Entity
    ) {
        guard let index = failedUpdates.firstIndex(where: { $0.id == updateId }) else { return }
        
        var update = failedUpdates[index]
        update.status = .pending
        update.error = nil
        
        // Remove from failed, add to pending
        failedUpdates.remove(at: index)
        pendingUpdates.append(update)
        
        // Retry sync
        Task {
            await performSync(updateId: updateId, operation: syncOperation)
        }
    }
    
    /// Clear failed updates
    public func clearFailed() {
        failedUpdates.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func addPendingUpdate(_ update: PendingUpdate<Entity>) {
        pendingUpdates.append(update)
        
        // Enforce max pending limit
        while pendingUpdates.count > configuration.maxPendingUpdates {
            let oldest = pendingUpdates.removeFirst()
            rollback(updateId: oldest.id)
        }
        
        // Set rollback timeout timer
        let timer = Timer.scheduledTimer(
            withTimeInterval: configuration.rollbackTimeout,
            repeats: false
        ) { [weak self] _ in
            self?.handleRollbackTimeout(updateId: update.id)
        }
        rollbackTimers[update.id] = timer
    }
    
    private func removePendingUpdate(updateId: String) {
        pendingUpdates.removeAll { $0.id == updateId }
        rollbackTimers[updateId]?.invalidate()
        rollbackTimers.removeValue(forKey: updateId)
    }
    
    private func updateStatus(updateId: String, status: UpdateStatus) {
        if let index = pendingUpdates.firstIndex(where: { $0.id == updateId }) {
            pendingUpdates[index].status = status
        }
    }
    
    private func handleRollbackTimeout(updateId: String) {
        guard let update = pendingUpdates.first(where: { $0.id == updateId }),
              update.status == .pending || update.status == .syncing else {
            return
        }
        
        // Rollback due to timeout
        rollback(updateId: updateId)
    }
}

// MARK: - Observable Entity Store

/// A simple observable store implementation
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public final class ObservableEntityStore<Entity: Codable & Identifiable>: OptimisticStore, ObservableObject where Entity.ID: Hashable {
    
    @Published public var entities: [Entity] = []
    
    public var entitiesPublisher: AnyPublisher<[Entity], Never> {
        $entities.eraseToAnyPublisher()
    }
    
    public init(entities: [Entity] = []) {
        self.entities = entities
    }
    
    public func find(id: Entity.ID) -> Entity? {
        entities.first { $0.id == id }
    }
    
    public func insert(_ entity: Entity) {
        entities.append(entity)
    }
    
    public func update(_ entity: Entity) {
        if let index = entities.firstIndex(where: { $0.id == entity.id }) {
            entities[index] = entity
        } else {
            entities.append(entity)
        }
    }
    
    public func remove(id: Entity.ID) {
        entities.removeAll { $0.id == id }
    }
}

// MARK: - SwiftUI Support

#if canImport(SwiftUI)
import SwiftUI

/// View modifier for showing pending state
@available(iOS 15.0, macOS 12.0, *)
public struct PendingOverlay: ViewModifier {
    let isPending: Bool
    let opacity: Double
    
    public init(isPending: Bool, opacity: Double = 0.5) {
        self.isPending = isPending
        self.opacity = opacity
    }
    
    public func body(content: Content) -> some View {
        content
            .opacity(isPending ? opacity : 1.0)
            .overlay(
                Group {
                    if isPending {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    }
                }
            )
    }
}

@available(iOS 15.0, macOS 12.0, *)
public extension View {
    /// Apply pending overlay based on update status
    func pendingOverlay(_ isPending: Bool, opacity: Double = 0.5) -> some View {
        modifier(PendingOverlay(isPending: isPending, opacity: opacity))
    }
}
#endif
