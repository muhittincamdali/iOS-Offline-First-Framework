import Foundation
#if os(iOS)
import BackgroundTasks
#endif
import Combine
import UserNotifications

// MARK: - Background Sync Configuration

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
        minimumInterval: 15 * 60,
        requiresNetworkConnectivity: true,
        requiresExternalPower: false,
        requiresCharging: false,
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

public struct BackgroundSyncResult: Codable, Sendable {
    public let timestamp: Date
    public let success: Bool
    public let itemsSynced: Int
    public let duration: TimeInterval
    public let error: String?
    
    public init(timestamp: Date = Date(), success: Bool, itemsSynced: Int = 0, duration: TimeInterval = 0, error: String? = nil) {
        self.timestamp = timestamp
        self.success = success
        self.itemsSynced = itemsSynced
        self.duration = duration
        self.error = error
    }
}

public protocol SyncHandler: Sendable {
    func performSync() async throws -> BackgroundSyncResult
}

#if os(iOS)
@available(iOS 15.0, *)
@MainActor
public final class BackgroundSyncScheduler: ObservableObject {
    @Published public private(set) var isEnabled: Bool = false
    @Published public private(set) var nextScheduledSync: Date?
    
    private let configuration: BackgroundSyncConfiguration
    private var syncHandler: SyncHandler?
    
    public init(configuration: BackgroundSyncConfiguration = .default) {
        self.configuration = configuration
    }
    
    public func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: configuration.taskIdentifier, using: nil) { [weak self] task in
            guard let self = self, let bgTask = task as? BGAppRefreshTask else { return }
            Task { @MainActor in await self.handleBackgroundTask(bgTask) }
        }
    }
    
    public func enable() {
        isEnabled = true
        scheduleNextSync()
    }
    
    public func disable() {
        isEnabled = false
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: configuration.taskIdentifier)
        nextScheduledSync = nil
    }
    
    public func scheduleNextSync() {
        guard isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: configuration.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: configuration.minimumInterval)
        try? BGTaskScheduler.shared.submit(request)
        nextScheduledSync = request.earliestBeginDate
    }
    
    private func handleBackgroundTask(_ task: BGAppRefreshTask) async {
        scheduleNextSync()
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        guard let handler = syncHandler else {
            task.setTaskCompleted(success: false)
            return
        }
        do {
            let result = try await handler.performSync()
            task.setTaskCompleted(success: result.success)
        } catch {
            task.setTaskCompleted(success: false)
        }
    }
}
#endif
