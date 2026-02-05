import Foundation
import Network
import Combine

// MARK: - Bandwidth Configuration

/// Configuration for bandwidth optimization
public struct BandwidthConfiguration: Codable, Sendable {
    public let maxConcurrentTransfers: Int
    public let chunkSize: Int
    public let adaptiveChunking: Bool
    public let wifiOnlyForLargeFiles: Bool
    public let largeFileThreshold: Int64
    public let compressionEnabled: Bool
    public let prioritizeUserInitiated: Bool
    public let backgroundTransferLimit: Int64  // bytes per second
    
    public static let `default` = BandwidthConfiguration(
        maxConcurrentTransfers: 4,
        chunkSize: 65536,
        adaptiveChunking: true,
        wifiOnlyForLargeFiles: true,
        largeFileThreshold: 10 * 1024 * 1024,  // 10MB
        compressionEnabled: true,
        prioritizeUserInitiated: true,
        backgroundTransferLimit: 512 * 1024  // 512KB/s
    )
    
    public static let conservative = BandwidthConfiguration(
        maxConcurrentTransfers: 2,
        chunkSize: 32768,
        adaptiveChunking: true,
        wifiOnlyForLargeFiles: true,
        largeFileThreshold: 5 * 1024 * 1024,
        compressionEnabled: true,
        prioritizeUserInitiated: true,
        backgroundTransferLimit: 256 * 1024
    )
    
    public static let aggressive = BandwidthConfiguration(
        maxConcurrentTransfers: 8,
        chunkSize: 131072,
        adaptiveChunking: true,
        wifiOnlyForLargeFiles: false,
        largeFileThreshold: 50 * 1024 * 1024,
        compressionEnabled: true,
        prioritizeUserInitiated: true,
        backgroundTransferLimit: 2 * 1024 * 1024
    )
    
    public init(
        maxConcurrentTransfers: Int = 4,
        chunkSize: Int = 65536,
        adaptiveChunking: Bool = true,
        wifiOnlyForLargeFiles: Bool = true,
        largeFileThreshold: Int64 = 10 * 1024 * 1024,
        compressionEnabled: Bool = true,
        prioritizeUserInitiated: Bool = true,
        backgroundTransferLimit: Int64 = 512 * 1024
    ) {
        self.maxConcurrentTransfers = maxConcurrentTransfers
        self.chunkSize = chunkSize
        self.adaptiveChunking = adaptiveChunking
        self.wifiOnlyForLargeFiles = wifiOnlyForLargeFiles
        self.largeFileThreshold = largeFileThreshold
        self.compressionEnabled = compressionEnabled
        self.prioritizeUserInitiated = prioritizeUserInitiated
        self.backgroundTransferLimit = backgroundTransferLimit
    }
}

// MARK: - Network Quality

/// Represents current network quality metrics
public struct NetworkQuality: Sendable {
    public let connectionType: ConnectionType
    public let isExpensive: Bool
    public let isConstrained: Bool
    public let estimatedBandwidth: Int64  // bytes per second
    public let latency: TimeInterval
    public let packetLoss: Double
    public let signalStrength: SignalStrength
    
    public var isGood: Bool {
        estimatedBandwidth > 1_000_000 && latency < 0.1 && packetLoss < 0.01
    }
    
    public var isFair: Bool {
        estimatedBandwidth > 100_000 && latency < 0.5 && packetLoss < 0.05
    }
    
    public var isPoor: Bool {
        !isGood && !isFair
    }
    
    public static let unknown = NetworkQuality(
        connectionType: .unknown,
        isExpensive: false,
        isConstrained: false,
        estimatedBandwidth: 0,
        latency: 0,
        packetLoss: 0,
        signalStrength: .unknown
    )
}

public enum ConnectionType: String, Codable, Sendable {
    case wifi
    case cellular
    case ethernet
    case unknown
}

public enum SignalStrength: Int, Codable, Sendable, Comparable {
    case unknown = 0
    case poor = 1
    case fair = 2
    case good = 3
    case excellent = 4
    
    public static func < (lhs: SignalStrength, rhs: SignalStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Transfer Priority

public enum TransferPriority: Int, Comparable, Sendable {
    case background = 0
    case low = 1
    case normal = 2
    case high = 3
    case userInitiated = 4
    
    public static func < (lhs: TransferPriority, rhs: TransferPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Transfer Task

/// Represents a bandwidth-managed transfer task
public struct TransferTask: Identifiable, Sendable {
    public let id: String
    public let type: TransferType
    public let dataSize: Int64
    public let priority: TransferPriority
    public let createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?
    public var transferredBytes: Int64
    public var status: TransferStatus
    public var error: String?
    
    public var progress: Double {
        guard dataSize > 0 else { return 0 }
        return Double(transferredBytes) / Double(dataSize)
    }
    
    public var throughput: Int64 {
        guard let started = startedAt else { return 0 }
        let duration = (completedAt ?? Date()).timeIntervalSince(started)
        guard duration > 0 else { return 0 }
        return Int64(Double(transferredBytes) / duration)
    }
    
    public init(
        id: String = UUID().uuidString,
        type: TransferType,
        dataSize: Int64,
        priority: TransferPriority = .normal
    ) {
        self.id = id
        self.type = type
        self.dataSize = dataSize
        self.priority = priority
        self.createdAt = Date()
        self.transferredBytes = 0
        self.status = .pending
    }
}

public enum TransferType: String, Codable, Sendable {
    case upload
    case download
    case sync
}

public enum TransferStatus: String, Codable, Sendable {
    case pending
    case queued
    case active
    case paused
    case completed
    case failed
    case cancelled
}

// MARK: - Bandwidth Optimizer

/// Optimizes network bandwidth usage for sync operations
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public actor BandwidthOptimizer {
    
    // MARK: - Publishers
    
    public nonisolated let qualityPublisher = PassthroughSubject<NetworkQuality, Never>()
    public nonisolated let transfersPublisher = PassthroughSubject<[TransferTask], Never>()
    public nonisolated let throughputPublisher = PassthroughSubject<Int64, Never>()
    
    // MARK: - Properties
    
    private let configuration: BandwidthConfiguration
    private let monitor: NWPathMonitor
    private var currentQuality: NetworkQuality = .unknown
    private var transferQueue: [TransferTask] = []
    private var activeTasks: [String: TransferTask] = []
    private var throughputSamples: [Int64] = []
    private var monitorQueue = DispatchQueue(label: "com.offlinefirst.bandwidth")
    
    // MARK: - Computed Properties
    
    public var optimalChunkSize: Int {
        guard configuration.adaptiveChunking else {
            return configuration.chunkSize
        }
        
        // Adapt chunk size based on network quality
        switch currentQuality.signalStrength {
        case .excellent:
            return configuration.chunkSize * 4
        case .good:
            return configuration.chunkSize * 2
        case .fair:
            return configuration.chunkSize
        case .poor:
            return configuration.chunkSize / 2
        case .unknown:
            return configuration.chunkSize
        }
    }
    
    public var maxConcurrentTasks: Int {
        // Adapt based on network quality
        if currentQuality.isPoor {
            return max(1, configuration.maxConcurrentTransfers / 2)
        }
        return configuration.maxConcurrentTransfers
    }
    
    public var averageThroughput: Int64 {
        guard !throughputSamples.isEmpty else { return 0 }
        return throughputSamples.reduce(0, +) / Int64(throughputSamples.count)
    }
    
    public var canTransferLargeFiles: Bool {
        if configuration.wifiOnlyForLargeFiles {
            return currentQuality.connectionType == .wifi || currentQuality.connectionType == .ethernet
        }
        return true
    }
    
    // MARK: - Initialization
    
    public init(configuration: BandwidthConfiguration = .default) {
        self.configuration = configuration
        self.monitor = NWPathMonitor()
        
        Task {
            await startMonitoring()
        }
    }
    
    deinit {
        monitor.cancel()
    }
    
    // MARK: - Network Monitoring
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task {
                await self?.handlePathUpdate(path)
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    private func handlePathUpdate(_ path: NWPath) {
        let connectionType: ConnectionType
        let isExpensive = path.isExpensive
        let isConstrained = path.isConstrained
        
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .ethernet
        } else {
            connectionType = .unknown
        }
        
        // Estimate bandwidth based on connection type
        let estimatedBandwidth: Int64
        let signalStrength: SignalStrength
        
        switch connectionType {
        case .wifi:
            estimatedBandwidth = 50_000_000  // 50 Mbps typical
            signalStrength = .good
        case .ethernet:
            estimatedBandwidth = 100_000_000  // 100 Mbps
            signalStrength = .excellent
        case .cellular:
            estimatedBandwidth = isConstrained ? 1_000_000 : 10_000_000
            signalStrength = isConstrained ? .poor : .fair
        case .unknown:
            estimatedBandwidth = 0
            signalStrength = .unknown
        }
        
        currentQuality = NetworkQuality(
            connectionType: connectionType,
            isExpensive: isExpensive,
            isConstrained: isConstrained,
            estimatedBandwidth: estimatedBandwidth,
            latency: 0.05,  // Would need actual measurement
            packetLoss: 0,
            signalStrength: signalStrength
        )
        
        qualityPublisher.send(currentQuality)
        
        // Adjust active transfers based on new quality
        adjustTransfers()
    }
    
    // MARK: - Transfer Management
    
    /// Queue a transfer task
    public func queueTransfer(_ task: TransferTask) -> String {
        var mutableTask = task
        mutableTask.status = .queued
        
        // Check large file constraint
        if task.dataSize > configuration.largeFileThreshold && !canTransferLargeFiles {
            mutableTask.status = .paused
            mutableTask.error = "Waiting for WiFi connection"
        }
        
        transferQueue.append(mutableTask)
        
        // Sort by priority
        transferQueue.sort { $0.priority > $1.priority }
        
        publishTransfers()
        processQueue()
        
        return task.id
    }
    
    /// Cancel a transfer
    public func cancelTransfer(id: String) {
        if var task = activeTasks[id] {
            task.status = .cancelled
            activeTasks.removeValue(forKey: id)
        }
        
        if let index = transferQueue.firstIndex(where: { $0.id == id }) {
            transferQueue[index].status = .cancelled
            transferQueue.remove(at: index)
        }
        
        publishTransfers()
        processQueue()
    }
    
    /// Pause a transfer
    public func pauseTransfer(id: String) {
        if var task = activeTasks[id] {
            task.status = .paused
            activeTasks.removeValue(forKey: id)
            transferQueue.insert(task, at: 0)
        }
        
        publishTransfers()
    }
    
    /// Resume a paused transfer
    public func resumeTransfer(id: String) {
        if let index = transferQueue.firstIndex(where: { $0.id == id && $0.status == .paused }) {
            transferQueue[index].status = .queued
            processQueue()
        }
    }
    
    /// Update transfer progress
    public func updateProgress(id: String, transferredBytes: Int64) {
        if var task = activeTasks[id] {
            task.transferredBytes = transferredBytes
            activeTasks[id] = task
            
            // Calculate throughput
            if let started = task.startedAt {
                let duration = Date().timeIntervalSince(started)
                if duration > 0 {
                    let throughput = Int64(Double(transferredBytes) / duration)
                    recordThroughput(throughput)
                }
            }
        }
        
        publishTransfers()
    }
    
    /// Mark transfer as completed
    public func completeTransfer(id: String) {
        if var task = activeTasks[id] {
            task.status = .completed
            task.completedAt = Date()
            task.transferredBytes = task.dataSize
            activeTasks.removeValue(forKey: id)
            
            // Record final throughput
            if let throughput = task.throughput as Int64? {
                recordThroughput(throughput)
            }
        }
        
        publishTransfers()
        processQueue()
    }
    
    /// Mark transfer as failed
    public func failTransfer(id: String, error: String) {
        if var task = activeTasks[id] {
            task.status = .failed
            task.error = error
            activeTasks.removeValue(forKey: id)
        }
        
        publishTransfers()
        processQueue()
    }
    
    // MARK: - Queue Processing
    
    private func processQueue() {
        // Don't process if at capacity
        guard activeTasks.count < maxConcurrentTasks else { return }
        
        // Find next eligible task
        while activeTasks.count < maxConcurrentTasks {
            guard let index = transferQueue.firstIndex(where: { task in
                task.status == .queued && isEligible(task)
            }) else {
                break
            }
            
            var task = transferQueue.remove(at: index)
            task.status = .active
            task.startedAt = Date()
            activeTasks[task.id] = task
        }
        
        publishTransfers()
    }
    
    private func isEligible(_ task: TransferTask) -> Bool {
        // Check large file constraint
        if task.dataSize > configuration.largeFileThreshold {
            return canTransferLargeFiles
        }
        
        // Check if network is available
        if currentQuality.connectionType == .unknown {
            return false
        }
        
        return true
    }
    
    private func adjustTransfers() {
        // Pause large file transfers if necessary
        if !canTransferLargeFiles {
            for (id, task) in activeTasks where task.dataSize > configuration.largeFileThreshold {
                pauseTransfer(id: id)
            }
        }
        
        // Reduce concurrent transfers on poor connection
        while activeTasks.count > maxConcurrentTasks {
            // Pause lowest priority active task
            if let lowestPriority = activeTasks.values.min(by: { $0.priority < $1.priority }) {
                pauseTransfer(id: lowestPriority.id)
            } else {
                break
            }
        }
        
        // Try to start more transfers if capacity available
        processQueue()
    }
    
    // MARK: - Throughput Tracking
    
    private func recordThroughput(_ throughput: Int64) {
        throughputSamples.append(throughput)
        
        // Keep last 100 samples
        if throughputSamples.count > 100 {
            throughputSamples.removeFirst()
        }
        
        throughputPublisher.send(averageThroughput)
    }
    
    // MARK: - Bandwidth Estimation
    
    /// Estimate time to transfer data
    public func estimateTransferTime(bytes: Int64) -> TimeInterval {
        let bandwidth = averageThroughput > 0 ? averageThroughput : currentQuality.estimatedBandwidth
        guard bandwidth > 0 else { return .infinity }
        return TimeInterval(bytes) / TimeInterval(bandwidth)
    }
    
    /// Get recommended batch size for current conditions
    public func recommendedBatchSize() -> Int {
        let baseSize = configuration.chunkSize
        
        switch currentQuality.signalStrength {
        case .excellent:
            return baseSize * 8
        case .good:
            return baseSize * 4
        case .fair:
            return baseSize * 2
        case .poor:
            return baseSize
        case .unknown:
            return baseSize / 2
        }
    }
    
    /// Check if should defer non-essential sync
    public func shouldDeferSync(priority: TransferPriority) -> Bool {
        // Don't defer user-initiated
        if priority == .userInitiated {
            return false
        }
        
        // Defer on expensive/constrained networks for low priority
        if (currentQuality.isExpensive || currentQuality.isConstrained) && priority < .normal {
            return true
        }
        
        // Defer on poor connection
        if currentQuality.isPoor && priority < .high {
            return true
        }
        
        return false
    }
    
    // MARK: - Publishing
    
    private nonisolated func publishTransfers() {
        Task {
            let all = await allTransfers()
            transfersPublisher.send(all)
        }
    }
    
    public func allTransfers() -> [TransferTask] {
        var all = Array(activeTasks.values)
        all.append(contentsOf: transferQueue)
        return all.sorted { $0.createdAt < $1.createdAt }
    }
    
    public func networkQuality() -> NetworkQuality {
        currentQuality
    }
}

// MARK: - Data Deduplication

/// Deduplicates data to reduce bandwidth usage
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public struct DataDeduplicator {
    
    private var hashCache: [String: Data] = [:]
    
    public init() {}
    
    /// Check if data was previously sent
    public mutating func isDuplicate(_ data: Data) -> Bool {
        let hash = computeHash(data)
        if hashCache[hash] != nil {
            return true
        }
        hashCache[hash] = data
        return false
    }
    
    /// Get hash for data
    public func computeHash(_ data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Clear cache
    public mutating func clearCache() {
        hashCache.removeAll()
    }
    
    /// Remove old entries
    public mutating func pruneCache(keepingLast count: Int) {
        if hashCache.count > count {
            let keysToRemove = Array(hashCache.keys.prefix(hashCache.count - count))
            for key in keysToRemove {
                hashCache.removeValue(forKey: key)
            }
        }
    }
}

import CryptoKit
