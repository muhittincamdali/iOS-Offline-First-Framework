import Foundation
import Network
import os

/// Reports whether the device can reach the network.
public protocol ConnectivityMonitor: Sendable {
    /// Whether the device is online: the current value first, then every change.
    func updates() -> AsyncStream<Bool>
}

/// A ``ConnectivityMonitor`` backed by `NWPathMonitor` from the Network framework.
///
/// "Online" means the system has a usable network path. It does not prove that your server is
/// reachable, so the store still handles failed requests with its ``RetryPolicy``.
public struct NetworkConnectivityMonitor: ConnectivityMonitor {
    /// Creates a monitor for every interface type.
    public init() {}

    public func updates() -> AsyncStream<Bool> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            continuation.onTermination = { _ in
                monitor.cancel()
            }
            monitor.start(queue: DispatchQueue(label: "OfflineFirstFramework.NetworkConnectivityMonitor"))
        }
    }
}

/// A ``ConnectivityMonitor`` you switch by hand, for tests, previews and an "offline mode"
/// switch in a demo.
public final class SimulatedConnectivity: ConnectivityMonitor {
    private struct State {
        var isOnline: Bool
        var continuations: [UUID: AsyncStream<Bool>.Continuation] = [:]
    }

    private let state: OSAllocatedUnfairLock<State>

    /// Creates a monitor that starts online or offline.
    public init(isOnline: Bool = true) {
        state = OSAllocatedUnfairLock(initialState: State(isOnline: isOnline))
    }

    /// Whether the simulated device is online.
    public var isOnline: Bool {
        state.withLock { $0.isOnline }
    }

    /// Switches the connection on or off and tells every listener.
    public func setOnline(_ online: Bool) {
        let listeners = state.withLock { state -> [AsyncStream<Bool>.Continuation] in
            guard state.isOnline != online else { return [] }
            state.isOnline = online
            return Array(state.continuations.values)
        }
        for listener in listeners {
            listener.yield(online)
        }
    }

    public func updates() -> AsyncStream<Bool> {
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        let current = state.withLock { state in
            state.continuations[id] = continuation
            return state.isOnline
        }
        continuation.yield(current)
        continuation.onTermination = { [weak self] _ in
            _ = self?.state.withLock { $0.continuations.removeValue(forKey: id) }
        }
        return stream
    }
}
