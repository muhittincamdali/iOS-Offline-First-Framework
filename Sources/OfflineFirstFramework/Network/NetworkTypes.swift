import Foundation

public enum OFConnectionType: String, Codable, Sendable {
    case wifi
    case cellular
    case ethernet
    case loopback
    case unknown
}

public enum OFConnectionQuality: String, Codable, Sendable {
    case excellent
    case good
    case fair
    case poor
    case unknown
}

public struct NetworkStatus: Sendable {
    public let isOnline: Bool
    public let connectionType: OFConnectionType
    public let connectionQuality: OFConnectionQuality
    
    public init(isOnline: Bool, connectionType: OFConnectionType, connectionQuality: OFConnectionQuality) {
        self.isOnline = isOnline
        self.connectionType = connectionType
        self.connectionQuality = connectionQuality
    }
}
