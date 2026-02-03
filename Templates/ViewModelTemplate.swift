// MARK: - Offline-First ViewModel Template
// Use this template for creating Offline-First ViewModels

import Foundation
import Combine

// MARK: - Protocol
@MainActor
protocol OfflineFirstViewModelProtocol: ObservableObject {
    var syncState: SyncState { get }
    var isOnline: Bool { get }
    var pendingChangesCount: Int { get }
    func load() async
    func sync() async
}

// MARK: - Sync State
enum SyncState: Equatable {
    case idle
    case syncing
    case synced(Date)
    case failed(SyncError)
    case offline
    
    var lastSyncDate: Date? {
        if case .synced(let date) = self { return date }
        return nil
    }
}

// MARK: - ViewModel
@MainActor
final class __NAME__OfflineViewModel: OfflineFirstViewModelProtocol {
    // MARK: - Published Properties
    @Published private(set) var syncState: SyncState = .idle
    @Published private(set) var data: [__TYPE__] = []
    @Published private(set) var isOnline: Bool = true
    @Published private(set) var pendingChangesCount: Int = 0
    
    // MARK: - Dependencies
    private let localStore: LocalStoreProtocol
    private let remoteService: RemoteServiceProtocol
    private let syncEngine: SyncEngineProtocol
    private let networkMonitor: NetworkMonitorProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(
        localStore: LocalStoreProtocol = LocalStore.shared,
        remoteService: RemoteServiceProtocol = RemoteService.shared,
        syncEngine: SyncEngineProtocol = SyncEngine.shared,
        networkMonitor: NetworkMonitorProtocol = NetworkMonitor.shared
    ) {
        self.localStore = localStore
        self.remoteService = remoteService
        self.syncEngine = syncEngine
        self.networkMonitor = networkMonitor
        setupNetworkMonitoring()
        setupSyncObserver()
    }
    
    // MARK: - Setup
    private func setupNetworkMonitoring() {
        networkMonitor.isConnectedPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isConnected in
                self?.isOnline = isConnected
                if isConnected {
                    Task { await self?.syncIfNeeded() }
                } else {
                    self?.syncState = .offline
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupSyncObserver() {
        syncEngine.pendingChangesPublisher
            .receive(on: DispatchQueue.main)
            .assign(to: &$pendingChangesCount)
    }
    
    // MARK: - Load (Local First)
    func load() async {
        // Always load from local first (instant)
        data = await localStore.fetchAll()
        
        // Then sync if online
        if isOnline {
            await sync()
        }
    }
    
    // MARK: - Sync
    func sync() async {
        guard isOnline else {
            syncState = .offline
            return
        }
        
        syncState = .syncing
        
        do {
            // Push local changes first
            try await pushLocalChanges()
            
            // Pull remote changes
            try await pullRemoteChanges()
            
            // Reload data
            data = await localStore.fetchAll()
            
            syncState = .synced(Date())
        } catch let error as SyncError {
            syncState = .failed(error)
        } catch {
            syncState = .failed(.unknown(error))
        }
    }
    
    private func syncIfNeeded() async {
        guard pendingChangesCount > 0 || shouldRefresh() else { return }
        await sync()
    }
    
    private func shouldRefresh() -> Bool {
        guard let lastSync = syncState.lastSyncDate else { return true }
        return Date().timeIntervalSince(lastSync) > 300 // 5 minutes
    }
    
    // MARK: - CRUD Operations (Offline-First)
    func create(_ item: __TYPE__) async {
        // Save locally immediately
        var newItem = item
        newItem.id = UUID().uuidString
        newItem.syncStatus = .pending
        newItem.createdAt = Date()
        newItem.modifiedAt = Date()
        
        await localStore.save(newItem)
        data = await localStore.fetchAll()
        
        // Queue for sync
        await syncEngine.queueChange(.create(newItem))
        
        // Sync if online
        if isOnline {
            await sync()
        }
    }
    
    func update(_ item: __TYPE__) async {
        var updatedItem = item
        updatedItem.syncStatus = .pending
        updatedItem.modifiedAt = Date()
        
        await localStore.save(updatedItem)
        data = await localStore.fetchAll()
        
        await syncEngine.queueChange(.update(updatedItem))
        
        if isOnline {
            await sync()
        }
    }
    
    func delete(_ item: __TYPE__) async {
        await localStore.delete(item.id)
        data = await localStore.fetchAll()
        
        await syncEngine.queueChange(.delete(item.id))
        
        if isOnline {
            await sync()
        }
    }
    
    // MARK: - Private Methods
    private func pushLocalChanges() async throws {
        let pendingChanges = await syncEngine.getPendingChanges()
        
        for change in pendingChanges {
            switch change {
            case .create(let item):
                let remoteItem = try await remoteService.create(item)
                await localStore.updateSyncStatus(item.id, status: .synced, remoteId: remoteItem.remoteId)
                
            case .update(let item):
                try await remoteService.update(item)
                await localStore.updateSyncStatus(item.id, status: .synced)
                
            case .delete(let id):
                try await remoteService.delete(id)
            }
            
            await syncEngine.markAsSynced(change)
        }
    }
    
    private func pullRemoteChanges() async throws {
        let lastSyncDate = syncState.lastSyncDate ?? Date.distantPast
        let remoteChanges = try await remoteService.getChanges(since: lastSyncDate)
        
        for change in remoteChanges {
            await localStore.applyRemoteChange(change)
        }
    }
}

// MARK: - Sync Error
enum SyncError: LocalizedError, Equatable {
    case networkUnavailable
    case conflict(itemId: String)
    case serverError(code: Int)
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .networkUnavailable: return "Network unavailable"
        case .conflict(let id): return "Conflict on item: \(id)"
        case .serverError(let code): return "Server error: \(code)"
        case .unknown(let error): return error.localizedDescription
        }
    }
    
    static func == (lhs: SyncError, rhs: SyncError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}

// MARK: - Preview
#if DEBUG
extension __NAME__OfflineViewModel {
    static var preview: __NAME__OfflineViewModel {
        __NAME__OfflineViewModel()
    }
}
#endif
