import Foundation
import RxSwift

/// Utility functions for the offline-first framework
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public final class OfflineFirstUtils {
    
    // MARK: - Data Validation
    
    /// Validates if data is suitable for offline storage
    /// - Parameter data: Data to validate
    /// - Returns: Validation result
    public static func validateData<T: Codable>(_ data: T) -> ValidationResult {
        do {
            let encoded = try JSONEncoder().encode(data)
            let decoded = try JSONDecoder().decode(T.self, from: encoded)
            
            // Check if data can be serialized and deserialized
            if String(describing: data) == String(describing: decoded) {
                return .valid
            } else {
                return .invalid("Data serialization mismatch")
            }
        } catch {
            return .invalid("Data encoding failed: \(error.localizedDescription)")
        }
    }
    
    /// Checks if data size is within acceptable limits
    /// - Parameter data: Data to check
    /// - Parameter maxSize: Maximum allowed size in bytes
    /// - Returns: Size validation result
    public static func validateDataSize<T: Codable>(_ data: T, maxSize: Int64) -> SizeValidationResult {
        do {
            let encoded = try JSONEncoder().encode(data)
            let size = Int64(encoded.count)
            
            if size <= maxSize {
                return .valid(size: size)
            } else {
                return .tooLarge(actualSize: size, maxSize: maxSize)
            }
        } catch {
            return .invalid("Size validation failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Network Utilities
    
    /// Checks if device has sufficient network connectivity
    /// - Returns: Network availability status
    public static func checkNetworkAvailability() -> NetworkAvailability {
        // This is a simplified implementation
        // In a real app, you would check actual network status
        return .available
    }
    
    /// Estimates sync time based on data size and network quality
    /// - Parameter dataSize: Size of data to sync in bytes
    /// - Parameter networkQuality: Current network quality
    /// - Returns: Estimated sync time in seconds
    public static func estimateSyncTime(dataSize: Int64, networkQuality: ConnectionQuality) -> TimeInterval {
        let baseTime: TimeInterval = 1.0 // Base time in seconds
        let sizeFactor = Double(dataSize) / 1024.0 / 1024.0 // Convert to MB
        let qualityFactor: Double
        
        switch networkQuality {
        case .excellent:
            qualityFactor = 1.0
        case .good:
            qualityFactor = 2.0
        case .fair:
            qualityFactor = 5.0
        case .poor:
            qualityFactor = 10.0
        case .unknown:
            qualityFactor = 3.0
        }
        
        return baseTime * sizeFactor * qualityFactor
    }
    
    // MARK: - Storage Utilities
    
    /// Calculates available storage space
    /// - Returns: Available space in bytes
    public static func getAvailableStorageSpace() -> Int64 {
        let fileManager = FileManager.default
        guard let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return 0
        }
        
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: documentsPath.path)
            return attributes[.systemFreeSize] as? Int64 ?? 0
        } catch {
            return 0
        }
    }
    
    /// Formats file size for display
    /// - Parameter bytes: Size in bytes
    /// - Returns: Formatted size string
    public static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Time Utilities
    
    /// Gets current timestamp in milliseconds
    /// - Returns: Current timestamp
    public static func getCurrentTimestamp() -> Int64 {
        return Int64(Date().timeIntervalSince1970 * 1000)
    }
    
    /// Formats duration for display
    /// - Parameter duration: Duration in seconds
    /// - Returns: Formatted duration string
    public static func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "0s"
    }
    
    // MARK: - Error Utilities
    
    /// Creates a user-friendly error message
    /// - Parameter error: Original error
    /// - Returns: User-friendly error message
    public static func getUserFriendlyErrorMessage(_ error: Error) -> String {
        if let syncError = error as? SyncError {
            switch syncError {
            case .networkError:
                return "Network connection is unavailable. Please check your internet connection."
            case .serverError:
                return "Server is temporarily unavailable. Please try again later."
            case .authenticationError:
                return "Authentication failed. Please log in again."
            case .timeout:
                return "Request timed out. Please try again."
            case .noDataToSync:
                return "No data available to sync."
            case .unknown:
                return "An unexpected error occurred. Please try again."
            }
        } else if let storageError = error as? StorageError {
            switch storageError {
            case .insufficientSpace:
                return "Insufficient storage space. Please free up some space and try again."
            case .corruptedData:
                return "Data is corrupted. Please restart the app."
            case .encryptionFailed:
                return "Data encryption failed. Please try again."
            case .compressionFailed:
                return "Data compression failed. Please try again."
            case .unknown:
                return "Storage error occurred. Please try again."
            }
        } else {
            return error.localizedDescription
        }
    }
}

// MARK: - Supporting Types

public enum ValidationResult {
    case valid
    case invalid(String)
}

public enum SizeValidationResult {
    case valid(size: Int64)
    case tooLarge(actualSize: Int64, maxSize: Int64)
    case invalid(String)
}

public enum NetworkAvailability {
    case available
    case unavailable
    case unknown
}
