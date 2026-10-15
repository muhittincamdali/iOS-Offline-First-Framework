import Foundation

/// How long a failed change waits before the next push, and when to stop trying.
///
/// The wait grows exponentially from ``initialDelay`` by ``multiplier`` per attempt up to
/// ``maximumDelay``. ``jitter`` takes a random part off each wait, so many devices that went
/// offline together do not all retry in the same second. After ``maximumAttempts`` failed
/// pushes the change is parked: it stays in the store, ``OfflineStore/failedChanges()`` lists
/// it, and ``OfflineStore/retryFailedChanges()`` puts it back in the queue.
///
/// Every value is checked when the policy is created: negative or non-finite numbers are
/// replaced, so a policy built from remote configuration cannot produce a negative, infinite
/// or overflowing delay.
public struct RetryPolicy: Hashable, Sendable {
    /// Pushes per change before it is parked as failed. At least 1.
    public let maximumAttempts: Int

    /// The wait after the first failure.
    public let initialDelay: Duration

    /// The longest wait between two attempts.
    public let maximumDelay: Duration

    /// The factor the wait grows by after each failure. At least 1.
    public let multiplier: Double

    /// The largest fraction of a wait that is randomly taken off, from 0 (none) to 1.
    public let jitter: Double

    /// Eight attempts, starting at 2 seconds, doubling up to 10 minutes, with up to half of each
    /// wait taken off at random.
    public static let `default` = RetryPolicy()

    /// Creates a policy. Out-of-range values are clamped; non-finite values fall back to the
    /// defaults.
    public init(
        maximumAttempts: Int = 8,
        initialDelay: Duration = .seconds(2),
        maximumDelay: Duration = .seconds(600),
        multiplier: Double = 2,
        jitter: Double = 0.5
    ) {
        self.maximumAttempts = max(1, maximumAttempts)
        self.initialDelay = max(.zero, initialDelay)
        self.maximumDelay = max(self.initialDelay, maximumDelay)
        self.multiplier = multiplier.isFinite ? max(1, multiplier) : 2
        self.jitter = jitter.isFinite ? min(max(jitter, 0), 1) : 0.5
    }

    /// Whether a change that failed `attempts` times is pushed again.
    public func allowsRetry(afterAttempts attempts: Int) -> Bool {
        attempts < maximumAttempts
    }

    /// The wait after the `attempt`-th failure (1 for the first).
    ///
    /// - Parameter random: A number in `0..<1`; values outside are clamped. The store passes a
    ///   random number; tests pass a fixed one.
    public func delay(afterAttempt attempt: Int, random: Double) -> Duration {
        let initial = initialDelay.seconds
        let maximum = maximumDelay.seconds
        // Double(attempt) - 1 rather than attempt - 1, which overflows for Int.min.
        let exponent = attempt <= 1 ? 0 : Double(attempt) - 1
        var seconds = initial * pow(multiplier, exponent)
        if !seconds.isFinite || seconds > maximum {
            seconds = maximum
        }
        let fraction = random.isFinite ? min(max(random, 0), 1) : 0
        seconds -= seconds * jitter * fraction
        return .seconds(max(0, seconds))
    }
}

extension Duration {
    /// The duration in seconds as a `Double`.
    var seconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}
