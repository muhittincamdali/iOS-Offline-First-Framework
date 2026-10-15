import Foundation

/// Stops pulls for a while after repeated failures.
///
/// After ``failureThreshold`` failed pulls in a row the breaker opens: the store skips pulls
/// until ``cooldown`` has passed, which saves battery and server load while the server is down.
/// The first pull after the cooldown is a trial (half-open): success closes the breaker,
/// failure opens it for another cooldown. Pushes do not depend on the breaker: each change
/// waits for its own retry date (see ``RetryPolicy``), so local edits still reach a server whose
/// pulls fail.
public struct CircuitBreaker: Hashable, Sendable {
    /// The state of the breaker.
    public enum State: Hashable, Sendable {
        /// Requests go through.
        case closed
        /// Requests are skipped until the date.
        case open(until: Date)
        /// One trial request goes through.
        case halfOpen
    }

    /// Failed attempts in a row that open the breaker. At least 1.
    public let failureThreshold: Int

    /// How long the breaker stays open.
    public let cooldown: Duration

    /// The current state.
    public private(set) var state: State = .closed

    /// Failed attempts since the last success, at most ``failureThreshold``.
    public private(set) var consecutiveFailures = 0

    /// Creates a closed breaker.
    public init(failureThreshold: Int = 5, cooldown: Duration = .seconds(60)) {
        self.failureThreshold = max(1, failureThreshold)
        self.cooldown = max(.zero, cooldown)
    }

    /// Whether an attempt may start at `date`. An open breaker whose cooldown has passed turns
    /// half-open and lets the attempt through.
    public mutating func allowsAttempt(at date: Date) -> Bool {
        switch state {
        case .closed, .halfOpen:
            return true
        case .open(let until):
            guard date >= until else { return false }
            state = .halfOpen
            return true
        }
    }

    /// Records a successful attempt and closes the breaker.
    public mutating func recordSuccess() {
        state = .closed
        consecutiveFailures = 0
    }

    /// Records a failed attempt at `date`; opens the breaker at the threshold or after a
    /// failed trial.
    public mutating func recordFailure(at date: Date) {
        consecutiveFailures = min(consecutiveFailures + 1, failureThreshold)
        if state == .halfOpen || consecutiveFailures >= failureThreshold {
            state = .open(until: date.addingTimeInterval(cooldown.seconds))
        }
    }
}
