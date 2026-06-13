import Foundation
import Combine

/// Utility methods for offline-first operations
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct OfflineFirstUtils: Sendable {
    
    public init() {}
    
    /// Generates a unique sync ID
    public func generateSyncId() -> String {
        return UUID().uuidString
    }
    
    /// Checks if a sync result indicates a conflict
    public func isConflict(_ error: Error) -> Bool {
        if let offlineError = error as? OfflineFirstError {
            if case .conflictDetected = offlineError {
                return true
            }
        }
        return false
    }
}
