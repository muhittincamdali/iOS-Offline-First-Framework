import Foundation
import RxSwift
import CocoaLumberjack

/// Manages analytics for offline usage patterns and sync performance
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public final class OfflineAnalyticsManager {
    
    // MARK: - Properties
    
    private let analyticsData = BehaviorSubject<OfflineAnalytics>(value: OfflineAnalytics())
    private let queue = DispatchQueue(label: "com.offlinefirst.analytics", qos: .utility)
    private let disposeBag = DisposeBag()
    
    // MARK: - Initialization
    
    public init() {
        loadAnalytics()
    }
    
    // MARK: - Public Methods
    
    public func initialize() {
        DDLogInfo("OfflineAnalyticsManager initialized")
    }
    
    public func startMonitoring() {
        startPeriodicAnalytics()
        DDLogInfo("Analytics monitoring started")
    }
    
    public func getAnalytics() -> Observable<OfflineAnalytics> {
        return analyticsData.asObservable()
    }
    
    public func recordOfflineSession(duration: TimeInterval) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var current = (try? self.analyticsData.value()) ?? OfflineAnalytics()
            current.offlineSessions += 1
            current.totalOfflineTime += duration
            current.averageOfflineTime = current.totalOfflineTime / Double(current.offlineSessions)
            
            self.analyticsData.onNext(current)
            self.saveAnalytics(current)
        }
    }
    
    public func recordSyncSuccess() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var current = (try? self.analyticsData.value()) ?? OfflineAnalytics()
            current.syncSuccessCount += 1
            current.syncSuccessRate = Double(current.syncSuccessCount) / Double(current.syncSuccessCount + current.syncFailureCount) * 100
            
            self.analyticsData.onNext(current)
            self.saveAnalytics(current)
        }
    }
    
    public func recordSyncFailure(error: Error) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var current = (try? self.analyticsData.value()) ?? OfflineAnalytics()
            current.syncFailureCount += 1
            current.syncSuccessRate = Double(current.syncSuccessCount) / Double(current.syncSuccessCount + current.syncFailureCount) * 100
            current.lastSyncError = error.localizedDescription
            
            self.analyticsData.onNext(current)
            self.saveAnalytics(current)
        }
    }
    
    public func recordStorageWarning() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var current = (try? self.analyticsData.value()) ?? OfflineAnalytics()
            current.storageWarnings += 1
            
            self.analyticsData.onNext(current)
            self.saveAnalytics(current)
        }
    }
    
    public func recordStorageFull() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var current = (try? self.analyticsData.value()) ?? OfflineAnalytics()
            current.storageFullEvents += 1
            
            self.analyticsData.onNext(current)
            self.saveAnalytics(current)
        }
    }
    
    public func recordSyncTime(duration: TimeInterval) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            var current = (try? self.analyticsData.value()) ?? OfflineAnalytics()
            current.syncTimes.append(duration)
            current.averageSyncTime = current.syncTimes.reduce(0, +) / Double(current.syncTimes.count)
            
            self.analyticsData.onNext(current)
            self.saveAnalytics(current)
        }
    }
    
    public func resetAnalytics() {
        let resetData = OfflineAnalytics()
        analyticsData.onNext(resetData)
        saveAnalytics(resetData)
        DDLogInfo("Analytics reset")
    }
    
    // MARK: - Private Methods
    
    private func loadAnalytics() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            if let data = UserDefaults.standard.data(forKey: "OfflineAnalytics"),
               let analytics = try? JSONDecoder().decode(OfflineAnalytics.self, from: data) {
                self.analyticsData.onNext(analytics)
            }
        }
    }
    
    private func saveAnalytics(_ analytics: OfflineAnalytics) {
        if let data = try? JSONEncoder().encode(analytics) {
            UserDefaults.standard.set(data, forKey: "OfflineAnalytics")
        }
    }
    
    private func startPeriodicAnalytics() {
        Timer.scheduledTimer(withTimeInterval: 3600.0, repeats: true) { [weak self] _ in
            self?.generateAnalyticsReport()
        }
    }
    
    private func generateAnalyticsReport() {
        guard let analytics = try? analyticsData.value() else { return }
        
        DDLogInfo("Analytics Report:")
        DDLogInfo("- Offline Sessions: \(analytics.offlineSessions)")
        DDLogInfo("- Total Offline Time: \(analytics.totalOfflineTime)s")
        DDLogInfo("- Average Offline Time: \(analytics.averageOfflineTime)s")
        DDLogInfo("- Sync Success Rate: \(analytics.syncSuccessRate)%")
        DDLogInfo("- Average Sync Time: \(analytics.averageSyncTime)s")
        DDLogInfo("- Storage Warnings: \(analytics.storageWarnings)")
        DDLogInfo("- Storage Full Events: \(analytics.storageFullEvents)")
    }
}

// MARK: - Supporting Types

public struct OfflineAnalytics: Codable {
    public var offlineSessions: Int = 0
    public var totalOfflineTime: TimeInterval = 0
    public var averageOfflineTime: TimeInterval = 0
    public var syncSuccessCount: Int = 0
    public var syncFailureCount: Int = 0
    public var syncSuccessRate: Double = 0
    public var averageSyncTime: TimeInterval = 0
    public var storageWarnings: Int = 0
    public var storageFullEvents: Int = 0
    public var lastSyncError: String = ""
    public var syncTimes: [TimeInterval] = []
    public var lastUpdated: Date = Date()
    
    public init() {}
    
    public init(offlineSessions: Int, totalOfflineTime: TimeInterval, averageOfflineTime: TimeInterval, syncSuccessCount: Int, syncFailureCount: Int, syncSuccessRate: Double, averageSyncTime: TimeInterval, storageWarnings: Int, storageFullEvents: Int, lastSyncError: String, syncTimes: [TimeInterval], lastUpdated: Date) {
        self.offlineSessions = offlineSessions
        self.totalOfflineTime = totalOfflineTime
        self.averageOfflineTime = averageOfflineTime
        self.syncSuccessCount = syncSuccessCount
        self.syncFailureCount = syncFailureCount
        self.syncSuccessRate = syncSuccessRate
        self.averageSyncTime = averageSyncTime
        self.storageWarnings = storageWarnings
        self.storageFullEvents = storageFullEvents
        self.lastSyncError = lastSyncError
        self.syncTimes = syncTimes
        self.lastUpdated = lastUpdated
    }
}
