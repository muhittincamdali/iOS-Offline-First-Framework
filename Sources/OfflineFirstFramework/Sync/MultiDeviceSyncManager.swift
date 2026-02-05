import Foundation
import Combine
import CryptoKit

// MARK: - Multi-Device Configuration

/// Configuration for multi-device synchronization
public struct MultiDeviceConfiguration: Codable, Sendable {
    public let deviceId: String
    public let deviceName: String
    public let platform: DevicePlatform
    public let syncProtocol: SyncProtocol
    public let heartbeatInterval: TimeInterval
    public let conflictStrategy: MultiDeviceConflictStrategy
    public let maxDevices: Int
    
    public static func `default`(deviceName: String) -> MultiDeviceConfiguration {
        MultiDeviceConfiguration(
            deviceId: UUID().uuidString,
            deviceName: deviceName,
            platform: .iOS,
            syncProtocol: .websocket,
            heartbeatInterval: 30.0,
            conflictStrategy: .lastWriteWins,
            maxDevices: 10
        )
    }
    
    public init(
        deviceId: String = UUID().uuidString,
        deviceName: String,
        platform: DevicePlatform = .iOS,
        syncProtocol: SyncProtocol = .websocket,
        heartbeatInterval: TimeInterval = 30.0,
        conflictStrategy: MultiDeviceConflictStrategy = .lastWriteWins,
        maxDevices: Int = 10
    ) {
        self.deviceId = deviceId
        self.deviceName = deviceName
        self.platform = platform
        self.syncProtocol = syncProtocol
        self.heartbeatInterval = heartbeatInterval
        self.conflictStrategy = conflictStrategy
        self.maxDevices = maxDevices
    }
}

public enum DevicePlatform: String, Codable, Sendable {
    case iOS
    case macOS
    case tvOS
    case watchOS
    case visionOS
    case android
    case web
}

public enum SyncProtocol: String, Codable, Sendable {
    case websocket
    case polling
    case pushNotification
    case hybrid
}

public enum MultiDeviceConflictStrategy: String, Codable, Sendable {
    case lastWriteWins
    case firstWriteWins
    case merge
    case askUser
    case devicePriority
}

// MARK: - Device Info

/// Represents a connected device
public struct DeviceInfo: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let platform: DevicePlatform
    public let lastSeen: Date
    public let syncVersion: Int64
    public let isOnline: Bool
    public let capabilities: Set<DeviceCapability>
    
    public init(
        id: String,
        name: String,
        platform: DevicePlatform,
        lastSeen: Date = Date(),
        syncVersion: Int64 = 0,
        isOnline: Bool = true,
        capabilities: Set<DeviceCapability> = []
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.lastSeen = lastSeen
        self.syncVersion = syncVersion
        self.isOnline = isOnline
        self.capabilities = capabilities
    }
}

public enum DeviceCapability: String, Codable, Sendable {
    case backgroundSync
    case pushNotifications
    case realTimeSync
    case offlineStorage
    case encryption
}

// MARK: - Sync Message

/// Message for device-to-device sync
public struct SyncMessage: Codable, Identifiable, Sendable {
    public let id: String
    public let sourceDeviceId: String
    public let targetDeviceId: String?  // nil = broadcast
    public let type: SyncMessageType
    public let payload: Data
    public let timestamp: Date
    public let vectorClock: VectorClock
    public let checksum: String
    
    public init(
        id: String = UUID().uuidString,
        sourceDeviceId: String,
        targetDeviceId: String? = nil,
        type: SyncMessageType,
        payload: Data,
        vectorClock: VectorClock
    ) {
        self.id = id
        self.sourceDeviceId = sourceDeviceId
        self.targetDeviceId = targetDeviceId
        self.type = type
        self.payload = payload
        self.timestamp = Date()
        self.vectorClock = vectorClock
        
        // Compute checksum
        var data = payload
        data.append(id.data(using: .utf8) ?? Data())
        self.checksum = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
}

public enum SyncMessageType: String, Codable, Sendable {
    case heartbeat
    case fullSync
    case deltaSync
    case conflictResolution
    case deviceRegistration
    case deviceDeregistration
    case acknowledgment
    case request
}

// MARK: - Multi-Device Sync Manager

/// Manages synchronization across multiple devices
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public actor MultiDeviceSyncManager {
    
    // MARK: - Properties
    
    public nonisolated let devicesPublisher = PassthroughSubject<[DeviceInfo], Never>()
    public nonisolated let messagesPublisher = PassthroughSubject<SyncMessage, Never>()
    public nonisolated let conflictsPublisher = PassthroughSubject<DeviceConflict, Never>()
    
    private let configuration: MultiDeviceConfiguration
    private var connectedDevices: [String: DeviceInfo] = [:]
    private var localVectorClock = VectorClock()
    private var pendingMessages: [SyncMessage] = []
    private var messageHandler: ((SyncMessage) async throws -> Void)?
    private var heartbeatTask: Task<Void, Never>?
    private var isRunning = false
    
    // MARK: - Computed Properties
    
    public var currentDevice: DeviceInfo {
        DeviceInfo(
            id: configuration.deviceId,
            name: configuration.deviceName,
            platform: configuration.platform,
            syncVersion: localVectorClock.timestamp(for: configuration.deviceId),
            capabilities: [.offlineStorage, .encryption, .backgroundSync]
        )
    }
    
    public var deviceCount: Int {
        connectedDevices.count + 1  // +1 for self
    }
    
    public var allDevices: [DeviceInfo] {
        var devices = Array(connectedDevices.values)
        devices.insert(currentDevice, at: 0)
        return devices
    }
    
    // MARK: - Initialization
    
    public init(configuration: MultiDeviceConfiguration) {
        self.configuration = configuration
        localVectorClock.increment(for: configuration.deviceId)
    }
    
    // MARK: - Lifecycle
    
    /// Start multi-device sync
    public func start() {
        guard !isRunning else { return }
        isRunning = true
        
        // Register this device
        Task {
            await registerDevice()
        }
        
        // Start heartbeat
        startHeartbeat()
    }
    
    /// Stop multi-device sync
    public func stop() {
        isRunning = false
        heartbeatTask?.cancel()
        heartbeatTask = nil
        
        // Deregister this device
        Task {
            await deregisterDevice()
        }
    }
    
    // MARK: - Device Management
    
    private func registerDevice() async {
        let message = SyncMessage(
            sourceDeviceId: configuration.deviceId,
            type: .deviceRegistration,
            payload: try! JSONEncoder().encode(currentDevice),
            vectorClock: localVectorClock
        )
        
        await broadcast(message)
    }
    
    private func deregisterDevice() async {
        let message = SyncMessage(
            sourceDeviceId: configuration.deviceId,
            type: .deviceDeregistration,
            payload: Data(),
            vectorClock: localVectorClock
        )
        
        await broadcast(message)
    }
    
    /// Update device info when received
    public func updateDevice(_ device: DeviceInfo) {
        connectedDevices[device.id] = device
        
        // Enforce max devices
        if connectedDevices.count > configuration.maxDevices {
            // Remove oldest offline device
            if let oldest = connectedDevices.values
                .filter({ !$0.isOnline })
                .min(by: { $0.lastSeen < $1.lastSeen }) {
                connectedDevices.removeValue(forKey: oldest.id)
            }
        }
        
        publishDevices()
    }
    
    /// Remove device
    public func removeDevice(id: String) {
        connectedDevices.removeValue(forKey: id)
        publishDevices()
    }
    
    /// Mark device as offline
    public func markOffline(deviceId: String) {
        if var device = connectedDevices[deviceId] {
            connectedDevices[deviceId] = DeviceInfo(
                id: device.id,
                name: device.name,
                platform: device.platform,
                lastSeen: device.lastSeen,
                syncVersion: device.syncVersion,
                isOnline: false,
                capabilities: device.capabilities
            )
            publishDevices()
        }
    }
    
    // MARK: - Messaging
    
    /// Set message handler for incoming messages
    public func setMessageHandler(_ handler: @escaping (SyncMessage) async throws -> Void) {
        self.messageHandler = handler
    }
    
    /// Broadcast message to all devices
    public func broadcast(_ message: SyncMessage) async {
        messagesPublisher.send(message)
        
        // Queue for retry if needed
        pendingMessages.append(message)
        
        // In a real implementation, this would send via WebSocket/Push/etc.
        // For now, we just publish
    }
    
    /// Send message to specific device
    public func send(_ message: SyncMessage, to deviceId: String) async {
        var targetedMessage = SyncMessage(
            id: message.id,
            sourceDeviceId: message.sourceDeviceId,
            targetDeviceId: deviceId,
            type: message.type,
            payload: message.payload,
            vectorClock: message.vectorClock
        )
        
        messagesPublisher.send(targetedMessage)
        pendingMessages.append(targetedMessage)
    }
    
    /// Handle incoming message
    public func handleIncoming(_ message: SyncMessage) async throws {
        // Validate checksum
        var data = message.payload
        data.append(message.id.data(using: .utf8) ?? Data())
        let expectedChecksum = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        
        guard message.checksum == expectedChecksum else {
            throw MultiDeviceSyncError.invalidChecksum
        }
        
        // Update vector clock
        localVectorClock = localVectorClock.merge(with: message.vectorClock)
        localVectorClock.increment(for: configuration.deviceId)
        
        // Process based on type
        switch message.type {
        case .heartbeat:
            await handleHeartbeat(message)
            
        case .deviceRegistration:
            await handleDeviceRegistration(message)
            
        case .deviceDeregistration:
            await handleDeviceDeregistration(message)
            
        case .fullSync, .deltaSync:
            try await messageHandler?(message)
            
        case .conflictResolution:
            await handleConflictResolution(message)
            
        case .acknowledgment:
            await handleAcknowledgment(message)
            
        case .request:
            try await handleRequest(message)
        }
        
        // Send acknowledgment
        await sendAcknowledgment(for: message)
    }
    
    // MARK: - Message Handlers
    
    private func handleHeartbeat(_ message: SyncMessage) async {
        guard let device = try? JSONDecoder().decode(DeviceInfo.self, from: message.payload) else {
            return
        }
        
        updateDevice(device)
    }
    
    private func handleDeviceRegistration(_ message: SyncMessage) async {
        guard let device = try? JSONDecoder().decode(DeviceInfo.self, from: message.payload) else {
            return
        }
        
        updateDevice(device)
        
        // Send our device info back
        let response = SyncMessage(
            sourceDeviceId: configuration.deviceId,
            targetDeviceId: device.id,
            type: .deviceRegistration,
            payload: try! JSONEncoder().encode(currentDevice),
            vectorClock: localVectorClock
        )
        
        await send(response, to: device.id)
    }
    
    private func handleDeviceDeregistration(_ message: SyncMessage) async {
        removeDevice(id: message.sourceDeviceId)
    }
    
    private func handleConflictResolution(_ message: SyncMessage) async {
        // Parse conflict resolution
        guard let resolution = try? JSONDecoder().decode(ConflictResolutionMessage.self, from: message.payload) else {
            return
        }
        
        // Apply resolution
        // This would be handled by the sync engine
    }
    
    private func handleAcknowledgment(_ message: SyncMessage) async {
        // Remove from pending
        pendingMessages.removeAll { $0.id == String(data: message.payload, encoding: .utf8) }
    }
    
    private func handleRequest(_ message: SyncMessage) async throws {
        try await messageHandler?(message)
    }
    
    private func sendAcknowledgment(for message: SyncMessage) async {
        let ack = SyncMessage(
            sourceDeviceId: configuration.deviceId,
            targetDeviceId: message.sourceDeviceId,
            type: .acknowledgment,
            payload: message.id.data(using: .utf8) ?? Data(),
            vectorClock: localVectorClock
        )
        
        await send(ack, to: message.sourceDeviceId)
    }
    
    // MARK: - Sync Operations
    
    /// Request full sync from all devices
    public func requestFullSync() async {
        let message = SyncMessage(
            sourceDeviceId: configuration.deviceId,
            type: .request,
            payload: "fullSync".data(using: .utf8) ?? Data(),
            vectorClock: localVectorClock
        )
        
        await broadcast(message)
    }
    
    /// Send delta sync to all devices
    public func sendDelta<T: Codable>(_ changes: [T]) async throws {
        let payload = try JSONEncoder().encode(changes)
        
        let message = SyncMessage(
            sourceDeviceId: configuration.deviceId,
            type: .deltaSync,
            payload: payload,
            vectorClock: localVectorClock
        )
        
        await broadcast(message)
        
        // Increment local clock
        localVectorClock.increment(for: configuration.deviceId)
    }
    
    // MARK: - Conflict Detection
    
    /// Detect conflicts between local and remote data
    public func detectConflict<T: Codable & Identifiable>(
        local: T,
        remote: T,
        remoteDeviceId: String,
        remoteVectorClock: VectorClock
    ) -> DeviceConflict? where T.ID: CustomStringConvertible {
        // Check if clocks are concurrent (conflict)
        guard localVectorClock.isConcurrent(with: remoteVectorClock) else {
            return nil
        }
        
        let conflict = DeviceConflict(
            entityId: String(describing: local.id),
            entityType: String(describing: T.self),
            localDeviceId: configuration.deviceId,
            remoteDeviceId: remoteDeviceId,
            localVectorClock: localVectorClock,
            remoteVectorClock: remoteVectorClock,
            localData: try? JSONEncoder().encode(local),
            remoteData: try? JSONEncoder().encode(remote)
        )
        
        conflictsPublisher.send(conflict)
        return conflict
    }
    
    /// Resolve conflict using configured strategy
    public func resolveConflict<T: Codable>(_ conflict: DeviceConflict, as type: T.Type) throws -> T {
        switch configuration.conflictStrategy {
        case .lastWriteWins:
            // Compare timestamps (using vector clock max)
            if conflict.localVectorClock.happenedBefore(conflict.remoteVectorClock) {
                guard let data = conflict.remoteData else { throw MultiDeviceSyncError.missingData }
                return try JSONDecoder().decode(T.self, from: data)
            } else {
                guard let data = conflict.localData else { throw MultiDeviceSyncError.missingData }
                return try JSONDecoder().decode(T.self, from: data)
            }
            
        case .firstWriteWins:
            // Opposite of last write wins
            if conflict.remoteVectorClock.happenedBefore(conflict.localVectorClock) {
                guard let data = conflict.remoteData else { throw MultiDeviceSyncError.missingData }
                return try JSONDecoder().decode(T.self, from: data)
            } else {
                guard let data = conflict.localData else { throw MultiDeviceSyncError.missingData }
                return try JSONDecoder().decode(T.self, from: data)
            }
            
        case .merge, .askUser, .devicePriority:
            // These require custom handling
            throw MultiDeviceSyncError.manualResolutionRequired
        }
    }
    
    // MARK: - Heartbeat
    
    private func startHeartbeat() {
        heartbeatTask = Task {
            while !Task.isCancelled && isRunning {
                await sendHeartbeat()
                
                do {
                    try await Task.sleep(nanoseconds: UInt64(configuration.heartbeatInterval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }
    
    private func sendHeartbeat() async {
        let message = SyncMessage(
            sourceDeviceId: configuration.deviceId,
            type: .heartbeat,
            payload: try! JSONEncoder().encode(currentDevice),
            vectorClock: localVectorClock
        )
        
        await broadcast(message)
        
        // Mark devices as offline if not seen recently
        let timeout = configuration.heartbeatInterval * 3
        let now = Date()
        
        for (id, device) in connectedDevices {
            if now.timeIntervalSince(device.lastSeen) > timeout {
                markOffline(deviceId: id)
            }
        }
    }
    
    // MARK: - Utilities
    
    private nonisolated func publishDevices() {
        Task {
            let devices = await allDevices
            devicesPublisher.send(devices)
        }
    }
}

// MARK: - Supporting Types

public struct DeviceConflict: Codable, Identifiable, Sendable {
    public let id: String
    public let entityId: String
    public let entityType: String
    public let localDeviceId: String
    public let remoteDeviceId: String
    public let localVectorClock: VectorClock
    public let remoteVectorClock: VectorClock
    public let localData: Data?
    public let remoteData: Data?
    public let timestamp: Date
    
    public init(
        id: String = UUID().uuidString,
        entityId: String,
        entityType: String,
        localDeviceId: String,
        remoteDeviceId: String,
        localVectorClock: VectorClock,
        remoteVectorClock: VectorClock,
        localData: Data?,
        remoteData: Data?
    ) {
        self.id = id
        self.entityId = entityId
        self.entityType = entityType
        self.localDeviceId = localDeviceId
        self.remoteDeviceId = remoteDeviceId
        self.localVectorClock = localVectorClock
        self.remoteVectorClock = remoteVectorClock
        self.localData = localData
        self.remoteData = remoteData
        self.timestamp = Date()
    }
}

public struct ConflictResolutionMessage: Codable, Sendable {
    public let conflictId: String
    public let resolution: String
    public let resolvedData: Data
    public let resolvedVectorClock: VectorClock
}

public enum MultiDeviceSyncError: Error, LocalizedError {
    case invalidChecksum
    case deviceNotFound
    case missingData
    case manualResolutionRequired
    case connectionFailed
    case timeout
    
    public var errorDescription: String? {
        switch self {
        case .invalidChecksum:
            return "Message checksum validation failed"
        case .deviceNotFound:
            return "Target device not found"
        case .missingData:
            return "Required data is missing"
        case .manualResolutionRequired:
            return "Conflict requires manual resolution"
        case .connectionFailed:
            return "Failed to connect to device"
        case .timeout:
            return "Operation timed out"
        }
    }
}
