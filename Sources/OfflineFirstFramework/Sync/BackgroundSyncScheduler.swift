import Foundation
import BackgroundTasks
import Combine
import UserNotifications

// MARK: - Background Sync Configuration

/// Configuration for background synchronization
public struct BackgroundSyncConfiguration: Codable, Sendable {
    public let taskIdentifier: String
    public let minimumInterval: TimeInterval
    public let requiresNetworkConnectivity: Bool
    public let requiresExternalPower: Bool
    public let requiresCharging: Bool
    public let notifyOnCompletion: Bool
    public let maxSyncDuration: TimeInterval
    
    public static let `default` = BackgroundSyncConfiguration(
        taskIdentifier: "com.offlinefirst.backgroundsync",
        minimumInterval: 15 * 60,  // 15 minutes
        requiresNetworkConnectivity: true,
        requiresExternalPower: false,
        requiresCharging: false,
        notifyOnCompletion: false,
        maxSyncDuration: 25  // 25 seconds (BGTask limit is 30)
    )
    
    public static let aggressive = BackgroundSyncConfiguration(
        taskIdentifier: "com.offlinefirst.backgroundsync",
        minimumInterval: 5 * 60,  // 5 minutes
        requiresNetworkConnectivity: true,
        requiresExternalPower: false,
        requiresCharging: false,
        notifyOnCompletion: true,
        maxSyncDuration: 25
    )
    
    public static let conservative = BackgroundSyncConfiguration(
        taskIdentifier: "com.offlinefirst.backgroundsync",
        minimumInterval: 60 * 60,  // 1 hour
        requiresNetworkConnectivity: true,
        requiresExternalPower: true,
        requiresCharging: true,
        notifyOnCompletion: false,
        maxSyncDuration: 25
    )
    
    public init(
        taskIdentifier: String = "com.offlinefirst.backgroundsync",
        minimumInterval: TimeInterval = 15 * 60,
        requiresNetworkConnectivity: Bool = true,
        requiresExternalPower: Bool = false,
        requiresCharging: Bool = false,
        notifyOnCompletion: Bool = false,
        maxSyncDuration: TimeInterval = 25
    ) {
        self.taskIdentifier = taskIdentifier
        self.minimumInterval = minimumInterval
        self.requiresNetworkConnectivity = requiresNetworkConnectivity
        self.requiresExternalPower = requiresExternalPower
        self.requiresCharging = requiresCharging
        self.notifyOnCompletion = notifyOnCompletion
        self.maxSyncDuration = maxSyncDuration
    }
}

// MARK: - Sync Result

public struct BackgroundSyncResult: Codable, Sendable {
    public let timestamp: Date
    public let success: Bool
    public let itemsSynced: Int
    public let conflicts: Int
    public let duration: TimeInterval
    public let error: String?
    
    public init(
        timestamp: Date = Date(),
        success: Bool,
        itemsSynced: Int = 0,
        conflicts: Int = 0,
        duration: TimeInterval = 0,
        error: String? = nil
    ) {
        self.timestamp = timestamp
        self.success = success
        self.itemsSynced = itemsSynced
        self.conflicts = conflicts
        self.duration = duration
        self.error = error
    }
}

// MARK: - Sync Handler Protocol

/// Protocol for sync operations
public protocol SyncHandler: Sendable {
    func performSync() async throws -> BackgroundSyncResult
}

// MARK: - Background Sync Scheduler

/// Manages background synchronization using BGTaskScheduler
@available(iOS 15.0, *)
@MainActor
public final class BackgroundSyncScheduler: ObservableObject {
    
    // MARK: - Published State
    
    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var lastSyncResult: BackgroundSyncResult?
    @Published public private(set) var nextScheduledSync: Date?
    @Published public private(set) var syncHistory: [BackgroundSyncResult] = []
    
    // MARK: - Properties
    
    private let configuration: BackgroundSyncConfiguration
    private var syncHandler: SyncHandler?
    private var cancellables = Set<AnyCancellable>()
    
    private let userDefaults = UserDefaults.standard
    private let lastSyncKey = "com.offlinefirst.lastSync"
    private let syncHistoryKey = "com.offlinefirst.syncHistory"
    private let maxHistoryCount = 50
    
    // MARK: - Initialization
    
    public init(configuration: BackgroundSyncConfiguration = .default) {
        self.configuration = configuration
        loadSyncHistory()
    }
    
    // MARK: - Registration
    
    /// Register the background task with the system
    /// Call this from AppDelegate's didFinishLaunchingWithOptions or @main App init
    public func registerBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: configuration.taskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let self = self, let bgTask = task as? BGAppRefreshTask else { return }
            
            Task { @MainActor in
                await self.handleBackgroundTask(bgTask)
            }
        }
    }
    
    /// Set the sync handler
    public func setSyncHandler(_ handler: SyncHandler) {
        self.syncHandler = handler
    }
    
    // MARK: - Scheduling
    
    /// Enable background sync
    public func enable() {
        isEnabled = true
        scheduleNextSync()
    }
    
    /// Disable background sync
    public func disable() {
        isEnabled = false
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: configuration.taskIdentifier)
        nextScheduledSync = nil
    }
    
    /// Schedule the next background sync
    public func scheduleNextSync() {
        guard isEnabled else { return }
        
        let request = BGAppRefreshTaskRequest(identifier: configuration.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: configuration.minimumInterval)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            nextScheduledSync = request.earliestBeginDate
        } catch {
            print("Failed to schedule background sync: \(error)")
        }
    }
    
    /// Force immediate sync (foreground)
    public func syncNow() async -> BackgroundSyncResult {
        guard let handler = syncHandler else {
            return BackgroundSyncResult(success: false, error: "No sync handler configured")
        }
        
        let startTime = Date()
        
        do {
            let result = try await handler.performSync()
            recordSyncResult(result)
            return result
        } catch {
            let result = BackgroundSyncResult(
                success: false,
                duration: Date().timeIntervalSince(startTime),
                error: error.localizedDescription
            )
            recordSyncResult(result)
            return result
        }
    }
    
    // MARK: - Background Task Handling
    
    private func handleBackgroundTask(_ task: BGAppRefreshTask) async {
        // Schedule next sync immediately
        scheduleNextSync()
        
        // Set up expiration handler
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
        
        guard let handler = syncHandler else {
            task.setTaskCompleted(success: false)
            return
        }
        
        let startTime = Date()
        
        do {
            // Perform sync with timeout
            let result = try await withTimeout(seconds: configuration.maxSyncDuration) {
                try await handler.performSync()
            }
            
            await MainActor.run {
                recordSyncResult(result)
            }
            
            // Show notification if configured
            if configuration.notifyOnCompletion && result.itemsSynced > 0 {
                await sendSyncNotification(result: result)
            }
            
            task.setTaskCompleted(success: true)
            
        } catch {
            let result = BackgroundSyncResult(
                success: false,
                duration: Date().timeIntervalSince(startTime),
                error: error.localizedDescription
            )
            
            await MainActor.run {
                recordSyncResult(result)
            }
            
            task.setTaskCompleted(success: false)
        }
    }
    
    // MARK: - History Management
    
    private func recordSyncResult(_ result: BackgroundSyncResult) {
        lastSyncResult = result
        syncHistory.insert(result, at: 0)
        
        // Trim history
        if syncHistory.count > maxHistoryCount {
            syncHistory = Array(syncHistory.prefix(maxHistoryCount))
        }
        
        saveSyncHistory()
    }
    
    private func saveSyncHistory() {
        if let data = try? JSONEncoder().encode(syncHistory) {
            userDefaults.set(data, forKey: syncHistoryKey)
        }
        
        if let lastResult = lastSyncResult, let data = try? JSONEncoder().encode(lastResult) {
            userDefaults.set(data, forKey: lastSyncKey)
        }
    }
    
    private func loadSyncHistory() {
        if let data = userDefaults.data(forKey: syncHistoryKey),
           let history = try? JSONDecoder().decode([BackgroundSyncResult].self, from: data) {
            syncHistory = history
        }
        
        if let data = userDefaults.data(forKey: lastSyncKey),
           let lastResult = try? JSONDecoder().decode(BackgroundSyncResult.self, from: data) {
            lastSyncResult = lastResult
        }
    }
    
    /// Clear sync history
    public func clearHistory() {
        syncHistory = []
        userDefaults.removeObject(forKey: syncHistoryKey)
    }
    
    // MARK: - Notifications
    
    private func sendSyncNotification(result: BackgroundSyncResult) async {
        let content = UNMutableNotificationContent()
        content.title = "Sync Complete"
        content.body = "\(result.itemsSynced) items synced"
        content.sound = .default
        
        let request = UNNotificationRequest(
            identifier: "sync-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Utilities
    
    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw BackgroundSyncError.timeout
            }
            
            guard let result = try await group.next() else {
                throw BackgroundSyncError.unknown
            }
            
            group.cancelAll()
            return result
        }
    }
}

// MARK: - Errors

public enum BackgroundSyncError: Error, LocalizedError {
    case timeout
    case noHandler
    case cancelled
    case unknown
    
    public var errorDescription: String? {
        switch self {
        case .timeout:
            return "Background sync timed out"
        case .noHandler:
            return "No sync handler configured"
        case .cancelled:
            return "Background sync was cancelled"
        case .unknown:
            return "Unknown background sync error"
        }
    }
}

// MARK: - Default Sync Handler

/// Default implementation of SyncHandler for testing
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct DefaultSyncHandler: SyncHandler {
    
    private let retryQueue: RetryQueue
    
    public init(retryQueue: RetryQueue) {
        self.retryQueue = retryQueue
    }
    
    public func performSync() async throws -> BackgroundSyncResult {
        let startTime = Date()
        
        // Process pending operations
        await retryQueue.startProcessing()
        
        // Wait for processing to complete (with timeout)
        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
        
        let status = await retryQueue.queueStatus
        
        return BackgroundSyncResult(
            success: status.failedCount == 0,
            itemsSynced: status.completedCount,
            conflicts: 0,
            duration: Date().timeIntervalSince(startTime)
        )
    }
}

// MARK: - BGTaskScheduler Extension for Testing

#if DEBUG
extension BackgroundSyncScheduler {
    /// Simulate background task for testing
    public func simulateBackgroundTask() async {
        guard isEnabled, let handler = syncHandler else { return }
        
        let startTime = Date()
        
        do {
            let result = try await handler.performSync()
            recordSyncResult(result)
        } catch {
            let result = BackgroundSyncResult(
                success: false,
                duration: Date().timeIntervalSince(startTime),
                error: error.localizedDescription
            )
            recordSyncResult(result)
        }
    }
}
#endif
