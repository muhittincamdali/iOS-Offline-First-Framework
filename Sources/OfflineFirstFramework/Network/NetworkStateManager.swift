import Foundation
import Network
@preconcurrency import Combine

/// Manages network connectivity and state monitoring
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public final class NetworkStateManager: Sendable {
    
    // MARK: - Properties
    
    public let isOnline = CurrentValueSubject<Bool, Never>(false)
    public let connectionType = CurrentValueSubject<OFConnectionType, Never>(.unknown)
    public let connectionQuality = CurrentValueSubject<OFConnectionQuality, Never>(.unknown)
    
    public var currentStatus: NetworkStatus {
        return NetworkStatus(
            isOnline: isOnline.value,
            connectionType: connectionType.value,
            connectionQuality: connectionQuality.value
        )
    }
    
    // MARK: - Private Properties
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.offlinefirst.network", qos: .utility)
    
    // MARK: - Initialization
    
    public init() {
        setupMonitoring()
    }
    
    // MARK: - Public Methods
    
    public func initialize() {
        Logger.info("NetworkStateManager initialized")
        startMonitoring()
    }
    
    public func startMonitoring() {
        monitor.start(queue: queue)
        Logger.info("Network monitoring started")
    }
    
    public func stopMonitoring() {
        monitor.cancel()
        Logger.info("Network monitoring stopped")
    }
    
    public func checkConnectivity() async -> NetworkStatus {
        return currentStatus
    }
    
    public func testConnection(url: URL) async throws -> ConnectionTestResult {
        let startTime = Date()
        let (_, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.unknown
        }
        
        return ConnectionTestResult(
            isSuccess: (200..<300).contains(httpResponse.statusCode),
            statusCode: httpResponse.statusCode,
            responseTime: Date().timeIntervalSince(startTime)
        )
    }
    
    // MARK: - Private Methods
    
    private func setupMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.handlePathUpdate(path)
            }
        }
    }
    
    private func handlePathUpdate(_ path: NWPath) {
        let isOnline = path.status == .satisfied
        let connectionType = determineConnectionType(path)
        let connectionQuality = determineConnectionQuality(path)
        
        self.isOnline.send(isOnline)
        self.connectionType.send(connectionType)
        self.connectionQuality.send(connectionQuality)
        
        Logger.info("Network update - Online: \(isOnline), Type: \(connectionType), Quality: \(connectionQuality)")
    }
    
    private func determineConnectionType(_ path: NWPath) -> OFConnectionType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else if path.usesInterfaceType(.loopback) {
            return .loopback
        } else {
            return .unknown
        }
    }
    
    private func determineConnectionQuality(_ path: NWPath) -> OFConnectionQuality {
        if path.status == .satisfied {
            return .good
        } else if path.status == .requiresConnection {
            return .poor
        } else {
            return .unknown
        }
    }
}

// MARK: - Supporting Types





public struct ConnectionTestResult: Sendable {
    public let isSuccess: Bool
    public let statusCode: Int
    public let responseTime: TimeInterval
    
    public init(isSuccess: Bool, statusCode: Int, responseTime: TimeInterval) {
        self.isSuccess = isSuccess
        self.statusCode = statusCode
        self.responseTime = responseTime
    }
}

public enum NetworkError: Error {
    case unknown
    case noConnection
    case timeout
    case serverError
}
