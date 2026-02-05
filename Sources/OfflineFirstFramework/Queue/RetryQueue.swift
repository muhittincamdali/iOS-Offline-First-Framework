import Foundation
import Combine

// MARK: - Retry Configuration

/// Configuration for retry queue operations
public struct RetryConfiguration: Codable, Sendable {
    public let maxRetries: Int
    public let initialDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let backoffMultiplier: Double
    public let jitterFactor: Double
    public let retryableStatusCodes: Set<Int>
    public let persistQueue: Bool
    
    public static let `default` = RetryConfiguration(
        maxRetries: 5,
        initialDelay: 1.0,
        maxDelay: 300.0,  // 5 minutes
        backoffMultiplier: 2.0,
        jitterFactor: 0.25,
        retryableStatusCodes: [408, 429, 500, 502, 503, 504],
        persistQueue: true
    )
    
    public static let aggressive = RetryConfiguration(
        maxRetries: 10,
        initialDelay: 0.5,
        maxDelay: 600.0,  // 10 minutes
        backoffMultiplier: 1.5,
        jitterFactor: 0.2,
        retryableStatusCodes: [408, 429, 500, 502, 503, 504],
        persistQueue: true
    )
    
    public init(
        maxRetries: Int = 5,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 300.0,
        backoffMultiplier: Double = 2.0,
        jitterFactor: Double = 0.25,
        retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504],
        persistQueue: Bool = true
    ) {
        self.maxRetries = maxRetries
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
        self.jitterFactor = jitterFactor
        self.retryableStatusCodes = retryableStatusCodes
        self.persistQueue = persistQueue
    }
}

// MARK: - Queue Operation

/// Represents an operation in the retry queue
public struct QueueOperation: Codable, Identifiable, Sendable {
    public let id: String
    public let type: OperationType
    public let entityId: String
    public let entityType: String
    public let payload: Data
    public let priority: OperationPriority
    public let createdAt: Date
    public var retryCount: Int
    public var lastAttempt: Date?
    public var nextRetry: Date?
    public var status: OperationStatus
    public var error: String?
    public var metadata: [String: String]
    
    public init(
        id: String = UUID().uuidString,
        type: OperationType,
        entityId: String,
        entityType: String,
        payload: Data,
        priority: OperationPriority = .normal,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.type = type
        self.entityId = entityId
        self.entityType = entityType
        self.payload = payload
        self.priority = priority
        self.createdAt = Date()
        self.retryCount = 0
        self.lastAttempt = nil
        self.nextRetry = nil
        self.status = .pending
        self.error = nil
        self.metadata = metadata
    }
}

public enum OperationType: String, Codable, Sendable {
    case create
    case update
    case delete
    case sync
    case upload
    case download
}

public enum OperationPriority: Int, Codable, Comparable, Sendable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3
    
    public static func < (lhs: OperationPriority, rhs: OperationPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum OperationStatus: String, Codable, Sendable {
    case pending
    case inProgress
    case completed
    case failed
    case cancelled
    case retrying
}

// MARK: - Retry Queue

/// Production-ready retry queue with exponential backoff
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public actor RetryQueue {
    
    // MARK: - Published State
    
    public nonisolated let operationsPublisher = PassthroughSubject<[QueueOperation], Never>()
    public nonisolated let statusPublisher = PassthroughSubject<QueueStatus, Never>()
    
    // MARK: - Properties
    
    private let configuration: RetryConfiguration
    private var operations: [QueueOperation] = []
    private var isProcessing = false
    private var processingTask: Task<Void, Never>?
    private var persistenceURL: URL?
    
    private let fileManager = FileManager.default
    
    // MARK: - Computed Properties
    
    public var pendingCount: Int {
        operations.filter { $0.status == .pending || $0.status == .retrying }.count
    }
    
    public var completedCount: Int {
        operations.filter { $0.status == .completed }.count
    }
    
    public var failedCount: Int {
        operations.filter { $0.status == .failed }.count
    }
    
    public var queueStatus: QueueStatus {
        QueueStatus(
            isProcessing: isProcessing,
            pendingCount: pendingCount,
            completedCount: completedCount,
            failedCount: failedCount,
            totalCount: operations.count
        )
    }
    
    // MARK: - Initialization
    
    public init(configuration: RetryConfiguration = .default) {
        self.configuration = configuration
        
        if configuration.persistQueue {
            setupPersistence()
        }
    }
    
    private func setupPersistence() {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        persistenceURL = documentsPath.appendingPathComponent("OfflineFirst/RetryQueue.json")
        
        // Create directory if needed
        let directory = persistenceURL!.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        
        // Load persisted operations
        Task {
            await loadPersistedOperations()
        }
    }
    
    // MARK: - Queue Management
    
    /// Add operation to queue
    public func enqueue(_ operation: QueueOperation) {
        var op = operation
        op.status = .pending
        op.nextRetry = Date()
        
        operations.append(op)
        operations.sort { $0.priority > $1.priority }
        
        persistOperations()
        publishState()
        
        // Auto-start processing if not already running
        if !isProcessing {
            startProcessing()
        }
    }
    
    /// Add multiple operations
    public func enqueueBatch(_ newOperations: [QueueOperation]) {
        for operation in newOperations {
            var op = operation
            op.status = .pending
            op.nextRetry = Date()
            operations.append(op)
        }
        
        operations.sort { $0.priority > $1.priority }
        persistOperations()
        publishState()
        
        if !isProcessing {
            startProcessing()
        }
    }
    
    /// Cancel operation
    public func cancel(id: String) {
        if let index = operations.firstIndex(where: { $0.id == id }) {
            operations[index].status = .cancelled
            persistOperations()
            publishState()
        }
    }
    
    /// Cancel all pending operations
    public func cancelAll() {
        for index in operations.indices {
            if operations[index].status == .pending || operations[index].status == .retrying {
                operations[index].status = .cancelled
            }
        }
        persistOperations()
        publishState()
    }
    
    /// Remove completed and cancelled operations
    public func cleanup() {
        operations.removeAll { $0.status == .completed || $0.status == .cancelled }
        persistOperations()
        publishState()
    }
    
    /// Get all operations
    public func allOperations() -> [QueueOperation] {
        operations
    }
    
    /// Get operations by status
    public func operations(withStatus status: OperationStatus) -> [QueueOperation] {
        operations.filter { $0.status == status }
    }
    
    /// Retry failed operations
    public func retryFailed() {
        for index in operations.indices {
            if operations[index].status == .failed {
                operations[index].status = .retrying
                operations[index].retryCount = 0
                operations[index].nextRetry = Date()
                operations[index].error = nil
            }
        }
        persistOperations()
        publishState()
        
        if !isProcessing {
            startProcessing()
        }
    }
    
    // MARK: - Processing
    
    /// Start processing queue
    public func startProcessing() {
        guard !isProcessing else { return }
        
        isProcessing = true
        publishState()
        
        processingTask = Task {
            await processQueue()
        }
    }
    
    /// Stop processing queue
    public func stopProcessing() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
        publishState()
    }
    
    private func processQueue() async {
        while !Task.isCancelled {
            // Get next operation ready for processing
            guard let operation = nextReadyOperation() else {
                // No operations ready - check if we should wait or stop
                if let nextRetryDate = nextRetryDate() {
                    let delay = nextRetryDate.timeIntervalSinceNow
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                    continue
                } else {
                    // No pending operations - stop processing
                    break
                }
            }
            
            await processOperation(operation)
        }
        
        isProcessing = false
        publishState()
    }
    
    private func nextReadyOperation() -> QueueOperation? {
        let now = Date()
        return operations.first { operation in
            (operation.status == .pending || operation.status == .retrying) &&
            (operation.nextRetry == nil || operation.nextRetry! <= now)
        }
    }
    
    private func nextRetryDate() -> Date? {
        let pendingOps = operations.filter { $0.status == .pending || $0.status == .retrying }
        return pendingOps.compactMap { $0.nextRetry }.min()
    }
    
    private func processOperation(_ operation: QueueOperation) async {
        guard let index = operations.firstIndex(where: { $0.id == operation.id }) else { return }
        
        operations[index].status = .inProgress
        operations[index].lastAttempt = Date()
        publishState()
        
        do {
            // Execute the operation
            try await executeOperation(operation)
            
            // Success
            operations[index].status = .completed
            operations[index].error = nil
            
        } catch {
            // Failure
            operations[index].retryCount += 1
            operations[index].error = error.localizedDescription
            
            if operations[index].retryCount >= configuration.maxRetries || !isRetryable(error) {
                // Max retries reached or non-retryable error
                operations[index].status = .failed
            } else {
                // Schedule retry with exponential backoff
                let delay = calculateBackoff(retryCount: operations[index].retryCount)
                operations[index].status = .retrying
                operations[index].nextRetry = Date().addingTimeInterval(delay)
            }
        }
        
        persistOperations()
        publishState()
    }
    
    private func executeOperation(_ operation: QueueOperation) async throws {
        // This is where the actual network/sync operation would be executed
        // In a real implementation, this would call the appropriate service
        
        // Simulate network delay for demonstration
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // The actual implementation would look something like:
        // switch operation.type {
        // case .create:
        //     try await apiService.create(operation.payload)
        // case .update:
        //     try await apiService.update(operation.entityId, payload: operation.payload)
        // case .delete:
        //     try await apiService.delete(operation.entityId)
        // case .sync:
        //     try await syncService.sync(operation.payload)
        // case .upload:
        //     try await uploadService.upload(operation.payload)
        // case .download:
        //     try await downloadService.download(operation.entityId)
        // }
    }
    
    // MARK: - Backoff Calculation
    
    private func calculateBackoff(retryCount: Int) -> TimeInterval {
        // Exponential backoff: initialDelay * multiplier^retryCount
        var delay = configuration.initialDelay * pow(configuration.backoffMultiplier, Double(retryCount - 1))
        
        // Cap at max delay
        delay = min(delay, configuration.maxDelay)
        
        // Add jitter to prevent thundering herd
        let jitter = delay * configuration.jitterFactor * Double.random(in: -1...1)
        delay += jitter
        
        return max(0, delay)
    }
    
    private func isRetryable(_ error: Error) -> Bool {
        // Check if error is retryable based on type
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }
        
        // Check HTTP status codes
        if let httpError = error as? HTTPError {
            return configuration.retryableStatusCodes.contains(httpError.statusCode)
        }
        
        return false
    }
    
    // MARK: - Persistence
    
    private func persistOperations() {
        guard configuration.persistQueue, let url = persistenceURL else { return }
        
        do {
            let data = try JSONEncoder().encode(operations)
            try data.write(to: url, options: .atomic)
        } catch {
            // Log error but don't fail
            print("Failed to persist retry queue: \(error)")
        }
    }
    
    private func loadPersistedOperations() {
        guard configuration.persistQueue, let url = persistenceURL else { return }
        
        do {
            let data = try Data(contentsOf: url)
            let loaded = try JSONDecoder().decode([QueueOperation].self, from: data)
            
            // Reset in-progress operations to retrying
            operations = loaded.map { operation in
                var op = operation
                if op.status == .inProgress {
                    op.status = .retrying
                    op.nextRetry = Date()
                }
                return op
            }
            
            publishState()
        } catch {
            // No persisted data or corrupted - start fresh
            operations = []
        }
    }
    
    // MARK: - State Publishing
    
    private nonisolated func publishState() {
        Task {
            let ops = await allOperations()
            let status = await queueStatus
            operationsPublisher.send(ops)
            statusPublisher.send(status)
        }
    }
}

// MARK: - Supporting Types

public struct QueueStatus: Sendable {
    public let isProcessing: Bool
    public let pendingCount: Int
    public let completedCount: Int
    public let failedCount: Int
    public let totalCount: Int
    
    public var progress: Double {
        guard totalCount > 0 else { return 1.0 }
        return Double(completedCount) / Double(totalCount)
    }
}

public struct HTTPError: Error {
    public let statusCode: Int
    public let message: String?
    
    public init(statusCode: Int, message: String? = nil) {
        self.statusCode = statusCode
        self.message = message
    }
}

// MARK: - Operation Builder

/// Builder for creating queue operations
public struct OperationBuilder {
    private var type: OperationType = .sync
    private var entityId: String = ""
    private var entityType: String = ""
    private var payload: Data = Data()
    private var priority: OperationPriority = .normal
    private var metadata: [String: String] = [:]
    
    public init() {}
    
    public func type(_ type: OperationType) -> OperationBuilder {
        var builder = self
        builder.type = type
        return builder
    }
    
    public func entity(id: String, type: String) -> OperationBuilder {
        var builder = self
        builder.entityId = id
        builder.entityType = type
        return builder
    }
    
    public func payload(_ payload: Data) -> OperationBuilder {
        var builder = self
        builder.payload = payload
        return builder
    }
    
    public func payload<T: Codable>(_ object: T) throws -> OperationBuilder {
        var builder = self
        builder.payload = try JSONEncoder().encode(object)
        return builder
    }
    
    public func priority(_ priority: OperationPriority) -> OperationBuilder {
        var builder = self
        builder.priority = priority
        return builder
    }
    
    public func metadata(_ metadata: [String: String]) -> OperationBuilder {
        var builder = self
        builder.metadata = metadata
        return builder
    }
    
    public func build() -> QueueOperation {
        QueueOperation(
            type: type,
            entityId: entityId,
            entityType: entityType,
            payload: payload,
            priority: priority,
            metadata: metadata
        )
    }
}
