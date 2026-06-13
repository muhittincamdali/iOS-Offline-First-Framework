import Foundation
import Combine

/// Manages analytics and monitoring for offline operations
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
@MainActor
public final class OfflineAnalyticsManager {
    
    private var events: [OfflineEvent] = []
    
    public init() {}
    
    public func initialize() {
        Logger.info("OfflineAnalyticsManager initialized")
    }
    
    public func startMonitoring() {
        Logger.info("Analytics monitoring started")
    }
    
    public func recordSyncSuccess() {
        track(event: .syncSuccess)
    }
    
    public func recordSyncFailure(error: String) {
        track(event: .syncFailure(error))
    }
    
    public func recordStorageWarning() {
        track(event: .storageWarning)
    }
    
    public func recordStorageFull() {
        track(event: .storageFull)
    }
    
    public func getAnalytics() async throws -> OfflineAnalytics {
        return OfflineAnalytics(
            totalSyncs: events.filter { if case .syncSuccess = $0.type { return true }; return false }.count,
            failedSyncs: events.filter { if case .syncFailure = $0.type { return true }; return false }.count,
            storageWarnings: events.filter { $0.type == .storageWarning }.count,
            lastSyncDate: events.last { if case .syncSuccess = $0.type { return true }; return false }?.timestamp
        )
    }
    
    private func track(event: OfflineEventType) {
        let entry = OfflineEvent(type: event, timestamp: Date())
        events.append(entry)
        Logger.info("Analytics event recorded: \(event)")
    }
}

// MARK: - Supporting Types

public struct OfflineAnalytics: Sendable {
    public let totalSyncs: Int
    public let failedSyncs: Int
    public let storageWarnings: Int
    public let lastSyncDate: Date?
}

public struct OfflineEvent: Sendable {
    public let type: OfflineEventType
    public let timestamp: Date
}

public enum OfflineEventType: Equatable, Sendable {
    case syncSuccess
    case syncFailure(String)
    case storageWarning
    case storageFull
}
