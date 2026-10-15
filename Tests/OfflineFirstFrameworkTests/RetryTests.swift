import Foundation
import Testing
@testable import OfflineFirstFramework

@Suite("Retry policy")
struct RetryPolicyTests {
    private let policy = RetryPolicy(maximumAttempts: 4, initialDelay: .seconds(1), maximumDelay: .seconds(10), multiplier: 2, jitter: 0)

    @Test func delaysGrowExponentiallyUpToTheMaximum() {
        let delays = (1...6).map { policy.delay(afterAttempt: $0, random: 0) }
        #expect(delays == [.seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(10), .seconds(10)])
    }

    @Test func attemptsStopAtTheMaximum() {
        #expect(policy.allowsRetry(afterAttempts: 3))
        #expect(!policy.allowsRetry(afterAttempts: 4))
    }

    @Test func jitterTakesOffAtMostItsFraction() {
        let jittered = RetryPolicy(initialDelay: .seconds(8), maximumDelay: .seconds(8), jitter: 0.5)
        #expect(jittered.delay(afterAttempt: 1, random: 0) == .seconds(8))
        #expect(jittered.delay(afterAttempt: 1, random: 0.5) == .seconds(6))
        #expect(jittered.delay(afterAttempt: 1, random: 1) == .seconds(4))
        #expect(jittered.delay(afterAttempt: 1, random: 7) == .seconds(4))
        #expect(jittered.delay(afterAttempt: 1, random: .nan) == .seconds(8))
    }

    @Test(arguments: [Int.max, Int.min, 0, -5, 2_000])
    func extremeAttemptNumbersStayInRange(attempt: Int) {
        let delay = RetryPolicy.default.delay(afterAttempt: attempt, random: 0.3)
        #expect(delay >= .zero)
        #expect(delay <= RetryPolicy.default.maximumDelay)
    }

    @Test func invalidSettingsAreReplaced() {
        let odd = RetryPolicy(maximumAttempts: -3, initialDelay: .seconds(-5), maximumDelay: .seconds(-9), multiplier: .nan, jitter: .infinity)
        #expect(odd.maximumAttempts == 1)
        #expect(odd.initialDelay == .zero)
        #expect(odd.maximumDelay == .zero)
        #expect(odd.multiplier == 2)
        #expect(odd.jitter == 0.5)
        #expect(odd.delay(afterAttempt: 3, random: 0.5) == .zero)
        #expect(RetryPolicy(multiplier: 0.1).multiplier == 1)
        #expect(RetryPolicy(jitter: -1).jitter == 0)
    }

    @Test func hugeMultiplierIsCappedInsteadOfOverflowing() {
        let steep = RetryPolicy(initialDelay: .seconds(1), maximumDelay: .seconds(30), multiplier: 1e300, jitter: 0)
        #expect(steep.delay(afterAttempt: 50, random: 0) == .seconds(30))
    }
}

@Suite("Circuit breaker")
struct CircuitBreakerTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func opensAfterTheThresholdAndClosesAfterASuccessfulTrial() {
        var breaker = CircuitBreaker(failureThreshold: 2, cooldown: .seconds(30))
        breaker.recordFailure(at: start)
        let allowedAfterOneFailure = breaker.allowsAttempt(at: start)
        #expect(allowedAfterOneFailure)
        breaker.recordFailure(at: start)
        #expect(breaker.state == .open(until: start.addingTimeInterval(30)))
        let allowedDuringCooldown = breaker.allowsAttempt(at: start.addingTimeInterval(29))
        #expect(!allowedDuringCooldown)
        let allowedAfterCooldown = breaker.allowsAttempt(at: start.addingTimeInterval(30))
        #expect(allowedAfterCooldown)
        #expect(breaker.state == .halfOpen)
        breaker.recordSuccess()
        #expect(breaker.state == .closed)
        #expect(breaker.consecutiveFailures == 0)
    }

    @Test func failedTrialOpensAgain() {
        var breaker = CircuitBreaker(failureThreshold: 3, cooldown: .seconds(10))
        for _ in 0..<3 { breaker.recordFailure(at: start) }
        _ = breaker.allowsAttempt(at: start.addingTimeInterval(10))
        breaker.recordFailure(at: start.addingTimeInterval(11))
        #expect(breaker.state == .open(until: start.addingTimeInterval(21)))
        #expect(breaker.consecutiveFailures == 3)
    }

    @Test func settingsAreClamped() {
        let breaker = CircuitBreaker(failureThreshold: 0, cooldown: .seconds(-1))
        #expect(breaker.failureThreshold == 1)
        #expect(breaker.cooldown == .zero)
    }
}
