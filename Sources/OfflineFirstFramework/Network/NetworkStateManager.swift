import Foundation
import Network
import RxSwift
import CocoaLumberjack

/// Manages network connectivity and state monitoring
@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public final class NetworkStateManager {
    
    // MARK: - Properties
    
    public let isOnline = BehaviorSubject<Bool>(value: false)
    public let connectionType = BehaviorSubject<ConnectionType>(value: .unknown)
    public let connectionQuality = BehaviorSubject<ConnectionQuality>(value: .unknown)
    
    public var currentStatus: NetworkStatus {
        return NetworkStatus(
            isOnline: (try? isOnline.value()) ?? false,
            connectionType: (try? connectionType.value()) ?? .unknown,
            connectionQuality: (try? connectionQuality.value()) ?? .unknown
        )
    }
    
    // MARK: - Private Properties
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.offlinefirst.network", qos: .utility)
    private let disposeBag = DisposeBag()
    
    // MARK: - Initialization
    
    public init() {
        setupMonitoring()
    }
    
    // MARK: - Public Methods
    
    public func initialize() {
        DDLogInfo("NetworkStateManager initialized")
        startMonitoring()
    }
    
    public func startMonitoring() {
        monitor.start(queue: queue)
        DDLogInfo("Network monitoring started")
    }
    
    public func stopMonitoring() {
        monitor.cancel()
        DDLogInfo("Network monitoring stopped")
    }
    
    public func checkConnectivity() -> Observable<NetworkStatus> {
        return Observable.create { [weak self] observer in
            guard let self = self else {
                observer.onCompleted()
                return Disposables.create()
            }
            
            let status = self.currentStatus
            observer.onNext(status)
            observer.onCompleted()
            
            return Disposables.create()
        }
    }
    
    public func testConnection(url: URL) -> Observable<ConnectionTestResult> {
        return Observable.create { observer in
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    observer.onNext(.failure(error))
                } else if let httpResponse = response as? HTTPURLResponse {
                    let result = ConnectionTestResult(
                        isSuccess: httpResponse.statusCode >= 200 && httpResponse.statusCode < 300,
                        statusCode: httpResponse.statusCode,
                        responseTime: Date().timeIntervalSince1970
                    )
                    observer.onNext(result)
                } else {
                    observer.onNext(.failure(NetworkError.unknown))
                }
                observer.onCompleted()
            }
            task.resume()
            
            return Disposables.create {
                task.cancel()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
    }
    
    private func handlePathUpdate(_ path: NWPath) {
        let isOnline = path.status == .satisfied
        let connectionType = determineConnectionType(path)
        let connectionQuality = determineConnectionQuality(path)
        
        DispatchQueue.main.async { [weak self] in
            self?.isOnline.onNext(isOnline)
            self?.connectionType.onNext(connectionType)
            self?.connectionQuality.onNext(connectionQuality)
            
            DDLogInfo("Network update - Online: \(isOnline), Type: \(connectionType), Quality: \(connectionQuality)")
        }
    }
    
    private func determineConnectionType(_ path: NWPath) -> ConnectionType {
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
    
    private func determineConnectionQuality(_ path: NWPath) -> ConnectionQuality {
        // This is a simplified implementation
        // In a real app, you would measure actual network performance
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

public enum ConnectionType {
    case wifi
    case cellular
    case ethernet
    case loopback
    case unknown
}

public enum ConnectionQuality {
    case excellent
    case good
    case fair
    case poor
    case unknown
}

public struct NetworkStatus {
    public let isOnline: Bool
    public let connectionType: ConnectionType
    public let connectionQuality: ConnectionQuality
    
    public init(isOnline: Bool, connectionType: ConnectionType, connectionQuality: ConnectionQuality) {
        self.isOnline = isOnline
        self.connectionType = connectionType
        self.connectionQuality = connectionQuality
    }
}

public struct ConnectionTestResult {
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
