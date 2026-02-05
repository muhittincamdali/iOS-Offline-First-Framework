// OfflineFirstFramework
// Production-ready iOS offline-first framework
// Copyright (c) 2024 Muhittin Camdali. MIT License.

import Foundation

// MARK: - Core
@_exported import struct Foundation.Data
@_exported import struct Foundation.Date
@_exported import struct Foundation.URL
@_exported import class Foundation.JSONEncoder
@_exported import class Foundation.JSONDecoder

// MARK: - Public API

/// OfflineFirst namespace for accessing all framework components
public enum OfflineFirst {
    
    /// Framework version
    public static let version = "2.0.0"
    
    /// Framework build
    public static let build = "2024.02.05"
    
    /// Check if running in debug mode
    public static var isDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}

// MARK: - Type Aliases

/// Alias for sync completion handler
public typealias SyncCompletion = (Result<SyncedData, Error>) -> Void

/// Alias for operation completion handler
public typealias OperationCompletion<T> = (Result<T, Error>) -> Void

/// Alias for progress handler
public typealias ProgressHandler = (Double) -> Void

// MARK: - Syncable Protocol

/// Protocol for entities that can be synced offline
public protocol Syncable: Codable, Identifiable, Equatable {
    /// Unique identifier for sync
    var syncId: String { get }
    
    /// Last modified timestamp
    var lastModified: Date { get }
    
    /// Sync version number
    var version: Int64 { get }
    
    /// Whether entity has local changes not yet synced
    var isDirty: Bool { get }
}

public extension Syncable where ID == String {
    var syncId: String { id }
}

// MARK: - Offline Store Protocol

/// Protocol for offline data stores
public protocol OfflineStore {
    associatedtype Entity: Syncable
    
    /// Save entity locally
    func save(_ entity: Entity) async throws
    
    /// Save multiple entities
    func saveAll(_ entities: [Entity]) async throws
    
    /// Find entity by ID
    func find(id: Entity.ID) async throws -> Entity?
    
    /// Fetch all entities
    func fetchAll() async throws -> [Entity]
    
    /// Fetch entities matching predicate
    func fetch(where predicate: @escaping (Entity) -> Bool) async throws -> [Entity]
    
    /// Delete entity
    func delete(_ entity: Entity) async throws
    
    /// Delete entity by ID
    func delete(id: Entity.ID) async throws
    
    /// Clear all data
    func clear() async throws
    
    /// Count entities
    func count() async throws -> Int
}

// MARK: - Remote API Protocol

/// Protocol for remote API interactions
public protocol RemoteAPI {
    associatedtype Entity: Syncable
    
    /// Fetch entity from remote
    func fetch(id: Entity.ID) async throws -> Entity
    
    /// Fetch all entities from remote
    func fetchAll() async throws -> [Entity]
    
    /// Fetch changes since version
    func fetchChanges(since version: Int64) async throws -> [Entity]
    
    /// Create entity on remote
    func create(_ entity: Entity) async throws -> Entity
    
    /// Update entity on remote
    func update(_ entity: Entity) async throws -> Entity
    
    /// Delete entity on remote
    func delete(id: Entity.ID) async throws
}

// MARK: - Sync Engine Protocol

/// Protocol for sync engines
public protocol SyncEngine {
    associatedtype Entity: Syncable
    
    /// Perform full sync
    func syncAll() async throws -> SyncResult
    
    /// Sync specific entity
    func sync(_ entity: Entity) async throws -> Entity
    
    /// Get pending operations count
    var pendingOperationsCount: Int { get async }
    
    /// Check if currently syncing
    var isSyncing: Bool { get async }
}

// MARK: - Network Reachability

/// Network reachability state
public enum NetworkReachability: String, Sendable {
    case unknown
    case notReachable
    case reachableViaWiFi
    case reachableViaCellular
    
    public var isReachable: Bool {
        self == .reachableViaWiFi || self == .reachableViaCellular
    }
}

// MARK: - Sync State

/// State of sync operation
public enum SyncState: Equatable, Sendable {
    case idle
    case syncing(progress: Double)
    case completed(changesCount: Int)
    case failed(error: String)
    case paused
    
    public static func == (lhs: SyncState, rhs: SyncState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.syncing(let p1), .syncing(let p2)): return p1 == p2
        case (.completed(let c1), .completed(let c2)): return c1 == c2
        case (.failed(let e1), .failed(let e2)): return e1 == e2
        case (.paused, .paused): return true
        default: return false
        }
    }
}

// MARK: - Framework Errors

/// Errors that can occur in OfflineFirst operations
public enum OfflineFirstError: Error, LocalizedError {
    case notInitialized
    case networkUnavailable
    case syncFailed(underlying: Error)
    case storageFailed(underlying: Error)
    case conflictDetected
    case entityNotFound
    case invalidData
    case encryptionFailed
    case compressionFailed
    case unauthorized
    case serverError(statusCode: Int)
    case timeout
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "OfflineFirst framework not initialized"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"
        case .storageFailed(let error):
            return "Storage operation failed: \(error.localizedDescription)"
        case .conflictDetected:
            return "Sync conflict detected"
        case .entityNotFound:
            return "Entity not found"
        case .invalidData:
            return "Invalid data format"
        case .encryptionFailed:
            return "Encryption operation failed"
        case .compressionFailed:
            return "Compression operation failed"
        case .unauthorized:
            return "Authorization required"
        case .serverError(let code):
            return "Server error: \(code)"
        case .timeout:
            return "Operation timed out"
        case .cancelled:
            return "Operation was cancelled"
        }
    }
}

// MARK: - Logging

/// Log levels for OfflineFirst
public enum LogLevel: Int, Comparable, Sendable {
    case verbose = 0
    case debug = 1
    case info = 2
    case warning = 3
    case error = 4
    case none = 5
    
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Internal logger
internal struct Logger {
    static var level: LogLevel = .info
    
    static func log(_ message: String, level: LogLevel = .debug, file: String = #file, function: String = #function, line: Int = #line) {
        guard level >= Self.level else { return }
        
        let filename = (file as NSString).lastPathComponent
        let prefix: String
        
        switch level {
        case .verbose: prefix = "📝"
        case .debug: prefix = "🔍"
        case .info: prefix = "ℹ️"
        case .warning: prefix = "⚠️"
        case .error: prefix = "❌"
        case .none: return
        }
        
        #if DEBUG
        print("\(prefix) [\(filename):\(line)] \(function): \(message)")
        #endif
    }
    
    static func verbose(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .verbose, file: file, function: function, line: line)
    }
    
    static func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }
    
    static func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }
    
    static func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }
    
    static func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
}
