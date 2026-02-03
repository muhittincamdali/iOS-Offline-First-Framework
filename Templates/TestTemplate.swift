// MARK: - Offline-First Test Template
// Use this template for testing Offline-First functionality

import XCTest
import CoreData
@testable import __MODULE__

final class __NAME__OfflineTests: XCTestCase {
    // MARK: - Properties
    private var sut: __NAME__OfflineViewModel!
    private var mockLocalStore: MockLocalStore!
    private var mockRemoteService: MockRemoteService!
    private var mockSyncEngine: MockSyncEngine!
    private var mockNetworkMonitor: MockNetworkMonitor!
    
    // MARK: - Setup & Teardown
    @MainActor
    override func setUp() {
        super.setUp()
        mockLocalStore = MockLocalStore()
        mockRemoteService = MockRemoteService()
        mockSyncEngine = MockSyncEngine()
        mockNetworkMonitor = MockNetworkMonitor()
        
        sut = __NAME__OfflineViewModel(
            localStore: mockLocalStore,
            remoteService: mockRemoteService,
            syncEngine: mockSyncEngine,
            networkMonitor: mockNetworkMonitor
        )
    }
    
    @MainActor
    override func tearDown() {
        sut = nil
        mockLocalStore = nil
        mockRemoteService = nil
        mockSyncEngine = nil
        mockNetworkMonitor = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    @MainActor
    func test_init_startsWithIdleState() {
        XCTAssertEqual(sut.syncState, .idle)
    }
    
    @MainActor
    func test_init_isOnlineByDefault() {
        XCTAssertTrue(sut.isOnline)
    }
    
    // MARK: - Load Tests
    @MainActor
    func test_load_fetchesFromLocalStoreFirst() async {
        // Given
        mockLocalStore.items = [__TYPE__.mock]
        mockNetworkMonitor.isConnected = false
        
        // When
        await sut.load()
        
        // Then
        XCTAssertEqual(sut.data.count, 1)
        XCTAssertTrue(mockLocalStore.fetchAllCalled)
        XCTAssertFalse(mockRemoteService.getChangesCalled)
    }
    
    @MainActor
    func test_load_syncsWhenOnline() async {
        // Given
        mockLocalStore.items = [__TYPE__.mock]
        mockNetworkMonitor.isConnected = true
        sut.isOnline = true
        
        // When
        await sut.load()
        
        // Then
        XCTAssertTrue(mockRemoteService.getChangesCalled)
    }
    
    // MARK: - Offline Operation Tests
    @MainActor
    func test_create_savesLocallyWhenOffline() async {
        // Given
        mockNetworkMonitor.isConnected = false
        sut.isOnline = false
        let newItem = __TYPE__.mock
        
        // When
        await sut.create(newItem)
        
        // Then
        XCTAssertTrue(mockLocalStore.saveCalled)
        XCTAssertTrue(mockSyncEngine.queueChangeCalled)
        XCTAssertFalse(mockRemoteService.createCalled)
    }
    
    @MainActor
    func test_update_queuesForSyncWhenOffline() async {
        // Given
        mockNetworkMonitor.isConnected = false
        sut.isOnline = false
        var item = __TYPE__.mock
        item.id = "existing_id"
        mockLocalStore.items = [item]
        
        // When
        await sut.update(item)
        
        // Then
        XCTAssertTrue(mockSyncEngine.queueChangeCalled)
        XCTAssertEqual(sut.pendingChangesCount, 1)
    }
    
    @MainActor
    func test_delete_createsLocalTombstoneWhenOffline() async {
        // Given
        mockNetworkMonitor.isConnected = false
        sut.isOnline = false
        let item = __TYPE__.mock
        mockLocalStore.items = [item]
        
        // When
        await sut.delete(item)
        
        // Then
        XCTAssertTrue(mockLocalStore.deleteCalled)
        XCTAssertTrue(mockSyncEngine.queueChangeCalled)
    }
    
    // MARK: - Sync Tests
    @MainActor
    func test_sync_pushesLocalChangesFirst() async {
        // Given
        mockNetworkMonitor.isConnected = true
        sut.isOnline = true
        mockSyncEngine.pendingChanges = [.create(__TYPE__.mock)]
        
        // When
        await sut.sync()
        
        // Then
        XCTAssertTrue(mockRemoteService.createCalled)
        XCTAssertTrue(mockSyncEngine.markAsSyncedCalled)
    }
    
    @MainActor
    func test_sync_pullsRemoteChanges() async {
        // Given
        mockNetworkMonitor.isConnected = true
        sut.isOnline = true
        mockRemoteService.remoteChanges = [.created(__TYPE__.mock)]
        
        // When
        await sut.sync()
        
        // Then
        XCTAssertTrue(mockRemoteService.getChangesCalled)
        XCTAssertTrue(mockLocalStore.applyRemoteChangeCalled)
    }
    
    @MainActor
    func test_sync_updatesStateOnSuccess() async {
        // Given
        mockNetworkMonitor.isConnected = true
        sut.isOnline = true
        
        // When
        await sut.sync()
        
        // Then
        if case .synced(let date) = sut.syncState {
            XCTAssertNotNil(date)
        } else {
            XCTFail("Expected synced state")
        }
    }
    
    @MainActor
    func test_sync_handlesConflict() async {
        // Given
        mockNetworkMonitor.isConnected = true
        sut.isOnline = true
        mockRemoteService.conflictingItemId = "conflict_id"
        
        // When
        await sut.sync()
        
        // Then
        // Conflict should be stored locally with conflict status
        XCTAssertTrue(mockLocalStore.items.contains { $0.syncStatus == .conflict })
    }
    
    // MARK: - Network Status Tests
    @MainActor
    func test_goingOffline_updatesSyncState() {
        // When
        mockNetworkMonitor.simulateDisconnect()
        
        // Then (after small delay for publisher)
        let expectation = expectation(description: "State updates")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(self.sut.syncState, .offline)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
    
    @MainActor
    func test_goingOnline_triggersSync() async {
        // Given
        mockNetworkMonitor.isConnected = false
        sut.isOnline = false
        mockSyncEngine.pendingChanges = [.create(__TYPE__.mock)]
        
        // When
        mockNetworkMonitor.simulateConnect()
        
        // Wait for sync to trigger
        try? await Task.sleep(nanoseconds: 200_000_000)
        
        // Then
        XCTAssertTrue(mockRemoteService.createCalled)
    }
}

// MARK: - Mock Objects
final class MockLocalStore: LocalStoreProtocol, @unchecked Sendable {
    var items: [__TYPE__] = []
    var fetchAllCalled = false
    var saveCalled = false
    var deleteCalled = false
    var applyRemoteChangeCalled = false
    
    func fetchAll<T: SyncableModel>() async -> [T] {
        fetchAllCalled = true
        return items as? [T] ?? []
    }
    
    func fetch<T: SyncableModel>(id: String) async -> T? {
        items.first { $0.id == id } as? T
    }
    
    func save<T: SyncableModel>(_ item: T) async {
        saveCalled = true
        if let item = item as? __TYPE__ {
            items.removeAll { $0.id == item.id }
            items.append(item)
        }
    }
    
    func delete(_ id: String) async {
        deleteCalled = true
        items.removeAll { $0.id == id }
    }
    
    func updateSyncStatus(_ id: String, status: SyncStatus, remoteId: String?) async {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].syncStatus = status
        }
    }
    
    func applyRemoteChange<T: SyncableModel>(_ change: RemoteChange<T>) async {
        applyRemoteChangeCalled = true
    }
}

final class MockRemoteService: RemoteServiceProtocol, @unchecked Sendable {
    var createCalled = false
    var updateCalled = false
    var deleteCalled = false
    var getChangesCalled = false
    var remoteChanges: [RemoteChange<__TYPE__>] = []
    var conflictingItemId: String?
    
    func create<T: SyncableModel>(_ item: T) async throws -> T {
        createCalled = true
        var result = item
        result.remoteId = "remote_\(item.id)"
        return result
    }
    
    func update<T: SyncableModel>(_ item: T) async throws {
        updateCalled = true
    }
    
    func delete(_ id: String) async throws {
        deleteCalled = true
    }
    
    func getChanges<T: SyncableModel>(since: Date) async throws -> [RemoteChange<T>] {
        getChangesCalled = true
        return remoteChanges as? [RemoteChange<T>] ?? []
    }
}

final class MockSyncEngine: SyncEngineProtocol, @unchecked Sendable {
    var pendingChanges: [ChangeType<__TYPE__>] = []
    var queueChangeCalled = false
    var markAsSyncedCalled = false
    
    var pendingChangesPublisher: AnyPublisher<Int, Never> {
        Just(pendingChanges.count).eraseToAnyPublisher()
    }
    
    func queueChange<T: SyncableModel>(_ change: ChangeType<T>) async {
        queueChangeCalled = true
        if let change = change as? ChangeType<__TYPE__> {
            pendingChanges.append(change)
        }
    }
    
    func getPendingChanges<T: SyncableModel>() async -> [ChangeType<T>] {
        pendingChanges as? [ChangeType<T>] ?? []
    }
    
    func markAsSynced<T: SyncableModel>(_ change: ChangeType<T>) async {
        markAsSyncedCalled = true
    }
}

final class MockNetworkMonitor: NetworkMonitorProtocol {
    var isConnected: Bool = true
    private let subject = PassthroughSubject<Bool, Never>()
    
    var isConnectedPublisher: AnyPublisher<Bool, Never> {
        subject.eraseToAnyPublisher()
    }
    
    func simulateConnect() {
        isConnected = true
        subject.send(true)
    }
    
    func simulateDisconnect() {
        isConnected = false
        subject.send(false)
    }
}

// MARK: - Mock Data
extension __TYPE__ {
    static var mock: __TYPE__ {
        var item = __TYPE__()
        item.id = UUID().uuidString
        item.syncStatus = .pending
        item.createdAt = Date()
        item.modifiedAt = Date()
        return item
    }
}
